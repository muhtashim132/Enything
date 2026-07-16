-- Additive RPC to prevent Category Starvation
-- Resolves the issue where limiting to 100 closest shops first, then filtering by category locally, causes empty results.

CREATE OR REPLACE FUNCTION public.get_nearby_shops(
  p_lat double precision,
  p_lng double precision,
  p_radius_km double precision DEFAULT 50.0,
  p_limit int DEFAULT 100,
  p_categories text[] DEFAULT NULL
)
RETURNS SETOF public.shops AS $$
BEGIN
  RETURN QUERY
  SELECT s.*
  FROM public.shops s
  WHERE s.is_active = true
    AND s.is_accepting_orders = true
    AND s.location IS NOT NULL
    AND (p_categories IS NULL OR s.category = ANY(p_categories))
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
