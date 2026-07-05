-- ============================================================================
-- Migration: referral_order_trigger.sql
-- Description: Trigger to process referral bonus on FIRST completed/delivered order.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.process_referral_on_first_order()
RETURNS TRIGGER AS $$
DECLARE
  v_referral_record RECORD;
  v_referrer_id UUID;
  v_bonus_amount NUMERIC;
  v_coupon_code TEXT;
BEGIN
  -- We only care when an order status transitions to a completed state
  IF NEW.status IN ('delivered', 'completed') AND (OLD.status IS NULL OR OLD.status NOT IN ('delivered', 'completed')) THEN
    
    -- 1. Check if this is the FIRST completed order for the Customer
    IF (SELECT count(*) FROM public.orders WHERE customer_id = NEW.customer_id AND status IN ('delivered', 'completed')) = 1 THEN
      -- Find referral where this customer is the referred_id and bonus is NOT paid
      SELECT * INTO v_referral_record FROM public.referrals WHERE referred_id = NEW.customer_id AND bonus_paid = false;
      
      IF FOUND THEN
        -- Mark as paid
        UPDATE public.referrals SET bonus_paid = true WHERE id = v_referral_record.id;
        v_referrer_id := v_referral_record.referrer_id;
        
        -- Get bonus amount
        SELECT value::numeric INTO v_bonus_amount FROM public.platform_config WHERE key = 'referral_bonus_amount';
        IF v_bonus_amount IS NULL THEN v_bonus_amount := 25.0; END IF;
        
        -- Give bonus to referrer
        PERFORM public.add_loyalty_points(v_referrer_id, v_bonus_amount::integer, 'earn_referral', 'Referral bonus for customer first order', NEW.id);
        
        -- Generate 25rs coupon
        v_coupon_code := 'REF25-' || upper(substr(md5(random()::text), 1, 6));
        INSERT INTO public.coupons (code, discount_type, discount_value, is_active, valid_from, valid_until)
        VALUES (v_coupon_code, 'flat', 25, true, now(), null);
        
        -- Send notification to referrer
        INSERT INTO public.notifications (user_id, title, body, notif_key)
        VALUES (
          v_referrer_id, 
          'Referral Bonus!', 
          'Your referred friend completed their first order. You got ₹' || v_bonus_amount || ' bonus and a ₹25 coupon: ' || v_coupon_code, 
          'ref_bonus_' || v_referral_record.id
        );
      END IF;
    END IF;

    -- 2. Check if this is the FIRST completed order for the Seller
    IF (SELECT count(*) FROM public.orders WHERE shop_id = NEW.shop_id AND status IN ('delivered', 'completed')) = 1 THEN
      -- Get seller_id
      DECLARE v_seller_id UUID;
      BEGIN
        SELECT seller_id INTO v_seller_id FROM public.shops WHERE id = NEW.shop_id;
        SELECT * INTO v_referral_record FROM public.referrals WHERE referred_id = v_seller_id AND bonus_paid = false;
        
        IF FOUND THEN
          UPDATE public.referrals SET bonus_paid = true WHERE id = v_referral_record.id;
          v_referrer_id := v_referral_record.referrer_id;
          
          SELECT value::numeric INTO v_bonus_amount FROM public.platform_config WHERE key = 'referral_bonus_amount';
          IF v_bonus_amount IS NULL THEN v_bonus_amount := 25.0; END IF;
          
          PERFORM public.add_loyalty_points(v_referrer_id, v_bonus_amount::integer, 'earn_referral', 'Referral bonus for seller first order', NEW.id);
          
          v_coupon_code := 'REF25-' || upper(substr(md5(random()::text), 1, 6));
          INSERT INTO public.coupons (code, discount_type, discount_value, is_active, valid_from, valid_until)
          VALUES (v_coupon_code, 'flat', 25, true, now(), null);
          
          INSERT INTO public.notifications (user_id, title, body, notif_key)
          VALUES (
            v_referrer_id, 
            'Referral Bonus!', 
            'Your referred seller completed their first order. You got ₹' || v_bonus_amount || ' bonus and a ₹25 coupon: ' || v_coupon_code, 
            'ref_bonus_' || v_referral_record.id
          );
        END IF;
      END;
    END IF;

    -- 3. Check if this is the FIRST completed order for the Rider
    IF (SELECT count(*) FROM public.orders WHERE delivery_partner_id = NEW.delivery_partner_id AND status IN ('delivered', 'completed')) = 1 THEN
      SELECT * INTO v_referral_record FROM public.referrals WHERE referred_id = NEW.delivery_partner_id AND bonus_paid = false;
      
      IF FOUND THEN
        UPDATE public.referrals SET bonus_paid = true WHERE id = v_referral_record.id;
        v_referrer_id := v_referral_record.referrer_id;
        
        SELECT value::numeric INTO v_bonus_amount FROM public.platform_config WHERE key = 'referral_bonus_amount';
        IF v_bonus_amount IS NULL THEN v_bonus_amount := 25.0; END IF;
        
        PERFORM public.add_loyalty_points(v_referrer_id, v_bonus_amount::integer, 'earn_referral', 'Referral bonus for rider first order', NEW.id);
        
        v_coupon_code := 'REF25-' || upper(substr(md5(random()::text), 1, 6));
        INSERT INTO public.coupons (code, discount_type, discount_value, is_active, valid_from, valid_until)
        VALUES (v_coupon_code, 'flat', 25, true, now(), null);
        -- Send notification to referrer
        INSERT INTO public.notifications (user_id, title, body, notif_key)
        VALUES (
          v_referrer_id, 
          'Referral Bonus!', 
          'Your referred rider completed their first order. You got ₹' || v_bonus_amount || ' bonus and a ₹25 coupon: ' || v_coupon_code, 
          'ref_bonus_' || v_referral_record.id
        );
      END IF;
    END IF;

  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop trigger if exists and recreate
DROP TRIGGER IF EXISTS trg_process_referral_on_first_order ON public.orders;
CREATE TRIGGER trg_process_referral_on_first_order
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.process_referral_on_first_order();
