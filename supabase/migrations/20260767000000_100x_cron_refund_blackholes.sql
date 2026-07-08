-- =============================================================================
-- Migration: 100x Cron Refund Blackholes Fix
-- Description:
--   1. Fixes `auto_cancel_expired_orders` to set `refund_status = 'processing'`
--      if the payment was captured before the acceptance/payment timeout.
--   2. Fixes `sweep_phantom_orders` to do the same for 24h phantom sweeps.
-- =============================================================================

-- 1. Fix auto_cancel_expired_orders
CREATE OR REPLACE FUNCTION auto_cancel_expired_orders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Cancel orders that are awaiting acceptance and past their acceptance deadline
  UPDATE orders
  SET status = 'timeout',
      refund_status = CASE WHEN payment_status = 'captured' THEN 'processing' ELSE refund_status END,
      updated_at = NOW()
  WHERE status = 'awaiting_acceptance' 
    AND acceptance_deadline < NOW();

  -- Cancel orders that are awaiting payment and past their payment deadline
  -- Uses COALESCE to fallback to created_at + 15 mins just in case payment_deadline is missing.
  UPDATE orders
  SET status = 'payment_failed',
      refund_status = CASE WHEN payment_status = 'captured' THEN 'processing' ELSE refund_status END,
      updated_at = NOW()
  WHERE status = 'awaiting_payment'
    AND COALESCE(payment_deadline, created_at + INTERVAL '15 minutes') < NOW();
END;
$$;


-- 2. Fix sweep_phantom_orders (if exists, recreate it safely)
CREATE OR REPLACE FUNCTION sweep_phantom_orders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE orders
  SET status = 'cancelled',
      rejection_message = 'Automated system cleanup: Order stuck in phantom state',
      refund_status = CASE WHEN payment_status = 'captured' THEN 'processing' ELSE refund_status END,
      updated_at = NOW()
  WHERE status IN ('pending', 'awaiting_payment', 'awaiting_acceptance')
    AND created_at < NOW() - INTERVAL '24 hours';
END;
$$;
