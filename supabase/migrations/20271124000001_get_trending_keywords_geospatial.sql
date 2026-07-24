-- ============================================================================
-- Migration: 20271124000001_get_trending_keywords_geospatial.sql
-- Description: ADDITIVE ONLY — new read-only RPC that returns the most-ordered
--              product names from the last 30 days of delivered orders,
--              filtered by an admin-defined delivery radius.
--
-- ADDITIVE GUARANTEE:
--   • CREATE OR REPLACE FUNCTION (new function, does not modify any existing one)
--   • No ALTER TABLE, no DROP, no trigger changes, no policy changes
--   • Uses existing ST_DWithin logic validated in search geospatial RPCs
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_trending_keywords_geospatial(
  p_lat double precision,
  p_lng double precision,
  p_radius_km double precision DEFAULT 15.0,
  p_limit int DEFAULT 12
)
RETURNS TABLE(keyword text)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT oi.product_name AS keyword
  FROM   public.order_items oi
  INNER JOIN public.orders o ON oi.order_id = o.id
  INNER JOIN public.shops s ON o.shop_id = s.id
  WHERE  oi.product_name IS NOT NULL
    AND  oi.product_name <> ''
    AND  length(trim(oi.product_name)) > 0
    AND  o.created_at >= NOW() - INTERVAL '30 days'
    AND  o.status = 'delivered'
    AND  s.location IS NOT NULL
    AND  ST_DWithin(
           s.location,
           ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
           p_radius_km * 1000
         )
  GROUP  BY oi.product_name
  ORDER  BY COUNT(*) DESC
  LIMIT  p_limit;
$$;

-- Grant execute to both roles
GRANT EXECUTE ON FUNCTION public.get_trending_keywords_geospatial(double precision, double precision, double precision, int) TO authenticated, anon;
