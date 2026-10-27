-- ==============================================================================
-- 100x Migration: Bulk Upload Shop Products - Explicit Unlimited Inventory Support
-- 
-- Fixes: Sets total_quantity = (v_prod->>'total_quantity')::INT so that when
-- quantity is blank/null, total_quantity is strictly NULL in public.products,
-- guaranteeing unlimited inventory per Enything platform standards.
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
  v_total_qty INT;
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

    -- Normalize total_quantity (NULL if omitted/null/empty for unlimited inventory)
    IF v_prod ? 'total_quantity' AND v_prod->>'total_quantity' IS NOT NULL AND v_prod->>'total_quantity' != '' THEN
      v_total_qty := (v_prod->>'total_quantity')::INT;
    ELSE
      v_total_qty := NULL;
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
        total_quantity = v_total_qty,
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
        total_quantity,
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
        v_total_qty,
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
