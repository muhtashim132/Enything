-- Additive update to search_products_geospatial to support demographic filtering at the DB layer, preventing Limit-before-Filter pagination bugs.

DROP FUNCTION IF EXISTS public.search_products_geospatial(double precision, double precision, text, text[], double precision, int, int);

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
      AND (p_special_tag IS NULL OR p_special_tag = ANY(p.special_tags) OR '#Unisex' = ANY(p.special_tags))
      AND ST_DWithin(
        s.location,
        ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
        LEAST(p_radius_km, 100.0) * 1000
      )
  ) r ON p_outer.id = r.id
  INNER JOIN public.shops s2 ON p_outer.shop_id = s2.id
  WHERE r.rn <= LEAST(p_limit_per_shop, 20)
  ORDER BY 
    ST_Distance(
      s2.location,
      ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography
    ) ASC,
    p_outer.rating DESC
  LIMIT LEAST(p_limit, 50);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.search_products_geospatial(double precision, double precision, text, text[], double precision, int, int, text) TO authenticated, anon;
