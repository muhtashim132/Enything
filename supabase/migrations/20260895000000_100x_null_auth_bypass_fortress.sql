-- Migration 20260895000000_100x_null_auth_bypass_fortress.sql
-- Additive fixes for SQL ternary logic NULL bypasses in Auth Guards

-- 1. Fix cancel_order NULL Auth Bypass
CREATE OR REPLACE FUNCTION cancel_order(p_order_id UUID, p_reason TEXT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_customer_id uuid;
  v_cart_group_id uuid;
  v_rec record;
  v_is_customer boolean;
BEGIN
  SELECT customer_id, cart_group_id INTO v_customer_id, v_cart_group_id
  FROM orders WHERE id = p_order_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  v_is_customer := (auth.uid() = v_customer_id);

  -- 100x FIX: Prevent Global DoS Cancellation Exploit (NULL Bypass)
  IF auth.uid() IS NULL OR (NOT COALESCE(v_is_customer, false) AND NOT public.is_active_admin(auth.uid())) THEN
    RAISE EXCEPTION 'Unauthorized: Only the customer or an admin can cancel this order.';
  END IF;

  IF v_cart_group_id IS NOT NULL THEN
    FOR v_rec IN SELECT id, status, payment_status, refund_status FROM orders WHERE cart_group_id = v_cart_group_id ORDER BY id FOR UPDATE LOOP
      IF COALESCE(v_is_customer, false) AND v_rec.status NOT IN (
        'awaiting_acceptance', 'awaiting_payment', 'pending',
        'cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel', 'rider_rejected'
      ) THEN
        RAISE EXCEPTION 'Order cannot be cancelled at this stage by customer';
      END IF;
      
      IF v_rec.status IN ('awaiting_acceptance', 'awaiting_payment', 'pending', 'seller_rejected', 'rider_rejected') THEN
        UPDATE orders
        SET 
          status = 'cancelled',
          cancelled_reason = p_reason,
          refund_status = CASE 
                            WHEN v_rec.payment_status = 'captured' AND COALESCE(v_rec.refund_status, 'none') NOT IN ('processing', 'completed') THEN 'processing' 
                            ELSE v_rec.refund_status 
                          END,
          updated_at = NOW()
        WHERE id = v_rec.id;
      END IF;
    END LOOP;
    
    PERFORM reallocate_cancelled_delivery_fees(v_cart_group_id);
    
  ELSE
    FOR v_rec IN SELECT id, status, payment_status, refund_status FROM orders WHERE id = p_order_id FOR UPDATE LOOP
      IF COALESCE(v_is_customer, false) AND v_rec.status NOT IN (
        'awaiting_acceptance', 'awaiting_payment', 'pending',
        'cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel', 'rider_rejected'
      ) THEN
        RAISE EXCEPTION 'Order cannot be cancelled at this stage by customer';
      END IF;

      IF v_rec.status IN ('awaiting_acceptance', 'awaiting_payment', 'pending', 'seller_rejected', 'rider_rejected') THEN
        UPDATE orders
        SET 
          status = 'cancelled',
          cancelled_reason = p_reason,
          refund_status = CASE 
                            WHEN v_rec.payment_status = 'captured' AND COALESCE(v_rec.refund_status, 'none') NOT IN ('processing', 'completed') THEN 'processing' 
                            ELSE v_rec.refund_status 
                          END,
          updated_at = NOW()
        WHERE id = v_rec.id;
      END IF;
    END LOOP;
  END IF;
END;
$$;

-- 2. Fix get_order_reorder_data NULL Auth Bypass
CREATE OR REPLACE FUNCTION get_order_reorder_data(p_order_id UUID)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_customer_id uuid;
  v_result json;
BEGIN
  -- Verify ownership
  SELECT customer_id INTO v_customer_id FROM orders WHERE id = p_order_id;
  IF auth.uid() IS NULL OR v_customer_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT json_agg(
    json_build_object(
      'quantity', oi.quantity,
      'variant_name', oi.variant_name,
      'product_id', oi.product_id,
      'product', row_to_json(p.*),
      'shop', row_to_json(s.*)
    )
  )
  INTO v_result
  FROM order_items oi
  JOIN products p ON p.id = oi.product_id
  JOIN shops s ON s.id = p.shop_id
  WHERE oi.order_id = p_order_id
    AND p.is_available = true
    AND s.is_active = true;

  RETURN COALESCE(v_result, '[]'::json);
END;
$$;

-- 3. Fix submit_seller_kyc NULL Auth Bypass
CREATE OR REPLACE FUNCTION submit_seller_kyc(
  p_seller_id UUID, p_aadhar_number TEXT, p_pan_number TEXT, 
  p_gst_number TEXT, p_trade_license TEXT, p_bank_account_holder TEXT, 
  p_bank_account_number TEXT, p_bank_ifsc TEXT, p_kyc_documents JSONB
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_seller_id THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  UPDATE shops
  SET 
    aadhar_number = p_aadhar_number,
    pan_number = p_pan_number,
    gst_number = p_gst_number,
    trade_license = p_trade_license,
    bank_account_holder = p_bank_account_holder,
    bank_account_number = p_bank_account_number,
    bank_ifsc = p_bank_ifsc,
    kyc_documents = p_kyc_documents,
    verification_status = 'pending'
  WHERE seller_id = p_seller_id;
END;
$$;

-- 4. Fix submit_delivery_kyc NULL Auth Bypass
CREATE OR REPLACE FUNCTION submit_delivery_kyc(
  p_partner_id UUID, p_aadhar_number TEXT, p_pan_number TEXT, 
  p_driving_license TEXT, p_bank_account_holder TEXT, 
  p_bank_account_number TEXT, p_bank_ifsc TEXT, p_kyc_documents JSONB
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_partner_id THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  UPDATE delivery_partners
  SET 
    aadhar_number = p_aadhar_number,
    pan_number = p_pan_number,
    driving_license = p_driving_license,
    bank_account_holder = p_bank_account_holder,
    bank_account_number = p_bank_account_number,
    bank_ifsc = p_bank_ifsc,
    kyc_documents = p_kyc_documents,
    verification_status = 'pending'
  WHERE id = p_partner_id;
END;
$$;

-- 5. Fix accept_order_rider NULL Auth Bypass
CREATE OR REPLACE FUNCTION accept_order_rider(p_order_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_status text;
  v_delivery_partner_id uuid;
  v_cart_group_id uuid;
  v_active_carts int;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('rider_acceptance_' || COALESCE(auth.uid()::text, 'system_admin')));

  SELECT COUNT(DISTINCT COALESCE(cart_group_id, id)) INTO v_active_carts
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

  IF auth.uid() IS NULL OR v_delivery_partner_id IS DISTINCT FROM auth.uid() THEN
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
