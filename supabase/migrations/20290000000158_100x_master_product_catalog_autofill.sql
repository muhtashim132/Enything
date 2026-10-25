-- Migration 20290000000158: 100x Master Product Catalog Autocomplete & Autofill
-- Allows merchants and admins to query existing items from any store to autofill all details (name, description, salts, images, price, categories, variants, etc.)

CREATE OR REPLACE FUNCTION search_global_product_catalog(
  p_query TEXT,
  p_shop_category TEXT DEFAULT NULL,
  p_limit INT DEFAULT 15
)
RETURNS TABLE (
  id UUID,
  name TEXT,
  description TEXT,
  price NUMERIC,
  original_price NUMERIC,
  category TEXT,
  menu_category TEXT,
  brand TEXT,
  is_veg BOOLEAN,
  unit_type TEXT,
  weight_per_unit NUMERIC,
  total_quantity INT,
  images JSONB,
  requires_prescription BOOLEAN,
  medicine_type TEXT,
  variants JSONB,
  gst_rate_override NUMERIC,
  special_tags JSONB,
  shop_name TEXT,
  shop_category TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_clean_query TEXT := TRIM(p_query);
BEGIN
  IF v_clean_query IS NULL OR LENGTH(v_clean_query) < 2 THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH matched_products AS (
    SELECT 
      p.id,
      p.name,
      p.description,
      p.price,
      p.original_price,
      p.category,
      p.menu_category,
      p.brand,
      p.is_veg,
      COALESCE(p.unit_type, 'pieces') AS unit_type,
      p.weight_per_unit,
      p.total_quantity,
      COALESCE(p.images, '[]'::jsonb) AS images,
      COALESCE(p.requires_prescription, false) AS requires_prescription,
      COALESCE(p.medicine_type, 'General') AS medicine_type,
      COALESCE(p.variants, '[]'::jsonb) AS variants,
      p.gst_rate_override,
      COALESCE(p.special_tags, '[]'::jsonb) AS special_tags,
      COALESCE(s.name, 'Partner Store') AS shop_name,
      COALESCE(s.category, p.category) AS shop_category,
      -- Quality score: prefer items with images, descriptions, matching shop category
      (
        CASE 
          WHEN p.images IS NOT NULL AND jsonb_typeof(p.images) = 'array' AND jsonb_array_length(p.images) > 0 THEN 20 
          ELSE 0 
        END +
        CASE 
          WHEN p.description IS NOT NULL AND LENGTH(p.description) > 3 THEN 10 
          ELSE 0 
        END +
        CASE 
          WHEN p.variants IS NOT NULL AND jsonb_typeof(p.variants) = 'array' AND jsonb_array_length(p.variants) > 0 THEN 5 
          ELSE 0 
        END +
        CASE 
          WHEN p_shop_category IS NOT NULL AND (p.category ILIKE p_shop_category OR s.category ILIKE p_shop_category) THEN 30 
          ELSE 0 
        END
      ) AS quality_score,
      -- Partition by normalized name, brand, and unit for deduplication across shops
      ROW_NUMBER() OVER (
        PARTITION BY LOWER(TRIM(p.name)), LOWER(COALESCE(TRIM(p.brand), '')), LOWER(COALESCE(TRIM(p.unit_type), ''))
        ORDER BY 
          CASE WHEN p.images IS NOT NULL AND jsonb_typeof(p.images) = 'array' AND jsonb_array_length(p.images) > 0 THEN 0 ELSE 1 END,
          CASE WHEN p.description IS NOT NULL AND LENGTH(p.description) > 3 THEN 0 ELSE 1 END,
          p.created_at DESC
      ) AS dedupe_rank
    FROM public.products p
    LEFT JOIN public.shops s ON s.id = p.shop_id
    WHERE p.is_deleted = false
      AND (
        p.name ILIKE '%' || v_clean_query || '%'
        OR COALESCE(p.description, '') ILIKE '%' || v_clean_query || '%'
        OR COALESCE(p.brand, '') ILIKE '%' || v_clean_query || '%'
        OR COALESCE(p.category, '') ILIKE '%' || v_clean_query || '%'
        OR COALESCE(p.menu_category, '') ILIKE '%' || v_clean_query || '%'
      )
  )
  SELECT 
    mp.id,
    mp.name,
    mp.description,
    mp.price,
    mp.original_price,
    mp.category,
    mp.menu_category,
    mp.brand,
    mp.is_veg,
    mp.unit_type,
    mp.weight_per_unit,
    mp.total_quantity,
    mp.images,
    mp.requires_prescription,
    mp.medicine_type,
    mp.variants,
    mp.gst_rate_override,
    mp.special_tags,
    mp.shop_name,
    mp.shop_category
  FROM matched_products mp
  WHERE mp.dedupe_rank = 1
  ORDER BY mp.quality_score DESC, mp.name ASC
  LIMIT COALESCE(p_limit, 15);
END;
$$;

-- Grant execution to authenticated sellers, anon, and service_role
GRANT EXECUTE ON FUNCTION search_global_product_catalog(TEXT, TEXT, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION search_global_product_catalog(TEXT, TEXT, INT) TO anon;
GRANT EXECUTE ON FUNCTION search_global_product_catalog(TEXT, TEXT, INT) TO service_role;
