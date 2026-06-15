-- ============================================================================
-- Background Removal Pipeline Setup
-- 1. Add cutout_url column to products table
-- 2. Grant service_role access to storage schema for webhooks
-- ============================================================================

-- Add cutout_url to products table (stores the transparent PNG URL)
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS cutout_url TEXT;

-- Grant SELECT on storage.objects for webhook routing
GRANT SELECT ON TABLE storage.objects TO service_role;

-- Ensure authenticated users can read cutout_url on products
GRANT SELECT (cutout_url) ON public.products TO authenticated;
GRANT SELECT (cutout_url) ON public.products TO anon;

-- Allow the service_role to update cutout_url (used by the Edge Function)
GRANT UPDATE (cutout_url) ON public.products TO service_role;
