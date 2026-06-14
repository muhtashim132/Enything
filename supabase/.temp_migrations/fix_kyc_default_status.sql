-- ============================================================================
-- Migration: fix_kyc_default_status.sql
-- Description: Changes default KYC status from 'pending' to 'unverified'
-- to fix premature verification-in-progress screens.
-- ============================================================================

-- 1. Alter default values to 'unverified' so new signups don't default to pending
ALTER TABLE public.shops ALTER COLUMN verification_status SET DEFAULT 'unverified';
ALTER TABLE public.delivery_partners ALTER COLUMN verification_status SET DEFAULT 'unverified';

-- 2. Fix existing rows that were incorrectly set to 'pending' (if they haven't submitted KYC)
UPDATE public.shops 
SET verification_status = 'unverified' 
WHERE verification_status = 'pending' AND (kyc_documents IS NULL OR kyc_documents = '{}'::jsonb);

UPDATE public.delivery_partners 
SET verification_status = 'unverified' 
WHERE verification_status = 'pending' AND (kyc_documents IS NULL OR kyc_documents = '{}'::jsonb);

-- 3. Notify PostgREST to reload schema cache
NOTIFY pgrst, 'reload schema';
