-- Migration 20260893000000_100x_absolute_auth_fortress.sql
-- Additive fixes for Global IDORs and Trigger Collisions

-- 1. Fix set_shop_dispute Global IDOR
CREATE OR REPLACE FUNCTION set_shop_dispute(p_order_id UUID, p_cancel BOOLEAN)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_status text;
  v_payment_status text;
  v_cart_group_id uuid;
  v_customer_id uuid;
BEGIN
  SELECT cart_group_id, customer_id INTO v_cart_group_id, v_customer_id FROM orders WHERE id = p_order_id;
  
  -- 100x FIX: Prevent Global DoS by unauthenticated / unauthorized users
  IF v_customer_id != auth.uid() AND NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: Only the customer or an admin can open a dispute';
  END IF;

  -- Strict Deterministic Locking
  IF v_cart_group_id IS NOT NULL THEN
    PERFORM id FROM orders WHERE cart_group_id = v_cart_group_id ORDER BY id FOR UPDATE;
  ELSE
    PERFORM id FROM orders WHERE id = p_order_id FOR UPDATE;
  END IF;

  SELECT status, payment_status INTO v_status, v_payment_status
  FROM orders WHERE id = p_order_id;

  IF v_status IN ('picked_up', 'out_for_delivery', 'delivered', 'cancelled', 'seller_rejected', 'verification_failed', 'shop_dispute_cancel') THEN
    RAISE EXCEPTION 'Cannot open shop dispute at this stage: %', v_status;
  END IF;

  IF p_cancel = true THEN
    UPDATE orders
    SET 
      status = 'cancelled', 
      cancelled_reason = 'shop_dispute', 
      wait_time_disputed = true,
      refund_status = CASE WHEN v_payment_status = 'captured' THEN 'processing' ELSE refund_status END
    WHERE id = p_order_id;
    
    IF v_cart_group_id IS NOT NULL THEN
      PERFORM reallocate_cancelled_delivery_fees(v_cart_group_id);
    END IF;
  ELSE
    UPDATE orders
    SET status = 'shop_dispute'
    WHERE id = p_order_id;
  END IF;
END;
$$;

-- 2. Fix set_customer_rated IDOR
CREATE OR REPLACE FUNCTION set_customer_rated(p_order_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM orders WHERE id = p_order_id AND (customer_id = auth.uid() OR public.is_active_admin(auth.uid()))) THEN
    RAISE EXCEPTION 'Unauthorized: Only the customer can mark this order as rated';
  END IF;
  UPDATE orders SET has_customer_rated = true WHERE id = p_order_id;
END;
$$;

-- 3. Fix set_delivery_rated IDOR
CREATE OR REPLACE FUNCTION set_delivery_rated(p_order_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM orders WHERE id = p_order_id AND (customer_id = auth.uid() OR public.is_active_admin(auth.uid()))) THEN
    RAISE EXCEPTION 'Unauthorized: Only the customer can mark delivery as rated';
  END IF;
  UPDATE orders SET has_delivery_rated = true WHERE id = p_order_id;
END;
$$;

-- 4. Fix set_seller_rated IDOR
CREATE OR REPLACE FUNCTION set_seller_rated(p_order_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Customer rates seller
  IF NOT EXISTS (SELECT 1 FROM orders WHERE id = p_order_id AND (customer_id = auth.uid() OR public.is_active_admin(auth.uid()))) THEN
    RAISE EXCEPTION 'Unauthorized: Only the customer can mark seller as rated';
  END IF;
  UPDATE orders SET has_seller_rated = true WHERE id = p_order_id;
END;
$$;

-- 5. Fix get_order_item_count_v1 IDOR Data Leak
CREATE OR REPLACE FUNCTION get_order_item_count_v1(p_order_id UUID)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_count integer;
  v_authorized boolean;
BEGIN
  -- Check if user is associated with this order
  SELECT EXISTS (
    SELECT 1 FROM orders o
    LEFT JOIN shops s ON o.shop_id = s.id
    WHERE o.id = p_order_id
    AND (
      o.customer_id = auth.uid() OR
      o.delivery_partner_id = auth.uid() OR
      s.seller_id = auth.uid() OR
      public.is_active_admin(auth.uid())
    )
  ) INTO v_authorized;
  
  IF NOT v_authorized THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT count(*)::integer INTO v_count FROM order_items WHERE order_id = p_order_id;
  RETURN v_count;
END;
$$;

-- 6. Fix process_referral_on_first_order Trigger Collision Crash
CREATE OR REPLACE FUNCTION process_referral_on_first_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_referral_record RECORD;
  v_referrer_id UUID;
  v_bonus_amount NUMERIC;
  v_coupon_code TEXT;
  v_coupon_inserted BOOLEAN := false;
  v_attempts INTEGER := 0;
BEGIN
  -- We only care when an order status transitions to a completed state
  IF NEW.status IN ('delivered', 'completed') AND (OLD.status IS NULL OR OLD.status NOT IN ('delivered', 'completed')) THEN
    
    -- 1. Check if this is the FIRST completed order for the Customer
    IF (SELECT count(*) FROM public.orders WHERE customer_id = NEW.customer_id AND status IN ('delivered', 'completed')) = 1 THEN
      SELECT * INTO v_referral_record FROM public.referrals WHERE referred_id = NEW.customer_id AND bonus_paid = false;
      
      IF FOUND THEN
        UPDATE public.referrals SET bonus_paid = true WHERE id = v_referral_record.id;
        v_referrer_id := v_referral_record.referrer_id;
        
        SELECT value::numeric INTO v_bonus_amount FROM public.platform_config WHERE key = 'referral_bonus_amount';
        IF v_bonus_amount IS NULL THEN v_bonus_amount := 25.0; END IF;
        
        -- 100x FIX: Loop coupon generation to prevent Delivery Freeze from UNIQUE constraint crashes
        v_coupon_inserted := false;
        v_attempts := 0;
        WHILE NOT v_coupon_inserted AND v_attempts < 10 LOOP
          v_coupon_code := 'REF25-' || upper(substr(md5(random()::text || clock_timestamp()::text || v_attempts::text), 1, 6));
          IF NOT EXISTS (SELECT 1 FROM public.coupons WHERE code = v_coupon_code) THEN
            INSERT INTO public.coupons (code, discount_type, discount_value, is_active, valid_from, valid_until)
            VALUES (v_coupon_code, 'flat', 25, true, now(), null);
            v_coupon_inserted := true;
          END IF;
          v_attempts := v_attempts + 1;
        END LOOP;
        
        -- Send notification to referrer
        IF v_coupon_inserted THEN
          INSERT INTO public.notifications (user_id, title, body, notif_key)
          VALUES (
            v_referrer_id, 
            'Referral Bonus!', 
            'Your referred friend completed their first order. You got a ₹25 coupon: ' || v_coupon_code, 
            'ref_bonus_' || v_referral_record.id
          );
        END IF;
      END IF;
    END IF;

    -- 2. Check if this is the FIRST completed order for the Seller
    IF (SELECT count(*) FROM public.orders WHERE shop_id = NEW.shop_id AND status IN ('delivered', 'completed')) = 1 THEN
      DECLARE v_seller_id UUID;
      BEGIN
        SELECT seller_id INTO v_seller_id FROM public.shops WHERE id = NEW.shop_id;
        SELECT * INTO v_referral_record FROM public.referrals WHERE referred_id = v_seller_id AND bonus_paid = false;
        
        IF FOUND THEN
          UPDATE public.referrals SET bonus_paid = true WHERE id = v_referral_record.id;
          v_referrer_id := v_referral_record.referrer_id;
          
          SELECT value::numeric INTO v_bonus_amount FROM public.platform_config WHERE key = 'referral_bonus_amount';
          IF v_bonus_amount IS NULL THEN v_bonus_amount := 25.0; END IF;
          
          v_coupon_inserted := false;
          v_attempts := 0;
          WHILE NOT v_coupon_inserted AND v_attempts < 10 LOOP
            v_coupon_code := 'REF25-' || upper(substr(md5(random()::text || clock_timestamp()::text || v_attempts::text), 1, 6));
            IF NOT EXISTS (SELECT 1 FROM public.coupons WHERE code = v_coupon_code) THEN
              INSERT INTO public.coupons (code, discount_type, discount_value, is_active, valid_from, valid_until)
              VALUES (v_coupon_code, 'flat', 25, true, now(), null);
              v_coupon_inserted := true;
            END IF;
            v_attempts := v_attempts + 1;
          END LOOP;
          
          IF v_coupon_inserted THEN
            INSERT INTO public.notifications (user_id, title, body, notif_key)
            VALUES (
              v_referrer_id, 
              'Referral Bonus!', 
              'Your referred seller completed their first order. You got a ₹25 coupon: ' || v_coupon_code, 
              'ref_bonus_' || v_referral_record.id
            );
          END IF;
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
        
        v_coupon_inserted := false;
        v_attempts := 0;
        WHILE NOT v_coupon_inserted AND v_attempts < 10 LOOP
          v_coupon_code := 'REF25-' || upper(substr(md5(random()::text || clock_timestamp()::text || v_attempts::text), 1, 6));
          IF NOT EXISTS (SELECT 1 FROM public.coupons WHERE code = v_coupon_code) THEN
            INSERT INTO public.coupons (code, discount_type, discount_value, is_active, valid_from, valid_until)
            VALUES (v_coupon_code, 'flat', 25, true, now(), null);
            v_coupon_inserted := true;
          END IF;
          v_attempts := v_attempts + 1;
        END LOOP;
        
        IF v_coupon_inserted THEN
          -- Send notification to referrer
          INSERT INTO public.notifications (user_id, title, body, notif_key)
          VALUES (
            v_referrer_id, 
            'Referral Bonus!', 
            'Your referred rider completed their first order. You got a ₹25 coupon: ' || v_coupon_code, 
            'ref_bonus_' || v_referral_record.id
          );
        END IF;
      END IF;
    END IF;

  END IF;
  
  RETURN NEW;
END;
$$;
