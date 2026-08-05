-- =============================================================================
-- Migration: 100x Rider Fast-Fail RLS Fix
-- Description:
--   The frontend uses a fast-fail `.select('status')` before calling the RPC.
--   If a rider is online (`is_accepting_orders` = true) but their account hasn't
--   been marked `is_active` = true, the RLS policy blocks the read, returning null.
--   This causes a false "This order is no longer available to accept" error.
--   This migration updates the RLS policy to align with the app's online toggle.
-- =============================================================================

DROP POLICY IF EXISTS "orders_select_available_rider" ON public.orders;

CREATE POLICY "orders_select_available_rider"
  ON public.orders FOR SELECT
  TO authenticated
  USING (
    delivery_partner_id IS NULL
    AND EXISTS (
      SELECT 1 FROM public.delivery_partners dp
      WHERE dp.id = auth.uid()
        AND (dp.is_active = true OR dp.is_available = true OR dp.is_accepting_orders = true)
    )
  );
