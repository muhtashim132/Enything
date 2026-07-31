-- =============================================================================
-- Migration: 20271240000000_fix_approved_shops_is_active.sql
-- Description: ADDITIVE DATA FIX — Sets is_active = true for shops whose
--              verification_status is 'approved' or 'verified' but whose
--              is_active is still false.
--
--              This covers the known case where:
--              a) Shop was approved (verification_status = 'approved')
--              b) Seller uninstalled / reinstalled the app, triggering
--                 auto_deactivate_shop_on_uninstall which set is_active = false
--              c) Shop became invisible to customers permanently
--
--              After is_active is restored the auto-sync trigger from
--              migration 20271239000000 will immediately compute the correct
--              is_accepting_orders value based on operating hours.
--
--              ADDITIVE ONLY: Touches ONLY rows that are provably wrong
--              (approved/verified + inactive). Zero impact on shops that are
--              correctly inactive (e.g. pending KYC).
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 1 ─ Restore is_active for all approved/verified-but-inactive shops
--           The UPDATE on is_active fires the trg_sync_shop_hours trigger which
--           immediately computes and sets the correct is_accepting_orders too.
-- ─────────────────────────────────────────────────────────────────────────────
UPDATE public.shops
SET is_active = true
WHERE verification_status IN ('approved', 'verified')
  AND is_active = false;

-- ─────────────────────────────────────────────────────────────────────────────
-- STEP 2 ─ Safety net: run the full hour-sync explicitly just in case the
--           trigger didn't fire (e.g. open_time/close_time weren't part of
--           the UPDATE column list, so trigger only fires if those cols change).
--           Running the cron function directly guarantees current state is right.
-- ─────────────────────────────────────────────────────────────────────────────
SELECT public.sync_shop_accepting_orders_by_hours();
