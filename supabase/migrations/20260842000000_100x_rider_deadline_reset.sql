-- =============================================================================
-- Migration: 100x Rider Deadline Reset
-- Description:
--   When a rider drops an order (reassign), the `reject_order_rider` RPC updates
--   the status to 'awaiting_acceptance'. However, if the old `acceptance_deadline` 
--   had already expired, the newly re-pinged riders would immediately receive an 
--   order that the cron job would cancel. 
--   This additive migration safely replaces `reject_order_rider` to reset the 
--   `acceptance_deadline` by +3 minutes when a rider drops it, maintaining the 
--   robust 100x logic for instant reallocation.
-- =============================================================================

CREATE OR REPLACE FUNCTION reject_order_rider(p_order_id UUID, p_reason TEXT, p_disputed BOOLEAN DEFAULT false)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_delivery_partner_id uuid;
  v_shop_id uuid;
BEGIN
  -- We ONLY fetch the exact order ID provided, locking it for update.
  SELECT delivery_partner_id, shop_id INTO v_delivery_partner_id, v_shop_id
  FROM orders 
  WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF v_delivery_partner_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  -- 100x Logic: Reset acceptance_deadline so new riders have time to accept
  UPDATE orders
  SET 
    status = 'awaiting_acceptance',
    partner_accepted = false,
    delivery_partner_id = null,
    arrived_at_shop_time = null,
    wait_time_penalty = 0,
    wait_time_disputed = COALESCE(p_disputed, false),
    acceptance_deadline = now() + interval '3 minutes'
  WHERE id = p_order_id;

  -- 100x Logic: We trigger a silent NOTIFY event that the Edge Function/Flutter App listens to 
  -- in order to instantly re-broadcast the order to nearby riders.
  PERFORM pg_notify('rider_dropped_order', json_build_object('order_id', p_order_id, 'shop_id', v_shop_id)::text);
END;
$$;

GRANT EXECUTE ON FUNCTION reject_order_rider(UUID, TEXT, BOOLEAN) TO authenticated;
