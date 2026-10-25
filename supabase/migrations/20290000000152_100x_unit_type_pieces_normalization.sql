-- =============================================================================
-- Migration 20290000000152: 100x Unit Type 'pieces' Normalization Fortress
-- Description:
--   Fixes dropdown crash in Flutter seller AddProductPage where DropdownButton
--   expects 'pieces' (plural) from _availableUnitTypes, but database default
--   was 'piece' (singular).
--   Normalizes all historical records and updates defaults.
-- =============================================================================

-- 1. Normalize all existing product records
UPDATE public.products 
SET unit_type = 'pieces' 
WHERE unit_type IN ('piece', 'pc', 'pcs') OR unit_type IS NULL;

UPDATE public.products 
SET unit = 'pieces' 
WHERE unit = 'piece' OR unit IS NULL;

-- 2. Update column defaults to 'pieces'
ALTER TABLE public.products ALTER COLUMN unit_type SET DEFAULT 'pieces';
ALTER TABLE public.products ALTER COLUMN unit SET DEFAULT 'pieces';

-- 3. Update bulk_upload_shop_products RPC to normalize incoming unit_type
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
  v_skipped_count INT := 0;
  v_shop_exists BOOLEAN;
  v_shop_cat TEXT;
  v_unit_type TEXT;
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
    -- Check if product already exists for this shop (soft-delete rule: is_deleted = false)
    IF EXISTS (
      SELECT 1 FROM public.products 
      WHERE shop_id = p_shop_id 
        AND is_deleted = false 
        AND LOWER(TRIM(name)) = LOWER(TRIM(v_prod->>'name'))
    ) THEN
      v_skipped_count := v_skipped_count + 1;
    ELSE
      -- Normalize unit_type to 'pieces'
      v_unit_type := LOWER(TRIM(COALESCE(v_prod->>'unit_type', 'pieces')));
      IF v_unit_type IN ('piece', 'pc', 'pcs', '') THEN
        v_unit_type := 'pieces';
      END IF;

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
    'skipped', v_skipped_count
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.bulk_upload_shop_products(UUID, JSONB) TO anon, authenticated, service_role;
