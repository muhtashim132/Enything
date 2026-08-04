-- ============================================================================
-- Migration: 20290000000009_trending_extreme_edge_cases_fix.sql
-- Description: ADDITIVE ONLY — Fixes extreme edge cases in Trending.
--              1. Removes radius capping to respect admin's absolute value.
--              2. Eliminates duplicate product name sales inflation using DISTINCT.
--              3. Applies hard-ceiling LIMIT LEAST(p_limit, 50) for protection.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_trending_keywords(
  p_limit               int              DEFAULT 12,
  p_disabled_categories text[]           DEFAULT '{}'
)
RETURNS TABLE(keyword text)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT active_products.name AS keyword
  FROM (
    -- DISTINCT eliminates duplicate product names within the same shop
    -- preventing sales multiplication logic failure.
    SELECT DISTINCT p.name, s.id as shop_id
    FROM public.products p
    INNER JOIN public.shops s ON p.shop_id = s.id
    WHERE p.is_available = true
      AND s.is_active = true
      AND s.is_accepting_orders = true
      AND (
        array_length(p_disabled_categories, 1) IS NULL
        OR s.category <> ALL(p_disabled_categories)
      )
  ) active_products
  LEFT JOIN (
    SELECT oi.product_name, o.shop_id, COUNT(*) as sales_count
    FROM public.order_items oi
    INNER JOIN public.orders o ON oi.order_id = o.id
    WHERE o.status = 'delivered' AND o.created_at >= NOW() - INTERVAL '30 days'
    GROUP BY oi.product_name, o.shop_id
  ) sales ON sales.product_name = active_products.name AND sales.shop_id = active_products.shop_id
  GROUP BY active_products.name
  ORDER BY SUM(COALESCE(sales.sales_count, 0)) DESC, active_products.name ASC
  LIMIT LEAST(p_limit, 50);
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
  SELECT active_products.name AS keyword
  FROM (
    -- DISTINCT eliminates duplicate product names within the same shop
    -- preventing sales multiplication logic failure.
    SELECT DISTINCT p.name, s.id as shop_id
    FROM public.products p
    INNER JOIN public.shops s ON p.shop_id = s.id
    WHERE p.is_available = true
      AND s.is_active = true
      AND s.is_accepting_orders = true
      AND s.location IS NOT NULL
      -- Strictly respect admin's provided radius without arbitrary clamping
      AND ST_DWithin(
             s.location,
             ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
             p_radius_km * 1000
           )
      AND (
        array_length(p_disabled_categories, 1) IS NULL
        OR s.category <> ALL(p_disabled_categories)
      )
  ) active_products
  LEFT JOIN (
    SELECT oi.product_name, o.shop_id, COUNT(*) as sales_count
    FROM public.order_items oi
    INNER JOIN public.orders o ON oi.order_id = o.id
    WHERE o.status = 'delivered' AND o.created_at >= NOW() - INTERVAL '30 days'
    GROUP BY oi.product_name, o.shop_id
  ) sales ON sales.product_name = active_products.name AND sales.shop_id = active_products.shop_id
  GROUP BY active_products.name
  ORDER BY SUM(COALESCE(sales.sales_count, 0)) DESC, active_products.name ASC
  LIMIT LEAST(p_limit, 50);
$$;

GRANT EXECUTE ON FUNCTION public.get_trending_keywords_geospatial(double precision, double precision, double precision, int, text[]) TO authenticated, anon;
