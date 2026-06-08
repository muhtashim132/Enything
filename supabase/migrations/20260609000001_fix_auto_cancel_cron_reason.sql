-- 20260609000001_fix_auto_cancel_cron_reason.sql
SELECT cron.unschedule('auto-cancel-unaccepted-orders');
SELECT cron.unschedule('auto-cancel-unpaid-orders');

SELECT cron.schedule('auto-cancel-unaccepted-orders', '* * * * *', $$
  UPDATE public.orders SET status = 'cancelled', cancelled_reason = 'timeout', updated_at = NOW()
  WHERE status = 'awaiting_acceptance' AND acceptance_deadline < NOW();
$$);

SELECT cron.schedule('auto-cancel-unpaid-orders', '* * * * *', $$
  UPDATE public.orders SET status = 'cancelled', cancelled_reason = 'timeout', updated_at = NOW()
  WHERE status = 'awaiting_payment' AND payment_deadline < NOW();
$$);
