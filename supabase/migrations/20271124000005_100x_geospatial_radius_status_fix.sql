-- =============================================================================
-- Migration: 20271124000005_100x_geospatial_radius_status_fix.sql
-- Description: Fixes a critical Cartesian bug where `get_nearby_unassigned_orders`
--              would join back against the entire cart group without re-filtering
--              by status. This resulted in riders receiving `timeout` or `cancelled`
--              sub-orders, which cascaded into catastrophic RPC rejection logic.
--              100% ADDITIVE - only REPLACE FUNCTION used.
-- =============================================================================

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
      SELECT value::double precision INTO v_admin_max_radius FROM public.platform_config WHERE key = 'max_delivery_radius_km';
      IF v_admin_max_radius IS NULL THEN v_admin_max_radius := 15.0; END IF;
    EXCEPTION WHEN OTHERS THEN v_admin_max_radius := 15.0;
    END;
    
    -- Original Admin config constraint
    p_radius_km := LEAST(p_radius_km, v_admin_max_radius);
    
    -- 100x HARD CAP (Circuit Breaker against REST API Abuse & Admin Tampering)
    p_radius_km := LEAST(GREATEST(p_radius_km, 1.0), 50.0);

    IF p_rider_lat IS NULL OR p_rider_lng IS NULL THEN
        -- 100x FIX: Fetch by Cartesian Group LIMIT, not row LIMIT!
        RETURN QUERY
        WITH eligible_groups AS (
          SELECT COALESCE(o.cart_group_id, o.id) as group_id, MIN(o.created_at) as created_at
          FROM public.orders o
          WHERE o.delivery_partner_id IS NULL
            AND o.status IN ('awaiting_acceptance', 'pending')
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
        -- Geographic Proximity Search with Cartesian Group LIMIT
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
