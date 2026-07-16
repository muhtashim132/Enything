-- Migration 20260849000000_100x_dead_rider_background_auth_fix.sql
-- Implements stateless cryptographic tracking secret for background location isolation.

ALTER TABLE public.delivery_partners ADD COLUMN IF NOT EXISTS bg_tracking_secret UUID DEFAULT gen_random_uuid();

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
  UPDATE orders
  SET delivery_lat = p_lat,
      delivery_lng = p_lng
  WHERE delivery_partner_id = p_rider_id
    AND status IN ('accepted', 'preparing', 'ready_for_pickup', 'delivering');

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION update_rider_location_bg(UUID, NUMERIC, NUMERIC, UUID) TO anon, authenticated;
