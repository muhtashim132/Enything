-- =============================================================================
-- Migration: 100x Notification Consolidation Fortress
-- Description: Consolidates redundant push notifications during multi-shop order 
--              acceptance and checkout. Group-level events (like waiting for payment
--              or order placed) use cart_group_id to prevent duplicates, while
--              shop-specific events (like preparing/ready for pickup) retain individual
--              order IDs to give precise shop status.
-- =============================================================================

-- 1. Consolidate "New Order Available" Push to Riders
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
      -- 100x FIX: Consolidate new order pushes using cart_group_id to prevent redundant pings for multi-shop orders
      IF TG_OP = 'INSERT' THEN
        v_notif_key := COALESCE(NEW.cart_group_id, NEW.id)::text || '_new_available';
      ELSE
        v_notif_key := COALESCE(NEW.cart_group_id, NEW.id)::text || '_reassigned_' || extract(epoch from now())::int;
      END IF;

      INSERT INTO public.notifications (user_id, notif_key, title, body, order_id)
      VALUES (v_rider.id, v_notif_key, v_title, v_body, NEW.id)
      ON CONFLICT (user_id, notif_key) DO NOTHING;
    END LOOP;

  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 2. Consolidate Status Notifications for Customers and Riders
CREATE OR REPLACE FUNCTION handle_order_status_notifications()
RETURNS TRIGGER AS $$
DECLARE
  v_title TEXT;
  v_body TEXT;
  v_notif_key TEXT;
  v_seller_id UUID;
  v_shop_name TEXT;
BEGIN
  -- Attempt to fetch the shop's name for richer notifications
  IF NEW.shop_id IS NOT NULL THEN
    SELECT name INTO v_shop_name FROM public.shops WHERE id = NEW.shop_id;
  END IF;

  -- We care about UPDATEs where the status changed OR seller_accepted changed
  IF TG_OP = 'UPDATE' AND (NEW.status != OLD.status OR NEW.seller_accepted != OLD.seller_accepted) THEN
    
    -- 1. Customer Notifications
    v_notif_key := NULL;
    v_title := NULL;
    v_body := NULL;

    -- Shop Accepted (special case, status might remain awaiting_acceptance)
    IF NEW.seller_accepted = true AND OLD.seller_accepted = false AND NEW.status = 'awaiting_acceptance' THEN
      v_title := '🏪 ' || COALESCE(v_shop_name, 'Shop') || ' Accepted!';
      v_body := COALESCE(v_shop_name, 'The shop') || ' accepted your order. Waiting for a rider now...';
      v_notif_key := NEW.id || '_shop_accepted';
    ELSIF NEW.status != OLD.status THEN
      CASE NEW.status
        WHEN 'awaiting_payment' THEN
          v_title := '✅ Shop & Rider Ready! Pay Now';
          v_body := 'Both the shop and rider have accepted your order. Open the app to complete payment.';
        WHEN 'confirmed' THEN
          v_title := '💳 Payment Confirmed!';
          v_body := 'Your payment was captured. ' || COALESCE(v_shop_name, 'Shop') || ' is preparing your order.';
        WHEN 'preparing' THEN
          v_title := '👨‍🍳 Order Being Prepared';
          v_body := COALESCE(v_shop_name, 'The shop') || ' is now preparing your order.';
        WHEN 'ready_for_pickup' THEN
          v_title := '📦 Ready for Pickup';
          v_body := 'Your order from ' || COALESCE(v_shop_name, 'the shop') || ' is packed and waiting for the rider.';
        WHEN 'picked_up' THEN
          v_title := '🛵 Rider Picked Up';
          v_body := 'Your order is on its way!';
        WHEN 'out_for_delivery' THEN
          v_title := '🚀 Out for Delivery!';
          v_body := 'Your order is almost there. Get ready!';
        WHEN 'delivered' THEN
          v_title := '🎉 Order Delivered!';
          v_body := 'Your order has been delivered. Enjoy!';
        WHEN 'cancelled' THEN
          v_title := '❌ Order Cancelled';
          v_body := 'Your order has been cancelled. No payment was taken.';
        WHEN 'seller_rejected' THEN
          v_title := '😔 Order Rejected';
          v_body := COALESCE(v_shop_name, 'The shop') || ' could not accept your order. No payment was taken.';
        WHEN 'partner_rejected' THEN
          v_title := '😔 No Rider Found';
          v_body := 'We couldn''t find a rider nearby. You can retry from your order history.';
        WHEN 'verification_failed' THEN
          v_title := '❌ Prescription Rejected';
          v_body := 'Your prescription could not be verified by ' || COALESCE(v_shop_name, 'the shop') || '.';
        ELSE
          -- Do nothing
      END CASE;
      
      IF v_title IS NOT NULL THEN
        -- 100x FIX: Consolidate group-level statuses using cart_group_id so the customer isn't spammed with identical notifications
        IF NEW.status IN ('awaiting_payment', 'partner_rejected', 'cancelled') THEN
          v_notif_key := COALESCE(NEW.cart_group_id, NEW.id)::text || '_' || NEW.status;
        ELSE
          v_notif_key := NEW.id::text || '_' || NEW.status;
        END IF;
      END IF;
    END IF;

    IF v_notif_key IS NOT NULL THEN
      INSERT INTO public.notifications (user_id, notif_key, title, body, order_id)
      VALUES (NEW.customer_id, v_notif_key, v_title, v_body, NEW.id)
      ON CONFLICT (user_id, notif_key) DO NOTHING;
    END IF;

    -- 2. Seller Notifications (Intentionally un-consolidated since sellers only care about their own shop)
    IF NEW.shop_id IS NOT NULL AND NEW.status != OLD.status THEN
      SELECT seller_id INTO v_seller_id FROM public.shops WHERE id = NEW.shop_id;
      
      IF v_seller_id IS NOT NULL THEN
        v_notif_key := NULL;
        v_title := NULL;
        v_body := NULL;

        CASE NEW.status
          WHEN 'awaiting_payment' THEN
            v_title := '⏳ Waiting for Customer Payment';
            v_body := 'Both you and the rider accepted. Customer is completing payment now.';
          WHEN 'confirmed' THEN
            v_title := '💳 Payment Done! Start Packing';
            v_body := 'Customer payment captured. Pack the order now — rider is on the way!';
          WHEN 'picked_up' THEN
            v_title := '✅ Order Picked Up';
            v_body := 'The rider has collected the order from your shop.';
          WHEN 'delivered' THEN
            v_title := '🎉 Order Delivered';
            v_body := 'The order was delivered successfully!';
          WHEN 'cancelled' THEN
            v_title := '❌ Order Cancelled';
            v_body := 'This order has been cancelled.';
          ELSE
            -- Do nothing
        END CASE;

        IF v_title IS NOT NULL THEN
          v_notif_key := NEW.id::text || '_' || NEW.status;
          INSERT INTO public.notifications (user_id, notif_key, title, body, order_id)
          VALUES (v_seller_id, v_notif_key, v_title, v_body, NEW.id)
          ON CONFLICT (user_id, notif_key) DO NOTHING;
        END IF;
      END IF;
    END IF;

    -- 3. Rider Notifications
    IF NEW.delivery_partner_id IS NOT NULL AND NEW.status != OLD.status THEN
      v_notif_key := NULL;
      v_title := NULL;
      v_body := NULL;

      CASE NEW.status
        WHEN 'awaiting_payment' THEN
          v_title := '⏳ Waiting for Customer Payment';
          v_body := 'Customer is completing payment. Stand by — you will be confirmed shortly!';
        WHEN 'confirmed' THEN
          v_title := '💳 Payment Done! Go Pick Up 🛵';
          v_body := 'Customer paid. Head to ' || COALESCE(v_shop_name, 'the shop') || ' and pick up the order now!';
        WHEN 'cancelled' THEN
          v_title := '❌ Order Cancelled';
          v_body := 'The order you accepted has been cancelled.';
        WHEN 'preparing' THEN
          v_title := '👨‍🍳 ' || COALESCE(v_shop_name, 'Shop') || ' Preparing';
          v_body := COALESCE(v_shop_name, 'The shop') || ' has started preparing the order. Head over!';
        WHEN 'ready_for_pickup' THEN
          v_title := '📦 Ready for Pickup at ' || COALESCE(v_shop_name, 'Shop') || '!';
          v_body := 'The order from ' || COALESCE(v_shop_name, 'the shop') || ' is ready. Go pick it up now!';
        ELSE
          -- Do nothing
      END CASE;

      IF v_title IS NOT NULL THEN
        -- 100x FIX: Consolidate rider notifications for group-level phases like waiting for payment
        IF NEW.status IN ('awaiting_payment', 'confirmed', 'cancelled') THEN
          v_notif_key := COALESCE(NEW.cart_group_id, NEW.id)::text || '_' || NEW.status;
        ELSE
          v_notif_key := NEW.id::text || '_' || NEW.status;
        END IF;
        
        INSERT INTO public.notifications (user_id, notif_key, title, body, order_id)
        VALUES (NEW.delivery_partner_id, v_notif_key, v_title, v_body, NEW.id)
        ON CONFLICT (user_id, notif_key) DO NOTHING;
      END IF;
    END IF;

  END IF;

  -- 4. INSERTs (New Orders for Seller, Placed for Customer)
  IF TG_OP = 'INSERT' THEN
    -- Customer: Order Placed
    -- 100x FIX: Consolidate _placed push so the customer doesn't get pinged for every shop in the cart
    INSERT INTO public.notifications (user_id, notif_key, title, body, order_id)
    VALUES (NEW.customer_id, COALESCE(NEW.cart_group_id, NEW.id)::text || '_placed', '🛍️ Order Sent!', 'Waiting for the shop & rider to accept. No charge yet — you pay only after both confirm.', NEW.id)
    ON CONFLICT (user_id, notif_key) DO NOTHING;

    -- Seller: New Order
    IF NEW.shop_id IS NOT NULL THEN
      SELECT seller_id INTO v_seller_id FROM public.shops WHERE id = NEW.shop_id;
      IF v_seller_id IS NOT NULL THEN
        INSERT INTO public.notifications (user_id, notif_key, title, body, order_id)
        VALUES (v_seller_id, NEW.id::text || '_new', '🔔 New Order!', 'You have a new order waiting for your acceptance.', NEW.id)
        ON CONFLICT (user_id, notif_key) DO NOTHING;
      END IF;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
