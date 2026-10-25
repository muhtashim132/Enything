-- ==============================================================================
-- 100X FORENSIC FORTRESS: FIX GET_NEARBY_SHOPS FUNCTION OVERLOAD AMBIGUITY (PGRST203)
-- ==============================================================================
-- Removes redundant 4-parameter overload of get_nearby_shops which causes PostgREST
-- error PGRST203 ('Could not choose the best candidate function between 4-param
-- and 5-param') when called without the optional p_categories parameter.
-- The 5-parameter version already provides `p_categories text[] DEFAULT NULL`,
-- seamlessly handling 2, 3, 4, or 5 parameter invocations with zero ambiguity.

DROP FUNCTION IF EXISTS public.get_nearby_shops(double precision, double precision, double precision, integer);
DROP FUNCTION IF EXISTS public.get_nearby_shops(double precision, double precision, double precision, int);

-- Re-assert 5-parameter canonical function with multi-category array support
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
    AND s.location IS NOT NULL
    AND (
      p_categories IS NULL 
      OR s.category = ANY(p_categories::text[])
      OR (s.categories IS NOT NULL AND s.categories && p_categories::text[])
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
