-- ============================================================================
-- Migration: 20260622000002_sync_missing_customer_addresses.sql
-- Description: Syncs customers who provided an address during account creation
--              but are missing from the saved_addresses table because they
--              signed up before the trigger was implemented. Also fixes
--              any lingering Grant SELECT errors.
-- ============================================================================

-- Migrate stranded customers who have an address but no saved_addresses
INSERT INTO public.saved_addresses (
  user_id,
  label,
  address,
  landmark,
  pincode,
  latitude,
  longitude,
  is_default
)
SELECT
  c.id,
  'Home',
  COALESCE(NULLIF(TRIM(c.default_address), ''), NULLIF(TRIM(c.address), '')),
  COALESCE(TRIM(c.landmark), ''),
  COALESCE(TRIM(c.pincode), ''),
  -- Extract lat/lng if location exists
  CASE WHEN c.location IS NOT NULL THEN ST_Y(c.location::geometry) ELSE 0 END,
  CASE WHEN c.location IS NOT NULL THEN ST_X(c.location::geometry) ELSE 0 END,
  true
FROM public.customers c
JOIN auth.users u ON c.id = u.id
WHERE 
  -- Has some address
  (COALESCE(NULLIF(TRIM(c.default_address), ''), NULLIF(TRIM(c.address), '')) IS NOT NULL)
  -- Doesn't already have a saved address
  AND NOT EXISTS (
    SELECT 1 FROM public.saved_addresses sa WHERE sa.user_id = c.id
  )
ON CONFLICT DO NOTHING;

-- Explicitly grant permissions to ensure no "Grant SELECT error" occurs
GRANT SELECT, INSERT, UPDATE, DELETE ON public.saved_addresses TO authenticated;
REVOKE ALL ON public.saved_addresses FROM anon;
