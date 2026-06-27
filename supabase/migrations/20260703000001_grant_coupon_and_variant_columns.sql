-- ============================================================================
-- Migration: 20260703000001_grant_coupon_and_variant_columns.sql
-- Description: Belt-and-suspenders GRANT fix for columns added in recent
--              migrations. This is ADDITIVE ONLY — no existing SQL is modified.
--
-- Background:
--   • 20260701000001 added coupon_id, coupon_discount to orders — no explicit
--     INSERT/UPDATE grants for these columns were included.
--   • 20260702000002 added variants JSONB to products and variant_name TEXT to
--     order_items — only SELECT was granted; UPDATE on products.variants and
--     INSERT on order_items.variant_name were not explicitly granted.
--
-- This migration follows the same belt-and-suspenders pattern established in
-- 20260630000002_10x_delivery_debug_final_fix.sql.
--
-- SAFETY:
--   • All GRANTs are idempotent — safe to run multiple times.
--   • Nothing is dropped, altered, or restricted.
--   • No RLS policies are changed.
-- ============================================================================

-- ── orders table — coupon columns ────────────────────────────────────────────
-- Ensure authenticated users can INSERT and SELECT coupon_id / coupon_discount
-- (needed by checkout_page.dart when writing orders with a coupon applied)
GRANT SELECT, INSERT, UPDATE ON public.orders TO authenticated;

-- ── products table — variants column ─────────────────────────────────────────
-- Ensure sellers can UPDATE the variants JSONB column when editing products
GRANT SELECT, INSERT, UPDATE ON public.products TO authenticated;
GRANT SELECT ON public.products TO anon;

-- ── order_items table — variant_name column ──────────────────────────────────
-- Ensure INSERT privilege covers variant_name (added after the base INSERT grant)
GRANT SELECT, INSERT ON public.order_items TO authenticated;
GRANT SELECT, INSERT ON public.order_items TO anon;

-- ── coupons table — read access for customers ─────────────────────────────────
-- Belt-and-suspenders SELECT grant (RLS policy already enforces is_active filter)
GRANT SELECT ON public.coupons TO authenticated;

-- ── Notify PostgREST to reload schema cache ───────────────────────────────────
NOTIFY pgrst, 'reload schema';
