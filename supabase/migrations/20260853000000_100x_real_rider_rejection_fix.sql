CREATE OR REPLACE FUNCTION public.accept_order_rider(p_order_id uuid, p_rider_phone text DEFAULT NULL::text, p_shop_lat numeric DEFAULT NULL::numeric, p_shop_lng numeric DEFAULT NULL::numeric)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_status text;
  v_seller_accepted boolean;
  v_payment_status text;
  v_payment_deadline timestamptz;
  v_order_ready_time timestamptz;
  v_new_status text;
  v_rows_affected INT;
  v_active_cart_groups_count INT;
  v_cart_group_id UUID;
BEGIN
  -- 100x ARCHITECTURE FIX: Transaction-level Advisory Lock with COALESCE NULL Protection
  PERFORM pg_advisory_xact_lock(hashtext('rider_acceptance_' || COALESCE(auth.uid()::text, 'system_admin')));

  -- Strict row locking & fetch cart_group_id
  SELECT status, seller_accepted, payment_status, payment_deadline, order_ready_time, cart_group_id
  INTO v_status, v_seller_accepted, v_payment_status, v_payment_deadline, v_order_ready_time, v_cart_group_id
  FROM orders WHERE id = p_order_id FOR UPDATE;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;
  
  -- Graceful cancellation check
  IF v_status = 'cancelled' THEN
    RAISE EXCEPTION 'ORDER_CANCELLED';
  END IF;

  -- 100x FIX: Allow rider to claim an order that has already crossed the payment threshold
  -- (e.g. if the previous rider dropped it due to an emergency).
  IF v_status NOT IN ('awaiting_acceptance', 'pending', 'confirmed', 'preparing', 'ready_for_pickup') THEN
    RAISE EXCEPTION 'Invalid state transition from %', v_status;
  END IF;

  -- 100x FIX: The Ultimate Null Pointer Cascading Fix
  -- Reinstating COALESCE(cart_group_id, id) so NULL cart groups are strictly counted
  SELECT COUNT(DISTINCT COALESCE(cart_group_id, id)) INTO v_active_cart_groups_count
  FROM orders
  WHERE delivery_partner_id = auth.uid()
    AND status NOT IN (
      'delivered', 
      'cancelled', 
      'seller_rejected', 
      'partner_rejected', 
      'returned', 
      'refunded', 
      'failed',
      'payment_failed',
      'timeout',
      'verification_failed',
      'no_rider',
      'shop_dispute_cancel'
    )
    AND COALESCE(cart_group_id, id) IS DISTINCT FROM COALESCE(v_cart_group_id, p_order_id);

  IF v_active_cart_groups_count >= 3 THEN
    RAISE EXCEPTION 'MAX_ORDERS_REACHED: You can only accept orders from up to 3 different customers at a time.';
  END IF;

  -- State Transition Logic
  -- 100x FIX: If the order has already crossed the payment threshold (e.g., rider dropped and new rider is picking up),
  -- we MUST preserve its current status! We only manage state transitions for pre-payment flows.
  IF v_status IN ('confirmed', 'preparing', 'ready_for_pickup') THEN
    v_new_status := v_status;
  ELSE
    IF v_seller_accepted = true THEN
      IF v_payment_status = 'captured' THEN
        IF v_order_ready_time IS NOT NULL THEN
          v_new_status := 'ready_for_pickup';
        ELSE
          v_new_status := 'preparing';
        END IF;
      ELSE
        v_new_status := 'awaiting_payment';
      END IF;
    ELSE
      v_new_status := v_status;
    END IF;
  END IF;

  UPDATE orders
  SET 
    partner_accepted = true,
    delivery_partner_id = auth.uid(),
    status = v_new_status,
    payment_deadline = CASE WHEN v_seller_accepted = true AND v_payment_status != 'captured' THEN (now() AT TIME ZONE 'utc') + interval '10 minutes' ELSE v_payment_deadline END,
    rider_phone = COALESCE(p_rider_phone, rider_phone),
    shop_lat = COALESCE(p_shop_lat, shop_lat),
    shop_lng = COALESCE(p_shop_lng, shop_lng)
  WHERE id = p_order_id AND (delivery_partner_id IS NULL OR delivery_partner_id = auth.uid());

  GET DIAGNOSTICS v_rows_affected = ROW_COUNT;
  IF v_rows_affected = 0 THEN
    RAISE EXCEPTION 'ORDER_ACCEPTED_BY_OTHER_RIDER';
  END IF;

  RETURN v_seller_accepted;
END;
$function$;
