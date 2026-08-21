-- Migration: Drop duplicate notification webhook trigger
-- 
-- ROOT CAUSE: The trigger_send_push webhook fires the send-push Edge Function
-- on every INSERT into the `notifications` table. This causes DOUBLE push
-- notifications because:
--
--   1. Seller/Rider order notifications are already sent directly via
--      sendBackgroundPush() from the client (checkout_page, seller_orders_page).
--
--   2. Broadcast notifications (send-broadcast Edge Function) already send
--      FCM pushes directly AND insert into `notifications` for history —
--      the webhook fires AGAIN for each inserted row.
--
-- With direct push calls covering all notification paths, this webhook trigger
-- is purely redundant and causes every notification to fire twice.
--
-- SAFE TO DROP: The `notifications` table INSERT still works for history/persistence.
-- Only the automatic webhook → send-push call is removed.

DROP TRIGGER IF EXISTS trigger_send_push ON public.notifications;
