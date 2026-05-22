-- ============================================================================
-- Migration: remove_phone_otps.sql
-- Description: Drops the phone_otps table and its policies as OTP verification
--              is now handled entirely by Firebase Authentication.
-- ============================================================================

-- Drop the table (this will automatically cascade and drop associated RLS policies)
DROP TABLE IF EXISTS public.phone_otps CASCADE;
