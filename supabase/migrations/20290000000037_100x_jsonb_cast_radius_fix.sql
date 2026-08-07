-- =============================================================================
-- Migration: 20290000000037_100x_jsonb_cast_radius_fix.sql
-- Description: Fixes a silent JSONB cast failure that swallowed the admin 
--              max_delivery_radius_km value and forced a fallback to 15.0km.
--              Also catches a missed 4-parameter overload of get_nearby_shops.
--              ADDITIVE ONLY. Keeps exact latest logic.
-- =============================================================================

-- 1. search_shops_geospatial
CREATE OR REPLACE FUNCTION public.search_shops_geospatial(
  p_lat double precision,
  p_lng double precision,
  p_query text DEFAULT NULL,
  p_categories text[] DEFAULT NULL,
  p_radius_km double precision DEFAULT 15.0,
  p_limit int DEFAULT 50
)
RETURNS SETOF public.shops AS $$
  DECLARE
    v_admin_max_radius double precision;
  BEGIN
    BEGIN
      SELECT (value#>>'{}')::double precision INTO v_admin_max_radius FROM public.platform_config WHERE key = 'max_delivery_radius_km';
      IF v_admin_max_radius IS NULL THEN v_admin_max_radius := 15.0; END IF;
    EXCEPTION WHEN OTHERS THEN v_admin_max_radius := 15.0;
    END;
    p_radius_km := LEAST(p_radius_km, v_admin_max_radius);
  RETURN QUERY
  SELECT s.*
  FROM public.shops s
  WHERE s.is_active = true
    AND s.is_accepting_orders = true
    AND s.location IS NOT NULL
    AND (p_query IS NULL OR s.name ILIKE '%' || p_query || '%')
    AND (p_categories IS NULL OR s.category = ANY(p_categories::text[]))
    AND ST_DWithin(
      s.location,
      ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
      p_radius_km * 1000
    )
  ORDER BY 
    ST_Distance(
      s.location,
      ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography
    ) ASC
  LIMIT LEAST(p_limit, 50);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.search_shops_geospatial(double precision, double precision, text, text[], double precision, int) TO authenticated, anon;


-- 2. search_products_geospatial
CREATE OR REPLACE FUNCTION public.search_products_geospatial(
  p_lat double precision,
  p_lng double precision,
  p_query text DEFAULT NULL,
  p_categories text[] DEFAULT NULL,
  p_radius_km double precision DEFAULT 15.0,
  p_limit int DEFAULT 50,
  p_limit_per_shop int DEFAULT 5,
  p_special_tag text DEFAULT NULL
)
RETURNS SETOF public.products AS $$
  DECLARE
    v_admin_max_radius double precision;
  BEGIN
    BEGIN
      SELECT (value#>>'{}')::double precision INTO v_admin_max_radius FROM public.platform_config WHERE key = 'max_delivery_radius_km';
      IF v_admin_max_radius IS NULL THEN v_admin_max_radius := 15.0; END IF;
    EXCEPTION WHEN OTHERS THEN v_admin_max_radius := 15.0;
    END;
    p_radius_km := LEAST(p_radius_km, v_admin_max_radius);
  RETURN QUERY
  SELECT p.*
  FROM (
    SELECT pr.*,
      ROW_NUMBER() OVER(PARTITION BY pr.shop_id ORDER BY pr.rating DESC, pr.created_at DESC) as rn
    FROM public.products pr
    WHERE pr.shop_id IN (
      SELECT s.id FROM public.shops s
      WHERE s.is_active = true
        AND s.is_accepting_orders = true
        AND s.location IS NOT NULL
        AND ST_DWithin(
          s.location,
          ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
          p_radius_km * 1000
        )
    )
    AND (p_query IS NULL OR pr.name ILIKE '%' || p_query || '%')
    AND (p_categories IS NULL OR pr.category = ANY(p_categories::text[]))
    AND (p_special_tag IS NULL OR pr.special_tags @> ARRAY[p_special_tag])
  ) p
  WHERE p.rn <= p_limit_per_shop
  LIMIT LEAST(p_limit, 50);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.search_products_geospatial(double precision, double precision, text, text[], double precision, int, int, text) TO authenticated, anon;


-- 3. get_nearby_shops (5-param with categories)
CREATE OR REPLACE FUNCTION public.get_nearby_shops(
  p_lat double precision,
  p_lng double precision,
  p_radius_km double precision DEFAULT 50.0,
  p_limit int DEFAULT 100,
  p_categories text[] DEFAULT NULL
)
RETURNS SETOF public.shops AS $$
  DECLARE
    v_admin_max_radius double precision;
  BEGIN
    BEGIN
      SELECT (value#>>'{}')::double precision INTO v_admin_max_radius FROM public.platform_config WHERE key = 'max_delivery_radius_km';
      IF v_admin_max_radius IS NULL THEN v_admin_max_radius := 15.0; END IF;
    EXCEPTION WHEN OTHERS THEN v_admin_max_radius := 15.0;
    END;
    p_radius_km := LEAST(p_radius_km, v_admin_max_radius);
  RETURN QUERY
  SELECT s.*
  FROM public.shops s
  WHERE s.is_active = true
    AND s.is_accepting_orders = true
    AND s.location IS NOT NULL
    AND (p_categories IS NULL OR s.category = ANY(p_categories::text[]))
    AND ST_DWithin(
      s.location,
      ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
      p_radius_km * 1000
    )
  ORDER BY 
    ST_Distance(
      s.location,
      ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography
    ) ASC
  LIMIT LEAST(p_limit, 100);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.get_nearby_shops(double precision, double precision, double precision, int, text[]) TO authenticated, anon;


-- 4. get_nearby_unassigned_orders
CREATE OR REPLACE FUNCTION public.get_nearby_unassigned_orders(
    p_rider_lat double precision DEFAULT NULL, 
    p_rider_lng double precision DEFAULT NULL, 
    p_radius_km double precision DEFAULT 15.0
)
 RETURNS SETOF public.orders
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_admin_max_radius double precision;
BEGIN
    BEGIN
      SELECT (value#>>'{}')::double precision INTO v_admin_max_radius FROM public.platform_config WHERE key = 'max_delivery_radius_km';
      IF v_admin_max_radius IS NULL THEN v_admin_max_radius := 15.0; END IF;
    EXCEPTION WHEN OTHERS THEN v_admin_max_radius := 15.0;
    END;
    
    p_radius_km := LEAST(p_radius_km, v_admin_max_radius);
    p_radius_km := GREATEST(p_radius_km, 1.0);

    IF p_rider_lat IS NULL OR p_rider_lng IS NULL THEN
        RETURN QUERY
        WITH eligible_groups AS (
          SELECT COALESCE(o.cart_group_id, o.id) as group_id, MIN(o.created_at) as created_at
          FROM public.orders o
          WHERE o.delivery_partner_id IS NULL
            AND o.status IN ('awaiting_acceptance', 'pending')
            -- EXCLUSIVE RIDER AFFINITY:
            AND NOT EXISTS (
                SELECT 1 FROM public.orders siblings
                WHERE COALESCE(siblings.cart_group_id, siblings.id) = COALESCE(o.cart_group_id, o.id)
                  AND siblings.delivery_partner_id IS NOT NULL
                  AND siblings.delivery_partner_id != auth.uid()
                  AND siblings.status NOT IN ('cancelled', 'delivered', 'returned', 'refunded', 'seller_rejected', 'partner_rejected', 'shop_dispute_cancel')
            )
          GROUP BY COALESCE(o.cart_group_id, o.id)
          ORDER BY MIN(o.created_at) DESC
          LIMIT 50
        )
        SELECT o.*
        FROM public.orders o
        JOIN eligible_groups eg ON COALESCE(o.cart_group_id, o.id) = eg.group_id
        WHERE o.status IN ('awaiting_acceptance', 'pending')
        ORDER BY o.created_at DESC;
    ELSE
        RETURN QUERY
        WITH eligible_groups AS (
          SELECT COALESCE(o.cart_group_id, o.id) as group_id, MIN(o.created_at) as created_at
          FROM public.orders o
          JOIN public.shops s ON o.shop_id = s.id
          WHERE o.delivery_partner_id IS NULL
            AND o.status IN ('awaiting_acceptance', 'pending')
            AND s.location IS NOT NULL
            AND ST_DWithin(
                s.location::geography, 
                ST_SetSRID(ST_MakePoint(p_rider_lng, p_rider_lat), 4326)::geography, 
                p_radius_km * 1000
            )
            -- EXCLUSIVE RIDER AFFINITY:
            AND NOT EXISTS (
                SELECT 1 FROM public.orders siblings
                WHERE COALESCE(siblings.cart_group_id, siblings.id) = COALESCE(o.cart_group_id, o.id)
                  AND siblings.delivery_partner_id IS NOT NULL
                  AND siblings.delivery_partner_id != auth.uid()
                  AND siblings.status NOT IN ('cancelled', 'delivered', 'returned', 'refunded', 'seller_rejected', 'partner_rejected', 'shop_dispute_cancel')
            )
          GROUP BY COALESCE(o.cart_group_id, o.id)
          ORDER BY MIN(o.created_at) ASC
          LIMIT 50
        )
        SELECT o.*
        FROM public.orders o
        JOIN eligible_groups eg ON COALESCE(o.cart_group_id, o.id) = eg.group_id
        WHERE o.status IN ('awaiting_acceptance', 'pending')
        ORDER BY o.created_at ASC;
    END IF;
END;
$function$;

GRANT EXECUTE ON FUNCTION get_nearby_unassigned_orders(double precision, double precision, double precision) TO authenticated;


-- 5. get_nearby_shops (4-param overload catch-all)
CREATE OR REPLACE FUNCTION public.get_nearby_shops(
  p_lat double precision, 
  p_lng double precision, 
  p_radius_km double precision DEFAULT 50.0, 
  p_limit integer DEFAULT 100
)
 RETURNS SETOF public.shops 
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
  DECLARE
    v_admin_max_radius double precision;
  BEGIN
    BEGIN
      SELECT (value#>>'{}')::double precision INTO v_admin_max_radius FROM public.platform_config WHERE key = 'max_delivery_radius_km';
      IF v_admin_max_radius IS NULL THEN v_admin_max_radius := 15.0; END IF;
    EXCEPTION WHEN OTHERS THEN v_admin_max_radius := 15.0;
    END;
    p_radius_km := LEAST(p_radius_km, v_admin_max_radius);
  RETURN QUERY
  SELECT s.*
  FROM public.shops s
  WHERE s.is_active = true
    AND s.is_accepting_orders = true
    AND s.location IS NOT NULL
    AND ST_DWithin(
      s.location,
      ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
      p_radius_km * 1000
    )
  ORDER BY 
    ST_Distance(
      s.location,
      ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography
    ) ASC
  LIMIT LEAST(p_limit, 100);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_nearby_shops(double precision, double precision, double precision, integer) TO authenticated, anon;
