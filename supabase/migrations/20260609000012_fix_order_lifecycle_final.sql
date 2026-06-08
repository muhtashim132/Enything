-- Fix BUG-CRON1: Ensure updated_at exists on orders
ALTER TABLE public.orders 
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- Auto-update updated_at on any orders change
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_orders_updated_at ON public.orders;
CREATE TRIGGER tr_orders_updated_at
  BEFORE UPDATE ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Fix BUG-RC1 at DB level: Add constraint that only one rider can claim
-- Fix RLS: riders can only UPDATE delivery_partner_id from NULL to their own ID
DROP POLICY IF EXISTS "orders_update_rider" ON public.orders;
CREATE POLICY "orders_update_rider"
  ON public.orders FOR UPDATE
  TO authenticated
  USING (
    delivery_partner_id = auth.uid()
    OR (
      delivery_partner_id IS NULL
      AND status IN ('awaiting_acceptance', 'pending', 'confirmed')
      AND EXISTS (
        SELECT 1 FROM public.delivery_partners dp
        WHERE dp.id = auth.uid()
          AND (dp.is_active = true OR dp.is_available = true)
      )
    )
  )
  WITH CHECK (
    -- When claiming: new delivery_partner_id must be the rider's own ID
    (delivery_partner_id = auth.uid())
  );

-- Fix: grant rider_phone write via authenticated role
GRANT UPDATE (rider_phone) ON public.orders TO authenticated;

-- Reload schema cache
NOTIFY pgrst, 'reload schema';
