-- =============================================================================
-- Migration: 20290000000087_fix_rider_notification_verification_status.sql
-- =============================================================================
-- Description:
--   ADDITIVE ONLY:
--   Fixes get_nearby_online_riders() to accept BOTH 'verified' AND 'approved'
--   verification statuses, matching the filter used by the DB trigger
--   handle_new_available_order_push(). Previously only 'approved' was checked,
--   causing riders with 'verified' status to be silently excluded from
--   proximity-based push notifications.
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
    AND dp.verification_status IN ('verified', 'approved')
    AND dp.location IS NOT NULL
    AND ST_DWithin(
        dp.location::geography,
        ST_SetSRID(ST_MakePoint(p_shop_lng, p_shop_lat), 4326)::geography,
        p_radius_km * 1000  -- Convert km to meters for ST_DWithin
    )
  LIMIT 50; -- Cap at 50 riders to prevent notification spam
END;
$function$;
