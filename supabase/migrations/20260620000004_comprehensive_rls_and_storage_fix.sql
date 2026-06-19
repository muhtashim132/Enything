-- ============================================================================
-- Migration: 20260620000004_comprehensive_rls_and_storage_fix.sql
-- Description: Fixes Supabase Storage RLS policies to allow image uploads 
--              (INSERT/UPDATE/DELETE) for authenticated users. Adds safe 
--              policies for reviews/withdrawals if those tables exist.
-- ============================================================================

-- 1. Storage Objects RLS Fixes
-- Enable INSERT, UPDATE, DELETE for authenticated users on raw-product-images bucket
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'Public Access Insert Raw Images' AND tablename = 'objects' AND schemaname = 'storage'
  ) THEN
    CREATE POLICY "Public Access Insert Raw Images" ON storage.objects FOR INSERT TO authenticated WITH CHECK (bucket_id = 'raw-product-images');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'Public Access Update Raw Images' AND tablename = 'objects' AND schemaname = 'storage'
  ) THEN
    CREATE POLICY "Public Access Update Raw Images" ON storage.objects FOR UPDATE TO authenticated USING (bucket_id = 'raw-product-images') WITH CHECK (bucket_id = 'raw-product-images');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'Public Access Delete Raw Images' AND tablename = 'objects' AND schemaname = 'storage'
  ) THEN
    CREATE POLICY "Public Access Delete Raw Images" ON storage.objects FOR DELETE TO authenticated USING (bucket_id = 'raw-product-images');
  END IF;

  -- Also allow deletion of processed images if the user deletes their product
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'Public Access Delete Clean Cutouts' AND tablename = 'objects' AND schemaname = 'storage'
  ) THEN
    CREATE POLICY "Public Access Delete Clean Cutouts" ON storage.objects FOR DELETE TO authenticated USING (bucket_id = 'clean-cutouts');
  END IF;
END $$;

-- 2. Fallback check for 'reviews' and 'withdrawals' tables
-- If these tables were created manually without RLS, we ensure they have basic policies.
DO $$
BEGIN
  -- Handle 'reviews' table if it exists (using customer_id or user_id)
  IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'reviews') THEN
    ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;
    GRANT SELECT, INSERT, UPDATE ON public.reviews TO authenticated;
    
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Public can read reviews' AND tablename = 'reviews') THEN
      CREATE POLICY "Public can read reviews" ON public.reviews FOR SELECT TO anon, authenticated USING (true);
    END IF;

    IF EXISTS (SELECT FROM information_schema.columns WHERE table_name = 'reviews' AND column_name = 'user_id') THEN
      IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Users can insert reviews' AND tablename = 'reviews') THEN
        EXECUTE 'CREATE POLICY "Users can insert reviews" ON public.reviews FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid())';
      END IF;
    END IF;
  END IF;

  -- Handle 'withdrawals' table if it exists
  IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'withdrawals') THEN
    ALTER TABLE public.withdrawals ENABLE ROW LEVEL SECURITY;
    GRANT SELECT, INSERT, UPDATE ON public.withdrawals TO authenticated;
    
    IF EXISTS (SELECT FROM information_schema.columns WHERE table_name = 'withdrawals' AND column_name = 'seller_id') THEN
      IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Sellers can manage their own withdrawals' AND tablename = 'withdrawals') THEN
        EXECUTE 'CREATE POLICY "Sellers can manage their own withdrawals" ON public.withdrawals FOR ALL TO authenticated USING (seller_id = auth.uid()) WITH CHECK (seller_id = auth.uid())';
      END IF;
    END IF;
  END IF;
END $$;

-- Reload Schema Cache
NOTIFY pgrst, 'reload schema';
