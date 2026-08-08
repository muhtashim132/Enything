-- Fix: get_feed_products and search_products_geospatial RPCs were NOT filtering
-- out soft-deleted products (is_deleted = true). This caused deleted products
-- to still appear on the customer home feed and search results, even though the
-- seller's Manage Products page correctly filtered them out.

-- 1. Fix get_feed_products — add AND is_deleted = false
DROP FUNCTION IF EXISTS public.get_feed_products(uuid[], integer, text[]);

CREATE OR REPLACE FUNCTION public.get_feed_products(
  p_shop_ids uuid[],
  p_limit_per_shop integer DEFAULT 5,
  p_categories text[] DEFAULT NULL
)
RETURNS SETOF public.products
LANGUAGE sql
STABLE
AS $$
  SELECT p.*
  FROM public.products p
  INNER JOIN (
    SELECT 
      id,
      ROW_NUMBER() OVER(PARTITION BY shop_id ORDER BY rating DESC, created_at DESC) as rn
    FROM public.products
    WHERE shop_id = ANY(p_shop_ids::uuid[])
      AND is_available = true
      AND is_deleted = false
      AND (p_categories IS NULL OR category = ANY(p_categories::text[]))
  ) r ON p.id = r.id
  WHERE r.rn <= p_limit_per_shop;
$$;

GRANT EXECUTE ON FUNCTION public.get_feed_products(uuid[], integer, text[]) TO authenticated, anon;


-- 2. Fix search_products_geospatial — add AND p.is_deleted = false
DROP FUNCTION IF EXISTS public.search_products_geospatial(double precision, double precision, text, text[], double precision, int, int);

CREATE OR REPLACE FUNCTION public.search_products_geospatial(
  p_lat double precision,
  p_lng double precision,
  p_query text DEFAULT NULL,
  p_categories text[] DEFAULT NULL,
  p_radius_km double precision DEFAULT 15.0,
  p_limit int DEFAULT 50,
  p_limit_per_shop int DEFAULT 5
)
RETURNS SETOF public.products AS $$
BEGIN
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
      AND p.is_deleted = false
      AND s.is_active = true
      AND s.location IS NOT NULL
      AND (p_query IS NULL OR p.name ILIKE '%' || p_query || '%')
      AND (p_categories IS NULL OR s.category = ANY(p_categories))
      AND ST_DWithin(
        s.location,
        ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
        p_radius_km * 1000
      )
  ) r ON p_outer.id = r.id
  INNER JOIN public.shops s2 ON p_outer.shop_id = s2.id
  WHERE r.rn <= p_limit_per_shop
  ORDER BY 
    ST_Distance(
      s2.location,
      ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography
    ) ASC,
    p_outer.rating DESC
  LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.search_products_geospatial(double precision, double precision, text, text[], double precision, int, int) TO authenticated, anon;


-- 3. Fix get_trending_keywords — add AND p.is_deleted = false
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
    AND p.is_deleted = false
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


-- 4. Fix get_trending_keywords_geospatial — add AND p.is_deleted = false
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
    AND p.is_deleted = false
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
