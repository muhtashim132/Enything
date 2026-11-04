-- =============================================================================
-- Migration: 100x Search Relevance & Exact Name Ranking Fortress
-- File: 20290000000179_100x_search_relevance_exact_name_ranking_fortress.sql
-- =============================================================================
--
-- 100x Forensic Enhancement:
--   1. Exact Name & Word Prefix Relevance Prioritization:
--      • Resolves the ranking anomaly where searching for concise exact product names
--        (e.g. "dew") ranked exact word matches like "dew 250" or "Dew 750 ml" at 7th or 8th
--        place behind compound-word substrings ("Dermadew") or body creams ("Vaseline Dewy").
--   2. Multi-Tiered SQL Search Relevance Scoring:
--      • Tier 1: Exact product name match (Score 1000).
--      • Tier 2: Product name starts with query followed by word boundary (Score 800, e.g. "Dew 750 ml", "dew 250").
--      • Tier 3: Product name starts with query (Score 600).
--      • Tier 4: Query is an isolated distinct word within title (Score 500, e.g. "Mountain Dew").
--      • Tier 5: Brand equals query (Score 400).
--      • Tier 6: Brand starts with query (Score 300).
--      • Tier 7: Word in title starts with query (Score 200, e.g. "Dewy").
--      • Tier 8: Substring inside word in title (Score 100, e.g. "Dermadew").
--      • Tier 9: Description / metadata match (Score 10).
--   3. Relevance-First Shop Partitioning:
--      • ROW_NUMBER() OVER (PARTITION BY p.shop_id) orders by relevance score first,
--        ensuring that exact query-matching products from a shop are never truncated
--        by p_limit_per_shop!
--   4. Title Compactness Bonus:
--      • Secondary tie-breaker prioritizes shorter, more concise titles closer to
--        query length over bloated description-heavy titles.
-- =============================================================================

DROP FUNCTION IF EXISTS public.search_products_geospatial(double precision, double precision, text, text[], double precision, int, int);
DROP FUNCTION IF EXISTS public.search_products_geospatial(double precision, double precision, text, text[], double precision, integer, integer);
DROP FUNCTION IF EXISTS public.search_products_geospatial(double precision, double precision, text, text[], double precision, int);
DROP FUNCTION IF EXISTS public.search_products_geospatial(double precision, double precision, text, text[], double precision, int, int, text);
DROP FUNCTION IF EXISTS public.search_products_geospatial(double precision, double precision, text, text[], double precision, integer, integer, text);

CREATE OR REPLACE FUNCTION public.search_products_geospatial(
  p_lat double precision,
  p_lng double precision,
  p_query text DEFAULT NULL,
  p_categories text[] DEFAULT NULL,
  p_radius_km double precision DEFAULT 15.0,
  p_limit int DEFAULT 100,
  p_limit_per_shop int DEFAULT 10,
  p_special_tag text DEFAULT NULL
)
RETURNS SETOF public.products
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_max_radius double precision;
  v_escaped_query text;
BEGIN
  IF p_lat IS NULL OR p_lng IS NULL THEN
    RETURN;
  END IF;

  BEGIN
    SELECT (value#>>'{}')::double precision INTO v_admin_max_radius 
    FROM public.platform_config 
    WHERE key = 'max_delivery_radius_km';
    IF v_admin_max_radius IS NULL THEN v_admin_max_radius := 15.0; END IF;
  EXCEPTION WHEN OTHERS THEN 
    v_admin_max_radius := 15.0;
  END;

  p_radius_km := LEAST(COALESCE(p_radius_km, 15.0), v_admin_max_radius);
  p_radius_km := GREATEST(p_radius_km, 1.0);

  IF p_query IS NOT NULL AND trim(p_query) != '' THEN
    v_escaped_query := regexp_replace(trim(p_query), '([.*+?^${}()|[\]\\])', '\\\1', 'g');
  ELSE
    v_escaped_query := NULL;
  END IF;

  RETURN QUERY
  SELECT p_outer.*
  FROM public.products p_outer
  INNER JOIN (
    SELECT 
      p.id,
      ROW_NUMBER() OVER(
        PARTITION BY p.shop_id 
        ORDER BY 
          -- 100x Relevance-First Partition Ordering
          (CASE 
            WHEN v_escaped_query IS NOT NULL THEN
              (CASE 
                -- 1. Exact name match
                WHEN lower(trim(p.name)) = lower(trim(p_query)) THEN 1000
                -- 2. Name starts with query followed by word boundary
                WHEN lower(trim(p.name)) ~* ('^' || v_escaped_query || '(\s|[-/|,()\[\]"]|$)') THEN 800
                -- 3. Name starts with query
                WHEN lower(trim(p.name)) LIKE lower(trim(p_query)) || '%' THEN 600
                -- 4. Distinct whole word in name
                WHEN lower(p.name) ~* ('\m' || v_escaped_query || '\M') THEN 500
                -- 5. Exact Brand match
                WHEN lower(trim(COALESCE(p.brand, ''))) = lower(trim(p_query)) THEN 400
                -- 6. Brand starts with query
                WHEN lower(trim(COALESCE(p.brand, ''))) LIKE lower(trim(p_query)) || '%' THEN 300
                -- 7. Word prefix in name (e.g. "Dewy")
                WHEN lower(p.name) ~* ('\m' || v_escaped_query) THEN 200
                -- 8. Substring inside name (e.g. "Dermadew")
                WHEN lower(p.name) LIKE '%' || lower(trim(p_query)) || '%' THEN 100
                -- 9. Description or salt match
                ELSE 10 
              END)
            ELSE 0 
          END) DESC,
          p.rating DESC, 
          p.created_at DESC
      ) as rn
    FROM public.products p
    INNER JOIN public.shops s ON p.shop_id = s.id
    WHERE p.is_available = true
      AND p.is_deleted = false
      AND s.is_active = true
      AND COALESCE(s.is_manually_closed, false) = false
      AND s.location IS NOT NULL
      -- 100x Multi-Token Omni-Search Matching across Name, Brand, Description, & Shop
      AND (
        p_query IS NULL 
        OR trim(p_query) = '' 
        OR (
          NOT EXISTS (
            SELECT 1 
            FROM unnest(string_to_array(trim(regexp_replace(p_query, '[,()"\x27]', ' ', 'g')), ' ')) AS token
            WHERE length(trim(token)) > 0
              AND NOT (
                -- Direct Token Matching across metadata and brand
                p.name ILIKE '%' || trim(token) || '%'
                OR COALESCE(p.brand, '') ILIKE '%' || trim(token) || '%'
                OR COALESCE(p.description, '') ILIKE '%' || trim(token) || '%'
                OR COALESCE(p.category, '') ILIKE '%' || trim(token) || '%'
                OR COALESCE(p.sub_category, '') ILIKE '%' || trim(token) || '%'
                OR COALESCE(p.menu_category, '') ILIKE '%' || trim(token) || '%'
                OR COALESCE(p.medicine_type, '') ILIKE '%' || trim(token) || '%'
                OR COALESCE(p.special_tags::text, '') ILIKE '%' || trim(token) || '%'
                OR s.name ILIKE '%' || trim(token) || '%'
                -- Plural-to-Singular Stemming (e.g. 'serums' -> 'serum')
                OR (
                  length(trim(token)) > 3 
                  AND lower(trim(token)) LIKE '%s'
                  AND (
                    p.name ILIKE '%' || substring(trim(token) from 1 for length(trim(token))-1) || '%'
                    OR COALESCE(p.brand, '') ILIKE '%' || substring(trim(token) from 1 for length(trim(token))-1) || '%'
                    OR COALESCE(p.description, '') ILIKE '%' || substring(trim(token) from 1 for length(trim(token))-1) || '%'
                  )
                )
                -- 100x Demographic Token Omni-Search:
                OR (
                  lower(trim(token)) IN ('men', 'mens', 'male', 'gents')
                  AND p.special_tags IS NOT NULL 
                  AND (p.special_tags ? '#Men' OR p.special_tags ? '#Unisex')
                )
                OR (
                  lower(trim(token)) IN ('women', 'womens', 'female', 'ladies', 'woman')
                  AND p.special_tags IS NOT NULL 
                  AND (p.special_tags ? '#Women' OR p.special_tags ? '#Unisex')
                )
                OR (
                  lower(trim(token)) IN ('boys', 'boy')
                  AND p.special_tags IS NOT NULL 
                  AND (p.special_tags ? '#Boys' OR p.special_tags ? '#Kids' OR p.special_tags ? '#Unisex')
                )
                OR (
                  lower(trim(token)) IN ('girls', 'girl')
                  AND p.special_tags IS NOT NULL 
                  AND (p.special_tags ? '#Girls' OR p.special_tags ? '#Kids' OR p.special_tags ? '#Unisex')
                )
                OR (
                  lower(trim(token)) IN ('kids', 'kid', 'children', 'child', 'toddler', 'infant')
                  AND p.special_tags IS NOT NULL 
                  AND (p.special_tags ? '#Kids' OR p.special_tags ? '#Boys' OR p.special_tags ? '#Girls' OR p.special_tags ? '#Unisex')
                )
                OR (
                  lower(trim(token)) = 'unisex'
                  AND p.special_tags IS NOT NULL 
                  AND p.special_tags ? '#Unisex'
                )
              )
          )
        )
      )
      -- Category Filter with 100x Store-Level Category Inheritance
      AND (
        p_categories IS NULL 
        OR p.category = ANY(p_categories)
        OR lower(trim(p.category)) = ANY(SELECT lower(trim(x)) FROM unnest(p_categories) x)
        -- Grocery Low Margin match
        OR (
          lower(trim(p.category)) IN ('grocerylm', 'grocery (low margin)', 'grocery low margin', 'grocery_lm')
          AND EXISTS (
            SELECT 1 FROM unnest(p_categories) cat_req
            WHERE lower(cat_req) LIKE '%grocery%'
               OR lower(cat_req) LIKE '%supermarket%'
               OR lower(cat_req) LIKE '%hypermarket%'
               OR lower(cat_req) LIKE '%supermart%'
               OR lower(cat_req) LIKE '%hypermart%'
          )
        )
        -- 100x Store-Level Category Inheritance:
        OR (
          (
            EXISTS (
              SELECT 1 FROM unnest(p_categories) cat_req
              WHERE lower(cat_req) LIKE '%supermarket%' 
                 OR lower(cat_req) LIKE '%hypermarket%' 
                 OR lower(cat_req) LIKE '%supermart%' 
                 OR lower(cat_req) LIKE '%hypermart%' 
                 OR lower(cat_req) LIKE '%grocery%'
                 OR lower(cat_req) LIKE '%departmental%'
            )
            OR NOT (
              lower(s.category) LIKE '%supermarket%' OR
              lower(s.category) LIKE '%hypermarket%' OR
              lower(s.category) LIKE '%supermart%' OR
              lower(s.category) LIKE '%hypermart%' OR
              lower(s.category) LIKE '%grocery%' OR
              lower(s.category) LIKE '%departmental%' OR
              lower(s.category) LIKE '%general store%' OR
              lower(s.category) LIKE '%provision store%' OR
              lower(s.category) LIKE '%kirana%'
            )
          ) AND (
            s.category = ANY(p_categories)
            OR lower(trim(s.category)) = ANY(SELECT lower(trim(x)) FROM unnest(p_categories) x)
            OR (
              s.categories IS NOT NULL 
              AND jsonb_typeof(s.categories) = 'array'
              AND (
                s.categories ?| p_categories
                OR EXISTS (
                  SELECT 1 
                  FROM jsonb_array_elements_text(s.categories) elem
                  JOIN unnest(p_categories) target ON lower(trim(elem)) = lower(trim(target))
                )
              )
            )
          )
        )
      )
      -- 100x Target Demographic Filter (ChoiceChips)
      AND (
        p_special_tag IS NULL 
        OR (
          p.special_tags IS NOT NULL AND (
            (p_special_tag IN ('#Men', 'Men') AND (p.special_tags ? '#Men' OR p.special_tags ? '#Unisex'))
            OR (p_special_tag IN ('#Women', 'Women') AND (p.special_tags ? '#Women' OR p.special_tags ? '#Unisex'))
            OR (p_special_tag IN ('#Boys', 'Boys') AND (p.special_tags ? '#Boys' OR p.special_tags ? '#Kids' OR p.special_tags ? '#Unisex'))
            OR (p_special_tag IN ('#Girls', 'Girls') AND (p.special_tags ? '#Girls' OR p.special_tags ? '#Kids' OR p.special_tags ? '#Unisex'))
            OR (p_special_tag IN ('#Kids', 'Kids') AND (p.special_tags ? '#Kids' OR p.special_tags ? '#Boys' OR p.special_tags ? '#Girls' OR p.special_tags ? '#Unisex'))
            OR (p_special_tag IN ('#Unisex', 'Unisex') AND p.special_tags ? '#Unisex')
            OR p.special_tags ? p_special_tag
            OR p.special_tags ? ('#' || p_special_tag)
            OR p.special_tags ? '#Unisex'
          )
        )
      )
      AND ST_DWithin(
        s.location,
        ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
        p_radius_km * 1000
      )
  ) filtered_ids ON p_outer.id = filtered_ids.id
  WHERE (p_limit_per_shop IS NULL OR filtered_ids.rn <= p_limit_per_shop)
  ORDER BY 
    -- 100x Global Search Relevance Scoring
    (CASE 
      WHEN v_escaped_query IS NOT NULL THEN
        (CASE 
          -- Tier 1: Exact product name match
          WHEN lower(trim(p_outer.name)) = lower(trim(p_query)) THEN 1000
          -- Tier 2: Product name starts with query as a distinct word (e.g. "Dew 750 ml", "dew 250")
          WHEN lower(trim(p_outer.name)) ~* ('^' || v_escaped_query || '(\s|[-/|,()\[\]"]|$)') THEN 800
          -- Tier 3: Product name starts with query prefix
          WHEN lower(trim(p_outer.name)) LIKE lower(trim(p_query)) || '%' THEN 600
          -- Tier 4: Query is an isolated distinct word inside product title (e.g. "Mountain Dew")
          WHEN lower(p_outer.name) ~* ('\m' || v_escaped_query || '\M') THEN 500
          -- Tier 5: Brand equals query
          WHEN lower(trim(COALESCE(p_outer.brand, ''))) = lower(trim(p_query)) THEN 400
          -- Tier 6: Brand starts with query
          WHEN lower(trim(COALESCE(p_outer.brand, ''))) LIKE lower(trim(p_query)) || '%' THEN 300
          -- Tier 7: A word in product name starts with query (e.g. "Dewy")
          WHEN lower(p_outer.name) ~* ('\m' || v_escaped_query) THEN 200
          -- Tier 8: Substring inside a single word in name (e.g. "Dermadew")
          WHEN lower(p_outer.name) LIKE '%' || lower(trim(p_query)) || '%' THEN 100
          -- Tier 9: Match in description or metadata only
          ELSE 10
        END)
      ELSE 0
    END) DESC,
    -- Compactness bonus: prefer shorter titles closer to query length over long titles
    (CASE WHEN v_escaped_query IS NOT NULL THEN length(p_outer.name) ELSE 0 END) ASC,
    p_outer.rating DESC,
    p_outer.created_at DESC
  LIMIT LEAST(COALESCE(p_limit, 100), 300);
END;
$$;

GRANT EXECUTE ON FUNCTION public.search_products_geospatial(double precision, double precision, text, text[], double precision, int, int, text) TO authenticated, anon;

