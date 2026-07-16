-- Migration 20271114000000_100x_rider_tracking_customer_fix.sql
-- Fixes a critical regression where the rider's background location updates 
-- were overwriting the customer's delivery_lat/lng instead of updating rider_lat/lng.

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

  -- 1. Update the rider's own tracking table
  UPDATE delivery_partners
  SET location = ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326),
      last_location_lat = p_lat,
      last_location_lng = p_lng
  WHERE id = p_rider_id;

  -- 2. Cascade location to all active orders directly in DB without overwriting delivery_lat/lng
  UPDATE orders
  SET rider_lat = p_lat,
      rider_lng = p_lng,
      rider_location_updated_at = NOW()
  WHERE delivery_partner_id = p_rider_id
    AND status IN ('accepted', 'confirmed', 'preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery', 'delivering');

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION update_rider_location_bg(UUID, NUMERIC, NUMERIC, UUID) TO anon, authenticated;
