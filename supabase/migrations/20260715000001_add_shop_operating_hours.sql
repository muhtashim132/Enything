-- Migration: Add opening and closing times to shops table
-- This allows shops to have defined operating hours and automatically reflect as "closed"

ALTER TABLE public.shops 
ADD COLUMN IF NOT EXISTS open_time TIME WITHOUT TIME ZONE DEFAULT '00:00:00',
ADD COLUMN IF NOT EXISTS close_time TIME WITHOUT TIME ZONE DEFAULT '23:59:59';

-- Re-grant SELECT to ensure postgREST picks up the new columns for authenticated and anon users
GRANT SELECT ON public.shops TO anon, authenticated;
GRANT UPDATE (open_time, close_time) ON public.shops TO authenticated;
