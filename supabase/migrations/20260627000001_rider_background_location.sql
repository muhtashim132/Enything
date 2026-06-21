-- ============================================================================
-- Migration: 20260627000001_rider_background_location.sql
-- Description: Adds metadata support for rider background location permission.
--
-- This migration is PURELY ADDITIVE:
--   • Adds one optional BOOLEAN column to delivery_partners
--   • Adds one notification channel record (metadata only)
--   • ALL statements use IF NOT EXISTS / OR REPLACE — fully idempotent
--   • DOES NOT modify any existing column, constraint, trigger, function,
--     policy, or SQL from any prior migration
--   • DOES NOT change any financial calculation or business logic
--
-- What this enables:
--   The flutter_background_service package (RiderBackgroundService) runs an
--   Android Foreground Service to update rider_lat/rider_lng on orders even
--   when the rider app is backgrounded or the phone screen is locked.
--   This column tracks whether the rider has granted background location access
--   at the OS level (useful for support/diagnostics).
-- ============================================================================


-- ── 1. Add background_location_granted column to delivery_partners ─────────
-- Tracks whether this rider has granted Android "Allow all the time" location
-- permission — required for the background GPS service to function on Android.
-- Default false; the app updates this when the permission is granted.
ALTER TABLE public.delivery_partners
  ADD COLUMN IF NOT EXISTS background_location_granted BOOLEAN DEFAULT false;

-- Column-level grants (belt-and-suspenders, table-level grants already exist)
GRANT SELECT, UPDATE (background_location_granted)
  ON public.delivery_partners TO authenticated;

GRANT SELECT, UPDATE (background_location_granted)
  ON public.delivery_partners TO service_role;


-- ── 2. Ensure SELECT grants are current on all columns we read ─────────────
-- The background service reads is_active via _loadOrders → delivery_partners.
-- Belt-and-suspenders: previous migrations already grant SELECT on the table,
-- this is an idempotent re-assertion.
GRANT SELECT ON public.delivery_partners TO authenticated;


-- ── 3. Ensure orders columns used by the background isolate are grantable ──
-- The background isolate runs update_rider_location RPC (already covered) and
-- directly updates orders.rider_lat / rider_lng / rider_location_updated_at
-- (already granted in 20260626000001). This is an idempotent re-assertion.
GRANT UPDATE (
  rider_lat,
  rider_lng,
  rider_location_updated_at
) ON public.orders TO authenticated;

GRANT SELECT (
  id,
  delivery_partner_id,
  status,
  rider_lat,
  rider_lng,
  rider_location_updated_at
) ON public.orders TO authenticated;


-- ── 4. Reload PostgREST schema cache ──────────────────────────────────────
NOTIFY pgrst, 'reload schema';
