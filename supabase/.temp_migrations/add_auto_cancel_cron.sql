-- Migration: Auto-cancel cron jobs for unaccepted and unpaid orders
-- 
-- NOTE: If this fails with a permission error on remote Supabase, you MUST enable pg_cron 
-- manually in the Supabase Dashboard: Database → Extensions → search "pg_cron" → Enable.

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;

-- Grant usage so migrations can schedule jobs
GRANT USAGE ON SCHEMA cron TO postgres;


-- Auto-cancel orders not accepted within 1 minute
SELECT cron.schedule(
  'auto-cancel-unaccepted-orders',
  '* * * * *',
  $$
  UPDATE public.orders
  SET status = 'cancelled'
  WHERE status = 'awaiting_acceptance'
    AND acceptance_deadline IS NOT NULL
    AND acceptance_deadline < NOW();
  $$
);

-- Auto-cancel orders not paid within 10 minutes of both accepting
SELECT cron.schedule(
  'auto-cancel-unpaid-orders',
  '* * * * *',
  $$
  UPDATE public.orders
  SET status = 'cancelled'
  WHERE status = 'awaiting_payment'
    AND payment_deadline IS NOT NULL
    AND payment_deadline < NOW();
  $$
);
