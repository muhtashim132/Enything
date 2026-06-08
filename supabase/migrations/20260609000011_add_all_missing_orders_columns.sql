-- ============================================================================
-- Migration: 20260609000011_add_all_missing_orders_columns.sql
-- Description: Adds ALL columns that are read/written by Dart code but have
--              no corresponding CREATE/ALTER in any existing migration.
--
-- GAP ANALYSIS SUMMARY:
--
-- CONFIRMED MISSING (no migration found):
--   orders:
--     - multi_shop_surcharge    (read by OrderModel.fromMap, used in grandTotal)
--     - arrived_at_shop_time    (read by OrderModel.fromMap, rider arrival geofencing)
--     - order_ready_time        (read by OrderModel.fromMap, wait-time penalty calc)
--     - wait_time_penalty       (read/written by delivery dashboard)
--     - wait_time_disputed      (read by OrderModel.fromMap)
--     - has_customer_rated      (read/written by track_order_page)
--     - has_seller_rated        (read by OrderModel.fromMap)
--     - has_delivery_rated      (read by OrderModel.fromMap)
--     - rider_lat / rider_lng / rider_location_updated_at (live GPS, shown on map)
--     - delivery_lat / delivery_lng (customer address snapshot)
--     - payment_deadline        (10-min payment countdown)
--     - acceptance_deadline     (2-min acceptance countdown)
--     - seller_accepted / partner_accepted (dual-acceptance flags)
--     - gst_item_total / gst_delivery / gst_platform (GST breakdown)
--     - enything_commission / seller_payout / gateway_deduction (payout fields)
--
--   order_items:
--     - special_instructions    (read by OrderItem.fromMap, used in cart)
--     - weight_kg               (read by OrderItem.fromMap, used in weight calc)
--
-- CONFIRMED PRESENT (existing migrations):
--   orders: cancelled_reason, rejection_message, cart_group_id, shop_lat, shop_lng,
--           estimated_distance_km, shop_prep_time_snapshot, prescription_urls,
--           s9_5_gst_amount, non_food_gst_amount, tcs_amount, grand_total_collected,
--           gst_rate_snapshot, razorpay_payment_id, razorpay_order_id,
--           rider_phone, customer_phone, shop_phone, payment_method, payment_status,
--           delivery_notes, address, rider_earnings, platform_fee, delivery_charges
--   delivery_partners: auto_accept (present, now disabled by prior migration),
--                      preferred_nav_app, vehicle_type
--
-- ALL statements use ADD COLUMN IF NOT EXISTS so this migration is fully idempotent
-- and safe to re-run multiple times.
-- ============================================================================

-- ── ORDERS: Dual-acceptance flags ───────────────────────────────────────────
-- Written by seller_orders_page and delivery/dashboard_page on accept.
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS seller_accepted  BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS partner_accepted BOOLEAN NOT NULL DEFAULT false;

-- ── ORDERS: Acceptance & payment countdown deadlines ────────────────────────
-- Set at order creation (acceptance_deadline) and when both parties accept (payment_deadline).
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS acceptance_deadline TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS payment_deadline    TIMESTAMPTZ;

-- ── ORDERS: Customer delivery GPS (snapshotted at checkout) ─────────────────
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS delivery_lat DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS delivery_lng DOUBLE PRECISION;

-- ── ORDERS: Rider live GPS (updated every 15s during out_for_delivery) ───────
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS rider_lat                 DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS rider_lng                 DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS rider_location_updated_at TIMESTAMPTZ;

-- ── ORDERS: Wait-time / dispute fields ──────────────────────────────────────
-- arrived_at_shop_time: set when rider taps "Arrived at Shop"
-- order_ready_time:     set when seller marks "Ready for Pickup"
-- wait_time_penalty:    ₹ compensation owed to rider if shop was slow
-- wait_time_disputed:   true if rider disputed the wait
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS arrived_at_shop_time TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS order_ready_time     TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS wait_time_penalty    NUMERIC(10, 2) NOT NULL DEFAULT 0.0,
  ADD COLUMN IF NOT EXISTS wait_time_disputed   BOOLEAN NOT NULL DEFAULT false;

-- ── ORDERS: Customer / Seller / Rider rating flags ───────────────────────────
-- Prevent re-showing the rating prompt when user re-opens the order page.
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS has_customer_rated  BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS has_seller_rated    BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS has_delivery_rated  BOOLEAN NOT NULL DEFAULT false;

-- ── ORDERS: Multi-shop surcharge ─────────────────────────────────────────────
-- Extra fee charged when a customer orders from 2+ shops in one checkout.
-- Read by OrderModel.grandTotal for display and by admin finance page.
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS multi_shop_surcharge NUMERIC(10, 2) NOT NULL DEFAULT 0.0;

-- ── ORDERS: GST breakdown columns ────────────────────────────────────────────
-- gst_item_total: total GST added on top of item prices (add-on model)
-- gst_delivery:   18% GST embedded in delivery charge (Enything remits)
-- gst_platform:   18% GST embedded in platform fee (Enything remits)
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS gst_item_total NUMERIC(10, 2) NOT NULL DEFAULT 0.0,
  ADD COLUMN IF NOT EXISTS gst_delivery   NUMERIC(10, 2) NOT NULL DEFAULT 0.0,
  ADD COLUMN IF NOT EXISTS gst_platform   NUMERIC(10, 2) NOT NULL DEFAULT 0.0;

-- ── ORDERS: Payout & commission breakdown ────────────────────────────────────
-- enything_commission: gross commission on base subtotal (5%)
-- seller_payout:       net amount sent to seller's bank
-- gateway_deduction:   Razorpay fee absorbed by Enything
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS enything_commission NUMERIC(10, 2) NOT NULL DEFAULT 0.0,
  ADD COLUMN IF NOT EXISTS seller_payout       NUMERIC(10, 2) NOT NULL DEFAULT 0.0,
  ADD COLUMN IF NOT EXISTS gateway_deduction   NUMERIC(10, 2) NOT NULL DEFAULT 0.0;

-- ── ORDER_ITEMS: Missing columns ─────────────────────────────────────────────
-- weight_kg:             used in delivery charge + heavy order fee calculation
-- special_instructions:  customer note per item (e.g. "no onion")
--                        stored in cart_provider and copied to order at checkout
ALTER TABLE public.order_items
  ADD COLUMN IF NOT EXISTS weight_kg            NUMERIC(10, 3) NOT NULL DEFAULT 0.0,
  ADD COLUMN IF NOT EXISTS special_instructions TEXT;

-- ── ORDER_ITEMS: Grant SELECT to authenticated ───────────────────────────────
-- The existing RLS policy (order_items_select_involved) allows customers,
-- sellers, and riders to SELECT. But the column-level grant may be missing
-- for the new columns if the policy uses SELECT (*).
-- A full GRANT at table level (already done by prior migrations) covers them.
GRANT SELECT, INSERT ON public.order_items TO authenticated;

-- ── INDEXES for new columns ───────────────────────────────────────────────────
-- Fast lookup for rider tracking subscription
CREATE INDEX IF NOT EXISTS idx_orders_delivery_partner_status
  ON public.orders (delivery_partner_id, status);

-- Fast lookup for countdown deadline scanning (cron jobs)
CREATE INDEX IF NOT EXISTS idx_orders_acceptance_deadline
  ON public.orders (acceptance_deadline)
  WHERE status = 'awaiting_acceptance';

CREATE INDEX IF NOT EXISTS idx_orders_payment_deadline
  ON public.orders (payment_deadline)
  WHERE status = 'awaiting_payment';

-- ── Reload PostgREST schema cache ────────────────────────────────────────────
NOTIFY pgrst, 'reload schema';
