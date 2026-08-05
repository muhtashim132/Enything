-- Migration 20290000000014_100x_rider_bg_location_fix.sql
-- Fixes a critical bug in background GPS tracking where the customer's delivery
-- drop-off location was being overwritten instead of the rider's coordinates.

CREATE OR REPLACE FUNCTION update_rider_location_bg(p_rider_id UUID, p_lat NUMERIC, p_lng NUMERIC, p_secret UUID)
RETURNS void AS $$
DECLARE
  v_secret UUID;
BEGIN
  -- Strict validation of secret
  SELECT bg_tracking_secret INTO v_secret 
  FROM delivery_partners 
  WHERE id = p_rider_id;

  IF v_secret IS NULL OR v_secret != p_secret THEN
    RAISE EXCEPTION 'Unauthorized tracking request: Secret mismatch';
  END IF;

  UPDATE delivery_partners
  SET location = ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326),
      last_location_lat = p_lat,
      last_location_lng = p_lng
  WHERE id = p_rider_id;

  -- 100x STRESS-TEST FIX: Cascade location to all active orders directly in DB
  -- CRITICAL BUG FIX: Ensure we update rider_lat/rider_lng, NOT delivery_lat/delivery_lng.
  -- Also updating rider_location_updated_at to trigger Realtime and using correct Enything statuses.
  UPDATE orders
  SET rider_lat = p_lat,
      rider_lng = p_lng,
      rider_location_updated_at = now() AT TIME ZONE 'utc'
  WHERE delivery_partner_id = p_rider_id
    AND status IN ('awaiting_payment', 'confirmed', 'preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery');

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION update_rider_location_bg(UUID, NUMERIC, NUMERIC, UUID) TO anon, authenticated;
