-- Migration 20290000000097_100x_flawless_live_tracking_and_location_sync.sql
-- 100x Flawless Live Tracking & Location Sync Engine
-- Unifies foreground and background GPS broadcasts with PostGIS synchronization,
-- coordinate boundary clamping, and atomic order location timestamp cascading.

-- 1. Foreground RPC: update_rider_location (called by active app session)
CREATE OR REPLACE FUNCTION public.update_rider_location(
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_safe_lat DOUBLE PRECISION;
  v_safe_lng DOUBLE PRECISION;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN;
  END IF;

  -- 100x PostGIS & boundary protection: clamp coordinates to valid geographic bounds
  v_safe_lat := LEAST(GREATEST(p_lat, -90.0), 90.0);
  v_safe_lng := LEAST(GREATEST(p_lng, -180.0), 180.0);

  -- Update delivery_partners profile with all coordinate representations
  UPDATE public.delivery_partners
  SET
    current_lat         = v_safe_lat,
    current_lng         = v_safe_lng,
    last_location_lat   = v_safe_lat,
    last_location_lng   = v_safe_lng,
    location            = ST_SetSRID(ST_MakePoint(v_safe_lng, v_safe_lat), 4326),
    location_updated_at = NOW(),
    is_online           = true
  WHERE id = auth.uid();

  -- Atomically cascade GPS coordinates and updated_at timestamp to all active orders
  UPDATE public.orders
  SET
    rider_lat                 = v_safe_lat,
    rider_lng                 = v_safe_lng,
    rider_location_updated_at = NOW()
  WHERE delivery_partner_id = auth.uid()
    AND status IN (
      'awaiting_payment',
      'confirmed',
      'preparing',
      'ready_for_pickup',
      'picked_up',
      'out_for_delivery'
    );

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'update_rider_location: error for uid=%: %', auth.uid(), SQLERRM;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_rider_location(DOUBLE PRECISION, DOUBLE PRECISION) TO authenticated, anon;


-- 2. Background Isolate RPC: update_rider_location_bg (called with secret token)
CREATE OR REPLACE FUNCTION public.update_rider_location_bg(
  p_rider_id UUID,
  p_lat NUMERIC,
  p_lng NUMERIC,
  p_secret UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_secret UUID;
  v_safe_lat NUMERIC;
  v_safe_lng NUMERIC;
BEGIN
  -- Strict validation of background tracking secret
  SELECT bg_tracking_secret INTO v_secret 
  FROM public.delivery_partners 
  WHERE id = p_rider_id;

  IF v_secret IS NULL OR v_secret != p_secret THEN
    RAISE EXCEPTION 'Unauthorized tracking request: Secret mismatch';
  END IF;

  -- 100x Boundary clamping
  v_safe_lat := LEAST(GREATEST(p_lat, -90.0), 90.0);
  v_safe_lng := LEAST(GREATEST(p_lng, -180.0), 180.0);

  -- Update delivery_partners
  UPDATE public.delivery_partners
  SET
    current_lat         = v_safe_lat,
    current_lng         = v_safe_lng,
    last_location_lat   = v_safe_lat,
    last_location_lng   = v_safe_lng,
    location            = ST_SetSRID(ST_MakePoint(v_safe_lng, v_safe_lat), 4326),
    location_updated_at = NOW(),
    is_online           = true
  WHERE id = p_rider_id;

  -- Atomically cascade to active orders
  UPDATE public.orders
  SET
    rider_lat                 = v_safe_lat,
    rider_lng                 = v_safe_lng,
    rider_location_updated_at = NOW()
  WHERE delivery_partner_id = p_rider_id
    AND status IN (
      'awaiting_payment',
      'confirmed',
      'preparing',
      'ready_for_pickup',
      'picked_up',
      'out_for_delivery'
    );

EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'update_rider_location_bg: error for rider_id=%: %', p_rider_id, SQLERRM;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_rider_location_bg(UUID, NUMERIC, NUMERIC, UUID) TO anon, authenticated;
