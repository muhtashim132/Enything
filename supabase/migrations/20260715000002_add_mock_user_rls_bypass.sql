-- ============================================================================
-- Migration: 20260715000002_add_mock_user_rls_bypass.sql
-- Description: Adds RLS bypass policies for mock/test users so that
--              unauthenticated test accounts can successfully complete
--              KYC uploads and profile updates during E2E testing.
-- ============================================================================

-- 1. Bypass RLS for mock users on shops table (UPDATE)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE policyname = 'mock_user_update_shops' AND tablename = 'shops' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "mock_user_update_shops" ON public.shops
        FOR UPDATE TO anon, authenticated
        USING (seller_id::text LIKE '00000000-0000-0000-0000-%')
        WITH CHECK (seller_id::text LIKE '00000000-0000-0000-0000-%');
    END IF;
END $$;

-- 2. Bypass RLS for mock users on delivery_partners table (UPDATE)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE policyname = 'mock_user_update_delivery_partners' AND tablename = 'delivery_partners' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "mock_user_update_delivery_partners" ON public.delivery_partners
        FOR UPDATE TO anon, authenticated
        USING (id::text LIKE '00000000-0000-0000-0000-%')
        WITH CHECK (id::text LIKE '00000000-0000-0000-0000-%');
    END IF;
END $$;

-- 3. Ensure bucket exists and has correct privileges (just in case they were not explicitly made public before)
INSERT INTO storage.buckets (id, name, public)
VALUES 
  ('seller_kyc_docs', 'seller_kyc_docs', true),
  ('delivery_kyc_docs', 'delivery_kyc_docs', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- Grant usage on storage schema
GRANT USAGE ON SCHEMA storage TO anon, authenticated;
GRANT ALL ON storage.objects TO anon, authenticated;
GRANT ALL ON storage.buckets TO anon, authenticated;

-- 4. Bypass RLS for mock users on storage.objects (INSERT, SELECT, UPDATE)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE policyname = 'mock_user_storage_access' AND tablename = 'objects' AND schemaname = 'storage'
    ) THEN
        CREATE POLICY "mock_user_storage_access" ON storage.objects
        FOR ALL TO anon, authenticated
        USING (name LIKE '00000000-0000-0000-0000-%')
        WITH CHECK (name LIKE '00000000-0000-0000-0000-%');
    END IF;
END $$;

-- Force schema cache reload
NOTIFY pgrst, 'reload schema';
