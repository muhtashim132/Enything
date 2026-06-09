-- ============================================================================
-- Migration: 20260609000016_allow_delivery_kyc_select.sql
-- Description: Grants SELECT privileges on KYC document columns for delivery
--              partners to the authenticated role.
--              Since delivery_partners has Row Level Security (RLS) restricting
--              reads to only the partner themselves (id = auth.uid()), it is
--              safe to expose these columns to standard SELECT queries.
-- ============================================================================

GRANT SELECT (aadhar_number, pan_number, driving_license)
ON public.delivery_partners TO authenticated;
