-- ============================================================================
-- Migration: 20271123000000_get_trending_keywords_rpc.sql
-- Description: ADDITIVE ONLY — new read-only RPC that returns the most-ordered
--              product names from the last 30 days of delivered orders.
--              Used by the home page Trending Strip to show real trending items
--              instead of a hardcoded static list.
--
-- ADDITIVE GUARANTEE:
--   • CREATE OR REPLACE FUNCTION (new function, does not modify any existing one)
--   • No ALTER TABLE, no DROP, no trigger changes, no policy changes
--   • Only reads: order_items, orders (existing tables, existing columns)
--   • product_name column confirmed in order_items (migration 20260892000000)
--   • status column confirmed in orders (core column)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_trending_keywords(
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
  WHERE  oi.product_name IS NOT NULL
    AND  oi.product_name <> ''
    AND  length(trim(oi.product_name)) > 0
    AND  o.created_at >= NOW() - INTERVAL '30 days'
    AND  o.status = 'delivered'
  GROUP  BY oi.product_name
  ORDER  BY COUNT(*) DESC
  LIMIT  p_limit;
$$;

-- Grant execute to both roles (matches pattern of all other RPCs in this project)
GRANT EXECUTE ON FUNCTION public.get_trending_keywords(int) TO authenticated, anon;
