-- Phase 21: Fix Pixel Overloading (Feed Monopoly)
-- This RPC limits the number of products returned PER SHOP using window functions.
-- This ensures the home page feed shows a diverse set of products from all nearby shops
-- rather than being monopolized by the first shop that has 100+ products.

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
    WHERE shop_id = ANY(p_shop_ids)
      AND is_available = true
      AND (p_categories IS NULL OR category = ANY(p_categories))
  ) r ON p.id = r.id
  WHERE r.rn <= p_limit_per_shop;
$$;
