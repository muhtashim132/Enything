CREATE OR REPLACE FUNCTION public.reject_order_rider(p_order_id uuid, p_reason text DEFAULT NULL::text, p_penalty numeric DEFAULT 0, p_disputed boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  -- 100x FIX: Wipe rider, but ONLY send back to awaiting_acceptance if it was awaiting_payment or awaiting_acceptance.
  -- If it has already crossed the payment threshold (pending, confirmed, etc.), leave the status AS IS so the customer
  -- isn't asked to pay again for an already paid order!
  UPDATE orders
  SET 
    status = CASE 
      WHEN v_status = 'awaiting_payment' THEN 'awaiting_acceptance' 
      ELSE status 
    END,
    partner_accepted = false,
    delivery_partner_id = null,
    arrived_at_shop_time = null,
    wait_time_penalty = 0,
    wait_time_disputed = COALESCE(p_disputed, false),
    -- 100x FIX: Prevent Double-Countdown Timeout. If we revert to awaiting_acceptance, we MUST extend the deadline!
    acceptance_deadline = CASE 
      WHEN v_status = 'awaiting_payment' THEN (now() + interval '3 minutes') 
      ELSE acceptance_deadline 
    END
  WHERE id = p_order_id;

  -- Trigger a silent NOTIFY event that the Edge Function/Flutter App listens to 
  -- in order to instantly re-broadcast the order to nearby riders.
  PERFORM pg_notify('rider_dropped_order', json_build_object('order_id', p_order_id, 'shop_id', v_shop_id)::text);
END;
$function$;

CREATE OR REPLACE FUNCTION public.claim_order_as_rider(p_order_id uuid, p_rider_id uuid, p_payment_deadline timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_updated int;
  v_seller_accepted boolean;
  v_status text;
BEGIN
  -- Read current state
  SELECT seller_accepted, status
  INTO v_seller_accepted, v_status
  FROM orders
  WHERE id = p_order_id;

  -- 100x FIX: Allow claiming orphaned orders that have already passed payment (confirmed, preparing, etc)
  -- so that if a rider drops a paid order, a new rider can still pick it up!
  IF v_status NOT IN ('awaiting_acceptance', 'pending', 'confirmed', 'preparing', 'ready_for_pickup') THEN
    RETURN false;
  END IF;

  -- Atomic update: only succeeds if delivery_partner_id IS NULL (no other rider has it)
  UPDATE orders
  SET
    delivery_partner_id = p_rider_id,
    partner_accepted    = true,
    status = CASE
      WHEN v_status = 'awaiting_acceptance' AND v_seller_accepted THEN 'awaiting_payment'
      ELSE status -- Leave it as confirmed, preparing, etc if it was already past payment
    END,
    payment_deadline = CASE
      WHEN v_status = 'awaiting_acceptance' AND v_seller_accepted AND p_payment_deadline IS NOT NULL THEN p_payment_deadline
      ELSE payment_deadline
    END
  WHERE id = p_order_id
    AND delivery_partner_id IS NULL   -- Atomic lock: fails if another rider took it
    AND status = v_status;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated = 1;
END;
$function$;
