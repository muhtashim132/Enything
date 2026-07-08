-- =============================================================================
-- Migration: 100x Atomic Cart Group Acceptance
-- Description: Completely eliminates the Partial Acceptance Deadlock and Split-Cart
-- Race Condition by upgrading the rider acceptance logic to atomically process
-- all orders within a cart_group_id under a unified transaction lock.
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
  v_delivery_partner_id UUID;
  v_new_status text;
  v_cart_group_id UUID;
  v_active_cart_groups_count INT;
  v_order_record RECORD;
  v_seller_accepted_return boolean := false;
BEGIN
  -- 1. Initial lookup to find the cart_group_id
  SELECT status, seller_accepted, cart_group_id, delivery_partner_id
  INTO v_status, v_seller_accepted, v_cart_group_id, v_delivery_partner_id
  FROM orders WHERE id = p_order_id;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  -- 2. Fast-path Idempotency Check (Safely returns if the client retries)
  IF v_delivery_partner_id = auth.uid() THEN
    RETURN v_seller_accepted;
  ELSIF v_delivery_partner_id IS NOT NULL THEN
    RAISE EXCEPTION 'ORDER_ACCEPTED_BY_OTHER_RIDER';
  END IF;

  -- 3. 100x ARCHITECTURE FIX: Absolute Transactional Serialization
  -- We take an advisory lock on the ENTIRE CART GROUP. This completely eradicates
  -- the TOCTOU race condition in the trigger, as concurrent acceptance attempts
  -- for ANY order in this cart will be sequentially queued here.
  PERFORM pg_advisory_xact_lock(hashtext('cart_group_accept_' || COALESCE(v_cart_group_id, p_order_id)::text));
  PERFORM pg_advisory_xact_lock(hashtext('rider_accept_' || auth.uid()::text));

  -- 4. Hoarding Check
  SELECT COUNT(DISTINCT COALESCE(cart_group_id, id)) INTO v_active_cart_groups_count
  FROM orders
  WHERE delivery_partner_id = auth.uid()
    AND status NOT IN ('delivered', 'cancelled', 'seller_rejected', 'partner_rejected', 'returned', 'refunded', 'failed')
    AND COALESCE(cart_group_id, id) IS DISTINCT FROM COALESCE(v_cart_group_id, p_order_id);

  IF v_active_cart_groups_count >= 3 THEN
    RAISE EXCEPTION 'MAX_ORDERS_REACHED: You can only accept orders from up to 3 different customers at a time.';
  END IF;

  -- 5. 100x ARCHITECTURE FIX: Atomic Cart Processing
  -- We loop through ALL orders in the cart group and assign them to the rider simultaneously.
  -- This entirely eliminates the Partial Acceptance Deadlock.
  FOR v_order_record IN 
    SELECT id, status, seller_accepted, payment_status, payment_deadline, order_ready_time, delivery_partner_id 
    FROM orders 
    WHERE COALESCE(cart_group_id, id) = COALESCE(v_cart_group_id, p_order_id)
    ORDER BY id
    FOR UPDATE
  LOOP
    -- Double-check assignment under lock
    IF v_order_record.delivery_partner_id IS NOT NULL THEN
      IF v_order_record.delivery_partner_id != auth.uid() THEN
        RAISE EXCEPTION 'ORDER_ACCEPTED_BY_OTHER_RIDER';
      END IF;
      CONTINUE; -- Already ours, safely skip
    END IF;

    -- Skip gracefully if an individual order in the cart was cancelled or rejected
    IF v_order_record.status NOT IN ('awaiting_acceptance', 'pending') THEN
      CONTINUE;
    END IF;

    -- Evaluate unique state transitions per order
    IF v_order_record.seller_accepted = true THEN
      IF v_order_record.payment_status = 'captured' THEN
        IF v_order_record.order_ready_time IS NOT NULL THEN
          v_new_status := 'ready_for_pickup';
        ELSE
          v_new_status := 'preparing';
        END IF;
      ELSE
        v_new_status := 'awaiting_payment';
      END IF;
    ELSE
      v_new_status := v_order_record.status;
    END IF;

    -- Atomic DB Update
    UPDATE orders
    SET 
      partner_accepted = true,
      delivery_partner_id = auth.uid(),
      status = v_new_status,
      payment_deadline = CASE WHEN v_order_record.seller_accepted = true AND v_order_record.payment_status != 'captured' THEN (now() AT TIME ZONE 'utc') + interval '10 minutes' ELSE v_order_record.payment_deadline END,
      rider_phone = COALESCE(p_rider_phone, rider_phone),
      shop_lat = CASE WHEN id = p_order_id THEN COALESCE(p_shop_lat, shop_lat) ELSE shop_lat END,
      shop_lng = CASE WHEN id = p_order_id THEN COALESCE(p_shop_lng, shop_lng) ELSE shop_lng END
    WHERE id = v_order_record.id;

    IF v_order_record.id = p_order_id THEN
      v_seller_accepted_return := v_order_record.seller_accepted;
    END IF;
  END LOOP;

  RETURN v_seller_accepted_return;
END;
$$;

GRANT EXECUTE ON FUNCTION accept_order_rider(UUID, text, numeric, numeric) TO authenticated;
