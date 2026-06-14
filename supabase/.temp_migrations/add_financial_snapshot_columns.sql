-- ============================================================================
-- Migration: add_financial_snapshot_columns.sql
-- Purpose  : Complete the Financial Snapshot Pattern for Enything
--            so every order is a legally-immutable tax record.
-- Law ref  : CGST Act 2017 §36 (6-year record retention),
--            GST Notification 17/2021-CT(R) §9(5) deemed supplier,
--            CGST §52 (TCS by ECO @ 1%).
-- ============================================================================
--
-- COLUMN MEANINGS:
--
--   s9_5_gst_amount      — GST on Section 9(5) food/restaurant items.
--                          Enything collects this and remits directly to Govt.
--                          Seller does NOT owe this. Used for GSTR-8 / GSTR-3B.
--
--   non_food_gst_amount  — GST on retail/grocery/pharma etc.
--                          Enything passes this to the seller in their payout.
--                          Seller must declare this in their own GSTR-1 & 3B.
--
--   tcs_amount           — 1% Tax Collected at Source (TCS) deducted by Enything
--                          from the net taxable supply paid to seller.
--                          Enything files GSTR-8 by 10th of next month.
--                          Seller claims this credit in their GSTR-2B.
--
--   grand_total_collected — Actual amount the customer paid (incl. all GST,
--                           delivery, platform fee). This is the true "turnover"
--                           figure for Enything's ECO reporting.
--
--   gst_rate_snapshot    — JSONB map of { category: gst_rate } for every item
--                          in this order. Frozen at order time so future GST
--                          rate changes never corrupt historical records.
--                          Example: {"Restaurant": 0.05, "Grocery": 0.05}
--
-- ============================================================================

ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS s9_5_gst_amount      NUMERIC(10, 2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS non_food_gst_amount   NUMERIC(10, 2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS tcs_amount            NUMERIC(10, 2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS grand_total_collected NUMERIC(10, 2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS gst_rate_snapshot     JSONB          NOT NULL DEFAULT '{}';

-- ── COMMENT each column for Supabase table editor clarity ─────────────────

COMMENT ON COLUMN orders.s9_5_gst_amount IS
  'GST on S.9(5) food/restaurant items — Enything remits to Govt. Not seller liability.';

COMMENT ON COLUMN orders.non_food_gst_amount IS
  'GST on retail/grocery/pharma — passed to seller who remits in GSTR-1/3B.';

COMMENT ON COLUMN orders.tcs_amount IS
  '1% TCS deducted from seller net payout per CGST §52. Enything files GSTR-8 by 10th.';

COMMENT ON COLUMN orders.grand_total_collected IS
  'Actual INR amount collected from customer including all taxes and fees.';

COMMENT ON COLUMN orders.gst_rate_snapshot IS
  'Frozen JSONB snapshot of {category:rate} used at checkout. Immutable for audits.';

-- ============================================================================
-- CA Monthly GST Report View
-- ============================================================================
-- This view is what you share with your Chartered Accountant every month.
-- It produces exactly the 4 documents needed:
--   1. Sales Register   → total_base_sales, non_food_gst_seller_remits (GSTR-1)
--   2. Commission Invoice → total_commission (CA claims ITC for Enything's service)
--   3. Section 9(5) Statement → s9_5_gst_enything_remits (proves Enything paid food GST)
--   4. TCS Statement    → tcs_collected (GSTR-8 / seller's GSTR-2B credit)
-- ============================================================================

CREATE OR REPLACE VIEW ca_monthly_gst_report AS
SELECT
  DATE_TRUNC('month', o.created_at)    AS tax_period,
  TO_CHAR(o.created_at, 'Mon YYYY')   AS period_label,
  o.shop_id,
  s.name                               AS shop_name,

  -- ── Volume ───────────────────────────────────────────────────────────────
  COUNT(*)                             AS delivered_orders,

  -- ── 1. Sales Register (GSTR-1 inputs) ───────────────────────────────────
  ROUND(SUM(o.total_amount), 2)        AS taxable_base_sales,
  ROUND(SUM(o.non_food_gst_amount), 2) AS gst_seller_must_remit,      -- GSTR-1/3B liability
  ROUND(SUM(o.s9_5_gst_amount), 2)     AS gst_enything_remits_s9_5,      -- Exempt for seller
  ROUND(SUM(o.gst_delivery), 2)        AS delivery_gst_enything,
  ROUND(SUM(o.gst_platform), 2)        AS platform_gst_enything,

  -- ── 2. Commission Invoice (ITC for seller) ────────────────────────────
  ROUND(SUM(o.enything_commission), 2)    AS enything_commission_total,
  ROUND(SUM(o.enything_commission) * 0.18, 2) AS gst_on_commission_itc, -- 18% GST on commission

  -- ── 3. TCS Statement (GSTR-8 / GSTR-2B) ─────────────────────────────
  ROUND(SUM(o.tcs_amount), 2)          AS tcs_deducted_by_enything,

  -- ── 4. Payout Reconciliation ──────────────────────────────────────────
  ROUND(SUM(o.seller_payout), 2)       AS net_seller_payout,
  ROUND(SUM(o.grand_total_collected), 2) AS gross_collected_from_customers,
  ROUND(SUM(o.gateway_deduction), 2)   AS razorpay_deductions

FROM orders o
JOIN shops  s ON s.id = o.shop_id
WHERE o.status = 'delivered'
GROUP BY
  DATE_TRUNC('month', o.created_at),
  TO_CHAR(o.created_at, 'Mon YYYY'),
  o.shop_id,
  s.name
ORDER BY tax_period DESC, shop_name;

-- ── Enything-wide P&L view (for Enything admin, not sellers) ────────────────────

CREATE OR REPLACE VIEW enything_pnl_monthly AS
SELECT
  DATE_TRUNC('month', created_at)       AS month,
  COUNT(*)                              AS orders,
  ROUND(SUM(grand_total_collected), 2)  AS total_collected,
  ROUND(SUM(enything_commission), 2)       AS commission_revenue,
  ROUND(SUM(platform_fee - gst_platform), 2) AS platform_net,
  ROUND(SUM(delivery_charges - gst_delivery), 2) AS delivery_net,
  ROUND(SUM(s9_5_gst_amount + gst_delivery + gst_platform), 2) AS gst_enything_must_remit,
  ROUND(SUM(tcs_amount), 2)             AS tcs_collected_gstr8,
  ROUND(SUM(gateway_deduction), 2)      AS gateway_paid_to_razorpay,
  ROUND(SUM(seller_payout), 2)          AS paid_out_to_sellers,
  ROUND(SUM(rider_earnings), 2)         AS paid_out_to_riders
FROM orders
WHERE status = 'delivered'
GROUP BY DATE_TRUNC('month', created_at)
ORDER BY month DESC;

-- ============================================================================
-- Enything Master Transaction Log (for Enything admin)
-- ============================================================================
-- Detailed order-by-order financial ledger for platform audits.
-- Provides complete visibility into the tax breakdown of every single order.

CREATE OR REPLACE VIEW enything_master_transactions AS
SELECT
  o.id                                 AS order_id,
  o.created_at                         AS transaction_date,
  s.name                               AS shop_name,
  
  ROUND(o.total_amount, 2)             AS base_sales_amount,
  ROUND(o.non_food_gst_amount, 2)      AS gst_seller_remits_retail,
  ROUND(o.s9_5_gst_amount, 2)          AS gst_enything_remits_s9_5_food,
  o.gst_rate_snapshot                  AS gst_rates_applied,
  
  ROUND(o.enything_commission, 2)         AS enything_commission_revenue,
  ROUND(o.tcs_amount, 2)               AS tcs_withheld_gstr8,
  
  ROUND(o.gst_delivery, 2)             AS delivery_gst,
  ROUND(o.gst_platform, 2)             AS platform_gst,
  ROUND(o.gateway_deduction, 2)        AS razorpay_gateway_fee,
  
  ROUND(o.seller_payout, 2)            AS net_seller_payout,
  ROUND(o.rider_earnings, 2)           AS net_rider_payout,
  ROUND(o.grand_total_collected, 2)    AS gross_customer_payment
FROM orders o
JOIN shops s ON s.id = o.shop_id
WHERE o.status = 'delivered'
ORDER BY o.created_at DESC;

