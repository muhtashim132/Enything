-- ==============================================================================
-- Migration 20290000000167: 100x Catalog Unit Type Inference & Bulk Upload Fortress
-- 
-- Fixes:
-- 1. Catalog Unit Remediation:
--    Retrofits all existing product records across public.products where unit_type
--    was defaulted to 'pieces'. Uses regex pattern matching on name and variants to
--    correctly assign 'ml', 'grams', 'kg', or 'liter'.
-- 2. Bulk Upload Intelligence:
--    Upgrades public.bulk_upload_shop_products to auto-infer unit_type from product
--    name and variants whenever unit_type is missing or 'pieces'.
--    Guarantees synchronization of both `unit_type` and legacy `unit` columns.
-- 3. Dedicated Remediation RPC:
--    Exposes public.remediate_catalog_product_units() for instant zero-downtime
--    catalog-wide unit harmonization.
-- ==============================================================================

-- 1. Liquids (ml)
UPDATE public.products
SET unit_type = 'ml', unit = 'ml'
WHERE is_deleted = false
  AND (
    name ~* '\m\d+(\.\d+)?\s*(ml|milliliter|milli\s*litre)\M'
    OR variants::text ~* '\m\d+(\.\d+)?\s*(ml|milliliter|milli\s*litre)\M'
    OR (
      unit_type IN ('pieces', 'piece', 'pc', 'pcs', '')
      AND name ~* '\m(perfume|edp|edt|cologne|mist|body spray|shampoo|conditioner|body wash|shower gel|face wash|lotion|serum|hair oil|toner|cleanser|micellar)\M'
      AND name !~* '\m(soap|powder|cream|butter|wax|scrub|strip|patch|roller|sponge|kit)\M'
    )
  );

-- 2. Solids, Creams, Gels, Powders (grams)
UPDATE public.products
SET unit_type = 'grams', unit = 'grams'
WHERE is_deleted = false
  AND (
    name ~* '\m\d+(\.\d+)?\s*(g|gm|gms|gram|grams)\M'
    OR variants::text ~* '\m\d+(\.\d+)?\s*(g|gm|gms|gram|grams)\M'
    OR (
      unit_type IN ('pieces', 'piece', 'pc', 'pcs', '')
      AND name ~* '\m(cream|moisturizer|clay|scrub|powder|soap bar|butter|wax|sunscreen gel|sunscreen cream|bleach)\M'
      AND name !~* '\m(strip|patch|roller|sponge|brush|kit|ml|perfume|shampoo|wash)\M'
    )
  );

-- 3. Liters (liter)
UPDATE public.products
SET unit_type = 'liter', unit = 'liter'
WHERE is_deleted = false
  AND (
    name ~* '\m\d+(\.\d+)?\s*(l|ltr|liter|litres?)\M'
    OR variants::text ~* '\m\d+(\.\d+)?\s*(l|ltr|liter|litres?)\M'
  );

-- 4. Kilograms (kg)
UPDATE public.products
SET unit_type = 'kg', unit = 'kg'
WHERE is_deleted = false
  AND (
    name ~* '\m\d+(\.\d+)?\s*(kg|kilo|kilogram)\M'
    OR variants::text ~* '\m\d+(\.\d+)?\s*(kg|kilo|kilogram)\M'
  );

-- 5. Synchronize unit column with unit_type across the board
UPDATE public.products
SET unit = unit_type
WHERE unit IS DISTINCT FROM unit_type;

-- 6. Upgrade bulk_upload_shop_products with smart unit detection
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
  v_name TEXT;
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
    v_name := TRIM(v_prod->>'name');
    v_unit_type := LOWER(TRIM(COALESCE(v_prod->>'unit_type', '')));

    -- Smart Auto-Inference for unit_type
    IF v_unit_type = '' OR v_unit_type IN ('piece', 'pc', 'pcs', 'pieces') THEN
      IF v_name ~* '\m\d+(\.\d+)?\s*(ml|milliliter|milli\s*litre)\M' OR (v_prod->'variants')::text ~* '\m\d+(\.\d+)?\s*(ml|milliliter|milli\s*litre)\M' THEN
        v_unit_type := 'ml';
      ELSIF v_name ~* '\m\d+(\.\d+)?\s*(kg|kilo|kilogram)\M' OR (v_prod->'variants')::text ~* '\m\d+(\.\d+)?\s*(kg|kilo|kilogram)\M' THEN
        v_unit_type := 'kg';
      ELSIF v_name ~* '\m\d+(\.\d+)?\s*(l|ltr|liter|litres?)\M' OR (v_prod->'variants')::text ~* '\m\d+(\.\d+)?\s*(l|ltr|liter|litres?)\M' THEN
        v_unit_type := 'liter';
      ELSIF v_name ~* '\m\d+(\.\d+)?\s*(g|gm|gms|gram|grams)\M' OR (v_prod->'variants')::text ~* '\m\d+(\.\d+)?\s*(g|gm|gms|gram|grams)\M' THEN
        v_unit_type := 'grams';
      ELSIF v_name ~* '\m(perfume|edp|edt|cologne|mist|body spray|shampoo|conditioner|body wash|shower gel|face wash|lotion|serum|hair oil|toner|cleanser|micellar)\M' 
            AND v_name !~* '\m(soap|powder|cream|butter|wax|scrub|strip|patch|roller|sponge|kit)\M' THEN
        v_unit_type := 'ml';
      ELSIF v_name ~* '\m(cream|moisturizer|clay|scrub|powder|soap bar|butter|wax|sunscreen gel|sunscreen cream|bleach)\M'
            AND v_name !~* '\m(strip|patch|roller|sponge|brush|kit|ml|perfume|shampoo|wash)\M' THEN
        v_unit_type := 'grams';
      ELSE
        v_unit_type := 'pieces';
      END IF;
    ELSIF v_unit_type IN ('g', 'gm', 'gms', 'gram') THEN
      v_unit_type := 'grams';
    ELSIF v_unit_type IN ('l', 'ltr', 'litre', 'litres') THEN
      v_unit_type := 'liter';
    ELSIF v_unit_type IN ('kg', 'kgs', 'kilogram') THEN
      v_unit_type := 'kg';
    ELSIF v_unit_type IN ('ml', 'milliliter') THEN
      v_unit_type := 'ml';
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
      AND LOWER(TRIM(name)) = LOWER(v_name)
    LIMIT 1;

    IF v_existing_id IS NOT NULL THEN
      -- UPDATE existing product with new details, brand, variants, images, and prices
      UPDATE public.products SET
        brand = COALESCE(NULLIF(TRIM(v_prod->>'brand'), ''), brand),
        sub_category = COALESCE(NULLIF(TRIM(v_prod->>'sub_category'), ''), sub_category),
        image_url = COALESCE(NULLIF(TRIM(v_prod->>'image_url'), ''), (v_prod->'images'->>0), image_url),
        price = (v_prod->>'price')::NUMERIC,
        description = NULLIF(TRIM(v_prod->>'description'), ''),
        category = COALESCE(NULLIF(TRIM(v_prod->>'category'), ''), v_shop_cat, 'Medical Store'),
        menu_category = COALESCE(NULLIF(TRIM(v_prod->>'menu_category'), ''), 'General / Wellness'),
        is_veg = (v_prod->>'is_veg')::BOOLEAN,
        is_available = COALESCE((v_prod->>'is_available')::BOOLEAN, true),
        weight_per_unit = COALESCE((v_prod->>'weight_per_unit')::NUMERIC, weight_per_unit),
        unit_type = v_unit_type,
        unit = v_unit_type,
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
        brand,
        sub_category,
        image_url,
        price,
        original_price,
        description,
        category,
        menu_category,
        is_veg,
        is_available,
        weight_per_unit,
        unit_type,
        unit,
        total_quantity,
        images,
        requires_prescription,
        medicine_type,
        variants,
        bulk_eligible,
        is_deleted
      ) VALUES (
        p_shop_id,
        v_name,
        NULLIF(TRIM(v_prod->>'brand'), ''),
        NULLIF(TRIM(v_prod->>'sub_category'), ''),
        COALESCE(NULLIF(TRIM(v_prod->>'image_url'), ''), (v_prod->'images'->>0)),
        (v_prod->>'price')::NUMERIC,
        NULL,
        NULLIF(TRIM(v_prod->>'description'), ''),
        COALESCE(NULLIF(TRIM(v_prod->>'category'), ''), v_shop_cat, 'Medical Store'),
        COALESCE(NULLIF(TRIM(v_prod->>'menu_category'), ''), 'General / Wellness'),
        (v_prod->>'is_veg')::BOOLEAN,
        COALESCE((v_prod->>'is_available')::BOOLEAN, true),
        (v_prod->>'weight_per_unit')::NUMERIC,
        v_unit_type,
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

-- 7. Remediation Function for on-demand execution
CREATE OR REPLACE FUNCTION public.remediate_catalog_product_units()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ml_count INT := 0;
  v_grams_count INT := 0;
  v_liter_count INT := 0;
  v_kg_count INT := 0;
  v_sync_count INT := 0;
BEGIN
  -- Liquids (ml)
  WITH updated_rows AS (
    UPDATE public.products
    SET unit_type = 'ml', unit = 'ml'
    WHERE is_deleted = false
      AND (
        name ~* '\m\d+(\.\d+)?\s*(ml|milliliter|milli\s*litre)\M'
        OR variants::text ~* '\m\d+(\.\d+)?\s*(ml|milliliter|milli\s*litre)\M'
        OR (
          unit_type IN ('pieces', 'piece', 'pc', 'pcs', '')
          AND name ~* '\m(perfume|edp|edt|cologne|mist|body spray|shampoo|conditioner|body wash|shower gel|face wash|lotion|serum|hair oil|toner|cleanser|micellar)\M'
          AND name !~* '\m(soap|powder|cream|butter|wax|scrub|strip|patch|roller|sponge|kit)\M'
        )
      )
      AND (unit_type != 'ml' OR unit != 'ml')
    RETURNING id
  )
  SELECT count(*) INTO v_ml_count FROM updated_rows;

  -- Solids / Creams (grams)
  WITH updated_rows AS (
    UPDATE public.products
    SET unit_type = 'grams', unit = 'grams'
    WHERE is_deleted = false
      AND (
        name ~* '\m\d+(\.\d+)?\s*(g|gm|gms|gram|grams)\M'
        OR variants::text ~* '\m\d+(\.\d+)?\s*(g|gm|gms|gram|grams)\M'
        OR (
          unit_type IN ('pieces', 'piece', 'pc', 'pcs', '')
          AND name ~* '\m(cream|moisturizer|clay|scrub|powder|soap bar|butter|wax|sunscreen gel|sunscreen cream|bleach)\M'
          AND name !~* '\m(strip|patch|roller|sponge|brush|kit|ml|perfume|shampoo|wash)\M'
        )
      )
      AND (unit_type != 'grams' OR unit != 'grams')
    RETURNING id
  )
  SELECT count(*) INTO v_grams_count FROM updated_rows;

  -- Liters (liter)
  WITH updated_rows AS (
    UPDATE public.products
    SET unit_type = 'liter', unit = 'liter'
    WHERE is_deleted = false
      AND (
        name ~* '\m\d+(\.\d+)?\s*(l|ltr|liter|litres?)\M'
        OR variants::text ~* '\m\d+(\.\d+)?\s*(l|ltr|liter|litres?)\M'
      )
      AND (unit_type != 'liter' OR unit != 'liter')
    RETURNING id
  )
  SELECT count(*) INTO v_liter_count FROM updated_rows;

  -- Kilograms (kg)
  WITH updated_rows AS (
    UPDATE public.products
    SET unit_type = 'kg', unit = 'kg'
    WHERE is_deleted = false
      AND (
        name ~* '\m\d+(\.\d+)?\s*(kg|kilo|kilogram)\M'
        OR variants::text ~* '\m\d+(\.\d+)?\s*(kg|kilo|kilogram)\M'
      )
      AND (unit_type != 'kg' OR unit != 'kg')
    RETURNING id
  )
  SELECT count(*) INTO v_kg_count FROM updated_rows;

  -- Sync unit column
  WITH updated_rows AS (
    UPDATE public.products
    SET unit = unit_type
    WHERE unit IS DISTINCT FROM unit_type
    RETURNING id
  )
  SELECT count(*) INTO v_sync_count FROM updated_rows;

  RETURN jsonb_build_object(
    'ml_updated', v_ml_count,
    'grams_updated', v_grams_count,
    'liter_updated', v_liter_count,
    'kg_updated', v_kg_count,
    'unit_sync_updated', v_sync_count
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.remediate_catalog_product_units() TO anon, authenticated, service_role;
