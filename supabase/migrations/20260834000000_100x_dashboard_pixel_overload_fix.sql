-- Migration: 100x Dashboard Pixel Overload & Geographic Starvation Fix
-- Description: Offloads geographic distance calculations to PostGIS to prevent
--              massive network payload fetching and client-side OOM crashes.
--              Includes a hard limit of 100 orders to guarantee constant-time 
--              network egress for the rider app.

CREATE OR REPLACE FUNCTION get_nearby_unassigned_orders(
    p_rider_lat double precision DEFAULT NULL, 
    p_rider_lng double precision DEFAULT NULL, 
    p_radius_km double precision DEFAULT 15.0
)
RETURNS SETOF public.orders
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF p_rider_lat IS NULL OR p_rider_lng IS NULL THEN
        -- Fallback: Just return newest 100 unassigned orders globally if no GPS
        -- (Prevents the app from throwing an error before location is acquired)
        RETURN QUERY
        SELECT *
        FROM public.orders
        WHERE delivery_partner_id IS NULL
          AND status IN ('awaiting_acceptance', 'pending')
        ORDER BY created_at DESC
        LIMIT 100;
    ELSE
        -- Geographic Proximity Search:
        -- Utilizes PostGIS ST_DWithin to accurately filter orders within radius
        RETURN QUERY
        SELECT o.*
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
        ORDER BY o.created_at ASC
        LIMIT 100;
    END IF;
END;
$$;

-- Grant execute permissions to authenticated users (Delivery Partners)
GRANT EXECUTE ON FUNCTION get_nearby_unassigned_orders(double precision, double precision, double precision) TO authenticated;
