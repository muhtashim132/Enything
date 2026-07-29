-- Migration: add_rider_distance_notifications.sql
-- Description: Adds location columns and functions for tracking online riders, and updates the push notification trigger.

-- 1. Add current_lat and current_lng for easier frontend access if needed
ALTER TABLE public.delivery_partners
  ADD COLUMN IF NOT EXISTS current_lat DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS current_lng DOUBLE PRECISION;

-- 2. Add config key for notification radius
INSERT INTO public.platform_config (key, value, label, description) 
VALUES ('rider_notification_radius_km', '15', 'Rider Notification Radius (km)', 'Radius for broadcasting new orders to online riders')
ON CONFLICT (key) DO NOTHING;

-- 3. Create RPC for updating rider location from the app
CREATE OR REPLACE FUNCTION update_rider_location(p_lat DOUBLE PRECISION, p_lng DOUBLE PRECISION)
RETURNS void AS $$
BEGIN
  UPDATE public.delivery_partners
  SET 
    current_lat = p_lat,
    current_lng = p_lng,
    location = ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)
  WHERE id = auth.uid();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Update the trigger to use ST_DWithin and the configurable radius
CREATE OR REPLACE FUNCTION handle_new_available_order_push()
RETURNS TRIGGER AS $$
DECLARE
  v_title TEXT;
  v_body TEXT;
  v_notif_key TEXT;
  v_rider record;
  v_amount TEXT;
  v_shop_location geography(Point, 4326);
  v_radius_km float;
BEGIN
  v_amount := COALESCE(NEW.total_amount::text, '0');

  -- Fetch configurable radius (default to 15.0 if not found)
  SELECT COALESCE((SELECT (value#>>'{}')::float FROM public.platform_config WHERE key = 'rider_notification_radius_km'), 15.0) INTO v_radius_km;

  -- Fetch shop location
  IF NEW.shop_id IS NOT NULL THEN
    SELECT location INTO v_shop_location FROM public.shops WHERE id = NEW.shop_id;
  END IF;

  IF (TG_OP = 'INSERT' AND NEW.status IN ('pending', 'awaiting_acceptance')) OR
     (TG_OP = 'UPDATE' AND NEW.status = 'pending' AND OLD.status != 'pending' AND NEW.delivery_partner_id IS NULL) 
  THEN
    
    v_title := '🔔 New Order Available!';
    v_body := 'A new order of ₹' || v_amount || ' is ready for pickup. Open the app to accept it!';

    -- Find all active and verified delivery partners within radius
    FOR v_rider IN 
      SELECT id FROM public.delivery_partners 
      WHERE is_active = true 
      AND verification_status IN ('verified', 'approved')
      AND location IS NOT NULL
      AND (v_shop_location IS NULL OR ST_DWithin(location, v_shop_location, v_radius_km * 1000))
    LOOP
      IF TG_OP = 'INSERT' THEN
        v_notif_key := NEW.id || '_new_available';
      ELSE
        v_notif_key := NEW.id || '_reassigned_' || extract(epoch from now())::int;
      END IF;

      INSERT INTO public.notifications (user_id, notif_key, title, body, order_id)
      VALUES (v_rider.id, v_notif_key, v_title, v_body, NEW.id)
      ON CONFLICT (user_id, notif_key) DO NOTHING;
    END LOOP;

  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
