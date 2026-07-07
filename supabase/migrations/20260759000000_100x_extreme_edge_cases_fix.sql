-- =============================================================================
-- Migration: 100x Extreme Edge Cases Fix (Financial Shield)
-- Description:
--   1. Protects Enything from the "Refund Blackhole" by ensuring wait penalties
--      are still deducted from sellers even if the order was refunded.
--   2. Fixes Admin Dashboard stats to accurately calculate negative profit and 
--      lost GMV on refunded orders.
--   3. Implements a mathematical cap on wait time penalties so they never exceed
--      the seller's payout for that specific order.
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

        v_calculated_wait_penalty := (v_wait_mins - COALESCE(v_shop_prep_time_snapshot, 0)) * v_wait_penalty_rate;
        
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

-- 2. Close the Refund Blackhole in request_seller_withdrawal
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

  -- FIX: Persist wait_time_penalty deduction even if the order was refunded
  SELECT COALESCE(SUM(
    CASE 
      WHEN COALESCE(refund_status, 'none') IN ('processing', 'completed') THEN 0 
      ELSE COALESCE(seller_payout, 0) 
    END 
    - COALESCE(wait_time_penalty, 0)
  ), 0) INTO v_total_earned
  FROM orders
  WHERE status = 'delivered'
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

-- 3. Close the Refund Blackhole in get_seller_balance
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

  -- FIX: Persist wait_time_penalty deduction even if the order was refunded
  SELECT COALESCE(SUM(
    CASE 
      WHEN COALESCE(refund_status, 'none') IN ('processing', 'completed') THEN 0 
      ELSE COALESCE(seller_payout, 0) 
    END 
    - COALESCE(wait_time_penalty, 0)
  ), 0) INTO v_total_earned
  FROM orders
  WHERE status = 'delivered'
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

-- 4. Close the Refund Blackhole in get_seller_daily_stats
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

    -- FIX: Persist wait_time_penalty deduction even if the order was refunded
    SELECT COALESCE(SUM(
      CASE 
        WHEN COALESCE(refund_status, 'none') IN ('processing', 'completed') THEN 0 
        ELSE COALESCE(seller_payout, 0) 
      END 
      - COALESCE(wait_time_penalty, 0)
    ), 0.0) INTO v_todays_earning
    FROM orders
    WHERE shop_id = p_shop_id
      AND status = 'delivered'
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

-- 5. Close the Refund Blackhole in get_seller_ca_report
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
    COALESCE(SUM(CASE WHEN COALESCE(refund_status, 'none') IN ('processing', 'completed') THEN 0 ELSE total_amount END), 0) as total_base_sales,
    COALESCE(SUM(CASE WHEN COALESCE(refund_status, 'none') IN ('processing', 'completed') THEN 0 ELSE non_food_gst_amount END), 0) as non_food_gst,
    COALESCE(SUM(CASE WHEN COALESCE(refund_status, 'none') IN ('processing', 'completed') THEN 0 ELSE s9_5_gst_amount END), 0) as s9_5_gst,
    COALESCE(SUM(gst_delivery), 0) as delivery_gst, -- Delivery GST still paid by platform
    COALESCE(SUM(gst_platform), 0) as platform_gst, -- Platform GST still paid by platform
    COALESCE(SUM(CASE WHEN COALESCE(refund_status, 'none') IN ('processing', 'completed') THEN 0 ELSE tcs_amount END), 0) as tcs_deducted,
    COALESCE(SUM(CASE WHEN COALESCE(refund_status, 'none') IN ('processing', 'completed') THEN 0 ELSE tds_amount END), 0) as tds_deducted,
    COALESCE(SUM(CASE WHEN COALESCE(refund_status, 'none') IN ('processing', 'completed') THEN 0 ELSE enything_commission END), 0) as commission,
    -- FIX: Persist wait_time_penalty deduction
    COALESCE(SUM(
      CASE 
        WHEN COALESCE(refund_status, 'none') IN ('processing', 'completed') THEN 0 
        ELSE COALESCE(seller_payout, 0) 
      END 
      - COALESCE(wait_time_penalty, 0)
    ), 0) as seller_payout,
    COALESCE(SUM(CASE WHEN COALESCE(refund_status, 'none') = 'completed' THEN 0 ELSE grand_total_collected END), 0) as grand_collected,
    COALESCE(SUM(gateway_deduction), 0) as gateway_fees, -- Gateway fee still paid on refunds
    COUNT(*) as delivered_orders
  INTO v_result
  FROM orders
  WHERE shop_id = p_shop_id
    AND status = 'delivered'
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

-- 6. Reality-Check Admin Stats (admin_get_finance_stats)
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
    -- FIX: GMV should exclude completed refunds
    COALESCE(SUM(
      CASE WHEN COALESCE(refund_status, 'none') = 'completed' THEN 0 ELSE grand_total_collected END
    ), 0),
    
    -- FIX: Pure profit on refunded orders is profoundly negative (We lose delivery cost and gateway fee, earn no commission)
    COALESCE(SUM(
      CASE 
        WHEN COALESCE(refund_status, 'none') = 'completed' THEN 
          0 - COALESCE(rider_earnings, 0) - COALESCE(gateway_deduction, 0)
        ELSE 
          COALESCE(enything_commission, 0) + 
          (COALESCE(platform_fee, 0) - COALESCE(gst_platform, 0)) + 
          (COALESCE(delivery_charges, 0) - COALESCE(gst_delivery, 0) - COALESCE(rider_earnings, 0)) - 
          COALESCE(gateway_deduction, 0)
      END
    ), 0)
  INTO v_gmv, v_pure_profit
  FROM orders WHERE status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected', 'verification_failed', 'shop_dispute_cancel');

  SELECT 
    -- FIX: Deduct wait_time_penalty from seller payouts even if refunded
    COALESCE(SUM(
      CASE 
        WHEN COALESCE(refund_status, 'none') IN ('processing', 'completed') THEN 0 
        ELSE COALESCE(seller_payout, 0) 
      END 
      - COALESCE(wait_time_penalty, 0)
    ), 0),
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
