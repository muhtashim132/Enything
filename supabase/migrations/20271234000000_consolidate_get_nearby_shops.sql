-- =============================================================================
-- Migration: Fix error 42809 — op ANY/ALL (array) requires array on right side
-- Root Cause: When PostgREST resolves DEFAULT NULL for a text[] parameter,
--   the NULL value may lose its array type annotation, causing
--   ANY(p_categories) to receive a non-array value at runtime.
-- Fix: Use explicit ::text[] cast on all ANY() calls for defensive safety.
-- =============================================================================

-- Drop existing versions so CREATE OR REPLACE picks up the new bodies
DROP FUNCTION IF EXISTS public.search_shops_geospatial(double precision, double precision, text, text[], double precision, int);
DROP FUNCTION IF EXISTS public.search_products_geospatial(double precision, double precision, text, text[], double precision, int, int);
DROP FUNCTION IF EXISTS public.search_products_geospatial(double precision, double precision, text, text[], double precision, int, int, text);

-- 1. search_shops_geospatial — defensive ::text[] cast
CREATE OR REPLACE FUNCTION public.search_shops_geospatial(
  p_lat double precision,
  p_lng double precision,
  p_query text DEFAULT NULL,
  p_categories text[] DEFAULT NULL,
  p_radius_km double precision DEFAULT 15.0,
  p_limit int DEFAULT 50
)
RETURNS SETOF public.shops AS $$
  DECLARE
    v_admin_max_radius double precision;
  BEGIN
    BEGIN
      SELECT value::double precision INTO v_admin_max_radius FROM public.platform_config WHERE key = 'max_delivery_radius_km';
      IF v_admin_max_radius IS NULL THEN v_admin_max_radius := 15.0; END IF;
    EXCEPTION WHEN OTHERS THEN v_admin_max_radius := 15.0;
    END;
    p_radius_km := LEAST(p_radius_km, v_admin_max_radius);
  RETURN QUERY
  SELECT s.*
  FROM public.shops s
  WHERE s.is_active = true
    AND s.is_accepting_orders = true
    AND s.location IS NOT NULL
    AND (p_query IS NULL OR s.name ILIKE '%' || p_query || '%')
    AND (p_categories IS NULL OR s.category = ANY(p_categories::text[]))
    AND ST_DWithin(
      s.location,
      ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
      LEAST(p_radius_km, 100.0) * 1000
    )
  ORDER BY 
    ST_Distance(
      s.location,
      ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography
    ) ASC
  LIMIT LEAST(p_limit, 50);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.search_shops_geospatial(double precision, double precision, text, text[], double precision, int) TO authenticated, anon;


-- 2. search_products_geospatial — defensive ::text[] cast + p_special_tag support
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
RETURNS SETOF public.products AS $$
  DECLARE
    v_admin_max_radius double precision;
  BEGIN
    BEGIN
      SELECT value::double precision INTO v_admin_max_radius FROM public.platform_config WHERE key = 'max_delivery_radius_km';
      IF v_admin_max_radius IS NULL THEN v_admin_max_radius := 15.0; END IF;
    EXCEPTION WHEN OTHERS THEN v_admin_max_radius := 15.0;
    END;
    p_radius_km := LEAST(p_radius_km, v_admin_max_radius);
  RETURN QUERY
  SELECT p.*
  FROM (
    SELECT pr.*,
      ROW_NUMBER() OVER(PARTITION BY pr.shop_id ORDER BY pr.rating DESC, pr.created_at DESC) as rn
    FROM public.products pr
    WHERE pr.shop_id IN (
      SELECT s.id FROM public.shops s
      WHERE s.is_active = true
        AND s.is_accepting_orders = true
        AND s.location IS NOT NULL
        AND ST_DWithin(
          s.location,
          ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
          LEAST(p_radius_km, 100.0) * 1000
        )
    )
    AND (p_query IS NULL OR pr.name ILIKE '%' || p_query || '%')
    AND (p_categories IS NULL OR pr.category = ANY(p_categories::text[]))
    AND (p_special_tag IS NULL OR pr.special_tags @> ARRAY[p_special_tag])
  ) p
  WHERE p.rn <= p_limit_per_shop
  LIMIT LEAST(p_limit, 50);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.search_products_geospatial(double precision, double precision, text, text[], double precision, int, int, text) TO authenticated, anon;


-- 3. get_nearby_shops (5-param with categories) — defensive ::text[] cast
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
    BEGIN
      SELECT value::double precision INTO v_admin_max_radius FROM public.platform_config WHERE key = 'max_delivery_radius_km';
      IF v_admin_max_radius IS NULL THEN v_admin_max_radius := 15.0; END IF;
    EXCEPTION WHEN OTHERS THEN v_admin_max_radius := 15.0;
    END;
    p_radius_km := LEAST(p_radius_km, v_admin_max_radius);
  RETURN QUERY
  SELECT s.*
  FROM public.shops s
  WHERE s.is_active = true
    AND s.is_accepting_orders = true
    AND s.location IS NOT NULL
    AND (p_categories IS NULL OR s.category = ANY(p_categories::text[]))
    AND ST_DWithin(
      s.location,
      ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
      LEAST(p_radius_km, 100.0) * 1000
    )
  ORDER BY 
    ST_Distance(
      s.location,
      ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography
    ) ASC
  LIMIT LEAST(p_limit, 100);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.get_nearby_shops(double precision, double precision, double precision, int, text[]) TO authenticated, anon;


-- 4. get_feed_products — defensive ::text[] and ::uuid[] casts
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
      id,
      ROW_NUMBER() OVER(PARTITION BY shop_id ORDER BY rating DESC, created_at DESC) as rn
    FROM public.products
    WHERE shop_id = ANY(p_shop_ids::uuid[])
      AND is_available = true
      AND (p_categories IS NULL OR category = ANY(p_categories::text[]))
  ) r ON p.id = r.id
  WHERE r.rn <= p_limit_per_shop;
$$;

GRANT EXECUTE ON FUNCTION public.get_feed_products(uuid[], integer, text[]) TO authenticated, anon;
