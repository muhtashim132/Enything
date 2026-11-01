-- =============================================================================
-- Migration: 100x Target Demographic Omni-Search with Automatic #Unisex Inclusion
-- File: 20290000000170_100x_demographic_unisex_omni_search_fortress.sql
-- =============================================================================
--
-- 100x Forensic Enhancement:
--   1. Fully integrates target demographics: 'Unisex', 'Men', 'Women', 'Boys', 'Girls', 'Kids'.
--   2. In search queries (p_query):
--        • When searching for 'men' (or 'mens', 'male', 'gents'), automatically matches
--          products tagged #Men OR #Unisex.
--        • When searching for 'women' (or 'womens', 'female', 'ladies'), automatically matches
--          products tagged #Women OR #Unisex.
--        • When searching for 'boys' (or 'boy'), automatically matches
--          products tagged #Boys OR #Kids OR #Unisex.
--        • When searching for 'girls' (or 'girl'), automatically matches
--          products tagged #Girls OR #Kids OR #Unisex.
--        • When searching for 'kids' (or 'children', 'kid'), automatically matches
--          products tagged #Kids OR #Boys OR #Girls OR #Unisex.
--        • When searching for 'unisex', matches products tagged #Unisex.
--   3. In p_special_tag filter:
--        • Automatically expands gendered and age demographics to include #Unisex.
--   4. Preserves exact canonical 8-parameter signature:
--        (p_lat, p_lng, p_query, p_categories, p_radius_km, p_limit, p_limit_per_shop, p_special_tag)
-- =============================================================================

DROP FUNCTION IF EXISTS public.search_products_geospatial(double precision, double precision, text, text[], double precision, int, int);
DROP FUNCTION IF EXISTS public.search_products_geospatial(double precision, double precision, text, text[], double precision, integer, integer);
DROP FUNCTION IF EXISTS public.search_products_geospatial(double precision, double precision, text, text[], double precision, int);
DROP FUNCTION IF EXISTS public.search_products_geospatial(double precision, double precision, text, text[], double precision, int, int, text);
DROP FUNCTION IF EXISTS public.search_products_geospatial(double precision, double precision, text, text[], double precision, integer, integer, text);

CREATE OR REPLACE FUNCTION public.search_products_geospatial(
  p_lat double precision,
  p_lng double precision,
  p_query text DEFAULT NULL,
  p_categories text[] DEFAULT NULL,
  p_radius_km double precision DEFAULT 15.0,
  p_limit int DEFAULT 50,
  p_limit_per_shop int DEFAULT 5,
  p_special_tag text DEFAULT NULL
)
RETURNS SETOF public.products
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_max_radius double precision;
BEGIN
  IF p_lat IS NULL OR p_lng IS NULL THEN
    RETURN;
  END IF;

  BEGIN
    SELECT (value#>>'{}')::double precision INTO v_admin_max_radius 
    FROM public.platform_config 
    WHERE key = 'max_delivery_radius_km';
    IF v_admin_max_radius IS NULL THEN v_admin_max_radius := 15.0; END IF;
  EXCEPTION WHEN OTHERS THEN 
    v_admin_max_radius := 15.0;
  END;

  p_radius_km := LEAST(COALESCE(p_radius_km, 15.0), v_admin_max_radius);
  p_radius_km := GREATEST(p_radius_km, 1.0);

  RETURN QUERY
  SELECT p_outer.*
  FROM public.products p_outer
  INNER JOIN (
    SELECT 
      p.id,
      ROW_NUMBER() OVER(PARTITION BY p.shop_id ORDER BY p.rating DESC, p.created_at DESC) as rn
    FROM public.products p
    INNER JOIN public.shops s ON p.shop_id = s.id
    WHERE p.is_available = true
      AND p.is_deleted = false
      AND s.is_active = true
      AND COALESCE(s.is_manually_closed, false) = false
      AND s.location IS NOT NULL
      AND (
        p_query IS NULL 
        OR trim(p_query) = '' 
        OR (
          NOT EXISTS (
            SELECT 1 
            FROM unnest(string_to_array(trim(regexp_replace(p_query, '[,()"\x27]', ' ', 'g')), ' ')) AS token
            WHERE length(trim(token)) > 0
              AND NOT (
                -- Standard text matching across all product metadata
                p.name ILIKE '%' || trim(token) || '%'
                OR COALESCE(p.description, '') ILIKE '%' || trim(token) || '%'
                OR COALESCE(p.brand, '') ILIKE '%' || trim(token) || '%'
                OR COALESCE(p.category, '') ILIKE '%' || trim(token) || '%'
                OR COALESCE(p.sub_category, '') ILIKE '%' || trim(token) || '%'
                OR COALESCE(p.menu_category, '') ILIKE '%' || trim(token) || '%'
                OR COALESCE(p.medicine_type, '') ILIKE '%' || trim(token) || '%'
                OR COALESCE(p.special_tags::text, '') ILIKE '%' || trim(token) || '%'
                OR s.name ILIKE '%' || trim(token) || '%'
                -- 100x Demographic Token Omni-Search:
                OR (
                  lower(trim(token)) IN ('men', 'mens', 'male', 'gents')
                  AND p.special_tags IS NOT NULL 
                  AND (p.special_tags ? '#Men' OR p.special_tags ? '#Unisex')
                )
                OR (
                  lower(trim(token)) IN ('women', 'womens', 'female', 'ladies', 'woman')
                  AND p.special_tags IS NOT NULL 
                  AND (p.special_tags ? '#Women' OR p.special_tags ? '#Unisex')
                )
                OR (
                  lower(trim(token)) IN ('boys', 'boy')
                  AND p.special_tags IS NOT NULL 
                  AND (p.special_tags ? '#Boys' OR p.special_tags ? '#Kids' OR p.special_tags ? '#Unisex')
                )
                OR (
                  lower(trim(token)) IN ('girls', 'girl')
                  AND p.special_tags IS NOT NULL 
                  AND (p.special_tags ? '#Girls' OR p.special_tags ? '#Kids' OR p.special_tags ? '#Unisex')
                )
                OR (
                  lower(trim(token)) IN ('kids', 'kid', 'children', 'child', 'toddler', 'infant')
                  AND p.special_tags IS NOT NULL 
                  AND (p.special_tags ? '#Kids' OR p.special_tags ? '#Boys' OR p.special_tags ? '#Girls' OR p.special_tags ? '#Unisex')
                )
                OR (
                  lower(trim(token)) = 'unisex'
                  AND p.special_tags IS NOT NULL 
                  AND p.special_tags ? '#Unisex'
                )
              )
          )
        )
      )
      AND (
        p_categories IS NULL 
        OR p.category = ANY(p_categories)
        OR lower(trim(p.category)) = ANY(SELECT lower(trim(x)) FROM unnest(p_categories) x)
        OR (
          lower(trim(p.category)) IN ('grocerylm', 'grocery (low margin)', 'grocery low margin', 'grocery_lm')
          AND EXISTS (
            SELECT 1 FROM unnest(p_categories) cat_req
            WHERE lower(cat_req) LIKE '%grocery%'
               OR lower(cat_req) LIKE '%supermarket%'
               OR lower(cat_req) LIKE '%hypermarket%'
          )
        )
        OR (
          (
            EXISTS (
              SELECT 1 FROM unnest(p_categories) cat_req
              WHERE lower(cat_req) LIKE '%supermarket%' 
                 OR lower(cat_req) LIKE '%hypermarket%' 
                 OR lower(cat_req) LIKE '%supermart%' 
                 OR lower(cat_req) LIKE '%departmental%'
            )
            OR NOT (
              lower(s.category) LIKE '%supermarket%' OR
              lower(s.category) LIKE '%hypermarket%' OR
              lower(s.category) LIKE '%supermart%' OR
              lower(s.category) LIKE '%departmental%' OR
              lower(s.category) LIKE '%general store%' OR
              lower(s.category) LIKE '%provision store%' OR
              lower(s.category) LIKE '%kirana%'
            )
          ) AND (
            s.category = ANY(p_categories)
            OR lower(trim(s.category)) = ANY(SELECT lower(trim(x)) FROM unnest(p_categories) x)
            OR (
              s.categories IS NOT NULL 
              AND jsonb_typeof(s.categories) = 'array'
              AND (
                s.categories ?| p_categories
                OR EXISTS (
                  SELECT 1 
                  FROM jsonb_array_elements_text(s.categories) elem
                  JOIN unnest(p_categories) target ON lower(trim(elem)) = lower(trim(target))
                )
              )
            )
          )
        )
      )
      AND (
        p_special_tag IS NULL 
        OR (
          p.special_tags IS NOT NULL AND (
            (p_special_tag IN ('#Men', 'Men') AND (p.special_tags ? '#Men' OR p.special_tags ? '#Unisex'))
            OR (p_special_tag IN ('#Women', 'Women') AND (p.special_tags ? '#Women' OR p.special_tags ? '#Unisex'))
            OR (p_special_tag IN ('#Boys', 'Boys') AND (p.special_tags ? '#Boys' OR p.special_tags ? '#Kids' OR p.special_tags ? '#Unisex'))
            OR (p_special_tag IN ('#Girls', 'Girls') AND (p.special_tags ? '#Girls' OR p.special_tags ? '#Kids' OR p.special_tags ? '#Unisex'))
            OR (p_special_tag IN ('#Kids', 'Kids') AND (p.special_tags ? '#Kids' OR p.special_tags ? '#Boys' OR p.special_tags ? '#Girls' OR p.special_tags ? '#Unisex'))
            OR (p_special_tag IN ('#Unisex', 'Unisex') AND p.special_tags ? '#Unisex')
            OR p.special_tags ? p_special_tag
            OR p.special_tags ? ('#' || p_special_tag)
            OR p.special_tags ? '#Unisex'
          )
        )
      )
      AND ST_DWithin(
        s.location,
        ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
        p_radius_km * 1000
      )
  ) filtered_ids ON p_outer.id = filtered_ids.id
  WHERE (p_limit_per_shop IS NULL OR filtered_ids.rn <= p_limit_per_shop)
  ORDER BY 
    p_outer.rating DESC,
    p_outer.created_at DESC
  LIMIT LEAST(COALESCE(p_limit, 50), 200);
END;
$$;

GRANT EXECUTE ON FUNCTION public.search_products_geospatial(double precision, double precision, text, text[], double precision, int, int, text) TO authenticated, anon;

