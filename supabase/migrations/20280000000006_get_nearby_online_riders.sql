-- =============================================================================
-- Migration: Add get_nearby_online_riders RPC for rider push notification
-- =============================================================================
-- This is a NEW, purely additive RPC. It does NOT modify any existing function,
-- table, or policy.
--
-- PURPOSE: Called from the checkout flow (client-side) AFTER an order is placed
-- to get the IDs of nearby online riders so push notifications can be sent to them.
-- This enables buzz notifications to riders even when their app is CLOSED/KILLED.
--
-- Returns: A table of (rider_id uuid) for all delivery_partners who are:
--   1. Currently online (is_accepting_orders = true)
--   2. Active and verified (is_active = true, verification_status = 'approved')
--   3. Within p_radius_km of the shop location
--   4. Have a known location (location IS NOT NULL)
--
-- Security:
--   - SECURITY DEFINER with search_path = public
--   - Callable by authenticated users only (customers placing orders)
--   - Only returns rider IDs (no PII, no location data returned)
--   - Rate-limited naturally: only called once per order placement
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_nearby_online_riders(
  p_shop_lat double precision,
  p_shop_lng double precision,
  p_radius_km double precision DEFAULT 15.0
)
RETURNS TABLE(rider_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Input validation: if coordinates are missing, return empty (safe default)
  IF p_shop_lat IS NULL OR p_shop_lng IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT dp.id AS rider_id
  FROM public.delivery_partners dp
  WHERE dp.is_accepting_orders = true
    AND dp.is_active = true
    AND dp.verification_status = 'approved'
    AND dp.location IS NOT NULL
    AND ST_DWithin(
        dp.location::geography,
        ST_SetSRID(ST_MakePoint(p_shop_lng, p_shop_lat), 4326)::geography,
        p_radius_km * 1000  -- Convert km to meters for ST_DWithin
    )
  LIMIT 50; -- Cap at 50 riders to prevent notification spam
END;
$function$;

-- Grant to authenticated users (customers) so checkout page can call it
GRANT EXECUTE ON FUNCTION public.get_nearby_online_riders(double precision, double precision, double precision) TO authenticated;
