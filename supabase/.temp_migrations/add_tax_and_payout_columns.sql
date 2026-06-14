-- ============================================================================
-- Migration: add_tax_and_payout_columns.sql  (UPDATED — Add-On GST Model)
-- ============================================================================
--
-- WHAT CHANGED (Add-On GST Model):
--   Previously: prices were MRP (GST-inclusive). GST was extracted & informational.
--   Now: prices are BASE prices (pre-GST). GST is ADDED ON TOP at checkout.
--         gst_item_total now stores REAL GST collected from the customer.
--
-- COLUMN MEANINGS:
--   total_amount      — Base item subtotal (pre-GST). This is the seller's
--                       revenue figure used in analytics. GST is separate.
--   gst_item_total    — GST actually charged to the customer on items.
--                       For S9(5) food categories: Enything remits to govt.
--                       For retail/grocery: Enything passes to seller.
--   gst_delivery      — 18% GST inside delivery charge (Enything remits).
--   gst_platform      — 18% GST inside platform fee (Enything remits).
--   enything_commission  — Gross commission Enything charged (10.24% for UPI, 10% COD).
--   seller_payout     — What seller actually receives:
--                       (base − commission + non-food GST) − seller gateway share
--   gateway_deduction — Razorpay's 2.36% cut of the ENTIRE transaction (UPI only).
--
-- All amounts are in INR (₹). Columns default to 0 for backward-compat.
-- ============================================================================

ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS gst_item_total      NUMERIC(10, 2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS gst_delivery        NUMERIC(10, 2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS gst_platform        NUMERIC(10, 2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS enything_commission    NUMERIC(10, 2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS seller_payout       NUMERIC(10, 2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS gateway_deduction   NUMERIC(10, 2) NOT NULL DEFAULT 0;

-- ── OPTIONAL: Enything P&L View ────────────────────────────────────────────────
-- Run this manually in Supabase SQL editor if you want a live P&L dashboard.
-- Uncomment and execute separately.
--
-- CREATE OR REPLACE VIEW enything_order_pnl AS
-- SELECT
--   o.id,
--   o.created_at::DATE                                   AS order_date,
--   o.payment_method,
--   o.total_amount                                       AS item_base_subtotal,
--   o.gst_item_total                                     AS item_gst_collected,
--   (o.total_amount + o.gst_item_total)                  AS item_gross_total,
--   o.delivery_charges                                   AS delivery_collected,
--   o.gst_delivery,
--   o.platform_fee,
--   o.gst_platform,
--   (o.gst_item_total + o.gst_delivery + o.gst_platform) AS total_gst_in_order,
--   o.enything_commission,
--   o.gateway_deduction,
--   (o.enything_commission
--     + o.delivery_charges - o.gst_delivery
--     + o.platform_fee - o.gst_platform
--     - o.gateway_deduction)                             AS enything_approx_net_profit,
--   o.seller_payout,
--   o.rider_earnings
-- FROM orders o
-- WHERE o.status = 'delivered'
-- ORDER BY o.created_at DESC;

