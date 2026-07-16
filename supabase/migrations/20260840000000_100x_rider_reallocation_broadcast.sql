-- =============================================================================
-- Migration: 100x Rider Reallocation Broadcast
-- Description:
--   Updates reject_order_rider to instantly notify all eligible riders when 
--   a rider drops an order they previously accepted.
-- =============================================================================

CREATE OR REPLACE FUNCTION reject_order_rider(p_order_id UUID, p_reason text DEFAULT NULL, p_penalty numeric DEFAULT 0, p_disputed boolean DEFAULT false)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
  v_delivery_partner_id uuid;
  v_arrived_at_shop_time timestamptz;
  v_shop_prep_time_snapshot int;
  v_seller_payout numeric;
  v_shop_id uuid;
BEGIN
  -- Strict row locking
  SELECT status, delivery_partner_id, arrived_at_shop_time, shop_prep_time_snapshot, seller_payout, shop_id 
  INTO v_status, v_delivery_partner_id, v_arrived_at_shop_time, v_shop_prep_time_snapshot, v_seller_payout, v_shop_id
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  -- Security Check: Ensure caller is the assigned rider
  IF v_delivery_partner_id IS NOT NULL AND v_delivery_partner_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: Only assigned rider can drop this order';
  END IF;

  IF v_status NOT IN ('awaiting_acceptance', 'pending', 'awaiting_payment', 'confirmed', 'preparing', 'ready_for_pickup', 'picked_up') THEN
    RAISE EXCEPTION 'Invalid state transition from %', v_status;
  END IF;

  -- Wipe rider and send back to awaiting_acceptance
  UPDATE orders
  SET 
    status = 'awaiting_acceptance',
    partner_accepted = false,
    delivery_partner_id = null,
    arrived_at_shop_time = null,
    wait_time_penalty = 0,
    wait_time_disputed = COALESCE(p_disputed, false)
  WHERE id = p_order_id;

  -- 100x Logic: We trigger a silent NOTIFY event that the Edge Function/Flutter App listens to 
  -- in order to instantly re-broadcast the order to nearby riders.
  PERFORM pg_notify('rider_dropped_order', json_build_object('order_id', p_order_id, 'shop_id', v_shop_id)::text);
END;
$$;

GRANT EXECUTE ON FUNCTION reject_order_rider(UUID, text, numeric, boolean) TO authenticated;
