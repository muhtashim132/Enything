-- 1. Ensure the pg_cron extension is enabled
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- 2. Update the restore stock trigger to include timeout and payment_failed
CREATE OR REPLACE FUNCTION restore_product_stock_on_cancel()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  item_row RECORD;
BEGIN
  -- Only restore stock when transitioning INTO a cancelled state
  IF NEW.status IN ('cancelled', 'seller_rejected', 'verification_failed', 'no_rider', 'payment_failed', 'timeout')
     AND OLD.status NOT IN ('cancelled', 'seller_rejected', 'verification_failed', 'no_rider', 'payment_failed', 'timeout') THEN

    FOR item_row IN
      SELECT product_id, quantity FROM order_items WHERE order_id = NEW.id
    LOOP
      UPDATE products
      SET total_quantity = total_quantity + item_row.quantity
      WHERE id = item_row.product_id
        AND total_quantity IS NOT NULL;
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$;

-- 3. Create a function to cancel expired orders
CREATE OR REPLACE FUNCTION auto_cancel_expired_orders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Cancel orders that are awaiting acceptance and past their deadline
  UPDATE orders
  SET status = 'timeout',
      updated_at = NOW()
  WHERE status = 'awaiting_acceptance' 
    AND acceptance_deadline < NOW();

  -- Cancel orders that are awaiting payment for more than 15 minutes past their deadline
  -- (Assuming payment should be done right after acceptance)
  UPDATE orders
  SET status = 'payment_failed',
      updated_at = NOW()
  WHERE status = 'awaiting_payment'
    AND acceptance_deadline < NOW() - INTERVAL '15 minutes';
END;
$$;

-- 4. Schedule the cron job to run every minute
SELECT cron.schedule(
  'auto-cancel-expired-orders',
  '* * * * *',
  $$SELECT auto_cancel_expired_orders()$$
);
