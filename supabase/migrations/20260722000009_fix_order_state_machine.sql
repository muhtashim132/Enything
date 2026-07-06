-- =============================================================================
-- Migration: Secure Order State Machine & Process Fixes
-- Description: Fixes critical race conditions and missing state validations
-- in Customer, Seller, Delivery Partner, and Admin RPCs.
-- =============================================================================

-- 1. Fix client_confirm_payment
CREATE OR REPLACE FUNCTION client_confirm_payment(
  p_order_id UUID DEFAULT NULL,
  p_cart_group_id UUID DEFAULT NULL,
  p_razorpay_payment_id text DEFAULT NULL,
  p_razorpay_order_id text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
  v_order_id uuid;
  v_rec record;
BEGIN
  IF p_cart_group_id IS NOT NULL THEN
    FOR v_rec IN SELECT id, status FROM orders WHERE cart_group_id = p_cart_group_id FOR UPDATE LOOP
      IF v_rec.status = 'awaiting_payment' THEN
        UPDATE orders
        SET 
          status = 'confirmed',
          payment_status = 'captured',
          razorpay_payment_id = p_razorpay_payment_id,
          razorpay_order_id = p_razorpay_order_id
        WHERE id = v_rec.id;
      ELSE
        -- Order status changed while customer was paying! Capture payment info and set to refund processing.
        UPDATE orders
        SET 
          payment_status = 'captured',
          refund_status = 'processing',
          razorpay_payment_id = p_razorpay_payment_id,
          razorpay_order_id = p_razorpay_order_id
        WHERE id = v_rec.id;
      END IF;
    END LOOP;
  ELSE
    SELECT status INTO v_status FROM orders WHERE id = p_order_id FOR UPDATE;
    IF FOUND THEN
      IF v_status = 'awaiting_payment' THEN
        UPDATE orders
        SET 
          status = 'confirmed',
          payment_status = 'captured',
          razorpay_payment_id = p_razorpay_payment_id,
          razorpay_order_id = p_razorpay_order_id
        WHERE id = p_order_id;
      ELSE
        -- State changed during payment
        UPDATE orders
        SET 
          payment_status = 'captured',
          refund_status = 'processing',
          razorpay_payment_id = p_razorpay_payment_id,
          razorpay_order_id = p_razorpay_order_id
        WHERE id = p_order_id;
      END IF;
    END IF;
  END IF;
END;
$$;

-- 2. Fix reject_order_rider
CREATE OR REPLACE FUNCTION reject_order_rider(p_order_id UUID, p_reason text DEFAULT NULL, p_penalty numeric DEFAULT 0, p_disputed boolean DEFAULT false)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
  v_delivery_partner_id uuid;
BEGIN
  SELECT status, delivery_partner_id INTO v_status, v_delivery_partner_id
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF v_status NOT IN ('awaiting_acceptance', 'pending', 'awaiting_payment') THEN
    RAISE EXCEPTION 'Invalid state transition from %', v_status;
  END IF;

  UPDATE orders
  SET 
    status = 'awaiting_acceptance',
    partner_accepted = false,
    delivery_partner_id = null,
    wait_time_penalty = COALESCE(p_penalty, 0),
    wait_time_disputed = COALESCE(p_disputed, false)
  WHERE id = p_order_id;
END;
$$;

-- 3. Fix set_shop_dispute
CREATE OR REPLACE FUNCTION set_shop_dispute(p_order_id UUID, p_cancel boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
  v_delivery_partner_id uuid;
BEGIN
  SELECT status, delivery_partner_id INTO v_status, v_delivery_partner_id
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF v_delivery_partner_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_status IN ('picked_up', 'out_for_delivery', 'delivered', 'cancelled', 'seller_rejected', 'verification_failed') THEN
    RAISE EXCEPTION 'Cannot open shop dispute at this stage: %', v_status;
  END IF;

  IF p_cancel = true THEN
    UPDATE orders
    SET status = 'cancelled', cancelled_reason = 'shop_dispute', wait_time_disputed = true
    WHERE id = p_order_id;
  ELSE
    UPDATE orders
    SET status = 'shop_dispute'
    WHERE id = p_order_id;
  END IF;
END;
$$;

-- 4. Fix reject_order_seller
CREATE OR REPLACE FUNCTION reject_order_seller(p_order_id UUID, p_reject_reason text, p_message text DEFAULT NULL)
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
  SELECT status, shop_id INTO v_status, v_shop_id
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  SELECT seller_id INTO v_seller_id FROM shops WHERE id = v_shop_id;
  IF v_seller_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_status NOT IN ('awaiting_acceptance', 'awaiting_payment', 'pending') THEN
    RAISE EXCEPTION 'Order cannot be rejected at this stage';
  END IF;

  UPDATE orders
  SET 
    status = CASE WHEN p_reject_reason = 'prescription' THEN 'verification_failed' ELSE 'seller_rejected' END,
    seller_accepted = false,
    partner_accepted = false,
    delivery_partner_id = null,
    rejection_message = p_message
  WHERE id = p_order_id;
END;
$$;

-- 5. Fix retry_find_rider
CREATE OR REPLACE FUNCTION retry_find_rider(p_order_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer_id uuid;
  v_status text;
  v_partner_accepted boolean;
  v_cart_group_id text;
BEGIN
  SELECT customer_id, status, partner_accepted, cart_group_id INTO v_customer_id, v_status, v_partner_accepted, v_cart_group_id
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF v_customer_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_status NOT IN ('pending', 'awaiting_acceptance') THEN
    RAISE EXCEPTION 'Cannot retry finding rider from status %', v_status;
  END IF;
  
  IF v_partner_accepted = true THEN
    RAISE EXCEPTION 'Rider has already accepted, cannot retry';
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
    WHERE cart_group_id = v_cart_group_id AND partner_accepted = false;
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
    WHERE id = p_order_id AND partner_accepted = false;
  END IF;
END;
$$;

-- 6. Fix cancel_order
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
  v_rec record;
BEGIN
  SELECT customer_id, status, cart_group_id INTO v_customer_id, v_status, v_cart_group_id
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF auth.uid() = v_customer_id THEN
    IF v_status NOT IN ('awaiting_acceptance', 'awaiting_payment') THEN
      RAISE EXCEPTION 'Order cannot be cancelled at this stage by customer';
    END IF;
  END IF;

  IF v_cart_group_id IS NOT NULL THEN
    FOR v_rec IN SELECT id, status, payment_status FROM orders WHERE cart_group_id = v_cart_group_id AND status IN ('awaiting_acceptance', 'awaiting_payment', 'pending') FOR UPDATE LOOP
      UPDATE orders
      SET 
        status = 'cancelled',
        cancelled_reason = p_reason,
        refund_status = CASE WHEN payment_status = 'captured' THEN 'processing' ELSE refund_status END
      WHERE id = v_rec.id;
    END LOOP;
  ELSE
    IF v_status IN ('awaiting_acceptance', 'awaiting_payment', 'pending') THEN
      UPDATE orders
      SET 
        status = 'cancelled',
        cancelled_reason = p_reason,
        refund_status = CASE WHEN (SELECT payment_status FROM orders WHERE id = p_order_id) = 'captured' THEN 'processing' ELSE refund_status END
      WHERE id = p_order_id;
    END IF;
  END IF;
END;
$$;

-- 7. Fix admin_cancel_order and admin_issue_refund
CREATE OR REPLACE FUNCTION admin_cancel_order(p_order_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
  v_payment_status text;
BEGIN
  SELECT status, payment_status INTO v_status, v_payment_status FROM orders WHERE id = p_order_id FOR UPDATE;
  
  IF v_status IN ('cancelled', 'delivered') THEN
    RAISE EXCEPTION 'Order is already %', v_status;
  END IF;
  
  UPDATE orders
  SET 
    status = 'cancelled', 
    cancelled_reason = 'admin',
    refund_status = CASE WHEN v_payment_status = 'captured' THEN 'processing' ELSE refund_status END
  WHERE id = p_order_id;
END;
$$;

CREATE OR REPLACE FUNCTION admin_issue_refund(p_order_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
BEGIN
  SELECT status INTO v_status FROM orders WHERE id = p_order_id FOR UPDATE;
  
  IF v_status = 'delivered' THEN
    RAISE EXCEPTION 'Cannot refund a delivered order directly without dispute';
  END IF;

  UPDATE orders
  SET 
    status = 'cancelled',
    refund_status = 'processing',
    cancelled_reason = 'admin_refund'
  WHERE id = p_order_id;
END;
$$;
