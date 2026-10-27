-- ==============================================================================
-- 100x Forensic Migration: Bulk Upsert Shop Products & Safe Purge RPC
-- 
-- Fixes:
-- 1. Upgrades public.bulk_upload_shop_products to perform an UPSERT (UPDATE if exists)
--    so re-running auto-upload or menu digitization accurately updates variants,
--    prices, images, and descriptions instead of silently skipping existing rows.
-- 2. Adds public.bulk_delete_shop_products for clean test purging.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.bulk_upload_shop_products(
  p_shop_id UUID,
  p_products JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_prod JSONB;
  v_inserted_count INT := 0;
  v_updated_count INT := 0;
  v_skipped_count INT := 0;
  v_shop_exists BOOLEAN;
  v_shop_cat TEXT;
  v_unit_type TEXT;
  v_existing_id UUID;
BEGIN
  -- Verify shop exists
  SELECT EXISTS(SELECT 1 FROM public.shops WHERE id = p_shop_id), category
  INTO v_shop_exists, v_shop_cat
  FROM public.shops WHERE id = p_shop_id;

  IF NOT v_shop_exists THEN
    RAISE EXCEPTION 'Shop with ID % does not exist', p_shop_id;
  END IF;

  FOR v_prod IN SELECT * FROM jsonb_array_elements(p_products)
  LOOP
    -- Normalize unit_type to 'pieces'
    v_unit_type := LOWER(TRIM(COALESCE(v_prod->>'unit_type', 'pieces')));
    IF v_unit_type IN ('piece', 'pc', 'pcs', '') THEN
      v_unit_type := 'pieces';
    END IF;

    -- Check if active product already exists for this shop
    SELECT id INTO v_existing_id
    FROM public.products
    WHERE shop_id = p_shop_id
      AND is_deleted = false
      AND LOWER(TRIM(name)) = LOWER(TRIM(v_prod->>'name'))
    LIMIT 1;

    IF v_existing_id IS NOT NULL THEN
      -- UPDATE existing product with new details, variants, images, and prices
      UPDATE public.products SET
        price = (v_prod->>'price')::NUMERIC,
        description = NULLIF(TRIM(v_prod->>'description'), ''),
        category = COALESCE(NULLIF(TRIM(v_prod->>'category'), ''), v_shop_cat, 'Medical Store'),
        menu_category = COALESCE(NULLIF(TRIM(v_prod->>'menu_category'), ''), 'General / Wellness'),
        is_veg = (v_prod->>'is_veg')::BOOLEAN,
        is_available = COALESCE((v_prod->>'is_available')::BOOLEAN, true),
        weight_per_unit = (v_prod->>'weight_per_unit')::NUMERIC,
        unit_type = v_unit_type,
        images = COALESCE(v_prod->'images', images, '[]'::jsonb),
        variants = COALESCE(v_prod->'variants', '[]'::jsonb),
        is_deleted = false,
        updated_at = NOW()
      WHERE id = v_existing_id;

      v_updated_count := v_updated_count + 1;
    ELSE
      -- INSERT new product
      INSERT INTO public.products (
        shop_id,
        name,
        price,
        original_price,
        description,
        category,
        menu_category,
        is_veg,
        is_available,
        weight_per_unit,
        unit_type,
        images,
        requires_prescription,
        medicine_type,
        variants,
        bulk_eligible,
        is_deleted
      ) VALUES (
        p_shop_id,
        TRIM(v_prod->>'name'),
        (v_prod->>'price')::NUMERIC,
        NULL,
        NULLIF(TRIM(v_prod->>'description'), ''),
        COALESCE(NULLIF(TRIM(v_prod->>'category'), ''), v_shop_cat, 'Medical Store'),
        COALESCE(NULLIF(TRIM(v_prod->>'menu_category'), ''), 'General / Wellness'),
        (v_prod->>'is_veg')::BOOLEAN,
        COALESCE((v_prod->>'is_available')::BOOLEAN, true),
        (v_prod->>'weight_per_unit')::NUMERIC,
        v_unit_type,
        COALESCE(v_prod->'images', '[]'::jsonb),
        COALESCE((v_prod->>'requires_prescription')::BOOLEAN, false),
        COALESCE(NULLIF(TRIM(v_prod->>'medicine_type'), ''), 'General'),
        COALESCE(v_prod->'variants', '[]'::jsonb),
        false,
        false
      );
      v_inserted_count := v_inserted_count + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'inserted', v_inserted_count,
    'updated', v_updated_count,
    'skipped', v_skipped_count
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.bulk_upload_shop_products(UUID, JSONB) TO anon, authenticated, service_role;

-- Safe bulk delete RPC for test purging and catalog reset
CREATE OR REPLACE FUNCTION public.bulk_delete_shop_products(
  p_shop_id UUID,
  p_names TEXT[]
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_deleted_count INT := 0;
BEGIN
  DELETE FROM public.products
  WHERE shop_id = p_shop_id
    AND LOWER(TRIM(name)) = ANY(
      SELECT LOWER(TRIM(n)) FROM unnest(p_names) AS n
    );
  GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
  RETURN jsonb_build_object('deleted', v_deleted_count);
END;
$$;

GRANT EXECUTE ON FUNCTION public.bulk_delete_shop_products(UUID, TEXT[]) TO anon, authenticated, service_role;
