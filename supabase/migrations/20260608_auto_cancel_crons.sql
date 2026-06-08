-- Migration: Set up pg_cron jobs for Order Timeouts
-- This ensures orders stuck in 'awaiting_acceptance' or 'awaiting_payment'
-- are automatically cancelled by the database if the client app crashes or loses connection.

-- Enable pg_cron extension if not already enabled (Requires Supabase superuser)
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- 1. Auto-cancel orders that were never accepted by both shop & rider within their 2-min deadline.
SELECT cron.schedule(
    'auto-cancel-unaccepted-orders',
    '* * * * *', -- Run every minute
    $$
    UPDATE public.orders 
    SET status = 'cancelled', 
        cancelled_reason = 'Auto-cancelled: Acceptance timeout exceeded',
        updated_at = NOW()
    WHERE status = 'awaiting_acceptance' 
      AND acceptance_deadline < NOW();
    $$
);

-- 2. Auto-cancel orders where both accepted, but customer failed to pay within 10 minutes.
SELECT cron.schedule(
    'auto-cancel-unpaid-orders',
    '* * * * *', -- Run every minute
    $$
    UPDATE public.orders 
    SET status = 'cancelled', 
        cancelled_reason = 'Auto-cancelled: Payment timeout exceeded',
        updated_at = NOW()
    WHERE status = 'awaiting_payment' 
      AND payment_deadline < NOW();
    $$
);

-- Note: Ensure that the 'payment_deadline' field exists and is set correctly in Dart.
-- We noticed in dashboard_page.dart that it's set to 10 minutes when both accept.
