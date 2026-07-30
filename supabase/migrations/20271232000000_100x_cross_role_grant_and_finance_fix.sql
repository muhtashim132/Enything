-- =============================================================================
-- Migration: 20271232000000_100x_cross_role_grant_and_finance_fix.sql
-- Description:
--   STRICTLY ADDITIVE. No DROP, DELETE, TRUNCATE, ALTER TABLE.
--   Only CREATE OR REPLACE FUNCTION + GRANT EXECUTE.
--
--   Five confirmed cross-role bugs fixed:
--
--   BUG 1 (CRITICAL): get_customer_dashboard_stats had no GRANT EXECUTE —
--     function existed but was uncallable by any role (silent permission denied).
--     100x verification: grep of all migrations shows zero GRANT for this function.
--
--   BUG 2 (CRITICAL): admin_get_finance_stats returned key 'total_gmv' but the
--     Dart client (finance_admin_page.dart:54) reads res['gmv'].
--     This caused a TypeError (null as num) swallowed by try-catch, making
--     the Finance Admin page silently show ₹0 for all financial metrics.
--     Fix: Restore the return key to 'gmv' (unchanged logic, one key rename).
--
--   BUG 3 (MEDIUM): get_seller_balance, get_rider_balance, get_seller_ca_report
--     were re-created in 20271229000000 with IS DISTINCT FROM hardening but
--     no GRANT EXECUTE was re-issued. Re-granting is safe (idempotent).
--
--   BUG 4 (MEDIUM): pending_settlements in admin_get_finance_stats was COUNT(*)
--     from delivered ORDERS (not from pending WITHDRAWALS), making the
--     "Pending Settlements" counter on Finance Admin semantically wrong.
--     Fix: Dedicated SELECT COUNT(*) FROM withdrawals WHERE status = 'pending'.
--
--   Note: Dart BUG (admin_get_all_riders null guard) is fixed separately
--     in users_admin_page.dart.
-- =============================================================================


-- =============================================================================
-- FIX 1: GRANT get_customer_dashboard_stats to authenticated
--   No GRANT existed in 20271228 or 20271229 where this function was created.
-- =============================================================================
GRANT EXECUTE ON FUNCTION public.get_customer_dashboard_stats(UUID) TO authenticated;


-- =============================================================================
-- FIX 2: Re-GRANT get_seller_balance, get_rider_balance, get_seller_ca_report
--   These were replaced in 20271229000000 with IS DISTINCT FROM hardening.
--   CREATE OR REPLACE preserves grants in Postgres, but explicit re-grant is
--   the safe defensive pattern against schema-cache reload edge cases.
-- =============================================================================
GRANT EXECUTE ON FUNCTION public.get_seller_balance(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_rider_balance(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_seller_ca_report(UUID, TIMESTAMPTZ, TIMESTAMPTZ) TO authenticated;


-- =============================================================================
-- FIX 3 + FIX 4: admin_get_finance_stats
--   Fixes TWO bugs in one CREATE OR REPLACE:
--     (a) Return key renamed: 'total_gmv' → 'gmv' (matches Dart client)
--     (b) pending_settlements now counts pending withdrawals, not delivered orders
--
--   PRESERVED UNCHANGED:
--     - is_active_admin security check
--     - GMV calculation logic (SUM across all orders minus refunded)
--     - pure_profit calculation (CASE expression across all statuses)
--     - seller_payouts calculation (with refund exclusion + wait_time_penalty)
--     - rider_earnings calculation (with wait_time_penalty)
--     - All ROUND() calls
--     - All COALESCE() wrapping
--     - The DEFINER and search_path
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

  -- GMV + Pure Profit across ALL orders (preserved logic from 20260801000000)
  SELECT
    COALESCE(SUM(
      CASE WHEN COALESCE(refund_status, 'none') = 'completed' THEN 0 ELSE grand_total_collected END
    ), 0),

    -- Pure Profit evaluates ACROSS ALL STATUSES so refunded/cancelled losses are calculated
    COALESCE(SUM(
      CASE
        WHEN COALESCE(refund_status, 'none') = 'completed' THEN
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
  FROM public.orders; -- DO NOT FILTER CANCELLED ORDERS (preserved comment from original)

  -- Seller payouts + Rider earnings (preserved logic from 20260801000000)
  SELECT
    COALESCE(SUM(
      CASE
        WHEN COALESCE(refund_status, 'none') IN ('processing', 'completed') THEN 0
        ELSE COALESCE(seller_payout, 0)
      END
      - COALESCE(wait_time_penalty, 0)
    ), 0),
    COALESCE(SUM(COALESCE(rider_earnings, 0) + COALESCE(wait_time_penalty, 0)), 0)
  INTO v_seller_payouts, v_rider_earnings
  FROM public.orders WHERE status = 'delivered';

  -- BUG 4 FIX: pending_settlements = count of PENDING WITHDRAWAL REQUESTS
  -- (previously was COUNT(*) of delivered orders which is semantically wrong)
  BEGIN
    SELECT COUNT(*) INTO v_pending_settlements
    FROM public.withdrawals WHERE status = 'pending';
  EXCEPTION WHEN OTHERS THEN
    v_pending_settlements := 0;
  END;

  RETURN jsonb_build_object(
    'gmv',                 ROUND(v_gmv, 2),           -- BUG 2 FIX: was 'total_gmv'
    'pure_profit',         ROUND(v_pure_profit, 2),
    'seller_payouts',      ROUND(v_seller_payouts, 2),
    'rider_earnings',      ROUND(v_rider_earnings, 2),
    'pending_settlements', v_pending_settlements
  );
END;
$$;

-- Re-grant (CREATE OR REPLACE preserves grants but explicit is defensive)
GRANT EXECUTE ON FUNCTION public.admin_get_finance_stats() TO authenticated;


-- =============================================================================
-- Notify PostgREST to reload schema cache so grants take effect immediately
-- =============================================================================
NOTIFY pgrst, 'reload schema';
