-- Migration: create_notification_webhook.sql
-- Description: Creates a database webhook to call the send-push edge function
--              whenever a new notification is inserted into the `notifications` table.

DROP TRIGGER IF EXISTS trigger_send_push ON public.notifications;

CREATE TRIGGER trigger_send_push
AFTER INSERT ON public.notifications
FOR EACH ROW
EXECUTE FUNCTION supabase_functions.http_request(
  'https://mmdrgcuaetwohflcvzou.supabase.co/functions/v1/send-push',
  'POST',
  '{"Content-Type":"application/json"}',
  '{}',
  '1000'
);

