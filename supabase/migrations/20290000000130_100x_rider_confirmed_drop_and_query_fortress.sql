-- =============================================================================
-- Migration 20290000000130: 100x Rider Confirmed Drop & Query Fortress
-- Description:
--   Adds 'confirmed' to the permitted drop statuses in reject_order_rider,
--   allowing riders to drop orders right after payment capture (when status
--   transitions from awaiting_payment -> confirmed via the payment trigger)
--   but before the shop starts preparing. This prevents rider lockout when
--   a rider has an emergency after payment but before food preparation.
--
--   This is a pure additive migration. No tables or schemas are altered.
--   Only the reject_order_rider function body is updated.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.reject_order_rider(p_order_id UUID, p_reason TEXT, p_disputed BOOLEAN DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_delivery_partner_id uuid;
  v_shop_id uuid;
  v_status text;
  v_cart_group_id uuid;
BEGIN
  -- First, fetch the cart_group_id without locking to determine lock scope
  SELECT delivery_partner_id, shop_id, status, cart_group_id 
  INTO v_delivery_partner_id, v_shop_id, v_status, v_cart_group_id
  FROM orders 
  WHERE id = p_order_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  -- 100x ARCHITECTURE FIX: Lock the entire cart group consistently to prevent deadlocks
  IF v_cart_group_id IS NOT NULL THEN
    PERFORM id FROM orders WHERE cart_group_id = v_cart_group_id ORDER BY id FOR UPDATE;
  ELSE
    PERFORM id FROM orders WHERE id = p_order_id FOR UPDATE;
  END IF;

  -- Re-fetch critical fields post-lock to guarantee state safety
  SELECT delivery_partner_id, status 
  INTO v_delivery_partner_id, v_status
  FROM orders 
  WHERE id = p_order_id;

  IF v_delivery_partner_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: You are not assigned to this order.';
  END IF;

  -- 100x FIX (Edge Case 3): Added 'confirmed' to the permitted drop statuses.
  -- 'confirmed' is the status right after customer pays (awaiting_payment -> confirmed)
  -- but before shop starts preparing. Without this, a rider who has an emergency
  -- right after payment capture is trapped and cannot drop the order.
  IF v_status NOT IN ('awaiting_acceptance', 'pending', 'confirmed', 'preparing', 'ready_for_pickup', 'awaiting_payment') THEN
    RAISE EXCEPTION 'CRITICAL: Cannot drop an order after it has been picked up or delivered (Status: %). Contact platform support.', v_status;
  END IF;

  -- 100x STRESS TEST FIX (Phase 13B): Atomic Cart Group Drop logic
  IF v_cart_group_id IS NOT NULL THEN
    UPDATE orders
    SET 
      status = 'awaiting_acceptance',
      partner_accepted = false,
      delivery_partner_id = null,
      arrived_at_shop_time = null,
      wait_time_penalty = 0,
      wait_time_disputed = COALESCE(p_disputed, false),
      acceptance_deadline = now() + interval '3 minutes'
    WHERE cart_group_id = v_cart_group_id 
      AND delivery_partner_id = auth.uid()
      -- 100x FIX (Edge Case 3): Added 'confirmed' to the WHERE clause
      -- so orders in 'confirmed' status are also reset on group drop.
      AND status IN ('awaiting_acceptance', 'pending', 'confirmed', 'preparing', 'ready_for_pickup', 'awaiting_payment');
  ELSE
    -- Single Order Logic
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
  END IF;

  -- 100x Logic: Trigger silent NOTIFY event to re-broadcast the dropped order to nearby riders
  PERFORM pg_notify('rider_dropped_order', json_build_object('order_id', p_order_id, 'shop_id', v_shop_id)::text);
END;
$function$;
