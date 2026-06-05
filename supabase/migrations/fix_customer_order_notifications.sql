-- ============================================================================
-- Migration: fix_customer_order_notifications
-- Description: DB trigger that fires when an order transitions to 'cancelled'
--              or 'seller_rejected' and inserts an in-app notification for
--              the customer AND fires an FCM push via pg_net to the Edge Function.
-- ============================================================================

CREATE OR REPLACE FUNCTION handle_order_status_customer_push()
RETURNS TRIGGER AS $$
DECLARE
  v_title TEXT;
  v_body TEXT;
BEGIN
  IF NEW.status = OLD.status THEN RETURN NEW; END IF;

  IF NEW.status = 'cancelled' THEN
    v_title := '❌ Order Cancelled';
    v_body  := 'Your order has been cancelled. No payment was taken.';
  ELSIF NEW.status = 'seller_rejected' THEN
    v_title := '😔 Order Rejected';
    v_body  := 'The shop could not accept your order. No payment was taken.';
  ELSE
    RETURN NEW;
  END IF;

  -- Persist in-app notification for customer
  INSERT INTO public.notifications (user_id, notif_key, title, body, order_id)
  VALUES (NEW.customer_id, 'order_' || NEW.id || '_' || NEW.status, v_title, v_body, NEW.id)
  ON CONFLICT DO NOTHING;

  -- Fire FCM push via pg_net -> send-push Edge Function
  -- Using current_setting('app.service_role_key', true) if configured, or a Vault secret.
  -- To keep it simple and safe for standard Supabase setups, we'll assume the URL and Key
  -- are available. If edge_function_url isn't in platform_config, it falls back gracefully or fails silently.
  BEGIN
    PERFORM net.http_post(
      url     := COALESCE((SELECT value FROM public.platform_config WHERE key = 'edge_function_url'), '') || '/send-push',
      headers := jsonb_build_object('Content-Type', 'application/json',
                                    'Authorization', 'Bearer ' || current_setting('app.supabase_service_role_key', true)),
      body    := jsonb_build_object('user_id', NEW.customer_id, 'title', v_title, 'body', v_body,
                                    'data', jsonb_build_object('order_id', NEW.id))
    );
  EXCEPTION WHEN OTHERS THEN
    -- Ignore pg_net errors if extension missing or config bad
  END;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS tr_customer_order_push ON public.orders;
CREATE TRIGGER tr_customer_order_push
AFTER UPDATE ON public.orders
FOR EACH ROW
EXECUTE FUNCTION handle_order_status_customer_push();
