-- =============================================================================
-- Migration: Rider Heartbeat Cron Job
-- Description:
--   Monitors rider location updates for active orders (pre-pickup).
--   If a rider ghosts (no location update for 15+ mins) during confirmed,
--   preparing, or ready_for_pickup, the system auto-cancels the assignment.
--   If it's in 'preparing' or 'ready_for_pickup', it sets cancellation reason
--   to 'no_rider' so the seller gets 100% payout.
-- =============================================================================

CREATE OR REPLACE FUNCTION monitor_rider_heartbeat()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Unassign rider or cancel order if rider ghosted before picking up the food
  -- (Phone died, uninstalled app, etc.)
  UPDATE orders
  SET 
    status = CASE WHEN status IN ('preparing', 'ready_for_pickup') THEN 'cancelled' ELSE 'pending' END,
    cancelled_reason = CASE WHEN status IN ('preparing', 'ready_for_pickup') THEN 'no_rider' ELSE cancelled_reason END,
    delivery_partner_id = NULL,
    partner_accepted = false
  WHERE 
    status IN ('confirmed', 'preparing', 'ready_for_pickup') 
    AND delivery_partner_id IS NOT NULL
    AND rider_location_updated_at IS NOT NULL
    AND rider_location_updated_at < (NOW() - INTERVAL '15 minutes');
END;
$$;

-- Schedule the job to run every 5 minutes
SELECT cron.schedule(
    'monitor_rider_heartbeat_job',
    '*/5 * * * *',
    'SELECT monitor_rider_heartbeat()'
);
