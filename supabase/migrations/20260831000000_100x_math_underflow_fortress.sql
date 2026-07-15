-- =============================================================================
-- Migration: 100x Math Underflow Fortress
-- Description:
--   Fixes an extreme PostgreSQL edge case where Haversine floating-point math 
--   can result in tiny negative numbers (e.g. -0.000000001), causing the 
--   SQRT function to crash with "cannot take square root of a negative number"
--   and blocking the entire order lifecycle.
-- =============================================================================

CREATE OR REPLACE FUNCTION set_arrived_at_shop(
  p_order_id UUID,
  p_rider_lat NUMERIC DEFAULT NULL,
  p_rider_lng NUMERIC DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
  v_delivery_partner_id uuid;
  v_auth_uid uuid;
  v_shop_lat numeric;
  v_shop_lng numeric;
  v_distance numeric;
  v_arrived_at_shop_time timestamptz;
BEGIN
  v_auth_uid := auth.uid();
  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT status, delivery_partner_id, shop_lat, shop_lng, arrived_at_shop_time 
  INTO v_status, v_delivery_partner_id, v_shop_lat, v_shop_lng, v_arrived_at_shop_time
  FROM orders 
  WHERE id = p_order_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF v_delivery_partner_id != v_auth_uid THEN
    RAISE EXCEPTION 'Unauthorized: Only the assigned rider can mark arrival';
  END IF;

  IF v_status NOT IN ('preparing', 'ready_for_pickup', 'accepted') THEN
    RAISE EXCEPTION 'Invalid status for arrival: %', v_status;
  END IF;

  IF v_arrived_at_shop_time IS NOT NULL THEN
    RETURN;
  END IF;

  IF p_rider_lat IS NOT NULL AND p_rider_lng IS NOT NULL AND v_shop_lat IS NOT NULL AND v_shop_lng IS NOT NULL THEN
    v_distance := 6371000 * 2 * ASIN(LEAST(1.0::double precision, SQRT(GREATEST(0.0::double precision, 
        POWER(SIN((p_rider_lat - v_shop_lat) * pi()/180 / 2), 2) +
        COS(v_shop_lat * pi()/180) * COS(p_rider_lat * pi()/180) *
        POWER(SIN((p_rider_lng - v_shop_lng) * pi()/180 / 2), 2)
    ))));
    IF v_distance > 300 THEN
      RAISE EXCEPTION 'GEO_FENCE_FAILED: You are % meters away from the shop. Max allowed is 300m.', v_distance::int;
    END IF;
  ELSE
    IF v_shop_lat IS NOT NULL AND v_shop_lng IS NOT NULL THEN
      RAISE EXCEPTION 'GEO_FENCE_FAILED: Rider GPS coordinates are required to mark arrival.';
    END IF;
  END IF;

  UPDATE orders
  SET 
    arrived_at_shop_time = NOW(),
    updated_at = NOW()
  WHERE id = p_order_id;
END;
$$;


CREATE OR REPLACE FUNCTION update_order_status(
    p_order_id uuid, 
    p_new_status text, 
    p_ready_time timestamptz DEFAULT NULL, 
    p_wait_penalty numeric DEFAULT 0,
    p_rider_lat numeric DEFAULT NULL,
    p_rider_lng numeric DEFAULT NULL,
    p_delivery_otp text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_status text;
  v_shop_id uuid;
  v_seller_id uuid;
  v_rider_id uuid;
  v_arrived_at_shop_time timestamptz;
  v_shop_prep_time_snapshot int;
  v_seller_payout numeric;
  v_calculated_wait_penalty numeric := 0;
  v_actual_ready_time timestamptz;
  v_wait_mins numeric;
  v_shop_category text;
  v_wait_penalty_rate numeric;
  v_customer_lat numeric;
  v_customer_lng numeric;
  v_distance_to_customer numeric;
  v_delivery_otp text;
BEGIN
  -- Strict row locking
  SELECT status, shop_id, delivery_partner_id, arrived_at_shop_time, shop_prep_time_snapshot, seller_payout, delivery_otp 
  INTO v_current_status, v_shop_id, v_rider_id, v_arrived_at_shop_time, v_shop_prep_time_snapshot, v_seller_payout, v_delivery_otp
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF p_new_status NOT IN ('preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery', 'delivered') THEN
    RAISE EXCEPTION 'Invalid status for this RPC: %', p_new_status;
  END IF;

  IF p_new_status IN ('preparing', 'ready_for_pickup') THEN
    SELECT seller_id INTO v_seller_id FROM shops WHERE id = v_shop_id;
    IF v_seller_id != auth.uid() THEN
      RAISE EXCEPTION 'Unauthorized: Only seller can update to %', p_new_status;
    END IF;
    
    IF p_new_status = 'preparing' AND v_current_status NOT IN ('awaiting_acceptance', 'pending', 'preparing', 'confirmed') THEN
      RAISE EXCEPTION 'Cannot mark preparing from terminal or downstream state: %', v_current_status;
    END IF;

    IF p_new_status = 'ready_for_pickup' AND v_current_status != 'preparing' THEN
      RAISE EXCEPTION 'Cannot mark ready_for_pickup from state: %', v_current_status;
    END IF;

  ELSIF p_new_status IN ('picked_up', 'out_for_delivery', 'delivered') THEN
    IF v_rider_id != auth.uid() THEN
      RAISE EXCEPTION 'Unauthorized: Only assigned rider can update to %', p_new_status;
    END IF;
    
    IF p_new_status = 'picked_up' AND v_current_status NOT IN ('preparing', 'ready_for_pickup') THEN
      RAISE EXCEPTION 'Cannot mark picked_up from %', v_current_status;
    END IF;
    
    IF p_new_status = 'out_for_delivery' AND v_current_status != 'picked_up' THEN
      RAISE EXCEPTION 'Cannot mark out_for_delivery from %', v_current_status;
    END IF;
    
    IF p_new_status = 'delivered' THEN
        IF v_current_status NOT IN ('out_for_delivery', 'picked_up') THEN
            RAISE EXCEPTION 'Cannot mark delivered from %', v_current_status;
        END IF;

        -- Legacy Address Deadlock Bypass
        SELECT delivery_lat, delivery_lng INTO v_customer_lat, v_customer_lng
        FROM orders
        WHERE id = p_order_id;

        IF v_customer_lat IS NOT NULL AND v_customer_lng IS NOT NULL THEN
            IF p_rider_lat IS NOT NULL AND p_rider_lng IS NOT NULL THEN
                v_distance_to_customer := 6371000 * 2 * ASIN(LEAST(1.0::double precision, SQRT(GREATEST(0.0::double precision, 
                    POWER(SIN((p_rider_lat - v_customer_lat) * pi()/180 / 2), 2) +
                    COS(v_customer_lat * pi()/180) * COS(p_rider_lat * pi()/180) *
                    POWER(SIN((p_rider_lng - v_customer_lng) * pi()/180 / 2), 2)
                ))));
                IF v_distance_to_customer > 300 THEN
                    RAISE EXCEPTION 'GEO_FENCE_FAILED: You are % meters away from the customer. Max allowed is 300m.', v_distance_to_customer::int;
                END IF;
            ELSE
                RAISE EXCEPTION 'GEO_FENCE_FAILED: Rider GPS coordinates are required to mark delivered.';
            END IF;
        END IF;
    END IF;
  END IF;

  IF (p_new_status = 'ready_for_pickup' OR p_new_status = 'picked_up') AND (v_current_status != 'ready_for_pickup') THEN
    v_actual_ready_time := now() AT TIME ZONE 'utc';
    
    IF v_arrived_at_shop_time IS NOT NULL THEN
      v_wait_mins := (EXTRACT(EPOCH FROM (v_actual_ready_time - v_arrived_at_shop_time)) / 60.0)::numeric;
      IF v_wait_mins > COALESCE(v_shop_prep_time_snapshot, 0) THEN
        
        SELECT category INTO v_shop_category FROM shops WHERE id = v_shop_id;
        BEGIN
          SELECT value::numeric INTO v_wait_penalty_rate FROM platform_config WHERE key = 'wait_penalty_per_min_' || v_shop_category;
        EXCEPTION WHEN OTHERS THEN 
          v_wait_penalty_rate := NULL; 
        END;

        IF v_wait_penalty_rate IS NULL THEN
          BEGIN
            SELECT value::numeric INTO v_wait_penalty_rate FROM platform_config WHERE key = 'wait_penalty_per_min';
          EXCEPTION WHEN OTHERS THEN 
            v_wait_penalty_rate := 2.0; 
          END;
        END IF;

        IF v_wait_penalty_rate IS NULL THEN
          v_wait_penalty_rate := 2.0;
        END IF;

        v_calculated_wait_penalty := ROUND(GREATEST(0::numeric, (v_wait_mins - COALESCE(v_shop_prep_time_snapshot, 0)::numeric)) * v_wait_penalty_rate, 2);
        
        IF v_calculated_wait_penalty > COALESCE(v_seller_payout, 0) THEN
          v_calculated_wait_penalty := COALESCE(v_seller_payout, 0);
        END IF;

      END IF;
    END IF;

    UPDATE orders
    SET 
      status = p_new_status,
      order_ready_time = v_actual_ready_time,
      wait_time_penalty = v_calculated_wait_penalty
    WHERE id = p_order_id;
  ELSE
    UPDATE orders
    SET status = p_new_status
    WHERE id = p_order_id;
  END IF;
END;
$$;
