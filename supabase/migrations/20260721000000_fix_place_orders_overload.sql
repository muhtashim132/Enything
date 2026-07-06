-- =============================================================================
-- Migration: Fix place_orders_transaction overload
-- Description: Drops the old 2-argument version of the function to resolve
-- PostgREST PGRST203 Multiple Choices error during checkout without a coupon.
-- =============================================================================

DROP FUNCTION IF EXISTS place_orders_transaction(jsonb, jsonb);
