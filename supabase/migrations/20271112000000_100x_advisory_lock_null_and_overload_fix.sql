-- =============================================================================
-- Migration: 100x Extreme Edge Case Hoarding Fixes (Phase 2)
-- Description:
--   1. Fixes a critical crashing bug where an unauthenticated or Service Role
--      call to accept_order_rider would crash the entire function because
--      hashtext() errors out on NULL strings. Uses COALESCE to fallback to 'system_admin'.
--   2. Plugs the massive function overload loophole by adding the exact same 
--      advisory lock and terminal-state filters to the overloaded 
--      accept_order_rider(UUID) version created in Pillar 4.
-- =============================================================================

-- =============================================================================
-- 1. Patch accept_order_rider(UUID, text, numeric, numeric)
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
  v_active_cart_groups_count INT;
  v_cart_group_id UUID;
BEGIN
  -- 100x ARCHITECTURE FIX: Transaction-level Advisory Lock with COALESCE NULL Protection
  -- Prevents backend cron/admin tasks from completely crashing the system if auth.uid() is null
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

  IF v_status NOT IN ('awaiting_acceptance', 'pending') THEN
    RAISE EXCEPTION 'Invalid state transition from %', v_status;
  END IF;

  -- 100x FIX: Hoarding Prevention Check with Full Terminal States
  SELECT COUNT(DISTINCT cart_group_id) INTO v_active_cart_groups_count
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
    AND cart_group_id IS DISTINCT FROM v_cart_group_id;

  IF v_active_cart_groups_count >= 3 THEN
    RAISE EXCEPTION 'MAX_ORDERS_REACHED: You can only accept orders from up to 3 different customers at a time.';
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
$$;

GRANT EXECUTE ON FUNCTION accept_order_rider(UUID, text, numeric, numeric) TO authenticated;


-- =============================================================================
-- 2. Patch the OVERLOADED accept_order_rider(UUID) from Pillar 4
-- =============================================================================
CREATE OR REPLACE FUNCTION accept_order_rider(p_order_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
  v_delivery_partner_id uuid;
  v_cart_group_id uuid;
  v_active_carts int;
BEGIN
  -- 100x ARCHITECTURE FIX: Apply the same strict advisory lock here to prevent API hackers 
  -- from spamming the overloaded function instead of the main one!
  PERFORM pg_advisory_xact_lock(hashtext('rider_acceptance_' || COALESCE(auth.uid()::text, 'system_admin')));

  -- 100x FIX: Enforce MAX 3 Active Cart Groups
  SELECT COUNT(DISTINCT cart_group_id) INTO v_active_carts
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
    );

  IF v_active_carts >= 3 THEN
    RAISE EXCEPTION 'MAX_ORDERS_REACHED: You cannot accept more than 3 active carts simultaneously.';
  END IF;

  SELECT cart_group_id INTO v_cart_group_id FROM orders WHERE id = p_order_id;
  
  IF v_cart_group_id IS NOT NULL THEN
    PERFORM id FROM orders WHERE cart_group_id = v_cart_group_id ORDER BY id FOR UPDATE;
  ELSE
    PERFORM id FROM orders WHERE id = p_order_id FOR UPDATE;
  END IF;

  SELECT status, delivery_partner_id
  INTO v_status, v_delivery_partner_id
  FROM orders WHERE id = p_order_id;

  IF v_status != 'ready_for_pickup' THEN
    RAISE EXCEPTION 'Order is not ready for pickup (Status: %)', v_status;
  END IF;

  IF v_delivery_partner_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: You are not assigned to this order.';
  END IF;

  UPDATE orders
  SET status = 'picked_up'
  WHERE id = p_order_id;

  -- Attempt to auto-cascade other orders in the same cart
  UPDATE orders
  SET status = 'picked_up'
  WHERE cart_group_id = v_cart_group_id
    AND id != p_order_id
    AND status = 'ready_for_pickup'
    AND delivery_partner_id = auth.uid();
END;
$$;

GRANT EXECUTE ON FUNCTION accept_order_rider(UUID) TO authenticated;
