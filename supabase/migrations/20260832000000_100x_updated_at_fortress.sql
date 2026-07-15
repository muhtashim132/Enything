-- =============================================================================
-- Migration: 100x Updated At Fortress
-- Description:
--   1. Ensures cancel_order updates the updated_at timestamp.
--   2. Ensures update_order_status updates the updated_at timestamp on all paths.
--   3. Ensures client_confirm_payment updates the updated_at timestamp.
-- =============================================================================

-- 1. Patch cancel_order
CREATE OR REPLACE FUNCTION cancel_order(p_order_id UUID, p_reason text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer_id uuid;
  v_cart_group_id uuid;
  v_rec record;
  v_is_customer boolean;
BEGIN
  -- First find group ID without locking to avoid partial lock deadlocks
  SELECT customer_id, cart_group_id INTO v_customer_id, v_cart_group_id
  FROM orders WHERE id = p_order_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  v_is_customer := (auth.uid() = v_customer_id);

  -- 100x FIX: Prevent Global DoS Cancellation Exploit
  -- If the caller is not the customer, and not an active admin, block the cancellation.
  IF NOT v_is_customer AND NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: Only the customer or an admin can cancel this order.';
  END IF;

  IF v_cart_group_id IS NOT NULL THEN
    -- Lock all orders in group consistently ordered by ID
    FOR v_rec IN SELECT id, status, payment_status FROM orders WHERE cart_group_id = v_cart_group_id ORDER BY id FOR UPDATE LOOP
      -- 100x FIX: Allow terminal states to exist in the cart group without blocking cancellation
      IF v_is_customer AND v_rec.status NOT IN (
        'awaiting_acceptance', 'awaiting_payment', 'pending',
        'cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel'
      ) THEN
        -- If ANY order in the group has moved past payment, the customer cannot cancel the group
        RAISE EXCEPTION 'Order cannot be cancelled at this stage by customer';
      END IF;
      
      IF v_rec.status IN ('awaiting_acceptance', 'awaiting_payment', 'pending') THEN
        UPDATE orders
        SET 
          status = 'cancelled',
          cancelled_reason = p_reason,
          refund_status = CASE WHEN v_rec.payment_status = 'captured' THEN 'processing' ELSE refund_status END,
          updated_at = NOW()
        WHERE id = v_rec.id;
      END IF;
    END LOOP;
  ELSE
    -- Single order lock
    FOR v_rec IN SELECT id, status, payment_status FROM orders WHERE id = p_order_id FOR UPDATE LOOP
      -- 100x FIX: Same UX lockout fix for single orders
      IF v_is_customer AND v_rec.status NOT IN (
        'awaiting_acceptance', 'awaiting_payment', 'pending',
        'cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel'
      ) THEN
        RAISE EXCEPTION 'Order cannot be cancelled at this stage by customer';
      END IF;

      IF v_rec.status IN ('awaiting_acceptance', 'awaiting_payment', 'pending') THEN
        UPDATE orders
        SET 
          status = 'cancelled',
          cancelled_reason = p_reason,
          refund_status = CASE WHEN v_rec.payment_status = 'captured' THEN 'processing' ELSE refund_status END,
          updated_at = NOW()
        WHERE id = v_rec.id;
      END IF;
    END LOOP;
  END IF;
END;
$$;


-- 2. Patch update_order_status
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
      wait_time_penalty = v_calculated_wait_penalty,
      updated_at = NOW()
    WHERE id = p_order_id;
  ELSE
    UPDATE orders
    SET 
      status = p_new_status,
      updated_at = NOW()
    WHERE id = p_order_id;
  END IF;
END;
$$;


-- 3. Patch client_confirm_payment
CREATE OR REPLACE FUNCTION client_confirm_payment(
  p_order_id UUID DEFAULT NULL,
  p_cart_group_id UUID DEFAULT NULL,
  p_razorpay_payment_id text DEFAULT NULL,
  p_razorpay_order_id text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
  v_payment_status text;
  v_existing_payment_id text;
  v_order_id uuid;
  v_rec record;
BEGIN
  -- 100x FIX: TOCTOU Double Spend Prevention via Transaction-Level Advisory Lock
  -- This forces all concurrent requests using the exact same payment ID to queue up here.
  IF p_razorpay_payment_id IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(hashtext('pay_' || p_razorpay_payment_id));
    
    IF EXISTS (
      SELECT 1 FROM orders 
      WHERE razorpay_payment_id = p_razorpay_payment_id 
      AND (
        (p_cart_group_id IS NOT NULL AND (cart_group_id IS NULL OR cart_group_id != p_cart_group_id))
        OR 
        (p_cart_group_id IS NULL AND id != p_order_id)
      )
    ) THEN
      RAISE EXCEPTION 'Double spend detected: Payment ID % is already used for another order or group.', p_razorpay_payment_id;
    END IF;
  END IF;

  IF p_cart_group_id IS NOT NULL THEN
    FOR v_rec IN SELECT id, status, payment_status, razorpay_payment_id FROM orders WHERE cart_group_id = p_cart_group_id ORDER BY id FOR UPDATE LOOP
      IF v_rec.status = 'awaiting_payment' THEN
        UPDATE orders
        SET 
          status = 'confirmed',
          payment_status = 'captured',
          razorpay_payment_id = p_razorpay_payment_id,
          razorpay_order_id = p_razorpay_order_id,
          updated_at = NOW()
        WHERE id = v_rec.id;
      ELSE
        -- If it's the exact same payment, just ignore (idempotent)
        IF v_rec.payment_status = 'captured' AND v_rec.razorpay_payment_id = p_razorpay_payment_id THEN
           CONTINUE;
        END IF;
        
        -- State changed during payment
        UPDATE orders
        SET 
          payment_status = 'captured',
          refund_status = 'processing',
          razorpay_payment_id = p_razorpay_payment_id,
          razorpay_order_id = p_razorpay_order_id,
          updated_at = NOW()
        WHERE id = v_rec.id;
      END IF;
    END LOOP;
  ELSE
    SELECT status, payment_status, razorpay_payment_id INTO v_status, v_payment_status, v_existing_payment_id FROM orders WHERE id = p_order_id FOR UPDATE;
    IF FOUND THEN
      IF v_status = 'awaiting_payment' THEN
        UPDATE orders
        SET 
          status = 'confirmed',
          payment_status = 'captured',
          razorpay_payment_id = p_razorpay_payment_id,
          razorpay_order_id = p_razorpay_order_id,
          updated_at = NOW()
        WHERE id = p_order_id;
      ELSE
        -- If it's the exact same payment, just ignore (idempotent)
        IF v_payment_status = 'captured' AND v_existing_payment_id = p_razorpay_payment_id THEN
           RETURN;
        END IF;
        
        -- State changed during payment
        UPDATE orders
        SET 
          payment_status = 'captured',
          refund_status = 'processing',
          razorpay_payment_id = p_razorpay_payment_id,
          razorpay_order_id = p_razorpay_order_id,
          updated_at = NOW()
        WHERE id = p_order_id;
      END IF;
    END IF;
  END IF;
END;
$$;
