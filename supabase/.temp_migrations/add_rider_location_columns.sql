-- Migration: add_rider_location_columns
-- Adds real-time rider GPS columns to orders so the customer
-- can see the delivery partner's live position on the track page.

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS rider_lat  DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS rider_lng  DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS rider_location_updated_at TIMESTAMPTZ;

-- Index for fast realtime lookups on active deliveries
CREATE INDEX IF NOT EXISTS idx_orders_rider_location
  ON public.orders (delivery_partner_id)
  WHERE status = 'out_for_delivery';
