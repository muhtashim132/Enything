-- =============================================================================
-- Migration 20290000000148: 100x Geospatial Radius and Discovery Fortress
-- Description:
--   1. Fortifies get_nearby_unassigned_orders:
--      - When rider coordinates are NULL, strictly returns an empty set (RETURN;).
--        Prevents riders without GPS from receiving platform-wide orders.
--      - Respects admin-configured `rider_notification_radius_km`, with fallback
--        to `max_delivery_radius_km`.
--      - Enforces ST_DWithin against rider GPS coordinates.
--   2. Fortifies search_shops_geospatial:
--      - Uncaps artificial 50-shop limit, allowing up to LEAST(p_limit, 200).
--      - Enforces admin-configured `max_delivery_radius_km`.
--   3. Fortifies get_nearby_shops:
--      - Uncaps artificial 100-shop limit, allowing up to LEAST(p_limit, 500).
--      - Enforces admin-configured `max_delivery_radius_km`.
-- =============================================================================

-- 1. get_nearby_unassigned_orders (plpgsql)
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
    -- 100x FORTRESS: If rider coordinates are NULL, never return unassigned orders.
    -- Riders must have an active GPS fix to receive localized delivery alerts.
    IF p_rider_lat IS NULL OR p_rider_lng IS NULL THEN
        RETURN;
    END IF;

    -- Resolve admin-configured rider notification radius, with fallback to max delivery radius
    BEGIN
      SELECT (value#>>'{}')::double precision INTO v_admin_max_radius 
      FROM public.platform_config 
      WHERE key = 'rider_notification_radius_km';

      IF v_admin_max_radius IS NULL THEN
        SELECT (value#>>'{}')::double precision INTO v_admin_max_radius 
        FROM public.platform_config 
        WHERE key = 'max_delivery_radius_km';
      END IF;

      IF v_admin_max_radius IS NULL THEN 
        v_admin_max_radius := 15.0; 
      END IF;
    EXCEPTION WHEN OTHERS THEN 
      v_admin_max_radius := 15.0;
    END;
    
    p_radius_km := LEAST(COALESCE(p_radius_km, 15.0), v_admin_max_radius);
    p_radius_km := GREATEST(p_radius_km, 1.0);

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
    ORDER BY o.created_at DESC;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_nearby_unassigned_orders(double precision, double precision, double precision) TO authenticated;


-- 2. search_shops_geospatial (plpgsql)
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
  LIMIT LEAST(COALESCE(p_limit, 50), 200);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.search_shops_geospatial(double precision, double precision, text, text[], double precision, int) TO authenticated, anon;


-- 3. get_nearby_shops (plpgsql)
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

  p_radius_km := LEAST(COALESCE(p_radius_km, 50.0), v_admin_max_radius);
  p_radius_km := GREATEST(p_radius_km, 1.0);

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
  LIMIT LEAST(COALESCE(p_limit, 100), 500);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.get_nearby_shops(double precision, double precision, double precision, int, text[]) TO authenticated, anon;
