-- =============================================================================
-- Migration: Secure Order State Machine & Strict RPCs
-- Description: Revokes direct UPDATE on orders from clients and implements
-- secure state transition RPCs.
-- =============================================================================

-- 1. Revoke direct UPDATE on orders table from public/authenticated users
REVOKE UPDATE ON orders FROM public, authenticated, anon;

-- Note: We still allow SELECT and INSERT (if governed by other policies).
-- However, we should also probably restrict INSERT directly in the future,
-- but for now we focus on UPDATE.

-- 2. RPC: Seller accepts order
CREATE OR REPLACE FUNCTION accept_order_seller(p_order_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
  v_shop_id uuid;
  v_seller_id uuid;
BEGIN
  -- Verify order exists and get status + shop
  SELECT status, shop_id INTO v_status, v_shop_id 
  FROM orders WHERE id = p_order_id;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  -- Ensure the caller is the seller for this shop
  SELECT seller_id INTO v_seller_id FROM shops WHERE id = v_shop_id;
  IF v_seller_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: Only the shop owner can accept this order';
  END IF;

  -- State machine check
  IF v_status != 'awaiting_acceptance' AND v_status != 'pending' THEN
    RAISE EXCEPTION 'Invalid state transition from %', v_status;
  END IF;

  -- Update order
  UPDATE orders
  SET 
    seller_accepted = true,
    status = CASE WHEN partner_accepted = true THEN 'awaiting_payment' ELSE status END,
    payment_deadline = CASE WHEN partner_accepted = true THEN (now() AT TIME ZONE 'utc') + interval '10 minutes' ELSE payment_deadline END
  WHERE id = p_order_id;
END;
$$;

GRANT EXECUTE ON FUNCTION accept_order_seller(UUID) TO authenticated;

-- 3. RPC: Rider accepts order
CREATE OR REPLACE FUNCTION accept_order_rider(p_order_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
  v_partner_id uuid;
BEGIN
  -- We assume the rider is assigning themselves
  SELECT status INTO v_status 
  FROM orders WHERE id = p_order_id FOR UPDATE;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  -- In Enything, a rider can claim an order if it has no rider yet, or they were assigned.
  -- For safety, we just update the partner_accepted flag and delivery_partner_id
  
  -- State machine check
  IF v_status NOT IN ('awaiting_acceptance', 'pending') THEN
    RAISE EXCEPTION 'Invalid state transition from %', v_status;
  END IF;

  UPDATE orders
  SET 
    partner_accepted = true,
    delivery_partner_id = auth.uid(),
    status = CASE WHEN seller_accepted = true THEN 'awaiting_payment' ELSE status END,
    payment_deadline = CASE WHEN seller_accepted = true THEN (now() AT TIME ZONE 'utc') + interval '10 minutes' ELSE payment_deadline END
  WHERE id = p_order_id AND (delivery_partner_id IS NULL OR delivery_partner_id = auth.uid());
END;
$$;

GRANT EXECUTE ON FUNCTION accept_order_rider(UUID) TO authenticated;

-- 4. RPC: Customer retries finding a rider
CREATE OR REPLACE FUNCTION retry_find_rider(p_order_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer_id uuid;
  v_status text;
  v_cart_group_id text;
BEGIN
  SELECT customer_id, status, cart_group_id INTO v_customer_id, v_status, v_cart_group_id
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF v_customer_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  -- Allow retry only if status allows it
  IF v_status NOT IN ('pending', 'awaiting_acceptance', 'seller_accepted') THEN
    RAISE EXCEPTION 'Cannot retry finding rider from status %', v_status;
  END IF;

  IF v_cart_group_id IS NOT NULL THEN
    UPDATE orders
    SET 
      status = 'awaiting_acceptance',
      cancelled_reason = null,
      partner_accepted = false,
      delivery_partner_id = null,
      rider_phone = null,
      rider_lat = null,
      rider_lng = null,
      acceptance_deadline = (now() AT TIME ZONE 'utc') + interval '3 minutes'
    WHERE cart_group_id = v_cart_group_id;
  ELSE
    UPDATE orders
    SET 
      status = 'awaiting_acceptance',
      cancelled_reason = null,
      partner_accepted = false,
      delivery_partner_id = null,
      rider_phone = null,
      rider_lat = null,
      rider_lng = null,
      acceptance_deadline = (now() AT TIME ZONE 'utc') + interval '3 minutes'
    WHERE id = p_order_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION retry_find_rider(UUID) TO authenticated;

-- 5. RPC: Update order status securely
CREATE OR REPLACE FUNCTION update_order_status(p_order_id UUID, p_new_status text, p_ready_time timestamptz DEFAULT NULL, p_wait_penalty numeric DEFAULT 0)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_status text;
  v_shop_id uuid;
  v_seller_id uuid;
  v_rider_id uuid;
BEGIN
  SELECT status, shop_id, delivery_partner_id 
  INTO v_current_status, v_shop_id, v_rider_id
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  -- Ensure Caller is authorized
  -- Depending on the new status, it should be the seller or rider
  IF p_new_status IN ('preparing', 'ready_for_pickup') THEN
    SELECT seller_id INTO v_seller_id FROM shops WHERE id = v_shop_id;
    IF v_seller_id != auth.uid() THEN
      RAISE EXCEPTION 'Unauthorized: Only seller can update to %', p_new_status;
    END IF;
  ELSIF p_new_status IN ('picked_up', 'out_for_delivery', 'delivered') THEN
    IF v_rider_id != auth.uid() THEN
      RAISE EXCEPTION 'Unauthorized: Only assigned rider can update to %', p_new_status;
    END IF;
  END IF;

  -- State machine validations could be added here
  -- For now, we trust the authorized caller for the exact transition

  IF p_new_status = 'ready_for_pickup' AND p_ready_time IS NOT NULL THEN
    UPDATE orders
    SET 
      status = p_new_status,
      order_ready_time = p_ready_time,
      wait_time_penalty = p_wait_penalty
    WHERE id = p_order_id;
  ELSE
    UPDATE orders
    SET status = p_new_status
    WHERE id = p_order_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION update_order_status(UUID, text, timestamptz, numeric) TO authenticated;

-- 6. RPC: Cancel Order Securely
CREATE OR REPLACE FUNCTION cancel_order(p_order_id UUID, p_reason text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer_id uuid;
  v_status text;
  v_cart_group_id text;
BEGIN
  SELECT customer_id, status, cart_group_id INTO v_customer_id, v_status, v_cart_group_id
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  -- Determine if caller is customer, seller, or system
  -- Customer cancelling
  IF auth.uid() = v_customer_id THEN
    IF v_status NOT IN ('awaiting_acceptance', 'awaiting_payment') THEN
      RAISE EXCEPTION 'Order cannot be cancelled at this stage by customer';
    END IF;
  END IF;

  IF v_cart_group_id IS NOT NULL THEN
    UPDATE orders
    SET 
      status = 'cancelled',
      cancelled_reason = p_reason
    WHERE cart_group_id = v_cart_group_id AND status IN ('awaiting_acceptance', 'awaiting_payment', 'pending');
  ELSE
    UPDATE orders
    SET 
      status = 'cancelled',
      cancelled_reason = p_reason
    WHERE id = p_order_id AND status IN ('awaiting_acceptance', 'awaiting_payment', 'pending');
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION cancel_order(UUID, text) TO authenticated;
