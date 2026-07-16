-- Migration: 100x_rider_gps_ddos_fix
-- Description: Overwrites update_rider_location to automatically cascade GPS updates to active orders, eliminating redundant background service select() and rpc() calls.

CREATE OR REPLACE FUNCTION public.update_rider_location(
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- 1. Update the rider's primary profile tracking
  UPDATE public.delivery_partners
  SET
    current_lat         = p_lat,
    current_lng         = p_lng,
    location_updated_at = NOW(),
    is_online           = true
  WHERE id = auth.uid();

  -- 2. Atomically cascade the GPS coordinates to all currently active assigned orders
  UPDATE public.orders
  SET 
    rider_lat = p_lat, 
    rider_lng = p_lng
  WHERE delivery_partner_id = auth.uid()
    AND status IN ('confirmed', 'preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery');

EXCEPTION WHEN OTHERS THEN
  -- Never throw exception; background isolate timer must keep running
  RAISE WARNING 'update_rider_location: failed for uid=%: %', auth.uid(), SQLERRM;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_rider_location(DOUBLE PRECISION, DOUBLE PRECISION) TO authenticated;
