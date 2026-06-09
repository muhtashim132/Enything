-- ============================================================================
-- Migration: 20260609000017_kyc_status_update_notifications.sql
-- Description: Updates the handle_kyc_notifications trigger to also notify
--              the seller or rider when their KYC is approved or rejected.
-- ============================================================================

CREATE OR REPLACE FUNCTION handle_kyc_notifications()
RETURNS TRIGGER AS $$
DECLARE
  v_title TEXT;
  v_body TEXT;
  v_notif_key TEXT;
  v_admin_id UUID;
  v_target_user_id UUID;
BEGIN
  -- 1. Notify Admins when KYC becomes 'pending'
  IF (TG_OP = 'INSERT' AND NEW.verification_status = 'pending') OR 
     (TG_OP = 'UPDATE' AND NEW.verification_status = 'pending' AND OLD.verification_status != 'pending') THEN
    
    IF TG_TABLE_NAME = 'shops' THEN
      v_title := '🏪 New Shop KYC!';
      v_body := COALESCE(NEW.name, 'A new shop') || ' has submitted KYC and is pending verification.';
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

  -- 2. Notify Seller/Rider when KYC is approved or rejected
  IF TG_OP = 'UPDATE' AND OLD.verification_status = 'pending' AND NEW.verification_status IN ('approved', 'verified', 'rejected') THEN
    
    IF TG_TABLE_NAME = 'shops' THEN
      v_target_user_id := NEW.seller_id;
      v_notif_key := 'shop_kyc_status_' || NEW.id || '_' || extract(epoch from now())::int;
      
      IF NEW.verification_status IN ('approved', 'verified') THEN
        v_title := '✅ KYC Approved!';
        v_body := 'Congratulations! Your shop KYC has been verified. You can now start accepting orders.';
      ELSE
        v_title := '❌ KYC Application Rejected';
        v_body := 'Your shop KYC application has been rejected. Please re-upload your documents and reapply.';
      END IF;

    ELSIF TG_TABLE_NAME = 'delivery_partners' THEN
      v_target_user_id := NEW.id;
      v_notif_key := 'rider_kyc_status_' || NEW.id || '_' || extract(epoch from now())::int;
      
      IF NEW.verification_status IN ('approved', 'verified') THEN
        v_title := '✅ KYC Approved!';
        v_body := 'Congratulations! Your rider KYC has been verified. You can now go online and start earning.';
      ELSE
        v_title := '❌ KYC Application Rejected';
        v_body := 'Your rider KYC application has been rejected. Please re-upload your documents and reapply.';
      END IF;
    END IF;

    IF v_target_user_id IS NOT NULL THEN
      INSERT INTO public.notifications (user_id, notif_key, title, body)
      VALUES (v_target_user_id, v_notif_key, v_title, v_body)
      ON CONFLICT DO NOTHING;
    END IF;

  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
