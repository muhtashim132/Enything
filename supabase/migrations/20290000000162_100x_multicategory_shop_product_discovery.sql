-- ==============================================================================
-- 100X FORENSIC FORTRESS: MULTI-CATEGORY SHOP & PRODUCT GEOSPATIAL DISCOVERY
-- ==============================================================================
-- Description:
--   Enables seamless customer discovery of multi-category omnibus shops
--   (Supermarkets, Hypermarkets, Supermarts, Departmental Stores) and their
--   cross-category inventory (e.g. Cosmetics, Stationery, Electronics, Pet Food)
--   across all geospatial search and browsing RPCs:
--
--   1. get_nearby_shops: Surfaces shops that carry active products in p_categories.
--   2. search_shops_geospatial: Surfaces shops that carry active products in p_categories.
--   3. search_products_geospatial: Verifies p.category in addition to shop category,
--      ensuring cosmetic/retail products in supermarkets appear in category discovery.
-- ==============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. get_nearby_shops
-- ─────────────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.get_nearby_shops(double precision, double precision, double precision, integer, text[]);
DROP FUNCTION IF EXISTS public.get_nearby_shops(double precision, double precision, double precision, int, text[]);

CREATE OR REPLACE FUNCTION public.get_nearby_shops(
  p_lat double precision,
  p_lng double precision,
  p_radius_km double precision DEFAULT 50.0,
  p_limit int DEFAULT 100,
  p_categories text[] DEFAULT NULL
)
RETURNS SETOF public.shops AS $$
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

  p_radius_km := LEAST(COALESCE(p_radius_km, 50.0), v_admin_max_radius);
  p_radius_km := GREATEST(p_radius_km, 1.0);

  RETURN QUERY
  SELECT s.*
  FROM public.shops s
  WHERE s.is_active = true
    AND COALESCE(s.is_manually_closed, false) = false
    AND s.location IS NOT NULL
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
  LIMIT LEAST(COALESCE(p_limit, 100), 500);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.get_nearby_shops(double precision, double precision, double precision, int, text[]) TO authenticated, anon;


-- ─────────────────────────────────────────────────────────────────────────────
-- 2. search_shops_geospatial
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
      OR EXISTS (
           SELECT 1 FROM public.products p_sub
           WHERE p_sub.shop_id = s.id
             AND p_sub.is_deleted = false
             AND p_sub.is_available = true
             AND (
               p_sub.name ILIKE '%' || p_query || '%'
               OR COALESCE(p_sub.description, '') ILIKE '%' || p_query || '%'
               OR COALESCE(p_sub.brand, '') ILIKE '%' || p_query || '%'
               OR COALESCE(p_sub.menu_category, '') ILIKE '%' || p_query || '%'
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


-- ─────────────────────────────────────────────────────────────────────────────
-- 3. search_products_geospatial
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
                p.name ILIKE '%' || trim(token) || '%'
                OR COALESCE(p.description, '') ILIKE '%' || trim(token) || '%'
                OR COALESCE(p.brand, '') ILIKE '%' || trim(token) || '%'
                OR COALESCE(p.category, '') ILIKE '%' || trim(token) || '%'
                OR COALESCE(p.sub_category, '') ILIKE '%' || trim(token) || '%'
                OR COALESCE(p.menu_category, '') ILIKE '%' || trim(token) || '%'
                OR COALESCE(p.medicine_type, '') ILIKE '%' || trim(token) || '%'
                OR COALESCE(p.special_tags::text, '') ILIKE '%' || trim(token) || '%'
                OR s.name ILIKE '%' || trim(token) || '%'
              )
          )
        )
      )
      AND (
        p_categories IS NULL 
        OR p.category = ANY(p_categories)
        OR lower(trim(p.category)) = ANY(SELECT lower(trim(x)) FROM unnest(p_categories) x)
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
        OR (p.special_tags IS NOT NULL AND (p.special_tags ? p_special_tag OR p.special_tags ? '#Unisex'))
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
