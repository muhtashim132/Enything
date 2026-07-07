-- =============================================================================
-- Migration: Phantom Orders Cron Job
-- Description:
--   1. Creates a function to automatically cancel expired awaiting_acceptance orders.
--   2. Schedules the function to run every minute using pg_cron.
-- =============================================================================

-- Enable pg_cron extension if not already enabled
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;

CREATE OR REPLACE FUNCTION auto_cancel_phantom_orders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Automatically cancel orders that have passed their acceptance deadline
  -- and are still awaiting acceptance.
  UPDATE orders
  SET 
    status = 'cancelled',
    cancelled_reason = 'timeout'
  WHERE 
    status = 'awaiting_acceptance' 
    AND acceptance_deadline IS NOT NULL 
    AND acceptance_deadline < NOW();
END;
$$;

-- Schedule the job to run every minute
-- Note: 'auto_cancel_phantom_orders_job' is the job name
SELECT cron.schedule(
    'auto_cancel_phantom_orders_job',
    '* * * * *',
    'SELECT auto_cancel_phantom_orders()'
);
