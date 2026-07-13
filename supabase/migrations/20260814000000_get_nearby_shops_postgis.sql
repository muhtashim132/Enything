-- Additive RPC for Phase 16/17: PostGIS Geospatial Shop Fetching
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

GRANT EXECUTE ON FUNCTION public.get_nearby_shops TO authenticated, anon;
