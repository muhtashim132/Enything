-- ============================================================================
-- Migration: 20260630000002_10x_delivery_debug_final_fix.sql
-- Description: Final additive-only grants and safety fixes from the 10x
--              delivery/order flow debug pass.
--
-- BUGS FIXED:
--
--   BUG-RT1 FIX (Dart fix already applied — this adds DB-layer safety):
--     _retryOrder() now includes multi_shop_surcharge, small_cart_fee,
--     heavy_order_fee, delivery_discount, address_label, rider_earnings in
--     the INSERT. All columns already exist in the DB (added by prior
--     migrations: 20260614000002 and 20260630000001). This migration adds
--     explicit column-level INSERT grants so future column-ACL tightening
--     never silently breaks the retry flow.
--
--   BUG-PAY1 FIX (Dart fix already applied — this adds DB-layer safety):
--     _retryFindRider() now sets delivery_partner_id = NULL and
--     rider_phone = NULL. The existing orders_update_customer RLS policy
--     (USING: customer_id = auth.uid()) already permits this update.
--     This migration adds an explicit GRANT UPDATE on delivery_partner_id
--     and rider_phone (belt-and-suspenders — already covered by table-level
--     GRANT from 20260630000001, but making it explicit protects against
--     any future column-level ACL rollback).
--
--   BUG-GPS2 FIX (Dart fix already applied):
--     Dart code now includes 'awaiting_payment' in the GPS broadcast
--     activeStatuses list. No DB change needed.
--
--   BUG-OG1 FIX (Dart fix already applied):
--     order_group.dart groupStatus now correctly returns 'confirmed',
--     'ready_for_pickup', 'preparing' before falling back to
--     'pickup_in_progress'. No DB change needed.
--
--   BUG-ADDRESS_LABEL_GRANT (NEW FINDING):
--     address_label was added by 20260630000001 with a table-level
--     GRANT SELECT,INSERT,UPDATE ON orders. However, that migration
--     does NOT include address_label in any explicit column-level INSERT
--     GRANT list. For belt-and-suspenders correctness, we add it here.
--
-- SAFETY:
--   • All GRANTs are idempotent in Postgres (safe to re-run).
--   • No existing SQL is modified.
--   • No existing business logic is changed.
--   • No columns are created (all already exist).
--   • NOTIFY pgrst at end to reload schema cache.
-- ============================================================================


-- ============================================================================
-- PART 1: Explicit INSERT grants for retry-order fields
--
-- _retryOrder() in track_order_page.dart now inserts 6 additional fields
-- (BUG-RT1 fix). Belt-and-suspenders: add explicit column-level INSERT grants
-- for these columns in case table-level GRANT is ever rolled back or if
-- column-level ACL becomes more restrictive.
-- ============================================================================

GRANT INSERT (
  -- Core fields (were already granted, re-stating is idempotent)
  cart_group_id, shop_id, customer_id, status,
  acceptance_deadline, total_amount, delivery_charges, rider_earnings,
  platform_fee, address, delivery_lat, delivery_lng, delivery_notes,
  payment_method, payment_status, customer_phone, shop_phone,
  gst_item_total, gst_delivery, gst_platform,
  enything_commission, seller_payout, gateway_deduction,
  s9_5_gst_amount, non_food_gst_amount, tcs_amount,
  grand_total_collected, gst_rate_snapshot,
  estimated_distance_km, shop_prep_time_snapshot, prescription_urls,
  -- BUG-RT1 fields (now included in retry insert — explicit grant):
  multi_shop_surcharge,
  small_cart_fee,
  heavy_order_fee,
  delivery_discount,
  address_label
) ON public.orders TO authenticated;


-- ============================================================================
-- PART 2: Explicit UPDATE grants for Find-New-Rider fields
--
-- _retryFindRider() in track_order_page.dart now sets delivery_partner_id
-- and rider_phone to NULL (BUG-PAY1 fix).
-- delivery_partner_id and rider_phone are already in the UPDATE grant list
-- from 20260626000001 (L255, L270). Re-asserting idempotently here for
-- documentation clarity.
-- ============================================================================

GRANT UPDATE (
  -- BUG-PAY1: customer sets these to NULL on "Find New Rider"
  delivery_partner_id,
  rider_phone,
  -- Additional fields set by _retryFindRider: already granted but re-assert
  status,
  cancelled_reason,
  seller_accepted,
  partner_accepted,
  acceptance_deadline,
  -- BUG-ADDRESS_LABEL_GRANT: address_label added in 20260630000001 but
  -- not in any existing column-level UPDATE grant list.
  address_label
) ON public.orders TO authenticated;


-- ============================================================================
-- PART 3: SELECT grant for address_label
--
-- address_label is already readable via the table-level SELECT from
-- 20260630000001. Adding explicit column-level grant for belt-and-suspenders.
-- This ensures Supabase Realtime payloads include address_label in UPDATE
-- events even when column-level ACL is evaluated per-column.
-- ============================================================================

GRANT SELECT (
  address_label
) ON public.orders TO authenticated;

GRANT SELECT (
  address_label
) ON public.orders TO service_role;


-- ============================================================================
-- PART 4: Validate orders_update_customer allows setting delivery_partner_id
--         to NULL (BUG-PAY1 safety check).
--
-- The existing orders_update_customer policy (20260606020000) is:
--   USING (customer_id = auth.uid())
-- with no WITH CHECK clause, meaning ANY column update is allowed for the
-- customer's own order — including setting delivery_partner_id = NULL.
-- This is correct and intentional. No policy change needed.
--
-- NOTE: If orders_update_customer ever gets a WITH CHECK clause added,
-- ensure it permits delivery_partner_id = NULL (Find New Rider) and
-- delivery_partner_id = NULL (cancellation flow).
-- ============================================================================

-- (No SQL action needed — comment is the documentation)


-- ============================================================================
-- PART 5: Reload PostgREST schema cache
-- ============================================================================

NOTIFY pgrst, 'reload schema';
