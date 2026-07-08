-- =============================================================================
-- Migration: 100x Stress Test Fixes (Operational Deadlock Resolution)
-- Description:
--   1. Replaces the strict 'ready_for_pickup' lock on riders with a Penalty 
--      Forfeiture mechanic. This solves the physical-world operational deadlock
--      where a seller hands over the food but refuses/forgets to press 'Ready'.
--      The rider can now force the 'picked_up' state to continue delivery, 
--      but doing so automatically zeroes out their wait time penalty, completely 
--      eliminating the financial incentive to spoof wait times.
-- =============================================================================

CREATE OR REPLACE FUNCTION update_order_status(p_order_id UUID, p_new_status text, p_ready_time timestamptz DEFAULT NULL, p_wait_penalty numeric DEFAULT 0)
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
  v_wait_mins int;
  v_shop_category text;
  v_wait_penalty_rate numeric;
BEGIN
  SELECT status, shop_id, delivery_partner_id, arrived_at_shop_time, shop_prep_time_snapshot, seller_payout 
  INTO v_current_status, v_shop_id, v_rider_id, v_arrived_at_shop_time, v_shop_prep_time_snapshot, v_seller_payout
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
    
    IF p_new_status = 'delivered' AND v_current_status NOT IN ('out_for_delivery', 'picked_up') THEN
      RAISE EXCEPTION 'Cannot mark delivered from %', v_current_status;
    END IF;
  END IF;

  IF (p_new_status = 'ready_for_pickup' OR p_new_status = 'picked_up') AND (v_current_status != 'ready_for_pickup') THEN
    v_actual_ready_time := COALESCE(p_ready_time, now());
    
    IF v_arrived_at_shop_time IS NOT NULL THEN
      v_wait_mins := EXTRACT(EPOCH FROM (v_actual_ready_time - v_arrived_at_shop_time)) / 60;
      
      -- 100x STRESS TEST FIX: Penalty Forfeiture Mechanic
      IF p_new_status = 'picked_up' AND v_current_status = 'preparing' THEN
        -- Rider forced the transition. Forfeit penalty to prevent spoofing.
        v_calculated_wait_penalty := 0;
      ELSIF v_wait_mins > COALESCE(v_shop_prep_time_snapshot, 0) THEN
        -- Calculate normally because Seller marked it ready
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

        v_calculated_wait_penalty := (v_wait_mins - COALESCE(v_shop_prep_time_snapshot, 0)) * v_wait_penalty_rate;
        
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

GRANT EXECUTE ON FUNCTION update_order_status(UUID, text, timestamptz, numeric) TO authenticated;
