-- ============================================================================
-- Migration: 20290000000008_fix_trending_overloads.sql
-- Description: ADDITIVE ONLY — Drops all overloads of trending functions
--              to resolve PostgREST ambiguity (PGRST203) and cleanly
--              re-creates the final version.
-- ============================================================================

-- Drop all possible overloads
DROP FUNCTION IF EXISTS public.get_trending_keywords(int);
DROP FUNCTION IF EXISTS public.get_trending_keywords(int, text[]);
DROP FUNCTION IF EXISTS public.get_trending_keywords_geospatial(double precision, double precision, double precision, int);
DROP FUNCTION IF EXISTS public.get_trending_keywords_geospatial(double precision, double precision, double precision, int, text[]);

-- Recreate exactly with the correct signature
CREATE OR REPLACE FUNCTION public.get_trending_keywords(
  p_limit               int              DEFAULT 12,
  p_disabled_categories text[]           DEFAULT '{}'
)
RETURNS TABLE(keyword text)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT p.name AS keyword
  FROM public.products p
  INNER JOIN public.shops s ON p.shop_id = s.id
  LEFT JOIN (
    SELECT oi.product_name, o.shop_id, COUNT(*) as sales_count
    FROM public.order_items oi
    INNER JOIN public.orders o ON oi.order_id = o.id
    WHERE o.status = 'delivered' AND o.created_at >= NOW() - INTERVAL '30 days'
    GROUP BY oi.product_name, o.shop_id
  ) sales ON sales.product_name = p.name AND sales.shop_id = s.id
  WHERE p.is_available = true
    AND s.is_active = true
    AND s.is_accepting_orders = true
    AND (
      array_length(p_disabled_categories, 1) IS NULL
      OR s.category <> ALL(p_disabled_categories)
    )
  GROUP BY p.name
  ORDER BY SUM(COALESCE(sales.sales_count, 0)) DESC, p.name ASC
  LIMIT p_limit;
$$;

GRANT EXECUTE ON FUNCTION public.get_trending_keywords(int, text[]) TO authenticated, anon;

CREATE OR REPLACE FUNCTION public.get_trending_keywords_geospatial(
  p_lat                 double precision,
  p_lng                 double precision,
  p_radius_km           double precision DEFAULT 15.0,
  p_limit               int              DEFAULT 12,
  p_disabled_categories text[]           DEFAULT '{}'
)
RETURNS TABLE(keyword text)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT p.name AS keyword
  FROM public.products p
  INNER JOIN public.shops s ON p.shop_id = s.id
  LEFT JOIN (
    SELECT oi.product_name, o.shop_id, COUNT(*) as sales_count
    FROM public.order_items oi
    INNER JOIN public.orders o ON oi.order_id = o.id
    WHERE o.status = 'delivered' AND o.created_at >= NOW() - INTERVAL '30 days'
    GROUP BY oi.product_name, o.shop_id
  ) sales ON sales.product_name = p.name AND sales.shop_id = s.id
  WHERE p.is_available = true
    AND s.is_active = true
    AND s.is_accepting_orders = true
    AND s.location IS NOT NULL
    AND ST_DWithin(
           s.location,
           ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
           LEAST(GREATEST(p_radius_km, 1.0), 50.0) * 1000
         )
    AND (
      array_length(p_disabled_categories, 1) IS NULL
      OR s.category <> ALL(p_disabled_categories)
    )
  GROUP BY p.name
  ORDER BY SUM(COALESCE(sales.sales_count, 0)) DESC, p.name ASC
  LIMIT p_limit;
$$;

GRANT EXECUTE ON FUNCTION public.get_trending_keywords_geospatial(double precision, double precision, double precision, int, text[]) TO authenticated, anon;
