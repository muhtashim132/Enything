-- =============================================================================
-- Migration 20290000000151: Auto Upload Bulk Products RPC & Ingestion for Noor Medicate
-- Description:
--   1. Provides public.bulk_upload_shop_products(p_shop_id UUID, p_products JSONB)
--      SECURITY DEFINER RPC that safely inserts products into any shop while
--      enforcing the soft-delete rule (is_deleted = false), schema parity,
--      and duplicate prevention.
--   2. Ingests the 16 medicines detected from Shelf1.jpeg for Noor Medicate.
-- =============================================================================

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
        COALESCE(NULLIF(TRIM(v_prod->>'unit_type'), ''), 'pieces'),
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

-- ── 2. Direct Ingestion for Noor Medicate (Shop ID: 56883899-c115-42d9-82a9-90a9e59d21ec) ──

DO $$
DECLARE
  v_shop_id UUID := '56883899-c115-42d9-82a9-90a9e59d21ec'::UUID;
BEGIN
  -- Product 1: Rosuvas 20Mg Strip Of 10 Tablets
  IF NOT EXISTS (SELECT 1 FROM public.products WHERE shop_id = v_shop_id AND is_deleted = false AND LOWER(name) = LOWER('Rosuvas 20Mg Strip Of 10 Tablets')) THEN
    INSERT INTO public.products (shop_id, name, price, original_price, description, category, menu_category, is_veg, is_available, images, requires_prescription, medicine_type, variants, is_deleted)
    VALUES (v_shop_id, 'Rosuvas 20Mg Strip Of 10 Tablets', 480.00, NULL, 'Rosuvastatin(20.0 Mg)', 'Medical Store', 'Heart & BP', NULL, true, to_jsonb(ARRAY['https://cdn01.pharmeasy.in/dam/productsnowatermark/152989/rosuvas-20mg-strip-of-10-tablets-front-2-1753347026-non-watermark.jpg', 'https://cdn01.pharmeasy.in/dam/productsnowatermark/152989/rosuvas-20mg-strip-of-10-tablets-combo-3-1753347024-non-watermark.jpg']), true, 'General', '[{"id": "v_strip_10", "name": "1 Strip (10 tabs)", "price": 480.00, "is_available": true}]'::jsonb, false);
  END IF;

  -- Product 2: Rosulip 5Mg Strip Of 15 Tablets
  IF NOT EXISTS (SELECT 1 FROM public.products WHERE shop_id = v_shop_id AND is_deleted = false AND LOWER(name) = LOWER('Rosulip 5Mg Strip Of 15 Tablets')) THEN
    INSERT INTO public.products (shop_id, name, price, original_price, description, category, menu_category, is_veg, is_available, images, requires_prescription, medicine_type, variants, is_deleted)
    VALUES (v_shop_id, 'Rosulip 5Mg Strip Of 15 Tablets', 217.37, NULL, 'Rosuvastatin(5.0 Mg)', 'Medical Store', 'Heart & BP', NULL, true, to_jsonb(ARRAY['https://cdn01.pharmeasy.in/dam/productsnowatermark/152973/rosulip-5mg-strip-of-15-tablets-front-2-1753347026-non-watermark.jpg', 'https://cdn01.pharmeasy.in/dam/productsnowatermark/152973/rosulip-5mg-strip-of-15-tablets-combo-3-1753347024-non-watermark.jpg']), true, 'General', '[{"id": "v_strip_15", "name": "1 Strip (15 tabs)", "price": 217.37, "is_available": true}]'::jsonb, false);
  END IF;

  -- Product 3: Rosuvas F 10Mg Strip Of 15 Tablets
  IF NOT EXISTS (SELECT 1 FROM public.products WHERE shop_id = v_shop_id AND is_deleted = false AND LOWER(name) = LOWER('Rosuvas F 10Mg Strip Of 15 Tablets')) THEN
    INSERT INTO public.products (shop_id, name, price, original_price, description, category, menu_category, is_veg, is_available, images, requires_prescription, medicine_type, variants, is_deleted)
    VALUES (v_shop_id, 'Rosuvas F 10Mg Strip Of 15 Tablets', 460.00, NULL, 'Rosuvastatin(10.0 Mg)+Fenofibrate(160.0 Mg)', 'Medical Store', 'Digestive Health', NULL, true, to_jsonb(ARRAY['https://cdn01.pharmeasy.in/dam/productsnowatermark/153000/rosuvas-f-10mg-strip-of-15-tablets-front-2-1753347026-non-watermark.jpg', 'https://cdn01.pharmeasy.in/dam/productsnowatermark/153000/rosuvas-f-10mg-strip-of-15-tablets-combo-3-1753347024-non-watermark.jpg']), true, 'General', '[{"id": "v_strip_15", "name": "1 Strip (15 tabs)", "price": 460.00, "is_available": true}]'::jsonb, false);
  END IF;

  -- Product 4: Rosuvas 5Mg Strip Of 15 Tablets
  IF NOT EXISTS (SELECT 1 FROM public.products WHERE shop_id = v_shop_id AND is_deleted = false AND LOWER(name) = LOWER('Rosuvas 5Mg Strip Of 15 Tablets')) THEN
    INSERT INTO public.products (shop_id, name, price, original_price, description, category, menu_category, is_veg, is_available, images, requires_prescription, medicine_type, variants, is_deleted)
    VALUES (v_shop_id, 'Rosuvas 5Mg Strip Of 15 Tablets', 215.00, NULL, 'Rosuvastatin(5.0 Mg)', 'Medical Store', 'Heart & BP', NULL, true, to_jsonb(ARRAY['https://cdn01.pharmeasy.in/dam/productsnowatermark/152985/rosuvas-5mg-strip-of-15-tablets-front-2-1753347026-non-watermark.jpg', 'https://cdn01.pharmeasy.in/dam/productsnowatermark/152985/rosuvas-5mg-strip-of-15-tablets-combo-3-1753347024-non-watermark.jpg']), true, 'General', '[{"id": "v_strip_15", "name": "1 Strip (15 tabs)", "price": 215.00, "is_available": true}]'::jsonb, false);
  END IF;

  -- Product 5: Sildohyp D 8Mg Strip Of 10 Capsules
  IF NOT EXISTS (SELECT 1 FROM public.products WHERE shop_id = v_shop_id AND is_deleted = false AND LOWER(name) = LOWER('Sildohyp D 8Mg Strip Of 10 Capsules')) THEN
    INSERT INTO public.products (shop_id, name, price, original_price, description, category, menu_category, is_veg, is_available, images, requires_prescription, medicine_type, variants, is_deleted)
    VALUES (v_shop_id, 'Sildohyp D 8Mg Strip Of 10 Capsules', 250.00, NULL, 'Silodosin(8.0 Mg)+Dutasteride(0.5 Mg)', 'Medical Store', 'General / Wellness', NULL, true, to_jsonb(ARRAY['https://cdn01.pharmeasy.in/dam/productsnowatermark/262512/sildohyp-d-8mg-strip-of-10-capsules-front-2-1753347026-non-watermark.jpg', 'https://cdn01.pharmeasy.in/dam/productsnowatermark/262512/sildohyp-d-8mg-strip-of-10-capsules-combo-3-1753347024-non-watermark.jpg']), true, 'General', '[{"id": "v_strip_10", "name": "1 Strip (10 caps)", "price": 250.00, "is_available": true}]'::jsonb, false);
  END IF;

  -- Product 6: Goutnil 0.5Mg Strip Of 10 Tablets
  IF NOT EXISTS (SELECT 1 FROM public.products WHERE shop_id = v_shop_id AND is_deleted = false AND LOWER(name) = LOWER('Goutnil 0.5Mg Strip Of 10 Tablets')) THEN
    INSERT INTO public.products (shop_id, name, price, original_price, description, category, menu_category, is_veg, is_available, images, requires_prescription, medicine_type, variants, is_deleted)
    VALUES (v_shop_id, 'Goutnil 0.5Mg Strip Of 10 Tablets', 35.07, NULL, 'Colchicine(0.5 Mg)', 'Medical Store', 'General / Wellness', NULL, true, to_jsonb(ARRAY['https://cdn01.pharmeasy.in/dam/productsnowatermark/076241/goutnil-05mg-strip-of-10-tablets-front-2-1753347026-non-watermark.jpg', 'https://cdn01.pharmeasy.in/dam/productsnowatermark/076241/goutnil-05mg-strip-of-10-tablets-combo-3-1753347024-non-watermark.jpg']), true, 'General', '[{"id": "v_strip_10", "name": "1 Strip (10 tabs)", "price": 35.07, "is_available": true}]'::jsonb, false);
  END IF;

  -- Product 7: Crestor 10Mg Strip Of 15 Tablets
  IF NOT EXISTS (SELECT 1 FROM public.products WHERE shop_id = v_shop_id AND is_deleted = false AND LOWER(name) = LOWER('Crestor 10Mg Strip Of 15 Tablets')) THEN
    INSERT INTO public.products (shop_id, name, price, original_price, description, category, menu_category, is_veg, is_available, images, requires_prescription, medicine_type, variants, is_deleted)
    VALUES (v_shop_id, 'Crestor 10Mg Strip Of 15 Tablets', 426.00, NULL, 'Rosuvastatin(10.0 Mg)', 'Medical Store', 'Heart & BP', NULL, true, to_jsonb(ARRAY['https://cdn01.pharmeasy.in/dam/productsnowatermark/047120/crestor-10mg-strip-of-15-tablets-front-2-1753347026-non-watermark.jpg', 'https://cdn01.pharmeasy.in/dam/productsnowatermark/047120/crestor-10mg-strip-of-15-tablets-combo-3-1753347024-non-watermark.jpg']), true, 'General', '[{"id": "v_strip_15", "name": "1 Strip (15 tabs)", "price": 426.00, "is_available": true}]'::jsonb, false);
  END IF;

  -- Product 8: Contiflo Icon 0.4Mg Strip Of 10 Tablets
  IF NOT EXISTS (SELECT 1 FROM public.products WHERE shop_id = v_shop_id AND is_deleted = false AND LOWER(name) = LOWER('Contiflo Icon 0.4Mg Strip Of 10 Tablets')) THEN
    INSERT INTO public.products (shop_id, name, price, original_price, description, category, menu_category, is_veg, is_available, images, requires_prescription, medicine_type, variants, is_deleted)
    VALUES (v_shop_id, 'Contiflo Icon 0.4Mg Strip Of 10 Tablets', 166.00, NULL, 'Tamsulosin(0.4 Mg)', 'Medical Store', 'General / Wellness', NULL, true, to_jsonb(ARRAY['https://cdn01.pharmeasy.in/dam/productsnowatermark/046030/contiflo-icon-04mg-strip-of-10-tablets-front-2-1753347026-non-watermark.jpg', 'https://cdn01.pharmeasy.in/dam/productsnowatermark/046030/contiflo-icon-04mg-strip-of-10-tablets-combo-3-1753347024-non-watermark.jpg']), true, 'General', '[{"id": "v_strip_10", "name": "1 Strip (10 tabs)", "price": 166.00, "is_available": true}]'::jsonb, false);
  END IF;

  -- Product 9: Roliflo Od 2Mg Strip Of 10 Capsules
  IF NOT EXISTS (SELECT 1 FROM public.products WHERE shop_id = v_shop_id AND is_deleted = false AND LOWER(name) = LOWER('Roliflo Od 2Mg Strip Of 10 Capsules')) THEN
    INSERT INTO public.products (shop_id, name, price, original_price, description, category, menu_category, is_veg, is_available, images, requires_prescription, medicine_type, variants, is_deleted)
    VALUES (v_shop_id, 'Roliflo Od 2Mg Strip Of 10 Capsules', 263.44, NULL, 'Tamsulosin(0.4 Mg)+Tolterodine(2.0 Mg)', 'Medical Store', 'General / Wellness', NULL, true, to_jsonb(ARRAY['https://cdn01.pharmeasy.in/dam/productsnowatermark/151978/roliflo-od-2mg-strip-of-10-capsules-front-2-1753347026-non-watermark.jpg', 'https://cdn01.pharmeasy.in/dam/productsnowatermark/151978/roliflo-od-2mg-strip-of-10-capsules-combo-3-1753347024-non-watermark.jpg']), true, 'General', '[{"id": "v_strip_10", "name": "1 Strip (10 caps)", "price": 263.44, "is_available": true}]'::jsonb, false);
  END IF;

  -- Product 10: Lipaglyn 4Mg Strip Of 10 Tablets
  IF NOT EXISTS (SELECT 1 FROM public.products WHERE shop_id = v_shop_id AND is_deleted = false AND LOWER(name) = LOWER('Lipaglyn 4Mg Strip Of 10 Tablets')) THEN
    INSERT INTO public.products (shop_id, name, price, original_price, description, category, menu_category, is_veg, is_available, images, requires_prescription, medicine_type, variants, is_deleted)
    VALUES (v_shop_id, 'Lipaglyn 4Mg Strip Of 10 Tablets', 501.13, NULL, 'Saroglitazar(4.0 Mg)', 'Medical Store', 'General / Wellness', NULL, true, to_jsonb(ARRAY['https://cdn01.pharmeasy.in/dam/productsnowatermark/096180/lipaglyn-4mg-strip-of-10-tablets-front-2-1753347026-non-watermark.jpg', 'https://cdn01.pharmeasy.in/dam/productsnowatermark/096180/lipaglyn-4mg-strip-of-10-tablets-combo-3-1753347024-non-watermark.jpg']), true, 'General', '[{"id": "v_strip_10", "name": "1 Strip (10 tabs)", "price": 501.13, "is_available": true}]'::jsonb, false);
  END IF;

  -- Product 11: Linvas 4Mg Strip Of 10 Tablets
  IF NOT EXISTS (SELECT 1 FROM public.products WHERE shop_id = v_shop_id AND is_deleted = false AND LOWER(name) = LOWER('Linvas 4Mg Strip Of 10 Tablets')) THEN
    INSERT INTO public.products (shop_id, name, price, original_price, description, category, menu_category, is_veg, is_available, images, requires_prescription, medicine_type, variants, is_deleted)
    VALUES (v_shop_id, 'Linvas 4Mg Strip Of 10 Tablets', 501.10, NULL, 'Saroglitazar(4.0 Mg)', 'Medical Store', 'General / Wellness', NULL, true, to_jsonb(ARRAY['https://cdn01.pharmeasy.in/dam/productsnowatermark/262520/linvas-4mg-strip-of-10-tablets-front-2-1753347026-non-watermark.jpg', 'https://cdn01.pharmeasy.in/dam/productsnowatermark/262520/linvas-4mg-strip-of-10-tablets-combo-3-1753347024-non-watermark.jpg']), true, 'General', '[{"id": "v_strip_10", "name": "1 Strip (10 tabs)", "price": 501.10, "is_available": true}]'::jsonb, false);
  END IF;

  -- Product 12: Bilypsa 4Mg Bottle Of 45 Tablets
  IF NOT EXISTS (SELECT 1 FROM public.products WHERE shop_id = v_shop_id AND is_deleted = false AND LOWER(name) = LOWER('Bilypsa 4Mg Bottle Of 45 Tablets')) THEN
    INSERT INTO public.products (shop_id, name, price, original_price, description, category, menu_category, is_veg, is_available, images, requires_prescription, medicine_type, variants, is_deleted)
    VALUES (v_shop_id, 'Bilypsa 4Mg Bottle Of 45 Tablets', 2255.08, NULL, 'Saroglitazar(4.0 Mg)', 'Medical Store', 'General / Wellness', NULL, true, to_jsonb(ARRAY['https://cdn01.pharmeasy.in/dam/productsnowatermark/262450/bilypsa-4mg-bottle-of-45-tablets-front-2-1753347026-non-watermark.jpg', 'https://cdn01.pharmeasy.in/dam/productsnowatermark/262450/bilypsa-4mg-bottle-of-45-tablets-combo-3-1753347024-non-watermark.jpg']), true, 'General', '[{"id": "v_strip_45", "name": "1 Bottle (45 tabs)", "price": 2255.08, "is_available": true}]'::jsonb, false);
  END IF;

  -- Product 13: Flotral 10Mg Strip Of 30 Tablets
  IF NOT EXISTS (SELECT 1 FROM public.products WHERE shop_id = v_shop_id AND is_deleted = false AND LOWER(name) = LOWER('Flotral 10Mg Strip Of 30 Tablets')) THEN
    INSERT INTO public.products (shop_id, name, price, original_price, description, category, menu_category, is_veg, is_available, images, requires_prescription, medicine_type, variants, is_deleted)
    VALUES (v_shop_id, 'Flotral 10Mg Strip Of 30 Tablets', 649.00, NULL, 'Alfuzosin(10.0 Mg)', 'Medical Store', 'General / Wellness', NULL, true, to_jsonb(ARRAY['https://cdn01.pharmeasy.in/dam/productsnowatermark/069810/flotral-10mg-strip-of-30-tablets-front-2-1753347026-non-watermark.jpg', 'https://cdn01.pharmeasy.in/dam/productsnowatermark/069810/flotral-10mg-strip-of-30-tablets-combo-3-1753347024-non-watermark.jpg']), true, 'General', '[{"id": "v_strip_30", "name": "1 Strip (30 tabs)", "price": 649.00, "is_available": true}]'::jsonb, false);
  END IF;

  -- Product 14: Flodart Plus Strip Of 10 Capsules
  IF NOT EXISTS (SELECT 1 FROM public.products WHERE shop_id = v_shop_id AND is_deleted = false AND LOWER(name) = LOWER('Flodart Plus Strip Of 10 Capsules')) THEN
    INSERT INTO public.products (shop_id, name, price, original_price, description, category, menu_category, is_veg, is_available, images, requires_prescription, medicine_type, variants, is_deleted)
    VALUES (v_shop_id, 'Flodart Plus Strip Of 10 Capsules', 225.00, NULL, 'Dutasteride(0.5 Mg)+Tamsulosin(0.4 Mg)', 'Medical Store', 'General / Wellness', NULL, true, to_jsonb(ARRAY['https://cdn01.pharmeasy.in/dam/productsnowatermark/069630/flodart-plus-strip-of-10-capsules-front-2-1753347026-non-watermark.jpg', 'https://cdn01.pharmeasy.in/dam/productsnowatermark/069630/flodart-plus-strip-of-10-capsules-combo-3-1753347024-non-watermark.jpg']), true, 'General', '[{"id": "v_strip_10", "name": "1 Strip (10 caps)", "price": 225.00, "is_available": true}]'::jsonb, false);
  END IF;

  -- Product 15: Silodal D 8Mg Strip Of 10 Capsules
  IF NOT EXISTS (SELECT 1 FROM public.products WHERE shop_id = v_shop_id AND is_deleted = false AND LOWER(name) = LOWER('Silodal D 8Mg Strip Of 10 Capsules')) THEN
    INSERT INTO public.products (shop_id, name, price, original_price, description, category, menu_category, is_veg, is_available, images, requires_prescription, medicine_type, variants, is_deleted)
    VALUES (v_shop_id, 'Silodal D 8Mg Strip Of 10 Capsules', 470.00, NULL, 'Silodosin(8.0 Mg)+Dutasteride(0.5 Mg)', 'Medical Store', 'General / Wellness', NULL, true, to_jsonb(ARRAY['https://cdn01.pharmeasy.in/dam/productsnowatermark/159820/silodal-d-8mg-strip-of-10-capsules-front-2-1753347026-non-watermark.jpg', 'https://cdn01.pharmeasy.in/dam/productsnowatermark/159820/silodal-d-8mg-strip-of-10-capsules-combo-3-1753347024-non-watermark.jpg']), true, 'General', '[{"id": "v_strip_10", "name": "1 Strip (10 caps)", "price": 470.00, "is_available": true}]'::jsonb, false);
  END IF;

  -- Product 16: Silofast D 8Mg Strip Of 10 Capsules
  IF NOT EXISTS (SELECT 1 FROM public.products WHERE shop_id = v_shop_id AND is_deleted = false AND LOWER(name) = LOWER('Silofast D 8Mg Strip Of 10 Capsules')) THEN
    INSERT INTO public.products (shop_id, name, price, original_price, description, category, menu_category, is_veg, is_available, images, requires_prescription, medicine_type, variants, is_deleted)
    VALUES (v_shop_id, 'Silofast D 8Mg Strip Of 10 Capsules', 561.51, NULL, 'Silodosin(8.0 Mg)+Dutasteride(0.5 Mg)', 'Medical Store', 'General / Wellness', NULL, true, to_jsonb(ARRAY['https://cdn01.pharmeasy.in/dam/productsnowatermark/159850/silofast-d-8mg-strip-of-10-capsules-front-2-1753347026-non-watermark.jpg', 'https://cdn01.pharmeasy.in/dam/productsnowatermark/159850/silofast-d-8mg-strip-of-10-capsules-combo-3-1753347024-non-watermark.jpg']), true, 'General', '[{"id": "v_strip_10", "name": "1 Strip (10 caps)", "price": 561.51, "is_available": true}]'::jsonb, false);
  END IF;
END $$;
