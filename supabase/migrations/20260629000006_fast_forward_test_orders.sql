-- ============================================================================
-- Migration: 20260629000006_fast_forward_test_orders.sql
-- Description: Automatically accepts orders placed by the Razorpay test account
--              so the reviewer can immediately test the Razorpay checkout
--              without needing a real shop or rider to manually accept it.
-- ============================================================================

CREATE OR REPLACE FUNCTION fast_forward_test_orders()
RETURNS TRIGGER AS $$
BEGIN
  -- If the order is created by the magic Razorpay test account
  IF NEW.customer_id = '00000000-0000-0000-0000-919999999996'::uuid AND NEW.status = 'awaiting_acceptance' THEN
    -- Instantly simulate shop & rider acceptance
    NEW.status := 'awaiting_payment';
    NEW.seller_accepted := true;
    NEW.partner_accepted := true;
    
    -- Give them a 1-hour payment window instead of 10 minutes so the reviewer isn't rushed
    NEW.payment_deadline := now() + interval '60 minutes';
    
    -- Nullify the acceptance countdown since it's already accepted
    NEW.acceptance_deadline := null;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_fast_forward_test_orders ON public.orders;
CREATE TRIGGER trigger_fast_forward_test_orders
BEFORE INSERT ON public.orders
FOR EACH ROW
EXECUTE FUNCTION fast_forward_test_orders();
