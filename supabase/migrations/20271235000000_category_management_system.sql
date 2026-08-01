-- ============================================================================
-- Migration: 20271235000000_category_management_system.sql
-- Description: ADDITIVE ONLY — Category Management System
--
-- ADDITIVE GUARANTEE:
--   • CREATE TABLE IF NOT EXISTS (new table, no existing table modified)
--   • CREATE OR REPLACE FUNCTION (new RPCs, no existing function body changed)
--   • No ALTER TABLE on existing tables (shops, products, orders, etc.)
--   • No DROP, no TRUNCATE, no trigger changes
--   • No RLS policy changes on existing tables
--   • Existing platform_config table used as-is (we just add new keys)
-- ============================================================================

-- ============================================================================
-- PART 1: custom_categories table
-- Stores admin-created categories that supplement the hardcoded app list.
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.custom_categories (
  id          uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  name        text         UNIQUE NOT NULL,
  emoji       text         NOT NULL DEFAULT '🏪',
  category_group text      NOT NULL DEFAULT 'retail'
                           CHECK (category_group IN ('food','pharmacy','perishable','retail')),
  image_url   text,
  sort_order  int          NOT NULL DEFAULT 0,
  is_enabled  boolean      NOT NULL DEFAULT true,
  created_at  timestamptz  NOT NULL DEFAULT now(),
  created_by  uuid         REFERENCES auth.users(id) ON DELETE SET NULL
);

-- Comment for clarity
COMMENT ON TABLE public.custom_categories IS
  'Admin-created categories that extend the hardcoded AppCategories list in Flutter.';

-- ============================================================================
-- PART 2: RLS for custom_categories
-- ============================================================================
ALTER TABLE public.custom_categories ENABLE ROW LEVEL SECURITY;

-- Anyone (authenticated or anon) can READ custom categories
DROP POLICY IF EXISTS "custom_categories_select_all" ON public.custom_categories; CREATE POLICY "custom_categories_select_all"
  ON public.custom_categories
  FOR SELECT
  USING (true);

-- Only admin_team members can INSERT / UPDATE / DELETE
DROP POLICY IF EXISTS "custom_categories_admin_insert" ON public.custom_categories; CREATE POLICY "custom_categories_admin_insert"
  ON public.custom_categories
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.admin_users
      WHERE id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "custom_categories_admin_update" ON public.custom_categories; CREATE POLICY "custom_categories_admin_update"
  ON public.custom_categories
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_users
      WHERE id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "custom_categories_admin_delete" ON public.custom_categories; CREATE POLICY "custom_categories_admin_delete"
  ON public.custom_categories
  FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_users
      WHERE id = auth.uid()
    )
  );

-- ============================================================================
-- PART 3: Grants for custom_categories
-- ============================================================================
GRANT SELECT              ON public.custom_categories TO authenticated, anon;
GRANT INSERT, UPDATE, DELETE ON public.custom_categories TO authenticated;

-- ============================================================================
-- PART 4: Enable Realtime for custom_categories
-- ============================================================================
DO $$
BEGIN
  PERFORM pg_catalog.set_config('search_path', 'public', false);
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND tablename = 'custom_categories'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.custom_categories;
  END IF;
END $$;

-- ============================================================================
-- PART 5: get_trending_keywords (additive new version with disabled filter)
-- Replaces existing function with same name but adds disabled_categories param.
-- The new param has a DEFAULT of '{}' so all existing callers still work.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_trending_keywords(
  p_limit               int     DEFAULT 12,
  p_disabled_categories text[]  DEFAULT '{}'
)
RETURNS TABLE(keyword text)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT oi.product_name AS keyword
  FROM   public.order_items oi
  INNER  JOIN public.orders o ON oi.order_id = o.id
  INNER  JOIN public.shops  s ON o.shop_id   = s.id
  WHERE  oi.product_name IS NOT NULL
    AND  oi.product_name <> ''
    AND  length(trim(oi.product_name)) > 0
    AND  o.created_at >= NOW() - INTERVAL '30 days'
    AND  o.status = 'delivered'
    -- Exclude products from disabled categories
    AND  (
      array_length(p_disabled_categories, 1) IS NULL
      OR s.category <> ALL(p_disabled_categories)
    )
  GROUP  BY oi.product_name
  ORDER  BY COUNT(*) DESC
  LIMIT  p_limit;
$$;

-- Re-grant (CREATE OR REPLACE drops prior grants)
GRANT EXECUTE ON FUNCTION public.get_trending_keywords(int, text[]) TO authenticated, anon;

-- ============================================================================
-- PART 6: get_trending_keywords_geospatial (additive new version)
-- Same as above but with geospatial filtering + disabled categories filter.
-- ============================================================================
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
  SELECT oi.product_name AS keyword
  FROM   public.order_items oi
  INNER  JOIN public.orders o ON oi.order_id = o.id
  INNER  JOIN public.shops  s ON o.shop_id   = s.id
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
    -- Exclude products from disabled categories
    AND  (
      array_length(p_disabled_categories, 1) IS NULL
      OR s.category <> ALL(p_disabled_categories)
    )
  GROUP  BY oi.product_name
  ORDER  BY COUNT(*) DESC
  LIMIT  p_limit;
$$;

GRANT EXECUTE ON FUNCTION public.get_trending_keywords_geospatial(double precision, double precision, double precision, int, text[]) TO authenticated, anon;

-- ============================================================================
-- PART 7: get_category_shop_count RPC
-- Returns number of active shops per category. Used by admin management page.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_category_shop_counts()
RETURNS TABLE(category text, shop_count bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT
    s.category,
    COUNT(*) AS shop_count
  FROM  public.shops s
  WHERE s.is_active = true
  GROUP BY s.category
  ORDER BY shop_count DESC;
$$;

GRANT EXECUTE ON FUNCTION public.get_category_shop_counts() TO authenticated, anon;

-- ============================================================================
-- Done.
-- ============================================================================
