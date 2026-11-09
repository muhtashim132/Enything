-- =============================================================================
-- Migration: 20290000000182_100x_cosmetics_and_multidepartment_feed_fortress.sql
-- Description: Upgrades public.get_feed_products to partition by shop_id and
--              department category, ensuring multi-department stores
--              (such as Supermarket / Hypermarket like Maxx Retail) return
--              diverse representations across both Grocery and Cosmetics & Beauty,
--              preventing one department from starving another out of the feed.
--              Also updates shops.categories for multi-department supermarkets.
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
      ROW_NUMBER() OVER(
        PARTITION BY 
          p_inner.shop_id,
          CASE 
            WHEN lower(p_inner.category) LIKE '%cosmetic%' OR lower(p_inner.category) LIKE '%beauty%' OR lower(p_inner.category) LIKE '%salon%' THEN 'Cosmetics'
            WHEN lower(p_inner.category) LIKE '%grocer%' OR lower(p_inner.category) LIKE '%supermarket%' OR lower(p_inner.category) LIKE '%hypermarket%' THEN 'Grocery'
            WHEN lower(p_inner.category) LIKE '%pharmac%' OR lower(p_inner.category) LIKE '%medic%' THEN 'Pharmacy'
            WHEN lower(p_inner.category) LIKE '%food%' OR lower(p_inner.category) LIKE '%restaurant%' OR lower(p_inner.category) LIKE '%bakery%' THEN 'Food'
            WHEN lower(p_inner.category) LIKE '%cloth%' OR lower(p_inner.category) LIKE '%footwear%' THEN 'Clothing'
            WHEN lower(p_inner.category) LIKE '%station%' THEN 'Stationery'
            ELSE COALESCE(p_inner.category, 'General')
          END
        ORDER BY p_inner.rating DESC, p_inner.created_at DESC
      ) as rn
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
  ) ranked ON p.id = ranked.id
  WHERE ranked.rn <= p_limit_per_shop
  ORDER BY p.rating DESC, p.created_at DESC;
$$;

GRANT EXECUTE ON FUNCTION public.get_feed_products(uuid[], integer, text[]) TO authenticated, anon;

-- Update Maxx Retail categories array to reflect multi-department capabilities
UPDATE public.shops
SET categories = '["Cosmetics & Beauty", "Grocerylm", "Grocery", "Supermarket / Hypermarket"]'::jsonb
WHERE id = '750b02ab-81f7-4023-929d-a9a00a8a8790';

