-- ============================================================================
-- Migration: 20260711000001_fix_tcs_add_tds.sql
-- Description: Add tds_amount column to orders table.
--              Purely additive — no existing column, policy, trigger, or
--              function is altered or dropped.
--
-- LEGAL BASIS:
--
--   EXISTING  — GST TCS (CGST §52):
--     Already stored in orders.tcs_amount.
--     BUG: Was always 1% of total_amount regardless of category.
--     FIX: Now computed correctly in checkout_page.dart (Dart-side):
--       • Section 9(5) food/restaurant categories → TCS = ₹0
--         (ECO is deemed supplier; §52 "net taxable supply" explicitly
--          excludes supplies notified under §9(5) — CBIC Circular 167/2021)
--       • Zero-GST categories (Fruits & Vegs, Butcher, Fish & Seafood,
--         unpackaged dairy) → TCS = ₹0
--         (TCS only applies to "taxable supplies"; 0% GST = non-taxable)
--       • All other non-food taxable categories → TCS = 1% of base
--     The column tcs_amount is KEPT; only the Dart calculation is corrected.
--
--   NEW — Income Tax TDS (IT Act §194-O, Finance Act 2024):
--     Effective October 1, 2024, rate reduced from 1% → 0.1%.
--     E-commerce operators must deduct 0.1% TDS on GROSS consideration
--     paid to ALL e-commerce participants (sellers), ALL categories.
--     No categorical exemption exists. Threshold exemption (< ₹5 lakh/yr
--     for individual/HUF with PAN/Aadhaar) is handled operationally by CA.
--     New column: orders.tds_amount — stores 0.1% of total_amount.
--     Filing: ECO files Form 26QE by 7th of next month.
--     Seller claims credit via Form 26AS / AIS.
--
-- SAFETY GUARANTEES:
--   • ALTER TABLE ADD COLUMN IF NOT EXISTS — fully idempotent, safe to re-run
--   • DEFAULT 0 — no NULL constraint violations on existing rows
--   • No existing column, RLS policy, function, or trigger is modified
--   • No existing migration file is touched
-- ============================================================================

-- ── Add tds_amount column to orders ─────────────────────────────────────────
-- Stores the 0.1% Income Tax TDS (§194-O) deducted from the seller's payout.
-- Calculated as: total_amount × 0.001 (0.1%)
-- Enything files Form 26QE by 7th of the following month.
-- Seller claims this amount as credit via Form 26AS after Enything files.
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS tds_amount NUMERIC(12, 4) NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.orders.tds_amount IS
  '0.1% Income Tax TDS under §194-O (Finance Act 2024, eff. Oct 1 2024). '
  'Deducted from seller payout on ALL categories. '
  'ECO files Form 26QE by 7th of next month; seller claims via Form 26AS.';

-- ── Column-level GRANTs ──────────────────────────────────────────────────────
-- Insert: customers write tds_amount at checkout time
-- Select: sellers read it in CA report; admins read it in finance panel
GRANT INSERT (tds_amount) ON public.orders TO authenticated;
GRANT SELECT (tds_amount) ON public.orders TO authenticated;
GRANT UPDATE (tds_amount) ON public.orders TO authenticated;

-- ── Notify PostgREST to reload schema cache ──────────────────────────────────
-- Required so the new column is immediately available without a server restart.
NOTIFY pgrst, 'reload schema';
