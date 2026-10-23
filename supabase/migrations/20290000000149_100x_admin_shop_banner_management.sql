-- ============================================================================
-- Migration: 20290000000149_100x_admin_shop_banner_management.sql
-- Description: 100x Forensic Parity & Admin Restaurant/Shop Banner Management
-- 
-- 1. Ensures storage bucket 'shops' is public with proper RLS policies.
-- 2. Provides atomic RPC: admin_update_shop_banner with dual-column sync
--    (banner_url and banner_image).
-- 3. Enforces strict admin RBAC and URL sanitization.
-- ============================================================================

-- STEP 1: Storage Bucket Configuration for 'shops'
INSERT INTO storage.buckets (id, name, public)
VALUES ('shops', 'shops', true)
ON CONFLICT (id) DO UPDATE SET public = true;

GRANT USAGE ON SCHEMA storage TO anon, authenticated;
GRANT ALL ON storage.objects TO anon, authenticated;
GRANT ALL ON storage.buckets TO anon, authenticated;

DO $$
BEGIN
    -- Public Read Access for shops bucket
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE policyname = 'Public Access Shops' AND tablename = 'objects' AND schemaname = 'storage'
    ) THEN
        CREATE POLICY "Public Access Shops" ON storage.objects 
        FOR SELECT 
        USING (bucket_id = 'shops');
    END IF;

    -- Authenticated Upload Access for banners folder
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE policyname = 'Authenticated Upload Shops Banners' AND tablename = 'objects' AND schemaname = 'storage'
    ) THEN
        CREATE POLICY "Authenticated Upload Shops Banners" ON storage.objects 
        FOR INSERT TO authenticated 
        WITH CHECK (bucket_id = 'shops' AND name LIKE 'banners/%');
    END IF;

    -- Authenticated Update Access for banners folder
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE policyname = 'Authenticated Update Shops Banners' AND tablename = 'objects' AND schemaname = 'storage'
    ) THEN
        CREATE POLICY "Authenticated Update Shops Banners" ON storage.objects 
        FOR UPDATE TO authenticated 
        USING (bucket_id = 'shops' AND name LIKE 'banners/%')
        WITH CHECK (bucket_id = 'shops' AND name LIKE 'banners/%');
    END IF;

    -- Authenticated Delete Access for banners folder
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies WHERE policyname = 'Authenticated Delete Shops Banners' AND tablename = 'objects' AND schemaname = 'storage'
    ) THEN
        CREATE POLICY "Authenticated Delete Shops Banners" ON storage.objects 
        FOR DELETE TO authenticated 
        USING (bucket_id = 'shops' AND name LIKE 'banners/%');
    END IF;
END $$;


-- STEP 2: Atomic RPC admin_update_shop_banner
CREATE OR REPLACE FUNCTION public.admin_update_shop_banner(
  p_shop_id UUID,
  p_banner_url TEXT
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_shop RECORD;
  v_clean_url TEXT;
BEGIN
  -- Strict Authorization Barrier: Admin or Super Admin
  IF NOT (public.is_active_admin(auth.uid()) OR public.is_super_admin(auth.uid())) THEN
    RAISE EXCEPTION 'Access denied: platform admin only';
  END IF;

  -- Clean and sanitize URL: trim whitespace, empty string converts to NULL
  v_clean_url := NULLIF(TRIM(p_banner_url), '');

  IF v_clean_url IS NOT NULL AND LENGTH(v_clean_url) > 1000 THEN
    RAISE EXCEPTION 'Banner URL exceeds maximum allowed length of 1000 characters';
  END IF;

  -- Atomically update both banner_url and banner_image in shops to maintain 100% parity
  UPDATE public.shops
  SET 
    banner_url = v_clean_url,
    banner_image = v_clean_url,
    updated_at = NOW()
  WHERE id = p_shop_id
  RETURNING id, name, banner_url, banner_image, is_active, is_accepting_orders
  INTO v_shop;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Shop with ID % not found', p_shop_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'id', v_shop.id,
    'name', v_shop.name,
    'banner_url', v_shop.banner_url,
    'banner_image', v_shop.banner_image,
    'is_active', v_shop.is_active,
    'is_accepting_orders', v_shop.is_accepting_orders
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_update_shop_banner(UUID, TEXT) TO authenticated;

-- Force schema cache reload
NOTIFY pgrst, 'reload schema';
