-- Add notification preference columns to profiles
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS notif_orders BOOLEAN DEFAULT true,
  ADD COLUMN IF NOT EXISTS notif_promos BOOLEAN DEFAULT true,
  ADD COLUMN IF NOT EXISTS notif_system BOOLEAN DEFAULT true;

-- Notify PostgREST to reload schema
NOTIFY pgrst, 'reload schema';
