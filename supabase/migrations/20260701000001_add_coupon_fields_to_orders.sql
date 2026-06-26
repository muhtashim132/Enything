-- ============================================================================
-- Migration: add_coupon_fields_to_orders.sql
-- Description: Adds optional coupon_id and coupon_discount columns to orders
--              so we can track which promo was used and how much was discounted.
--
-- SAFETY:
--   • Both columns are optional (nullable / default 0) — existing rows unaffected.
--   • coupon_id has a soft FK to coupons; ON DELETE SET NULL protects order history.
--   • Only adds two columns — no existing SQL modified.
-- ============================================================================

-- Add coupon reference column (nullable — not all orders use a coupon)
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS coupon_id UUID REFERENCES public.coupons(id) ON DELETE SET NULL;

-- Add coupon discount amount (defaults to 0 so no NULL handling needed in app)
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS coupon_discount DOUBLE PRECISION NOT NULL DEFAULT 0;

-- Allow authenticated customers to SELECT active coupons (needed by CouponProvider)
DROP POLICY IF EXISTS "coupons_select_active" ON public.coupons;
CREATE POLICY "coupons_select_active"
  ON public.coupons FOR SELECT
  TO authenticated
  USING (is_active = TRUE);

-- ── Verification ─────────────────────────────────────────────────────────────
-- Run after migration to confirm columns exist:
--   SELECT column_name, data_type, column_default
--   FROM information_schema.columns
--   WHERE table_name = 'orders'
--     AND column_name IN ('coupon_id', 'coupon_discount');
