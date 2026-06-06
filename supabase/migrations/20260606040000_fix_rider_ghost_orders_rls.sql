
-- Fix for Rider Ghost Orders
-- When a seller declines an order, its status becomes 'seller_rejected' or 'verification_failed'.
-- If the rider's SELECT RLS policy filters out these statuses, the row leaves their RLS scope.
-- Supabase Realtime does not send an UPDATE event, so the rider's app never removes the order.
-- FIX: Relax orders_select_available_rider to allow reading ALL orders with delivery_partner_id IS NULL.
-- The frontend already filters out cancelled/rejected orders via .inFilter() when querying.

DROP POLICY IF EXISTS "orders_select_available_rider" ON public.orders;
CREATE POLICY "orders_select_available_rider"
  ON public.orders FOR SELECT
  TO authenticated
  USING (
    delivery_partner_id IS NULL
    AND EXISTS (
      SELECT 1 FROM public.delivery_partners dp
      WHERE dp.id = auth.uid()
        AND (dp.is_active = true OR dp.is_available = true)
    )
  );
