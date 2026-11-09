-- =============================================================================
-- Migration: 20290000000183_100x_semantic_demographic_search_fortress.sql
-- Description: Upgrades public.search_products_geospatial to support human-like
--              semantic demographic search for gender and age queries
--              (e.g. 'woman', 'women', 'men', 'boys', 'girls', 'kids').
--              • Returns Women items + Unisex lifestyle items for 'woman'.
--              • Returns Men items + Unisex lifestyle items for 'men'.
--              • Strictly excludes Food/Grocery cooking items on pure demographic searches.
--              • Strictly isolates opposite genders (e.g. no beard oil in 'woman' search).
--              • Provides deterministic relevance ranking prioritizing target demographic
--                followed by unisex lifestyle products.
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
  v_is_pure_demo_women boolean := false;
  v_is_pure_demo_men boolean := false;
  v_is_pure_demo_kids boolean := false;
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
    IF lower(trim(p_query)) IN ('women', 'womens', 'female', 'ladies', 'woman') THEN
      v_is_pure_demo_women := true;
    ELSIF lower(trim(p_query)) IN ('men', 'mens', 'male', 'gents', 'man') THEN
      v_is_pure_demo_men := true;
    ELSIF lower(trim(p_query)) IN ('kids', 'kid', 'children', 'child', 'boy', 'boys', 'girl', 'girls', 'baby', 'infant') THEN
      v_is_pure_demo_kids := true;
    END IF;
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
                -- 1B. Pure Demographic Women Tier 1
                WHEN v_is_pure_demo_women AND (
                  (p.special_tags IS NOT NULL AND p.special_tags ? '#Women')
                  OR lower(p.category) IN ('cosmetics & beauty', 'jewellery')
                  OR lower(p.name) ~* '\m(lipstick|saree|kurti|bra|mascara|eyeliner|kajal|pads|heels)\M'
                ) THEN 950
                -- 1C. Pure Demographic Women Tier 2 (Unisex Lifestyle)
                WHEN v_is_pure_demo_women AND (
                  (p.special_tags IS NOT NULL AND p.special_tags ? '#Unisex')
                  OR lower(p.category) IN ('clothing', 'footwear', 'electronics', 'stationery')
                  OR lower(p.name) ~* '\m(sunscreen|moisturizer|face wash|shampoo|sneaker|backpack)\M'
                ) THEN 750
                -- 1D. Pure Demographic Men Tier 1
                WHEN v_is_pure_demo_men AND (
                  (p.special_tags IS NOT NULL AND p.special_tags ? '#Men')
                  OR lower(p.name) ~* '\m(beard|shaving|trimmer|boxer|briefs|sherwani|tie)\M'
                ) THEN 950
                -- 1E. Pure Demographic Men Tier 2 (Unisex Lifestyle)
                WHEN v_is_pure_demo_men AND (
                  (p.special_tags IS NOT NULL AND p.special_tags ? '#Unisex')
                  OR lower(p.category) IN ('clothing', 'footwear', 'electronics', 'stationery', 'salon & beauty')
                  OR lower(p.name) ~* '\m(sunscreen|moisturizer|face wash|shampoo|sneaker|backpack)\M'
                ) THEN 750
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
                -- 100x Semantic Demographic Token Omni-Search:
                OR (
                  lower(trim(token)) IN ('women', 'womens', 'female', 'ladies', 'woman')
                  AND (
                    (p.special_tags IS NOT NULL AND (p.special_tags ? '#Women' OR p.special_tags ? '#Unisex'))
                    OR lower(p.category) IN ('cosmetics & beauty', 'salon & beauty', 'jewellery')
                    OR (
                      lower(p.category) IN ('clothing', 'footwear', 'electronics', 'stationery', 'sports', 'home decor', 'pharmacy', 'medical store')
                      AND NOT (lower(p.name) ~* '\m(men|mens|men''s|male|gents|beard|boxer|boxers|briefs)\M')
                    )
                    OR lower(p.name) ~* '\m(lipstick|mascara|kajal|eyeliner|foundation|blush|nail|pad|pads|napkin|tampon|saree|sari|kurti|lehenga|dupatta|dress|frock|bra|heels|bellies|handbag|purse|earring|earrings|jhumka|bangle|bangles|mangalsutra|serum|lotion|shampoo|sunscreen|moisturizer|face wash|backpack|sneaker)\M'
                  )
                  AND NOT (
                    v_is_pure_demo_women
                    AND lower(p.category) IN ('food', 'restaurant', 'fast food', 'bakery', 'sweets & mithai', 'butcher', 'fish & seafood', 'dairy & eggs', 'fruits & vegs', 'grocery', 'grocerylm', 'grocery (low margin)', 'ice cream', 'paan shop', 'beverages')
                  )
                  AND NOT (lower(p.name) ~* '\m(beard|aftershave|boxers|briefs)\M')
                )
                OR (
                  lower(trim(token)) IN ('men', 'mens', 'male', 'gents', 'man')
                  AND (
                    (p.special_tags IS NOT NULL AND (p.special_tags ? '#Men' OR p.special_tags ? '#Unisex'))
                    OR (
                      lower(p.category) IN ('clothing', 'footwear', 'electronics', 'stationery', 'sports', 'home decor', 'salon & beauty', 'cosmetics & beauty', 'pharmacy', 'medical store')
                      AND NOT (lower(p.name) ~* '\m(women|womens|women''s|female|ladies|saree|kurti|bra|lipstick|heels|sanitary|pad|pads|napkin|tampon)\M')
                    )
                    OR lower(p.name) ~* '\m(beard|shaving|trimmer|boxer|boxers|briefs|sherwani|cufflinks|tie|men|serum|lotion|shampoo|sunscreen|moisturizer|face wash|backpack|sneaker)\M'
                  )
                  AND NOT (
                    v_is_pure_demo_men
                    AND lower(p.category) IN ('food', 'restaurant', 'fast food', 'bakery', 'sweets & mithai', 'butcher', 'fish & seafood', 'dairy & eggs', 'fruits & vegs', 'grocery', 'grocerylm', 'grocery (low margin)', 'ice cream', 'paan shop', 'beverages')
                  )
                  AND NOT (lower(p.name) ~* '\m(saree|kurti|lehenga|bra|lipstick|mascara|kajal|high heels|sanitary pad)\M')
                )
                OR (
                  lower(trim(token)) IN ('boys', 'boy')
                  AND (
                    (p.special_tags IS NOT NULL AND (p.special_tags ? '#Boys' OR p.special_tags ? '#Kids' OR p.special_tags ? '#Unisex'))
                    OR lower(p.category) IN ('toys & games', 'stationery', 'clothing', 'footwear')
                    OR lower(p.name) ~* '\m(boy|boys|toy|action figure|cars|shorts)\M'
                  )
                )
                OR (
                  lower(trim(token)) IN ('girls', 'girl')
                  AND (
                    (p.special_tags IS NOT NULL AND (p.special_tags ? '#Girls' OR p.special_tags ? '#Kids' OR p.special_tags ? '#Unisex'))
                    OR lower(p.category) IN ('toys & games', 'stationery', 'clothing', 'footwear', 'jewellery')
                    OR lower(p.name) ~* '\m(girl|girls|doll|barbie|frock|skirt|hair clip)\M'
                  )
                )
                OR (
                  lower(trim(token)) IN ('kids', 'kid', 'children', 'child', 'toddler', 'infant', 'baby', 'babies')
                  AND (
                    (p.special_tags IS NOT NULL AND (p.special_tags ? '#Kids' OR p.special_tags ? '#Boys' OR p.special_tags ? '#Girls' OR p.special_tags ? '#Unisex'))
                    OR lower(p.category) IN ('toys & games', 'stationery')
                    OR lower(p.name) ~* '\m(diaper|baby|infant|toddler|toy|doll|puzzle)\M'
                  )
                )
                OR (
                  lower(trim(token)) = 'unisex'
                  AND (
                    (p.special_tags IS NOT NULL AND p.special_tags ? '#Unisex')
                    OR lower(p.category) IN ('electronics', 'stationery', 'sports', 'home decor')
                  )
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
          -- Tier 1B: Pure Demographic Women Tier 1
          WHEN v_is_pure_demo_women AND (
            (p_outer.special_tags IS NOT NULL AND p_outer.special_tags ? '#Women')
            OR lower(p_outer.category) IN ('cosmetics & beauty', 'jewellery')
            OR lower(p_outer.name) ~* '\m(lipstick|saree|kurti|bra|mascara|eyeliner|kajal|pads|heels)\M'
          ) THEN 950
          -- Tier 1C: Pure Demographic Women Tier 2 (Unisex Lifestyle)
          WHEN v_is_pure_demo_women AND (
            (p_outer.special_tags IS NOT NULL AND p_outer.special_tags ? '#Unisex')
            OR lower(p_outer.category) IN ('clothing', 'footwear', 'electronics', 'stationery')
            OR lower(p_outer.name) ~* '\m(sunscreen|moisturizer|face wash|shampoo|sneaker|backpack)\M'
          ) THEN 750
          -- Tier 1D: Pure Demographic Men Tier 1
          WHEN v_is_pure_demo_men AND (
            (p_outer.special_tags IS NOT NULL AND p_outer.special_tags ? '#Men')
            OR lower(p_outer.name) ~* '\m(beard|shaving|trimmer|boxer|briefs|sherwani|tie)\M'
          ) THEN 950
          -- Tier 1E: Pure Demographic Men Tier 2 (Unisex Lifestyle)
          WHEN v_is_pure_demo_men AND (
            (p_outer.special_tags IS NOT NULL AND p_outer.special_tags ? '#Unisex')
            OR lower(p_outer.category) IN ('clothing', 'footwear', 'electronics', 'stationery', 'salon & beauty')
            OR lower(p_outer.name) ~* '\m(sunscreen|moisturizer|face wash|shampoo|sneaker|backpack)\M'
          ) THEN 750
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

