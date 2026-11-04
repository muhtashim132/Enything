-- =============================================================================
-- Migration: 100x All-Categories Feed & Store-Level Inheritance Fortress
-- File: 20290000000178_100x_all_categories_feed_store_inheritance_fortress.sql
-- =============================================================================
--
-- 100x Forensic Parity & Zero-Leakage Architecture:
--   1. Direct Item Category Match:
--      Product's own category matches any of p_categories (case-insensitive).
--   2. Grocery Low Margin Match:
--      When browsing grocery/supermarket, includes grocerylm products.
--   3. Omnibus Store-Level Category Inheritance:
--      When browsing Supermarket, Hypermarket, or Grocery, includes ALL products
--      stocked in Supermarket / Grocery / Departmental stores (e.g. Maxx Retail).
--   4. Specialty Store Match for all other categories (Food, Pharmacy, Clothing, Electronics, More):
--      When browsing a specialty category, includes products from shops that belong
--      to that category (e.g. Restaurant, Pharmacy, Clothing, Electronics).
--   5. Zero-Leakage Specialty Protection:
--      Specialty store inheritance strictly excludes omnibus stores, guaranteeing that
--      general grocery/produce from a supermarket never leaks into specialty feeds
--      like Pharmacy or Food unless the product's item category explicitly matches.
-- =============================================================================

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
      p_inner.id,
      ROW_NUMBER() OVER(PARTITION BY p_inner.shop_id ORDER BY p_inner.rating DESC, p_inner.created_at DESC) as rn
    FROM public.products p_inner
    INNER JOIN public.shops s_inner ON p_inner.shop_id = s_inner.id
    WHERE p_inner.shop_id = ANY(p_shop_ids::uuid[])
      AND p_inner.is_available = true
      AND p_inner.is_deleted = false
      AND s_inner.is_active = true
      AND COALESCE(s_inner.is_manually_closed, false) = false
      AND (
        p_categories IS NULL 
        -- 1. Direct Item Category Match
        OR p_inner.category = ANY(p_categories::text[])
        OR lower(trim(p_inner.category)) = ANY(SELECT lower(trim(x)) FROM unnest(p_categories::text[]) x)
        -- 2. Grocery Low Margin match
        OR (
          lower(trim(p_inner.category)) IN ('grocerylm', 'grocery (low margin)', 'grocery low margin', 'grocery_lm')
          AND EXISTS (
            SELECT 1 FROM unnest(p_categories::text[]) cat_req
            WHERE lower(cat_req) LIKE '%grocery%'
               OR lower(cat_req) LIKE '%supermarket%'
               OR lower(cat_req) LIKE '%hypermarket%'
               OR lower(cat_req) LIKE '%supermart%'
               OR lower(cat_req) LIKE '%hypermart%'
          )
        )
        -- 3. 100x Omnibus Store-Level Category Inheritance:
        -- When customer browses Supermarket / Hypermarket / Grocery, include ALL products from Supermarket / Grocery shops!
        OR (
          EXISTS (
            SELECT 1 FROM unnest(p_categories::text[]) cat_req
            WHERE lower(cat_req) LIKE '%supermarket%' 
               OR lower(cat_req) LIKE '%hypermarket%' 
               OR lower(cat_req) LIKE '%supermart%' 
               OR lower(cat_req) LIKE '%hypermart%'
               OR lower(cat_req) LIKE '%grocery%'
               OR lower(cat_req) LIKE '%departmental%'
          )
          AND (
            lower(s_inner.category) LIKE '%supermarket%' OR
            lower(s_inner.category) LIKE '%hypermarket%' OR
            lower(s_inner.category) LIKE '%supermart%' OR
            lower(s_inner.category) LIKE '%hypermart%' OR
            lower(s_inner.category) LIKE '%grocery%' OR
            lower(s_inner.category) LIKE '%departmental%' OR
            lower(s_inner.category) LIKE '%general store%' OR
            lower(s_inner.category) LIKE '%provision store%' OR
            lower(s_inner.category) LIKE '%kirana%' OR
            (
              s_inner.categories IS NOT NULL 
              AND jsonb_typeof(s_inner.categories) = 'array'
              AND (
                s_inner.categories ?| p_categories::text[]
                OR EXISTS (
                  SELECT 1 
                  FROM jsonb_array_elements_text(s_inner.categories) elem
                  JOIN unnest(p_categories::text[]) target ON lower(trim(elem)) = lower(trim(target))
                )
              )
            )
          )
        )
        -- 4. 100x Specialty Store Match for all other categories (Food, Pharmacy, Clothing, Electronics, More):
        -- When browsing a specialty category, include products from shops whose store category matches.
        -- Zero-Leakage: Strictly excludes omnibus stores so grocery does not leak into specialty feeds.
        OR (
          NOT (
            lower(s_inner.category) LIKE '%supermarket%' OR
            lower(s_inner.category) LIKE '%hypermarket%' OR
            lower(s_inner.category) LIKE '%supermart%' OR
            lower(s_inner.category) LIKE '%hypermart%' OR
            lower(s_inner.category) LIKE '%grocery%' OR
            lower(s_inner.category) LIKE '%departmental%' OR
            lower(s_inner.category) LIKE '%general store%' OR
            lower(s_inner.category) LIKE '%provision store%' OR
            lower(s_inner.category) LIKE '%kirana%'
          )
          AND (
            s_inner.category = ANY(p_categories::text[])
            OR lower(trim(s_inner.category)) = ANY(SELECT lower(trim(x)) FROM unnest(p_categories::text[]) x)
            OR (
              s_inner.categories IS NOT NULL 
              AND jsonb_typeof(s_inner.categories) = 'array'
              AND (
                s_inner.categories ?| p_categories::text[]
                OR EXISTS (
                  SELECT 1 
                  FROM jsonb_array_elements_text(s_inner.categories) elem
                  JOIN unnest(p_categories::text[]) target ON lower(trim(elem)) = lower(trim(target))
                )
              )
            )
          )
        )
      )
  ) r ON p.id = r.id
  WHERE r.rn <= p_limit_per_shop;
$$;

GRANT EXECUTE ON FUNCTION public.get_feed_products(uuid[], integer, text[]) TO authenticated, anon;

