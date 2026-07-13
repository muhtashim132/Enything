-- Additive RPC for Phase 16: Geospatial Shop Fetching
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
    AND s.location->>'lat' IS NOT NULL
    AND s.location->>'lng' IS NOT NULL
    AND (
      6371 * acos(
        cos(radians(p_lat)) * 
        cos(radians((s.location->>'lat')::numeric)) * 
        cos(radians((s.location->>'lng')::numeric) - radians(p_lng)) + 
        sin(radians(p_lat)) * 
        sin(radians((s.location->>'lat')::numeric))
      )
    ) <= p_radius_km
  ORDER BY (
    6371 * acos(
      cos(radians(p_lat)) * 
      cos(radians((s.location->>'lat')::numeric)) * 
      cos(radians((s.location->>'lng')::numeric) - radians(p_lng)) + 
      sin(radians(p_lat)) * 
      sin(radians((s.location->>'lat')::numeric))
    )
  ) ASC
  LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.get_nearby_shops TO authenticated, anon;
