-- 1. Snapshot shop coords onto orders at accept time
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS shop_lat  DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS shop_lng  DOUBLE PRECISION;

-- 2. Persist rider nav-app preference
ALTER TABLE public.delivery_partners
  ADD COLUMN IF NOT EXISTS preferred_nav_app TEXT DEFAULT 'google_maps';

-- 3. Vehicle type on delivery_partners
ALTER TABLE public.delivery_partners
  ADD COLUMN IF NOT EXISTS vehicle_type TEXT DEFAULT 'motorcycle';

-- Vehicle change requests (admin-approved)
CREATE TABLE IF NOT EXISTS public.vehicle_change_requests (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rider_id        UUID NOT NULL REFERENCES public.delivery_partners(id) ON DELETE CASCADE,
  requested_type  TEXT NOT NULL,
  status          TEXT NOT NULL DEFAULT 'pending', -- pending | approved | rejected
  admin_note      TEXT,
  requested_at    TIMESTAMPTZ DEFAULT now(),
  resolved_at     TIMESTAMPTZ
);
ALTER TABLE public.vehicle_change_requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY "rider_own" ON public.vehicle_change_requests
  FOR ALL USING (rider_id = auth.uid());

-- 4. Auto-accept toggle on delivery_partners
ALTER TABLE public.delivery_partners
  ADD COLUMN IF NOT EXISTS auto_accept BOOLEAN DEFAULT false;

-- Notify PostgREST to reload schema
NOTIFY pgrst, 'reload schema';
