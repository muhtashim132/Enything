-- ============================================================================
-- Migration: fix_rider_realtime_rls
-- Description: Updates the 'orders_select_available_rider' policy to include
--              the 'awaiting_acceptance' status, allowing delivery partners
--              to view new orders that are waiting for acceptance.
-- ============================================================================

DROP POLICY IF EXISTS "orders_select_available_rider" ON public.orders;

CREATE POLICY "orders_select_available_rider"
  ON public.orders FOR SELECT
  TO authenticated
  USING (
    delivery_partner_id IS NULL
    AND status IN ('pending', 'confirmed', 'awaiting_acceptance')
    AND EXISTS (
      SELECT 1 FROM public.delivery_partners dp
      WHERE dp.id = auth.uid()
        AND dp.is_active = true
    )
  );

-- Notify PostgREST to reload schema cache
NOTIFY pgrst, 'reload schema';
