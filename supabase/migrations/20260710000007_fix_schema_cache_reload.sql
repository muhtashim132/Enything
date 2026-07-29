-- Migration: 20260710000007_fix_schema_cache_reload.sql
-- Description: Explicitly grant SELECT on KYC columns and reload PostgREST schema cache. Purely additive.

GRANT SELECT (aadhar_number, pan_number, driving_license) ON public.delivery_partners TO authenticated;
NOTIFY pgrst, 'reload schema';
