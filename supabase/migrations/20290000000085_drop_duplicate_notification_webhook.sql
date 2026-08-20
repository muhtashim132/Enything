-- Migration: Drop duplicate notification webhook trigger
-- Fixes duplicate push notifications sent to sellers and riders when
-- notifications are saved to the notifications history table.

DROP TRIGGER IF EXISTS trigger_send_push ON public.notifications;
