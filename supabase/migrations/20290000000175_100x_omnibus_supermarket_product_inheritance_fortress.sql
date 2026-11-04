-- =============================================================================
-- Migration: 100x Omnibus Supermarket & Grocery Store-Level Product Inheritance Fortress
-- File: 20290000000175_100x_omnibus_supermarket_product_inheritance_fortress.sql
-- =============================================================================
--
-- 100x Forensic Enhancement:
--   1. Dual-Belonging Category Architecture:
--      A product belongs simultaneously to:
--        • Its specific item category (e.g. lipstick -> 'Cosmetics & Beauty')
--        • Its parent store category (e.g. Maxx Retail -> 'Supermarket / Hypermarket')
--   2. In get_feed_products and search_products_geospatial:
--      When browsing Supermarket, Hypermarket, Supermart, Hypermart, or Grocery:
--        • ALL products stocked in that Supermarket / Grocery shop are reflected and counted,
--          regardless of whether the product's item category is Cosmetics, Stationery, or Grocery.
--   3. Zero-Leakage Specialty Protection:
--      When browsing a specialty category (e.g. Cosmetics & Beauty):
--        • Only products whose item category actually matches Cosmetics & Beauty appear.
--        • Groceries/produce (Atta, Dal, Milk) from a supermarket will NEVER leak into Cosmetics.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. get_feed_products (with 100x Store-Level Category Inheritance)
-- ─────────────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.get_feed_products(uuid[], integer, text[]);

CREATE OR REPLACE FUNCTION public.get_feed_products(
  p_shop_ids uuid[],
  p_limit_per_shop integer DEFAULT 5,
  p_categories text[] DEFAULT NULL
)
RETURNS SETOF public.products
LANGUAGE sql
STABLE
AS $$
  SELECT p.*
  FROM public.products p
  INNER JOIN (
    SELECT 
      p_inner.id,
      ROW_NUMBER() OVER(PARTITION BY p_inner.shop_id ORDER BY p_inner.rating DESC, p_inner.created_at DESC) as rn
    FROM public.products p_inner
    INNER JOIN public.shops s_inner ON p_inner.shop_id = s_inner.id
    WHERE p_inner.shop_id = ANY(p_shop_ids::uuid[])
      AND p_inner.is_available = true
      AND p_inner.is_deleted = false
      AND s_inner.is_active = true
      AND COALESCE(s_inner.is_manually_closed, false) = false
      AND (
        p_categories IS NULL 
        OR p_inner.category = ANY(p_categories::text[])
        OR lower(trim(p_inner.category)) = ANY(SELECT lower(trim(x)) FROM unnest(p_categories::text[]) x)
        -- Grocery Low Margin match
        OR (
          lower(trim(p_inner.category)) IN ('grocerylm', 'grocery (low margin)', 'grocery low margin', 'grocery_lm')
          AND EXISTS (
            SELECT 1 FROM unnest(p_categories::text[]) cat_req
            WHERE lower(cat_req) LIKE '%grocery%'
               OR lower(cat_req) LIKE '%supermarket%'
               OR lower(cat_req) LIKE '%hypermarket%'
               OR lower(cat_req) LIKE '%supermart%'
               OR lower(cat_req) LIKE '%hypermart%'
          )
        )
        -- 100x Store-Level Category Inheritance:
        -- When customer browses Supermarket / Hypermarket / Grocery, include ALL products from Supermarket / Grocery shops!
        OR (
          EXISTS (
            SELECT 1 FROM unnest(p_categories::text[]) cat_req
            WHERE lower(cat_req) LIKE '%supermarket%' 
               OR lower(cat_req) LIKE '%hypermarket%' 
               OR lower(cat_req) LIKE '%supermart%' 
               OR lower(cat_req) LIKE '%hypermart%'
               OR lower(cat_req) LIKE '%grocery%'
               OR lower(cat_req) LIKE '%departmental%'
          )
          AND (
            lower(s_inner.category) LIKE '%supermarket%' OR
            lower(s_inner.category) LIKE '%hypermarket%' OR
            lower(s_inner.category) LIKE '%supermart%' OR
            lower(s_inner.category) LIKE '%hypermart%' OR
            lower(s_inner.category) LIKE '%grocery%' OR
            lower(s_inner.category) LIKE '%departmental%' OR
            lower(s_inner.category) LIKE '%general store%' OR
            lower(s_inner.category) LIKE '%provision store%' OR
            lower(s_inner.category) LIKE '%kirana%' OR
            (
              s_inner.categories IS NOT NULL 
              AND jsonb_typeof(s_inner.categories) = 'array'
              AND (
                s_inner.categories ?| p_categories::text[]
                OR EXISTS (
                  SELECT 1 
                  FROM jsonb_array_elements_text(s_inner.categories) elem
                  JOIN unnest(p_categories::text[]) target ON lower(trim(elem)) = lower(trim(target))
                )
              )
            )
          )
        )
      )
  ) r ON p.id = r.id
  WHERE r.rn <= p_limit_per_shop;
$$;

GRANT EXECUTE ON FUNCTION public.get_feed_products(uuid[], integer, text[]) TO authenticated, anon;


-- ─────────────────────────────────────────────────────────────────────────────
-- 2. search_products_geospatial (with unified Grocery & Supermarket Store Inheritance)
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
               OR lower(cat_req) LIKE '%supermart%'
               OR lower(cat_req) LIKE '%hypermart%'
          )
        )
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
  LIMIT LEAST(COALESCE(p_limit, 50), 300);
END;
$$;

GRANT EXECUTE ON FUNCTION public.search_products_geospatial(double precision, double precision, text, text[], double precision, int, int, text) TO authenticated, anon;

