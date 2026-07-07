-- =============================================================================
-- Migration: Ghosting Deadlock Cron Job
-- Description:
--   1. Creates a function to automatically cancel 'confirmed' and 'preparing' orders
--      that have been abandoned by sellers or riders.
--   2. Schedules the function to run every 5 minutes using pg_cron.
-- =============================================================================

CREATE OR REPLACE FUNCTION auto_cancel_ghost_prep_orders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Automatically cancel orders stuck in confirmed or preparing for > 1.5 hours
  -- after the payment deadline, indicating someone ghosted.
  UPDATE orders
  SET 
    status = 'cancelled',
    cancelled_reason = 'timeout'
  WHERE 
    status IN ('confirmed', 'preparing') 
    AND payment_deadline IS NOT NULL 
    AND payment_deadline < (NOW() - INTERVAL '1.5 hours');
END;
$$;

-- Schedule the job to run every 5 minutes
SELECT cron.schedule(
    'auto_cancel_ghost_prep_orders_job',
    '*/5 * * * *',
    'SELECT auto_cancel_ghost_prep_orders()'
);
