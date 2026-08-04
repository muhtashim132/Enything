-- ============================================================================
-- Migration: 20290000000011_trending_rename_immunity.sql
-- Description: ADDITIVE ONLY — Fixes cascading logic failure on product renames.
--              Modifies the left join in Trending RPCs to match on `product_id`
--              instead of `product_name`. This preserves a product's 30-day
--              sales history perfectly even if the shop renames the product,
--              while avoiding duplicate name multiplication anomalies.
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
    -- Fetch raw product identity so we can match sales deterministically by UUID,
    -- bypassing the vulnerability where a seller renaming a product wipes their history.
    SELECT p.id as product_id, p.name, s.id as shop_id
    FROM public.products p
    INNER JOIN public.shops s ON p.shop_id = s.id
    WHERE p.is_available = true
      AND (p.total_quantity IS NULL OR p.total_quantity > 0)
      AND s.is_active = true
      AND s.is_accepting_orders = true
      AND (
        array_length(p_disabled_categories, 1) IS NULL
        OR s.category <> ALL(p_disabled_categories)
      )
  ) active_products
  LEFT JOIN (
    -- Group sales by raw product UUID to capture the item's true historical popularity
    -- regardless of what its string name was 3 weeks ago.
    SELECT oi.product_id, o.shop_id, COUNT(*) as sales_count
    FROM public.order_items oi
    INNER JOIN public.orders o ON oi.order_id = o.id
    WHERE o.status = 'delivered' AND o.created_at >= NOW() - INTERVAL '30 days'
    GROUP BY oi.product_id, o.shop_id
  ) sales ON sales.product_id = active_products.product_id AND sales.shop_id = active_products.shop_id
  
  -- Group the final result by exact string name.
  -- This ensures "Burger" aggregates the exact count, deduplicating identical naming 
  -- naturally without artificially multiplying sales history.
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
    -- Fetch raw product identity so we can match sales deterministically by UUID.
    SELECT p.id as product_id, p.name, s.id as shop_id
    FROM public.products p
    INNER JOIN public.shops s ON p.shop_id = s.id
    WHERE p.is_available = true
      AND (p.total_quantity IS NULL OR p.total_quantity > 0)
      AND s.is_active = true
      AND s.is_accepting_orders = true
      AND s.location IS NOT NULL
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
    -- Group sales by raw product UUID to capture the item's true historical popularity.
    SELECT oi.product_id, o.shop_id, COUNT(*) as sales_count
    FROM public.order_items oi
    INNER JOIN public.orders o ON oi.order_id = o.id
    WHERE o.status = 'delivered' AND o.created_at >= NOW() - INTERVAL '30 days'
    GROUP BY oi.product_id, o.shop_id
  ) sales ON sales.product_id = active_products.product_id AND sales.shop_id = active_products.shop_id
  
  -- Group the final result by exact string name.
  GROUP BY active_products.name
  ORDER BY SUM(COALESCE(sales.sales_count, 0)) DESC, active_products.name ASC
  LIMIT LEAST(p_limit, 50);
$$;

GRANT EXECUTE ON FUNCTION public.get_trending_keywords_geospatial(double precision, double precision, double precision, int, text[]) TO authenticated, anon;
