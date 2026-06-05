-- Replaces the handle_kyc_notifications function with SECURITY DEFINER
-- This ensures the trigger has permission to insert admin notifications
-- even when invoked by a delivery partner or shop owner whose own RLS
-- policies on public.notifications might forbid inserting rows for admins.

CREATE OR REPLACE FUNCTION handle_kyc_notifications()
RETURNS TRIGGER AS $$
DECLARE
  v_title TEXT;
  v_body TEXT;
  v_notif_key TEXT;
  v_admin_id UUID;
BEGIN
  -- We only care about inserts or updates where verification_status becomes 'pending'
  IF (TG_OP = 'INSERT' AND NEW.verification_status = 'pending') OR 
     (TG_OP = 'UPDATE' AND NEW.verification_status = 'pending' AND OLD.verification_status != 'pending') THEN
    
    IF TG_TABLE_NAME = 'shops' THEN
      v_title := '🏪 New Shop KYC!';
      v_body := COALESCE(NEW.shop_name, 'A new shop') || ' has submitted KYC and is pending verification.';
      v_notif_key := 'shop_kyc_' || NEW.id;
    ELSIF TG_TABLE_NAME = 'delivery_partners' THEN
      v_title := '🛵 New Rider KYC!';
      v_body := 'A delivery partner has submitted KYC and is pending verification.';
      v_notif_key := 'rider_kyc_' || NEW.id;
    END IF;

    -- Insert a notification for every active admin user
    FOR v_admin_id IN SELECT id FROM public.admin_users WHERE is_active = true LOOP
      INSERT INTO public.notifications (user_id, notif_key, title, body)
      VALUES (v_admin_id, v_notif_key, v_title, v_body)
      ON CONFLICT DO NOTHING;
    END LOOP;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
