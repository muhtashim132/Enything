-- Migration: Add cancellation reason + rejection message to orders
-- These power the smart recovery UI after an order fails / is rejected.

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS cancelled_reason   TEXT,       -- 'shop_rejected' | 'no_rider' | 'timeout' | 'customer'
  ADD COLUMN IF NOT EXISTS rejection_message  TEXT,       -- seller's freetext message to customer
  ADD COLUMN IF NOT EXISTS cart_group_id      TEXT;       -- groups orders from same checkout (multi-shop, up to 3)

-- Add index for fast sibling-order lookup
CREATE INDEX IF NOT EXISTS orders_cart_group_id_idx ON public.orders(cart_group_id);

-- Update auto-cancel cron to stamp cancelled_reason correctly
-- (drop old jobs and recreate with reason column)
SELECT cron.unschedule('auto-cancel-unaccepted-orders');
SELECT cron.unschedule('auto-cancel-unpaid-orders');

-- Auto-cancel with reason: neither accepted within 2 minutes
SELECT cron.schedule(
  'auto-cancel-unaccepted-orders',
  '* * * * *',
  $$
  UPDATE public.orders
  SET status = 'cancelled',
      cancelled_reason = 'timeout'
  WHERE status = 'awaiting_acceptance'
    AND acceptance_deadline IS NOT NULL
    AND acceptance_deadline < NOW();
  $$
);

-- Auto-cancel with reason: shop accepted but no rider within 2 mins
SELECT cron.schedule(
  'auto-cancel-unpaid-orders',
  '* * * * *',
  $$
  UPDATE public.orders
  SET status = 'cancelled',
      cancelled_reason = 'no_rider'
  WHERE status = 'awaiting_payment'
    AND payment_deadline IS NOT NULL
    AND payment_deadline < NOW();
  $$
);

NOTIFY pgrst, 'reload schema';
