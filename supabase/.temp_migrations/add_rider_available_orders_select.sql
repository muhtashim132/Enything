-- ============================================================================
-- Migration: add_rider_available_orders_select
-- Description: Allows online delivery partners to SELECT orders that are
--              unassigned (delivery_partner_id IS NULL) so the available-orders
--              pool is visible in the dashboard before accepting.
--
-- Previously the only rider SELECT policy was "orders_select_rider" which
-- only shows orders WHERE delivery_partner_id = auth.uid(). Unassigned orders
-- (the pool a rider browses and accepts) were invisible under strict RLS.
--
-- HOW TO RUN:
--   Supabase Dashboard → SQL Editor → paste & run.
-- ============================================================================

DROP POLICY IF EXISTS "orders_select_available_rider" ON public.orders;

-- Riders who are currently active (is_active = true) may browse the
-- unassigned, seller-accepted order pool.
CREATE POLICY "orders_select_available_rider"
  ON public.orders FOR SELECT
  TO authenticated
  USING (
    delivery_partner_id IS NULL
    AND seller_accepted = true
    AND status IN ('pending', 'confirmed')
    AND EXISTS (
      SELECT 1 FROM public.delivery_partners dp
      WHERE dp.id = auth.uid()
        AND dp.is_active = true
    )
  );

-- Notify PostgREST to reload schema cache
NOTIFY pgrst, 'reload schema';
