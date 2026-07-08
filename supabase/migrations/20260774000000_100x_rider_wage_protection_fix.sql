-- =============================================================================
-- Migration: 100x Rider Wage Protection Fix
-- Description:
--   1. Fixes the "Negative Wait Penalty Exploit" where sellers preparing food 
--      faster than the estimated time caused a mathematically negative penalty, 
--      which explicitly robbed riders of their delivery fee and paid it to the seller.
--   2. Fixes the "Rider Wage Theft" refund blackhole, ensuring that if a customer 
--      receives a refund for bad food (seller fault), the rider who successfully
--      completed the delivery is STILL paid their hard-earned delivery fee.
-- =============================================================================

-- 1. Cap Wait Time Penalty in update_order_status
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
  -- FIX: Fetch seller_payout to use as a cap for the penalty
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

        -- 100x FIX 1: Implement mathematically strict floor (GREATEST 0) so fast sellers don't cause negative penalties
        -- Negative penalties would explicitly steal rider wages and reward the seller!
        v_calculated_wait_penalty := GREATEST(0, (v_wait_mins - COALESCE(v_shop_prep_time_snapshot, 0))) * v_wait_penalty_rate;
        
        -- FIX: Implement mathematical penalty cap to prevent unbounded liability
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


-- 2. Restore Rider Wage Integrity in request_rider_withdrawal
CREATE OR REPLACE FUNCTION request_rider_withdrawal(
  p_amount NUMERIC,
  p_upi_id TEXT DEFAULT NULL,
  p_bank_account_number TEXT DEFAULT NULL,
  p_bank_ifsc TEXT DEFAULT NULL,
  p_bank_account_holder TEXT DEFAULT NULL
)
RETURNS JSON AS $$
DECLARE
  v_user_id UUID;
  v_total_earned NUMERIC := 0;
  v_total_paid NUMERIC := 0;
  v_available_balance NUMERIC := 0;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Financial Lock: pg_advisory_xact_lock to prevent double-spending
  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text));

  -- 100x FIX 2: Restore rider earnings regardless of refund_status. If an order is 'delivered',
  -- the rider completed the physical labor and MUST be paid. Customer refunds for bad food
  -- are the seller's fault, and the rider should NOT suffer wage theft for it.
  SELECT COALESCE(SUM(COALESCE(rider_earnings, 0) + COALESCE(wait_time_penalty, 0)), 0) INTO v_total_earned
  FROM orders
  WHERE status = 'delivered'
  AND delivery_partner_id = v_user_id;

  SELECT COALESCE(SUM(amount), 0) INTO v_total_paid
  FROM withdrawals
  WHERE user_id = v_user_id
  AND user_role = 'delivery_partner'
  AND status != 'rejected';

  v_available_balance := v_total_earned - v_total_paid;

  IF p_amount > v_available_balance THEN
    RAISE EXCEPTION 'Insufficient balance. Available: %', v_available_balance;
  END IF;

  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be greater than zero';
  END IF;

  INSERT INTO withdrawals (
    user_id, user_role, amount, upi_id, bank_account_number, bank_ifsc, bank_account_holder, status
  ) VALUES (
    v_user_id, 'delivery_partner', p_amount, p_upi_id, p_bank_account_number, p_bank_ifsc, p_bank_account_holder, 'pending'
  );

  RETURN json_build_object('success', true, 'remaining_balance', v_available_balance - p_amount);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION request_rider_withdrawal(NUMERIC, TEXT, TEXT, TEXT, TEXT) TO authenticated;
