-- Additive RPC for Phase 31: Geospatial Starvation Fix (Storefront Blackout)
-- Drops and recreates RPCs to enforce s.is_accepting_orders = true

DROP FUNCTION IF EXISTS public.get_nearby_shops(double precision, double precision, double precision, int);
DROP FUNCTION IF EXISTS public.search_shops_geospatial(double precision, double precision, text, text[], double precision, int);
DROP FUNCTION IF EXISTS public.search_products_geospatial(double precision, double precision, text, text[], double precision, int, int);

-- 1. get_nearby_shops
CREATE OR REPLACE FUNCTION public.get_nearby_shops(
  p_lat double precision,
  p_lng double precision,
  p_radius_km double precision DEFAULT 50.0,
  p_limit int DEFAULT 100
)
RETURNS SETOF public.shops AS $$
BEGIN
  RETURN QUERY
  SELECT s.*
  FROM public.shops s
  WHERE s.is_active = true
    AND s.is_accepting_orders = true
    AND s.location IS NOT NULL
    AND ST_DWithin(
      s.location,
      ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
      p_radius_km * 1000
    )
  ORDER BY 
    ST_Distance(
      s.location,
      ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography
    ) ASC
  LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. search_shops_geospatial
CREATE OR REPLACE FUNCTION public.search_shops_geospatial(
  p_lat double precision,
  p_lng double precision,
  p_query text DEFAULT NULL,
  p_categories text[] DEFAULT NULL,
  p_radius_km double precision DEFAULT 15.0,
  p_limit int DEFAULT 50
)
RETURNS SETOF public.shops AS $$
BEGIN
  RETURN QUERY
  SELECT s.*
  FROM public.shops s
  WHERE s.is_active = true
    AND s.is_accepting_orders = true
    AND s.location IS NOT NULL
    AND (p_query IS NULL OR s.name ILIKE '%' || p_query || '%')
    AND (p_categories IS NULL OR s.category = ANY(p_categories))
    AND ST_DWithin(
      s.location,
      ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
      p_radius_km * 1000
    )
  ORDER BY 
    ST_Distance(
      s.location,
      ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography
    ) ASC
  LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. search_products_geospatial
CREATE OR REPLACE FUNCTION public.search_products_geospatial(
  p_lat double precision,
  p_lng double precision,
  p_query text DEFAULT NULL,
  p_categories text[] DEFAULT NULL,
  p_radius_km double precision DEFAULT 15.0,
  p_limit int DEFAULT 50,
  p_limit_per_shop int DEFAULT 5
)
RETURNS SETOF public.products AS $$
BEGIN
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
      AND s.is_active = true
      AND s.is_accepting_orders = true
      AND s.location IS NOT NULL
      AND (p_query IS NULL OR p.name ILIKE '%' || p_query || '%')
      AND (p_categories IS NULL OR s.category = ANY(p_categories))
      AND ST_DWithin(
        s.location,
        ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
        p_radius_km * 1000
      )
  ) r ON p_outer.id = r.id
  INNER JOIN public.shops s2 ON p_outer.shop_id = s2.id
  WHERE r.rn <= p_limit_per_shop
  ORDER BY 
    ST_Distance(
      s2.location,
      ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography
    ) ASC,
    p_outer.rating DESC
  LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.get_nearby_shops(double precision, double precision, double precision, int) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.search_shops_geospatial(double precision, double precision, text, text[], double precision, int) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.search_products_geospatial(double precision, double precision, text, text[], double precision, int, int) TO authenticated, anon;
