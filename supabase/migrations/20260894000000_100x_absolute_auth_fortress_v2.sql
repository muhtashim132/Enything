-- Migration 20260894000000_100x_absolute_auth_fortress_v2.sql

-- 1. Fix set_shop_dispute Global IDOR Null logic
CREATE OR REPLACE FUNCTION set_shop_dispute(p_order_id UUID, p_cancel BOOLEAN)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_status text;
  v_payment_status text;
  v_cart_group_id uuid;
  v_customer_id uuid;
BEGIN
  SELECT cart_group_id, customer_id INTO v_cart_group_id, v_customer_id FROM orders WHERE id = p_order_id;
  
  -- 100x FIX: Prevent Global DoS by unauthenticated / unauthorized users. Use IS DISTINCT FROM to handle NULLs properly!
  IF auth.uid() IS NULL OR (v_customer_id IS DISTINCT FROM auth.uid() AND NOT public.is_active_admin(auth.uid())) THEN
    RAISE EXCEPTION 'Unauthorized: Only the customer or an admin can open a dispute';
  END IF;

  -- Strict Deterministic Locking
  IF v_cart_group_id IS NOT NULL THEN
    PERFORM id FROM orders WHERE cart_group_id = v_cart_group_id ORDER BY id FOR UPDATE;
  ELSE
    PERFORM id FROM orders WHERE id = p_order_id FOR UPDATE;
  END IF;

  SELECT status, payment_status INTO v_status, v_payment_status
  FROM orders WHERE id = p_order_id;

  IF v_status IN ('picked_up', 'out_for_delivery', 'delivered', 'cancelled', 'seller_rejected', 'verification_failed', 'shop_dispute_cancel') THEN
    RAISE EXCEPTION 'Cannot open shop dispute at this stage: %', v_status;
  END IF;

  IF p_cancel = true THEN
    UPDATE orders
    SET 
      status = 'cancelled', 
      cancelled_reason = 'shop_dispute', 
      wait_time_disputed = true,
      refund_status = CASE WHEN v_payment_status = 'captured' THEN 'processing' ELSE refund_status END
    WHERE id = p_order_id;
    
    IF v_cart_group_id IS NOT NULL THEN
      PERFORM reallocate_cancelled_delivery_fees(v_cart_group_id);
    END IF;
  ELSE
    UPDATE orders
    SET status = 'shop_dispute'
    WHERE id = p_order_id;
  END IF;
END;
$$;

-- 2. Fix get_order_item_count_v1 IDOR Data Leak
CREATE OR REPLACE FUNCTION get_order_item_count_v1(p_order_id UUID)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_count integer;
  v_authorized boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  -- Check if user is associated with this order
  SELECT EXISTS (
    SELECT 1 FROM orders o
    LEFT JOIN shops s ON o.shop_id = s.id
    WHERE o.id = p_order_id
    AND (
      o.customer_id = auth.uid() OR
      o.delivery_partner_id = auth.uid() OR
      s.seller_id = auth.uid() OR
      public.is_active_admin(auth.uid())
    )
  ) INTO v_authorized;
  
  IF NOT v_authorized THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT count(*)::integer INTO v_count FROM order_items WHERE order_id = p_order_id;
  RETURN v_count;
END;
$$;
