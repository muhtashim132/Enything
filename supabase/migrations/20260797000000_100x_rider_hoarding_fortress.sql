-- =============================================================================
-- Migration: 100x Rider Hoarding Fortress
-- Description:
--   Fixes a critical vulnerability where riders could hoard an infinite number
--   of orders from different customers simultaneously.
--   Enforces that a rider can only accept an order if they currently have 0 
--   active orders OR if the new order belongs to the SAME cart_group_id as 
--   their existing active order(s).
-- =============================================================================

CREATE OR REPLACE FUNCTION accept_order_rider(
  p_order_id UUID, 
  p_rider_phone text DEFAULT NULL, 
  p_shop_lat numeric DEFAULT NULL, 
  p_shop_lng numeric DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
  v_seller_accepted boolean;
  v_payment_status text;
  v_payment_deadline timestamptz;
  v_order_ready_time timestamptz;
  v_new_status text;
  v_rows_affected INT;
  v_cart_group_id UUID;
  v_active_cart_group_id UUID;
BEGIN
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

  IF v_status NOT IN ('awaiting_acceptance', 'pending') THEN
    RAISE EXCEPTION 'Invalid state transition from %', v_status;
  END IF;

  -- 100x FIX: Hoarding Prevention Check
  -- Ensure the rider does not have active orders from a DIFFERENT cart group
  SELECT cart_group_id INTO v_active_cart_group_id
  FROM orders
  WHERE delivery_partner_id = auth.uid()
    AND status NOT IN ('delivered', 'cancelled', 'seller_rejected', 'partner_rejected', 'returned', 'refunded', 'failed')
    AND cart_group_id IS DISTINCT FROM v_cart_group_id
  LIMIT 1;

  IF v_active_cart_group_id IS NOT NULL THEN
    RAISE EXCEPTION 'ACTIVE_ORDER_EXISTS: You cannot accept orders from multiple customers at once.';
  END IF;

  -- State Transition Logic
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

  -- Strict Concurrency Update
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

  -- Verify the update actually applied to the row
  GET DIAGNOSTICS v_rows_affected = ROW_COUNT;
  IF v_rows_affected = 0 THEN
    -- Another rider claimed the order milliseconds before this transaction reached the UPDATE statement
    RAISE EXCEPTION 'ORDER_ACCEPTED_BY_OTHER_RIDER';
  END IF;

  RETURN v_seller_accepted;
END;
$$;

GRANT EXECUTE ON FUNCTION accept_order_rider(UUID, text, numeric, numeric) TO authenticated;
