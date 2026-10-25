-- =============================================================================
-- Migration 20290000000154: 100x Medicine Salts & Omni-Search Fortress
-- Description:
--   1. Calibrates search_products_geospatial to perform comprehensive, tokenized
--      multi-field matching across product name, description (salts & active chemical
--      composition), brand, category, sub_category, menu_category, medicine_type,
--      special_tags, and shop name.
--   2. Enables tokenized matching where every user search token is matched across
--      product fields (e.g. "Rosuvastatin 20", "Dolo 650", "Maggi noodles", "Slim jeans").
--   3. Avoids PostgREST PGRST203 overload ambiguity by dropping old overloads and
--      retaining a single canonical 8-parameter function with DEFAULT values.
--   4. Calibrates search_shops_geospatial so shops carrying matching products/salts
--      are also discovered in shop search results.
--   5. Strictly preserves soft-delete rule (p.is_deleted = false), availability,
--      closed-shop discovery parity, and admin max delivery radius.
-- =============================================================================

-- ── 1. Drop all prior overloads of search_products_geospatial to prevent PGRST203 ──
DROP FUNCTION IF EXISTS public.search_products_geospatial(double precision, double precision, text, text[], double precision, int, int, text);
DROP FUNCTION IF EXISTS public.search_products_geospatial(double precision, double precision, text, text[], double precision, int, int);
DROP FUNCTION IF EXISTS public.search_products_geospatial(double precision, double precision, text, text[], double precision, integer, integer);
DROP FUNCTION IF EXISTS public.search_products_geospatial(double precision, double precision, text, text[], double precision, int);

-- ── 2. Canonical search_products_geospatial ──────────────────────────────────
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
        OR s.category = ANY(p_categories)
        OR (s.categories IS NOT NULL AND s.categories ?| p_categories)
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
  ) r ON p_outer.id = r.id
  INNER JOIN public.shops s2 ON p_outer.shop_id = s2.id
  WHERE r.rn <= p_limit_per_shop
  ORDER BY 
    (s2.is_active AND s2.is_accepting_orders) DESC,
    ST_Distance(
      s2.location,
      ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography
    ) ASC,
    p_outer.rating DESC
  LIMIT p_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION public.search_products_geospatial(double precision, double precision, text, text[], double precision, int, int, text) TO authenticated, anon;


-- ── 3. search_shops_geospatial (Surfacing shops carrying matching products/salts)
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
      OR (s.categories IS NOT NULL AND s.categories ?| p_categories::text[])
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
