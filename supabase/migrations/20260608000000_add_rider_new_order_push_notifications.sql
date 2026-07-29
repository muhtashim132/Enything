-- Migration: add_rider_new_order_push_notifications.sql
-- Description: Creates a trigger that alerts online riders when a new order is available.

CREATE OR REPLACE FUNCTION handle_new_available_order_push()
RETURNS TRIGGER AS $$
DECLARE
  v_title TEXT;
  v_body TEXT;
  v_notif_key TEXT;
  v_rider record;
  v_amount TEXT;
BEGIN
  v_amount := COALESCE(NEW.total_amount::text, '0');

  IF (TG_OP = 'INSERT' AND NEW.status IN ('pending', 'awaiting_acceptance')) OR
     (TG_OP = 'UPDATE' AND NEW.status = 'pending' AND OLD.status != 'pending' AND NEW.delivery_partner_id IS NULL) 
  THEN
    
    v_title := '🔔 New Order Available!';
    v_body := 'A new order of ₹' || v_amount || ' is ready for pickup. Open the app to accept it!';

    -- Find all active and verified delivery partners
    FOR v_rider IN 
      SELECT id FROM public.delivery_partners 
      WHERE is_active = true 
      AND verification_status IN ('verified', 'approved')
    LOOP
      -- For inserts, use the order id. If it's a reassignment, use a unique key to allow a new notification.
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

DROP TRIGGER IF EXISTS tr_rider_new_order_push ON public.orders;

CREATE TRIGGER tr_rider_new_order_push
AFTER INSERT OR UPDATE ON public.orders
FOR EACH ROW
EXECUTE FUNCTION handle_new_available_order_push();
