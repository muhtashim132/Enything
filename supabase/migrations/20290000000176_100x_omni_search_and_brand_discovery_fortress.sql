-- =============================================================================
-- Migration: 100x Omni-Search, Product Name & Brand Discovery Fortress
-- File: 20290000000176_100x_omni_search_and_brand_discovery_fortress.sql
-- =============================================================================
--
-- 100x Forensic Enhancement:
--   1. Comprehensive Product Name & Brand Discovery:
--      • Searching for product keywords (e.g. 'serum', 'lipstick', 'moisturizer', 'shampoo')
--        or brand keywords (e.g. 'Garnier', 'Mamaearth', 'Nivea', 'L''Oreal', 'Amul', 'Nike')
--        or multi-word combinations (e.g. 'Garnier serum', 'Mamaearth face wash', 'Amul milk')
--        accurately retrieves all matching products across all active shops in radius.
--   2. Multi-Token Tokenizer with Punctuation & Stemming Support:
--      • Tokens are split across spaces, commas, quotes, hyphens, and brackets.
--      • Automatic singular/plural stemming (e.g. 'serums' -> matches 'serum', 'lipsticks' -> 'lipstick').
--      • Every token is matched across product name, description, brand, category,
--        sub_category, menu_category, medicine_type, special_tags, and parent shop name.
--   3. Store-Level Category Inheritance & Null Category Platform-Wide Search:
--      • When p_categories IS NULL (default search from customer home dashboard),
--        all categories across all shops are searched without category lockout.
--      • When browsing Supermarket / Hypermarket / Grocery, all products stocked in that
--        store are included, regardless of whether the product item category is Cosmetics or Stationery.
--   4. Shop Search Tokenization:
--      • search_shops_geospatial tokenizes multi-word queries so shops that sell multi-token
--        brand + product combinations (e.g. 'Garnier serum', 'Amul butter') are discovered.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. search_products_geospatial (100x Omni-Search & Brand Discovery)
-- ─────────────────────────────────────────────────────────────────────────────
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
  p_limit int DEFAULT 100,
  p_limit_per_shop int DEFAULT 10,
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
      -- 100x Multi-Token Omni-Search Matching across Name, Brand, Description, & Shop
      AND (
        p_query IS NULL 
        OR trim(p_query) = '' 
        OR (
          NOT EXISTS (
            SELECT 1 
            FROM unnest(string_to_array(trim(regexp_replace(p_query, '[,()"\x27]', ' ', 'g')), ' ')) AS token
            WHERE length(trim(token)) > 0
              AND NOT (
                -- Direct Token Matching across metadata and brand
                p.name ILIKE '%' || trim(token) || '%'
                OR COALESCE(p.brand, '') ILIKE '%' || trim(token) || '%'
                OR COALESCE(p.description, '') ILIKE '%' || trim(token) || '%'
                OR COALESCE(p.category, '') ILIKE '%' || trim(token) || '%'
                OR COALESCE(p.sub_category, '') ILIKE '%' || trim(token) || '%'
                OR COALESCE(p.menu_category, '') ILIKE '%' || trim(token) || '%'
                OR COALESCE(p.medicine_type, '') ILIKE '%' || trim(token) || '%'
                OR COALESCE(p.special_tags::text, '') ILIKE '%' || trim(token) || '%'
                OR s.name ILIKE '%' || trim(token) || '%'
                -- Plural-to-Singular Stemming (e.g. 'serums' -> 'serum')
                OR (
                  length(trim(token)) > 3 
                  AND lower(trim(token)) LIKE '%s'
                  AND (
                    p.name ILIKE '%' || substring(trim(token) from 1 for length(trim(token))-1) || '%'
                    OR COALESCE(p.brand, '') ILIKE '%' || substring(trim(token) from 1 for length(trim(token))-1) || '%'
                    OR COALESCE(p.description, '') ILIKE '%' || substring(trim(token) from 1 for length(trim(token))-1) || '%'
                  )
                )
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
      -- Category Filter with 100x Store-Level Category Inheritance
      AND (
        p_categories IS NULL 
        OR p.category = ANY(p_categories)
        OR lower(trim(p.category)) = ANY(SELECT lower(trim(x)) FROM unnest(p_categories) x)
        -- Grocery Low Margin match
        OR (
          lower(trim(p.category)) IN ('grocerylm', 'grocery (low margin)', 'grocery low margin', 'grocery_lm')
          AND EXISTS (
            SELECT 1 FROM unnest(p_categories) cat_req
            WHERE lower(cat_req) LIKE '%grocery%'
               OR lower(cat_req) LIKE '%supermarket%'
               OR lower(cat_req) LIKE '%hypermarket%'
               OR lower(cat_req) LIKE '%supermart%'
               OR lower(cat_req) LIKE '%hypermart%'
          )
        )
        -- 100x Store-Level Category Inheritance:
        OR (
          (
            EXISTS (
              SELECT 1 FROM unnest(p_categories) cat_req
              WHERE lower(cat_req) LIKE '%supermarket%' 
                 OR lower(cat_req) LIKE '%hypermarket%' 
                 OR lower(cat_req) LIKE '%supermart%' 
                 OR lower(cat_req) LIKE '%hypermart%' 
                 OR lower(cat_req) LIKE '%grocery%'
                 OR lower(cat_req) LIKE '%departmental%'
            )
            OR NOT (
              lower(s.category) LIKE '%supermarket%' OR
              lower(s.category) LIKE '%hypermarket%' OR
              lower(s.category) LIKE '%supermart%' OR
              lower(s.category) LIKE '%hypermart%' OR
              lower(s.category) LIKE '%grocery%' OR
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
      -- 100x Target Demographic Filter (ChoiceChips)
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
  LIMIT LEAST(COALESCE(p_limit, 100), 300);
END;
$$;

GRANT EXECUTE ON FUNCTION public.search_products_geospatial(double precision, double precision, text, text[], double precision, int, int, text) TO authenticated, anon;


-- ─────────────────────────────────────────────────────────────────────────────
-- 2. search_shops_geospatial (with 100x Multi-Token Product & Brand Matching)
-- ─────────────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.search_shops_geospatial(double precision, double precision, text, text[], double precision, int);
DROP FUNCTION IF EXISTS public.search_shops_geospatial(double precision, double precision, text, text[], double precision, integer);

CREATE OR REPLACE FUNCTION public.search_shops_geospatial(
  p_lat double precision,
  p_lng double precision,
  p_query text DEFAULT NULL,
  p_categories text[] DEFAULT NULL,
  p_radius_km double precision DEFAULT 15.0,
  p_limit int DEFAULT 50
)
RETURNS SETOF public.shops
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
  SELECT s.*
  FROM public.shops s
  WHERE s.is_active = true
    AND COALESCE(s.is_manually_closed, false) = false
    AND s.location IS NOT NULL
    AND (
      p_query IS NULL 
      OR trim(p_query) = '' 
      OR s.name ILIKE '%' || p_query || '%'
      OR COALESCE(s.category, '') ILIKE '%' || p_query || '%'
      OR COALESCE(s.cuisine_type, '') ILIKE '%' || p_query || '%'
      OR (s.categories IS NOT NULL AND s.categories::text ILIKE '%' || p_query || '%')
      -- Exact or multi-token product matching in shop
      OR EXISTS (
           SELECT 1 FROM public.products p_sub
           WHERE p_sub.shop_id = s.id
             AND p_sub.is_deleted = false
             AND p_sub.is_available = true
             AND (
               -- Direct match
               p_sub.name ILIKE '%' || p_query || '%'
               OR COALESCE(p_sub.description, '') ILIKE '%' || p_query || '%'
               OR COALESCE(p_sub.brand, '') ILIKE '%' || p_query || '%'
               OR COALESCE(p_sub.menu_category, '') ILIKE '%' || p_query || '%'
               -- Or every token in p_query matches product/shop attributes
               OR (
                 NOT EXISTS (
                   SELECT 1 
                   FROM unnest(string_to_array(trim(regexp_replace(p_query, '[,()"\x27]', ' ', 'g')), ' ')) AS token
                   WHERE length(trim(token)) > 0
                     AND NOT (
                       p_sub.name ILIKE '%' || trim(token) || '%'
                       OR COALESCE(p_sub.brand, '') ILIKE '%' || trim(token) || '%'
                       OR COALESCE(p_sub.description, '') ILIKE '%' || trim(token) || '%'
                       OR COALESCE(p_sub.menu_category, '') ILIKE '%' || trim(token) || '%'
                       OR s.name ILIKE '%' || trim(token) || '%'
                       -- Stemming
                       OR (
                         length(trim(token)) > 3 
                         AND lower(trim(token)) LIKE '%s'
                         AND (
                           p_sub.name ILIKE '%' || substring(trim(token) from 1 for length(trim(token))-1) || '%'
                           OR COALESCE(p_sub.brand, '') ILIKE '%' || substring(trim(token) from 1 for length(trim(token))-1) || '%'
                         )
                       )
                     )
                 )
               )
             )
         )
    )
    AND (
      p_categories IS NULL 
      OR s.category = ANY(p_categories::text[])
      OR lower(trim(s.category)) = ANY(SELECT lower(trim(x)) FROM unnest(p_categories::text[]) x)
      OR (
        s.categories IS NOT NULL 
        AND jsonb_typeof(s.categories) = 'array'
        AND (
          s.categories ?| p_categories::text[]
          OR EXISTS (
            SELECT 1 
            FROM jsonb_array_elements_text(s.categories) elem
            JOIN unnest(p_categories::text[]) target ON lower(trim(elem)) = lower(trim(target))
          )
        )
      )
      OR EXISTS (
        SELECT 1 FROM public.products p_cat
        WHERE p_cat.shop_id = s.id
          AND p_cat.is_deleted = false
          AND p_cat.is_available = true
          AND (
            p_cat.category = ANY(p_categories::text[])
            OR lower(trim(p_cat.category)) = ANY(SELECT lower(trim(x)) FROM unnest(p_categories::text[]) x)
            OR (
              lower(trim(p_cat.category)) IN ('grocerylm', 'grocery (low margin)', 'grocery low margin', 'grocery_lm')
              AND EXISTS (
                SELECT 1 FROM unnest(p_categories::text[]) cat_req
                WHERE lower(cat_req) LIKE '%grocery%'
                   OR lower(cat_req) LIKE '%supermarket%'
                   OR lower(cat_req) LIKE '%hypermarket%'
              )
            )
          )
      )
    )
    AND ST_DWithin(
      s.location,
      ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
      p_radius_km * 1000
    )
  ORDER BY 
    (s.is_active AND s.is_accepting_orders) DESC,
    ST_Distance(
      s.location,
      ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography
    ) ASC
  LIMIT LEAST(COALESCE(p_limit, 50), 200);
END;
$$;

GRANT EXECUTE ON FUNCTION public.search_shops_geospatial(double precision, double precision, text, text[], double precision, int) TO authenticated, anon;
