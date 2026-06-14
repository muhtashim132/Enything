-- Migration: add_order_status_failsafe_notifications.sql
-- This creates a database trigger that automatically inserts into the `notifications` table
-- when an order status changes to critical states (like awaiting_payment or cancelled).
-- This ensures that if the customer's app is CLOSED, they still receive the notification 
-- in their notification center when they reopen it.

CREATE OR REPLACE FUNCTION handle_order_status_notifications()
RETURNS TRIGGER AS $$
DECLARE
  v_title TEXT;
  v_body TEXT;
  v_notif_key TEXT;
  v_seller_id UUID;
BEGIN
  -- We only care about UPDATEs where the status changed
  IF TG_OP = 'UPDATE' AND NEW.status != OLD.status THEN
    
    -- 1. Customer Notifications
    IF NEW.status = 'awaiting_payment' THEN
      v_title := '✅ Shop & Rider Ready! Pay Now';
      v_body := 'Both the shop and rider have accepted your order. Open the app to complete payment.';
      v_notif_key := NEW.id || '_awaiting_payment';
      
      INSERT INTO public.notifications (user_id, notif_key, title, body, order_id)
      VALUES (NEW.customer_id, v_notif_key, v_title, v_body, NEW.id)
      ON CONFLICT (user_id, notif_key) DO NOTHING;

    ELSIF NEW.status = 'cancelled' THEN
      v_title := '❌ Order Cancelled';
      v_body := 'Your order has been cancelled. No payment was taken.';
      v_notif_key := NEW.id || '_cancelled';
      
      INSERT INTO public.notifications (user_id, notif_key, title, body, order_id)
      VALUES (NEW.customer_id, v_notif_key, v_title, v_body, NEW.id)
      ON CONFLICT (user_id, notif_key) DO NOTHING;
      
    ELSIF NEW.status = 'seller_rejected' THEN
      v_title := '😔 Order Rejected';
      v_body := 'The shop could not accept your order. No payment was taken.';
      v_notif_key := NEW.id || '_seller_rejected';
      
      INSERT INTO public.notifications (user_id, notif_key, title, body, order_id)
      VALUES (NEW.customer_id, v_notif_key, v_title, v_body, NEW.id)
      ON CONFLICT (user_id, notif_key) DO NOTHING;
    END IF;

    -- 2. Seller Notifications
    IF NEW.shop_id IS NOT NULL THEN
      -- Get the actual User ID of the shop owner
      SELECT seller_id INTO v_seller_id FROM public.shops WHERE id = NEW.shop_id;
      
      IF v_seller_id IS NOT NULL THEN
        IF NEW.status = 'awaiting_payment' THEN
          INSERT INTO public.notifications (user_id, notif_key, title, body, order_id)
          VALUES (v_seller_id, NEW.id || '_awaiting_payment', '⌛ Waiting for Customer Payment', 'Both you and the rider accepted. Customer is completing payment now.', NEW.id)
          ON CONFLICT (user_id, notif_key) DO NOTHING;
          
        ELSIF NEW.status = 'cancelled' THEN
          INSERT INTO public.notifications (user_id, notif_key, title, body, order_id)
          VALUES (v_seller_id, NEW.id || '_cancelled', '❌ Order Cancelled', 'This order has been cancelled.', NEW.id)
          ON CONFLICT (user_id, notif_key) DO NOTHING;
        END IF;
      END IF;
    END IF;

  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop trigger if exists to allow safe re-runs
DROP TRIGGER IF EXISTS tr_order_status_notifications ON public.orders;

-- Create the trigger
CREATE TRIGGER tr_order_status_notifications
AFTER UPDATE ON public.orders
FOR EACH ROW
EXECUTE FUNCTION handle_order_status_notifications();
