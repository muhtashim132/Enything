-- =============================================================================
-- Migration: Fix Rider Reorder Notifications
-- Description: Updates handle_new_available_order_push to correctly broadcast
--              to riders when an order is retried (status changes to 
--              awaiting_acceptance via UPDATE).
-- =============================================================================

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

  -- The critical fix: Trigger on UPDATE when status becomes 'awaiting_acceptance' (e.g. from 'cancelled' via retry_find_rider)
  IF (TG_OP = 'INSERT' AND NEW.status IN ('pending', 'awaiting_acceptance')) OR
     (TG_OP = 'UPDATE' AND NEW.status IN ('pending', 'awaiting_acceptance') AND OLD.status NOT IN ('pending', 'awaiting_acceptance') AND NEW.delivery_partner_id IS NULL) 
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
