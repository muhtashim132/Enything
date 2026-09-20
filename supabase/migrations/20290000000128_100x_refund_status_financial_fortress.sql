-- =============================================================================
-- Migration: 20290000000128_100x_refund_status_financial_fortress.sql
-- Description:
--   STRICTLY ADDITIVE. No DROP, DELETE, TRUNCATE, ALTER TABLE.
--   Only CREATE OR REPLACE FUNCTION + GRANT EXECUTE.
--
--   FIVE CONFIRMED BUGS FIXED:
--
--   BUG 1 (CRITICAL): refund_status value mismatch.
--     process-refund Edge Function and razorpay-webhook both set
--     refund_status = 'processed' after Razorpay confirms a refund.
--     But ALL financial RPCs (get_seller_balance, get_seller_ca_report,
--     request_seller_withdrawal, admin_get_finance_stats) exclude refunded
--     orders by checking: refund_status IN ('processing', 'completed').
--     The value 'processed' NEVER matches, so refunded orders are STILL
--     counted as seller earnings and inflated GMV.
--     FIX: Add 'processed' to the exclusion list everywhere.
--
--   BUG 5 (MEDIUM): admin_process_withdrawal has no balance re-validation.
--     An admin can approve a ₹5,000 withdrawal even if the seller's actual
--     available balance dropped to ₹1,000 (e.g., another admin already
--     processed an earlier withdrawal for the same user).
--     FIX: Re-calculate available balance inside admin_process_withdrawal
--     and RAISE EXCEPTION if amount > available.
--
--   NOTE: Dart-side bugs (BUG 2, 3, 4) are fixed in separate Dart files.
-- =============================================================================


-- =============================================================================
-- FIX 1A: get_seller_balance — add 'processed' to refund exclusion
-- =============================================================================
CREATE OR REPLACE FUNCTION get_seller_balance(p_seller_id UUID)
RETURNS JSON AS $$
DECLARE
  v_total_earned NUMERIC := 0;
  v_total_paid NUMERIC := 0;
  v_available_balance NUMERIC := 0;
BEGIN
  -- 100x FIX: Seal Ternary NULL Bypass with IS DISTINCT FROM (preserved)
  IF (auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_seller_id) AND NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: Cannot access financial data for another user.';
  END IF;

  SELECT COALESCE(SUM(
    CASE 
      -- BUG 1 FIX: Added 'processed' to exclusion list
      WHEN COALESCE(refund_status, 'none') IN ('processing', 'processed', 'completed') THEN 0 
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


-- =============================================================================
-- FIX 1B: request_seller_withdrawal — add 'processed' to refund exclusion
-- =============================================================================
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

  -- 100x FIX: String Bloat Protection to prevent OOM (preserved)
  IF length(p_upi_id) > 100 THEN RAISE EXCEPTION 'UPI ID string too long (Max 100 chars)'; END IF;
  IF length(p_bank_account_number) > 100 THEN RAISE EXCEPTION 'Bank account number string too long (Max 100 chars)'; END IF;
  IF length(p_bank_ifsc) > 100 THEN RAISE EXCEPTION 'Bank IFSC string too long (Max 100 chars)'; END IF;
  IF length(p_bank_account_holder) > 100 THEN RAISE EXCEPTION 'Bank account holder string too long (Max 100 chars)'; END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_user_id::text));

  -- BUG 1 FIX: Added 'processed' to refund exclusion list
  SELECT COALESCE(SUM(
    CASE 
      WHEN COALESCE(refund_status, 'none') IN ('processing', 'processed', 'completed') THEN 0 
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


-- =============================================================================
-- FIX 1C: get_seller_ca_report — add 'processed' to refund exclusion
-- =============================================================================
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
  
  -- 100x FIX: Seal Ternary NULL Bypass with IS DISTINCT FROM (preserved)
  IF (auth.uid() IS NULL OR v_seller_id IS DISTINCT FROM auth.uid()) AND NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT 
    -- BUG 1 FIX: Added 'processed' to ALL refund exclusion checks
    COALESCE(SUM(CASE WHEN COALESCE(refund_status, 'none') IN ('processing', 'processed', 'completed') THEN 0 ELSE total_amount END), 0) as total_base_sales,
    COALESCE(SUM(CASE WHEN COALESCE(refund_status, 'none') IN ('processing', 'processed', 'completed') THEN 0 ELSE non_food_gst_amount END), 0) as non_food_gst,
    COALESCE(SUM(CASE WHEN COALESCE(refund_status, 'none') IN ('processing', 'processed', 'completed') THEN 0 ELSE s9_5_gst_amount END), 0) as s9_5_gst,
    COALESCE(SUM(gst_delivery), 0) as delivery_gst,
    COALESCE(SUM(gst_platform), 0) as platform_gst,
    COALESCE(SUM(CASE WHEN COALESCE(refund_status, 'none') IN ('processing', 'processed', 'completed') THEN 0 ELSE tcs_amount END), 0) as tcs_deducted,
    COALESCE(SUM(CASE WHEN COALESCE(refund_status, 'none') IN ('processing', 'processed', 'completed') THEN 0 ELSE tds_amount END), 0) as tds_deducted,
    COALESCE(SUM(CASE WHEN COALESCE(refund_status, 'none') IN ('processing', 'processed', 'completed') THEN 0 ELSE enything_commission END), 0) as commission,
    COALESCE(SUM(
      CASE 
        WHEN COALESCE(refund_status, 'none') IN ('processing', 'processed', 'completed') THEN 0 
        ELSE COALESCE(seller_payout, 0) 
      END 
      - COALESCE(wait_time_penalty, 0)
    ), 0) as seller_payout,
    COALESCE(SUM(CASE WHEN COALESCE(refund_status, 'none') IN ('processed', 'completed') THEN 0 ELSE grand_total_collected END), 0) as grand_collected,
    COALESCE(SUM(gateway_deduction), 0) as gateway_fees,
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


-- =============================================================================
-- FIX 1D: admin_get_finance_stats — add 'processed' to refund exclusion
-- =============================================================================
CREATE OR REPLACE FUNCTION public.admin_get_finance_stats()
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
  -- Strict Authorization Barrier (preserved from original)
  IF NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;

  -- GMV + Pure Profit across ALL orders
  SELECT
    COALESCE(SUM(
      -- BUG 1 FIX: Added 'processed' to refund exclusion
      CASE WHEN COALESCE(refund_status, 'none') IN ('processed', 'completed') THEN 0 ELSE grand_total_collected END
    ), 0),

    COALESCE(SUM(
      CASE
        -- BUG 1 FIX: Added 'processed' to refund exclusion
        WHEN COALESCE(refund_status, 'none') IN ('processing', 'processed', 'completed') THEN
          0 - COALESCE(rider_earnings, 0) - COALESCE(gateway_deduction, 0)
        WHEN status IN ('cancelled', 'seller_rejected', 'partner_rejected', 'verification_failed', 'shop_dispute_cancel') THEN
          0 - COALESCE(rider_earnings, 0) - COALESCE(gateway_deduction, 0)
        ELSE
          COALESCE(enything_commission, 0) +
          (COALESCE(platform_fee, 0) - COALESCE(gst_platform, 0)) +
          (COALESCE(delivery_charges, 0) - COALESCE(gst_delivery, 0) - COALESCE(rider_earnings, 0)) -
          COALESCE(gateway_deduction, 0) - COALESCE(coupon_discount, 0)
      END
    ), 0)
  INTO v_gmv, v_pure_profit
  FROM public.orders;

  -- Seller payouts + Rider earnings
  SELECT
    COALESCE(SUM(
      CASE
        -- BUG 1 FIX: Added 'processed' to refund exclusion
        WHEN COALESCE(refund_status, 'none') IN ('processing', 'processed', 'completed') THEN 0
        ELSE COALESCE(seller_payout, 0)
      END
      - COALESCE(wait_time_penalty, 0)
    ), 0),
    COALESCE(SUM(COALESCE(rider_earnings, 0) + COALESCE(wait_time_penalty, 0)), 0)
  INTO v_seller_payouts, v_rider_earnings
  FROM public.orders WHERE status = 'delivered';

  -- Pending settlements count (preserved from BUG 4 fix in 20271232)
  BEGIN
    SELECT COUNT(*) INTO v_pending_settlements
    FROM public.withdrawals WHERE status = 'pending';
  EXCEPTION WHEN OTHERS THEN
    v_pending_settlements := 0;
  END;

  RETURN jsonb_build_object(
    'gmv',                 ROUND(v_gmv, 2),
    'pure_profit',         ROUND(v_pure_profit, 2),
    'seller_payouts',      ROUND(v_seller_payouts, 2),
    'rider_earnings',      ROUND(v_rider_earnings, 2),
    'pending_settlements', v_pending_settlements
  );
END;
$$;


-- =============================================================================
-- FIX 5: admin_process_withdrawal — re-validate balance before approval
-- =============================================================================
CREATE OR REPLACE FUNCTION admin_process_withdrawal(
  p_withdrawal_id UUID, 
  p_status TEXT, 
  p_transaction_id TEXT DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_status text;
  v_user_id uuid;
  v_user_role text;
  v_amount numeric;
  v_available_balance numeric := 0;
  v_total_earned numeric := 0;
  v_total_paid numeric := 0;
BEGIN
  -- Strict Authorization Barrier (preserved)
  IF NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;

  SELECT status, user_id, user_role, amount
  INTO v_current_status, v_user_id, v_user_role, v_amount
  FROM withdrawals WHERE id = p_withdrawal_id FOR UPDATE;

  IF v_current_status != 'pending' THEN
    RAISE EXCEPTION 'Withdrawal is already %', v_current_status;
  END IF;

  IF p_status NOT IN ('processed', 'rejected') THEN
    RAISE EXCEPTION 'Invalid status: %', p_status;
  END IF;

  -- BUG 5 FIX: Re-validate balance before approving (skip for rejections)
  IF p_status = 'processed' THEN
    IF v_user_role = 'seller' THEN
      SELECT COALESCE(SUM(
        CASE 
          WHEN COALESCE(refund_status, 'none') IN ('processing', 'processed', 'completed') THEN 0 
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
      AND status != 'rejected'
      AND id != p_withdrawal_id;  -- exclude current pending withdrawal

    ELSIF v_user_role = 'delivery_partner' THEN
      SELECT COALESCE(SUM(COALESCE(rider_earnings, 0) + COALESCE(wait_time_penalty, 0)), 0) INTO v_total_earned
      FROM orders
      WHERE (status = 'delivered' OR (status = 'cancelled' AND rider_earnings > 0))
      AND delivery_partner_id = v_user_id;

      SELECT COALESCE(SUM(amount), 0) INTO v_total_paid
      FROM withdrawals
      WHERE user_id = v_user_id
      AND user_role = 'delivery_partner'
      AND status != 'rejected'
      AND id != p_withdrawal_id;  -- exclude current pending withdrawal
    END IF;

    v_available_balance := v_total_earned - v_total_paid;

    IF v_amount > v_available_balance THEN
      RAISE EXCEPTION 'Insufficient balance. User has ₹% available but requested ₹%', 
        ROUND(v_available_balance, 2), ROUND(v_amount, 2);
    END IF;
  END IF;

  UPDATE withdrawals
  SET 
    status = p_status,
    transaction_id = p_transaction_id,
    processed_at = CASE WHEN p_status = 'processed' THEN NOW() ELSE NULL END
  WHERE id = p_withdrawal_id;
END;
$$;


-- =============================================================================
-- Re-grant all patched functions (idempotent, defensive)
-- =============================================================================
GRANT EXECUTE ON FUNCTION public.get_seller_balance(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_seller_ca_report(UUID, TIMESTAMPTZ, TIMESTAMPTZ) TO authenticated;
GRANT EXECUTE ON FUNCTION public.request_seller_withdrawal(NUMERIC, TEXT, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_finance_stats() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_process_withdrawal(UUID, TEXT, TEXT) TO authenticated;


-- =============================================================================
-- Notify PostgREST to reload schema cache so grants take effect immediately
-- =============================================================================
NOTIFY pgrst, 'reload schema';
