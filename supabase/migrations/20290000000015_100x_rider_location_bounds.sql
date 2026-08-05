-- Migration 20290000000015_100x_rider_location_bounds.sql
-- Fixes a critical PostGIS vulnerability where out-of-bounds coordinates
-- crash downstream geography-cast queries.

CREATE OR REPLACE FUNCTION update_rider_location_bg(p_rider_id UUID, p_lat NUMERIC, p_lng NUMERIC, p_secret UUID)
RETURNS void AS $$
DECLARE
  v_secret UUID;
  v_safe_lat NUMERIC;
  v_safe_lng NUMERIC;
BEGIN
  -- Strict validation of secret
  SELECT bg_tracking_secret INTO v_secret 
  FROM delivery_partners 
  WHERE id = p_rider_id;

  IF v_secret IS NULL OR v_secret != p_secret THEN
    RAISE EXCEPTION 'Unauthorized tracking request: Secret mismatch';
  END IF;

  -- 100x ARCHITECTURE FIX: Prevent PostGIS cascading failures from bad hardware/spoofing
  -- Clamp values to strict geography bounds
  v_safe_lat := LEAST(GREATEST(p_lat, -90.0), 90.0);
  v_safe_lng := LEAST(GREATEST(p_lng, -180.0), 180.0);

  UPDATE delivery_partners
  SET location = ST_SetSRID(ST_MakePoint(v_safe_lng, v_safe_lat), 4326),
      last_location_lat = v_safe_lat,
      last_location_lng = v_safe_lng
  WHERE id = p_rider_id;

  -- Cascade location to all active orders directly in DB
  UPDATE orders
  SET rider_lat = v_safe_lat,
      rider_lng = v_safe_lng,
      rider_location_updated_at = now() AT TIME ZONE 'utc'
  WHERE delivery_partner_id = p_rider_id
    AND status IN ('awaiting_payment', 'confirmed', 'preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery');

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION update_rider_location_bg(UUID, NUMERIC, NUMERIC, UUID) TO anon, authenticated;
