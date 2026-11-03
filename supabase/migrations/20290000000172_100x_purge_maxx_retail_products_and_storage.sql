-- ==============================================================================
-- 100x Forensic Migration: Purge Maxx Retail Catalog & Free Storage Space
-- Target Shop: Maxx Retail (750b02ab-81f7-4023-929d-a9a00a8a8790)
-- 
-- Actions:
-- 1. Permanently removes all product photos and packshots from Supabase Storage
--    (bucket 'products' under folder '750b02ab-81f7-4023-929d-a9a00a8a8790/').
-- 2. Permanently deletes all products belonging to Maxx Retail from public.products.
-- 3. Provides public.admin_purge_shop_catalog_and_storage RPC for future use.
-- ==============================================================================

-- 1. Purge Supabase Storage packshots & pictures for Maxx Retail
DO $$
BEGIN
  DELETE FROM storage.objects 
  WHERE bucket_id = 'products' 
    AND name LIKE '750b02ab-81f7-4023-929d-a9a00a8a8790/%';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Storage purge notice: %', SQLERRM;
END $$;

-- 2. Hard delete all products for Maxx Retail to free database storage
DELETE FROM public.products 
WHERE shop_id = '750b02ab-81f7-4023-929d-a9a00a8a8790';

-- 3. Dedicated Admin Purge RPC for future maintenance & zero test leftover safety
CREATE OR REPLACE FUNCTION public.admin_purge_shop_catalog_and_storage(p_shop_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, storage
AS $$
DECLARE
  v_deleted_products INT := 0;
  v_deleted_storage INT := 0;
BEGIN
  -- Delete storage objects
  BEGIN
    DELETE FROM storage.objects
    WHERE bucket_id = 'products'
      AND name LIKE (p_shop_id::text || '/%');
    GET DIAGNOSTICS v_deleted_storage = ROW_COUNT;
  EXCEPTION WHEN OTHERS THEN
    v_deleted_storage := 0;
  END;

  -- Delete products
  DELETE FROM public.products
  WHERE shop_id = p_shop_id;
  GET DIAGNOSTICS v_deleted_products = ROW_COUNT;

  RETURN jsonb_build_object(
    'shop_id', p_shop_id,
    'deleted_products', v_deleted_products,
    'deleted_storage_objects', v_deleted_storage
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_purge_shop_catalog_and_storage(UUID) TO authenticated, service_role;
