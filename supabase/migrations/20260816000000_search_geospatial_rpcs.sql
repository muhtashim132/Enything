-- Additive RPC for Phase 24: Search Bar Geospatial Starvation Fix
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

CREATE OR REPLACE FUNCTION public.search_products_geospatial(
  p_lat double precision,
  p_lng double precision,
  p_query text DEFAULT NULL,
  p_categories text[] DEFAULT NULL,
  p_radius_km double precision DEFAULT 15.0,
  p_limit int DEFAULT 50
)
RETURNS SETOF public.products AS $$
BEGIN
  RETURN QUERY
  SELECT p.*
  FROM public.products p
  INNER JOIN public.shops s ON p.shop_id = s.id
  WHERE p.is_available = true
    AND s.is_active = true
    AND s.location IS NOT NULL
    AND (p_query IS NULL OR p.name ILIKE '%' || p_query || '%')
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
    ) ASC,
    p.rating DESC
  LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.search_shops_geospatial TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.search_products_geospatial TO authenticated, anon;
