-- =============================================================================
-- Migration: 100x Wait Penalty Financial Sync
-- Description:
--   1. Implements dynamic `wait_time_penalty` configuration per category.
--   2. Secures `request_rider_withdrawal` to honor wait penalties.
--   3. Secures `request_seller_withdrawal` to deduct wait penalties from payouts.
--   4. Syncs `get_seller_balance`, `get_seller_daily_stats`, and `get_seller_ca_report`
--      to properly report net earnings minus wait penalties.
--   5. Fixes `admin_get_finance_stats` to accurately reflect transfers.
-- =============================================================================

-- 1. update_order_status
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
  v_calculated_wait_penalty numeric := 0;
  v_actual_ready_time timestamptz;
  v_wait_mins int;
  v_shop_category text;
  v_wait_penalty_rate numeric;
BEGIN
  SELECT status, shop_id, delivery_partner_id, arrived_at_shop_time, shop_prep_time_snapshot 
  INTO v_current_status, v_shop_id, v_rider_id, v_arrived_at_shop_time, v_shop_prep_time_snapshot
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  -- Strictly allowlist the statuses this RPC can handle
  IF p_new_status NOT IN ('preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery', 'delivered') THEN
    RAISE EXCEPTION 'Invalid status for this RPC: %', p_new_status;
  END IF;

  -- Ensure Caller is authorized
  IF p_new_status IN ('preparing', 'ready_for_pickup') THEN
    SELECT seller_id INTO v_seller_id FROM shops WHERE id = v_shop_id;
    IF v_seller_id != auth.uid() THEN
      RAISE EXCEPTION 'Unauthorized: Only seller can update to %', p_new_status;
    END IF;
  ELSIF p_new_status IN ('picked_up', 'out_for_delivery', 'delivered') THEN
    IF v_rider_id != auth.uid() THEN
      RAISE EXCEPTION 'Unauthorized: Only assigned rider can update to %', p_new_status;
    END IF;
    
    -- Strict State Machine Validations for Riders
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

  -- Securely calculate wait_time_penalty on the server.
  IF (p_new_status = 'ready_for_pickup' OR p_new_status = 'picked_up') AND (v_current_status != 'ready_for_pickup') THEN
    v_actual_ready_time := COALESCE(p_ready_time, now());
    
    IF v_arrived_at_shop_time IS NOT NULL THEN
      -- Calculate difference in minutes
      v_wait_mins := EXTRACT(EPOCH FROM (v_actual_ready_time - v_arrived_at_shop_time)) / 60;
      IF v_wait_mins > COALESCE(v_shop_prep_time_snapshot, 0) THEN
        
        -- DYNAMIC WAIT PENALTY FETCH
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

-- 2. request_rider_withdrawal
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

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text));

  -- FIX: Add wait_time_penalty to rider earnings
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

-- 3. request_seller_withdrawal
CREATE OR REPLACE FUNCTION request_seller_withdrawal(
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

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text));

  -- FIX: Deduct wait_time_penalty from seller payout
  SELECT COALESCE(SUM(COALESCE(seller_payout, 0) - COALESCE(wait_time_penalty, 0)), 0) INTO v_total_earned
  FROM orders
  WHERE status = 'delivered'
  AND COALESCE(refund_status, 'none') NOT IN ('processing', 'completed')
  AND shop_id IN (SELECT id FROM shops WHERE seller_id = v_user_id);

  SELECT COALESCE(SUM(amount), 0) INTO v_total_paid
  FROM withdrawals
  WHERE user_id = v_user_id
  AND user_role = 'seller'
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
    v_user_id, 'seller', p_amount, p_upi_id, p_bank_account_number, p_bank_ifsc, p_bank_account_holder, 'pending'
  );

  RETURN json_build_object('success', true, 'remaining_balance', v_available_balance - p_amount);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION request_seller_withdrawal(NUMERIC, TEXT, TEXT, TEXT, TEXT) TO authenticated;

-- 4. get_seller_balance
CREATE OR REPLACE FUNCTION get_seller_balance(p_seller_id UUID)
RETURNS JSON AS $$
DECLARE
  v_total_earned NUMERIC := 0;
  v_total_paid NUMERIC := 0;
  v_available_balance NUMERIC := 0;
BEGIN
  IF p_seller_id IS NULL THEN
    RAISE EXCEPTION 'Seller ID is required';
  END IF;

  -- FIX: Deduct wait_time_penalty from seller payout
  SELECT COALESCE(SUM(COALESCE(seller_payout, 0) - COALESCE(wait_time_penalty, 0)), 0) INTO v_total_earned
  FROM orders
  WHERE status = 'delivered'
  AND COALESCE(refund_status, 'none') NOT IN ('processing', 'completed')
  AND shop_id IN (SELECT id FROM shops WHERE seller_id = p_seller_id);

  SELECT COALESCE(SUM(amount), 0) INTO v_total_paid
  FROM withdrawals
  WHERE user_id = p_seller_id
  AND user_role = 'seller'
  AND status != 'rejected';

  v_available_balance := v_total_earned - v_total_paid;

  RETURN json_build_object(
    'total_earned', v_total_earned,
    'total_paid', v_total_paid,
    'available_balance', v_available_balance
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_seller_balance(UUID) TO authenticated;

-- 5. get_seller_daily_stats
CREATE OR REPLACE FUNCTION get_seller_daily_stats(p_shop_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_total_orders integer := 0;
    v_pending_orders integer := 0;
    v_todays_earning numeric := 0.0;
    v_products integer := 0;
BEGIN
    SELECT count(*) INTO v_total_orders
    FROM orders
    WHERE shop_id = p_shop_id
      AND status NOT IN ('cancelled', 'seller_rejected');

    SELECT count(*) INTO v_pending_orders
    FROM orders
    WHERE shop_id = p_shop_id
      AND status IN ('pending', 'awaiting_acceptance');

    -- FIX: Deduct wait_time_penalty
    SELECT COALESCE(SUM(COALESCE(seller_payout, 0) - COALESCE(wait_time_penalty, 0)), 0.0) INTO v_todays_earning
    FROM orders
    WHERE shop_id = p_shop_id
      AND status = 'delivered'
      AND COALESCE(refund_status, 'none') NOT IN ('processing', 'completed')
      AND DATE(updated_at AT TIME ZONE 'Asia/Kolkata') = DATE(CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Kolkata');

    SELECT count(*) INTO v_products
    FROM products
    WHERE shop_id = p_shop_id AND is_deleted = false;

    RETURN json_build_object(
        'total_orders', v_total_orders,
        'pending_orders', v_pending_orders,
        'todays_earning', v_todays_earning,
        'products', v_products
    );
END;
$$;

GRANT EXECUTE ON FUNCTION get_seller_daily_stats(uuid) TO authenticated;

-- 6. get_seller_ca_report
CREATE OR REPLACE FUNCTION get_seller_ca_report(p_shop_id uuid, p_start_date timestamptz, p_end_date timestamptz)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_seller_id uuid;
  v_result record;
BEGIN
  SELECT seller_id INTO v_seller_id FROM shops WHERE id = p_shop_id;
  IF v_seller_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT 
    COALESCE(SUM(total_amount), 0) as total_base_sales,
    COALESCE(SUM(non_food_gst_amount), 0) as non_food_gst,
    COALESCE(SUM(s9_5_gst_amount), 0) as s9_5_gst,
    COALESCE(SUM(gst_delivery), 0) as delivery_gst,
    COALESCE(SUM(gst_platform), 0) as platform_gst,
    COALESCE(SUM(tcs_amount), 0) as tcs_deducted,
    COALESCE(SUM(tds_amount), 0) as tds_deducted,
    COALESCE(SUM(enything_commission), 0) as commission,
    -- FIX: Expose seller_payout - wait_time_penalty
    COALESCE(SUM(COALESCE(seller_payout, 0) - COALESCE(wait_time_penalty, 0)), 0) as seller_payout,
    COALESCE(SUM(grand_total_collected), 0) as grand_collected,
    COALESCE(SUM(gateway_deduction), 0) as gateway_fees,
    COUNT(*) as delivered_orders
  INTO v_result
  FROM orders
  WHERE shop_id = p_shop_id
    AND status = 'delivered'
    AND COALESCE(refund_status, 'none') NOT IN ('processing', 'completed')
    AND updated_at >= p_start_date
    AND updated_at < p_end_date;

  RETURN json_build_object(
    'total_base_sales', v_result.total_base_sales,
    'non_food_gst', v_result.non_food_gst,
    's9_5_gst', v_result.s9_5_gst,
    'delivery_gst', v_result.delivery_gst,
    'platform_gst', v_result.platform_gst,
    'tcs_deducted', v_result.tcs_deducted,
    'tds_deducted', v_result.tds_deducted,
    'commission', v_result.commission,
    'seller_payout', v_result.seller_payout,
    'grand_collected', v_result.grand_collected,
    'gateway_fees', v_result.gateway_fees,
    'delivered_orders', v_result.delivered_orders
  );
END;
$$;

GRANT EXECUTE ON FUNCTION get_seller_ca_report(uuid, timestamptz, timestamptz) TO authenticated;

-- 7. admin_get_finance_stats
CREATE OR REPLACE FUNCTION admin_get_finance_stats()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_gmv NUMERIC;
  v_pure_profit NUMERIC;
  v_seller_payouts NUMERIC;
  v_rider_earnings NUMERIC;
  v_pending_settlements INT;
BEGIN
  IF NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;

  SELECT 
    COALESCE(SUM(grand_total_collected), 0),
    COALESCE(SUM(
      COALESCE(enything_commission, 0) + 
      (COALESCE(platform_fee, 0) - COALESCE(gst_platform, 0)) + 
      (COALESCE(delivery_charges, 0) - COALESCE(gst_delivery, 0) - COALESCE(rider_earnings, 0)) - 
      COALESCE(gateway_deduction, 0)
    ), 0)
  INTO v_gmv, v_pure_profit
  FROM orders WHERE status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected', 'verification_failed', 'shop_dispute_cancel');

  -- FIX: Deduct wait_time_penalty from seller payouts and add it to rider earnings
  SELECT 
    COALESCE(SUM(COALESCE(seller_payout, 0) - COALESCE(wait_time_penalty, 0)), 0),
    COALESCE(SUM(COALESCE(rider_earnings, 0) + COALESCE(wait_time_penalty, 0)), 0),
    COUNT(*)
  INTO v_seller_payouts, v_rider_earnings, v_pending_settlements
  FROM orders WHERE status = 'delivered';

  RETURN jsonb_build_object(
    'gmv', v_gmv,
    'pure_profit', v_pure_profit,
    'seller_payouts', v_seller_payouts,
    'rider_earnings', v_rider_earnings,
    'pending_settlements', v_pending_settlements
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_get_finance_stats() TO authenticated;
