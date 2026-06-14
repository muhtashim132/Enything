-- ============================================================================
-- Migration: add_kyc_status_to_profiles.sql
-- Description: Adds kyc_status and verification_status columns to the
--              profiles table so admin KYC approve/reject can stamp the
--              user's profile record. Also adds the missing admin UPDATE
--              policy on profiles (previously only SELECT was allowed for
--              admins, causing a second silent failure even after the
--              columns are added).
-- ============================================================================

-- 1. Add the missing columns (safe to run multiple times)
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS kyc_status         TEXT NOT NULL DEFAULT 'unverified',
  ADD COLUMN IF NOT EXISTS verification_status TEXT NOT NULL DEFAULT 'unverified';

-- 2. Add admin UPDATE policy on profiles
--    (existing policies only allow a user to update their OWN profile;
--     admins need to update any user's profile when approving / rejecting KYC)
DROP POLICY IF EXISTS "profiles_admin_all" ON public.profiles;
CREATE POLICY "profiles_admin_all"
  ON public.profiles FOR ALL
  TO authenticated
  USING (public.is_active_admin(auth.uid()))
  WITH CHECK (public.is_active_admin(auth.uid()));

-- 3. Force PostgREST to reload its schema cache so the new columns are
--    immediately visible without a server restart (fixes PGRST204)
NOTIFY pgrst, 'reload schema';
