-- =============================================================================
-- Migration: 20290000000050_100x_partial_rejection_master_fortress.sql
-- =============================================================================
-- Description:
--   1. Fixes database cron decision timeout query in `safe_auto_cancel_expired_orders()`
--      to ignore cart groups where replacement orders were placed ('customer_replaced')
--      and calculate decision deadline from MAX(updated_at of unhandled rejections).
--   2. Enhances `reject_order_seller` RPC to accept optional `p_out_of_stock_product_id`
--      parameter for precise out-of-stock marking on multi-item orders.
--   3. Enforces atomic execution of `reallocate_cancelled_delivery_fees` and
--      `rebalance_active_delivery_fees` across all rejection entrypoints.
-- =============================================================================

-- 1. Upgrade `reject_order_seller`
CREATE OR REPLACE FUNCTION public.reject_order_seller(
  p_order_id uuid,
  p_reject_reason text,
  p_message text DEFAULT NULL::text,
  p_out_of_stock_product_id uuid DEFAULT NULL::uuid
)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_status text;
  v_shop_id uuid;
  v_seller_id uuid;
  v_payment_status text;
  v_cart_group_id uuid;
BEGIN
  -- Fetch cart_group_id first without locking to prevent out-of-order lock deadlocks
  SELECT cart_group_id INTO v_cart_group_id
  FROM orders WHERE id = p_order_id;

  -- Lock all orders in the group deterministically by ID if it's a multi-shop order
  IF v_cart_group_id IS NOT NULL THEN
    PERFORM id FROM orders WHERE cart_group_id = v_cart_group_id ORDER BY id FOR UPDATE;
  END IF;

  -- Lock target order
  SELECT status, shop_id, payment_status INTO v_status, v_shop_id, v_payment_status
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  SELECT seller_id INTO v_seller_id FROM shops WHERE id = v_shop_id;
  
  -- Tenant isolation & authorization check
  IF v_seller_id IS NULL OR v_seller_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_status NOT IN ('awaiting_acceptance', 'awaiting_payment', 'pending', 'confirmed', 'preparing') THEN
    RAISE EXCEPTION 'Order cannot be rejected at this stage';
  END IF;

  -- Precise Out of Stock item resolution
  IF p_reject_reason = 'out_of_stock' THEN
    IF p_out_of_stock_product_id IS NOT NULL THEN
      UPDATE products
      SET is_available = false
      WHERE id = p_out_of_stock_product_id
        AND shop_id = v_shop_id;
    ELSIF (SELECT COUNT(DISTINCT product_id) FROM order_items WHERE order_id = p_order_id) = 1 THEN
      PERFORM id FROM products 
      WHERE id IN (SELECT product_id FROM order_items WHERE order_id = p_order_id)
        AND shop_id = v_shop_id
      ORDER BY id FOR UPDATE;
      
      UPDATE products
      SET is_available = false
      WHERE id IN (SELECT product_id FROM order_items WHERE order_id = p_order_id)
        AND shop_id = v_shop_id;
    END IF;
  END IF;

  UPDATE orders
  SET 
    status = CASE WHEN p_reject_reason = 'prescription' THEN 'verification_failed' ELSE 'seller_rejected' END,
    seller_accepted = false,
    partner_accepted = false,
    delivery_partner_id = null,
    rejection_message = substring(p_message from 1 for 500),
    refund_status = CASE 
      WHEN v_payment_status = 'captured' AND COALESCE(refund_status, 'none') NOT IN ('processing', 'completed') THEN 'processing' 
      ELSE refund_status 
    END,
    updated_at = NOW()
  WHERE id = p_order_id;

  -- Reallocate delivery fees & rebalance active orders atomically
  IF v_cart_group_id IS NOT NULL THEN
    PERFORM reallocate_cancelled_delivery_fees(v_cart_group_id);
    PERFORM rebalance_active_delivery_fees(v_cart_group_id);
  END IF;
END;
$function$;


-- 2. Upgrade `safe_auto_cancel_expired_orders`
CREATE OR REPLACE FUNCTION public.safe_auto_cancel_expired_orders()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_group RECORD;
BEGIN
  -- 1. Awaiting Acceptance Timeout
  FOR v_group IN 
    SELECT cart_group_id, array_agg(id) as order_ids, array_agg(payment_status) as payment_statuses
    FROM orders 
    WHERE status = 'awaiting_acceptance' AND acceptance_deadline < NOW() 
    GROUP BY cart_group_id
    LIMIT 100
  LOOP
    IF v_group.cart_group_id IS NOT NULL THEN
      PERFORM id FROM orders WHERE cart_group_id = v_group.cart_group_id ORDER BY id FOR UPDATE;
    ELSE
      PERFORM id FROM orders WHERE id = ANY(v_group.order_ids) FOR UPDATE;
    END IF;

    UPDATE orders
    SET status = 'cancelled',
        cancelled_reason = 'timeout',
        refund_status = CASE WHEN payment_status = 'captured' THEN 'processing' ELSE refund_status END,
        updated_at = NOW()
    WHERE id = ANY(v_group.order_ids);
    
    IF v_group.cart_group_id IS NOT NULL THEN
      PERFORM reallocate_cancelled_delivery_fees(v_group.cart_group_id);
      PERFORM rebalance_active_delivery_fees(v_group.cart_group_id);
    END IF;
  END LOOP;

  -- 2. Awaiting Payment Timeout
  FOR v_group IN 
    SELECT cart_group_id, array_agg(id) as order_ids, array_agg(payment_status) as payment_statuses
    FROM orders 
    WHERE status = 'awaiting_payment' AND COALESCE(payment_deadline, created_at + INTERVAL '15 minutes') < NOW() 
    GROUP BY cart_group_id
    LIMIT 100
  LOOP
    IF v_group.cart_group_id IS NOT NULL THEN
      PERFORM id FROM orders WHERE cart_group_id = v_group.cart_group_id ORDER BY id FOR UPDATE;
    ELSE
      PERFORM id FROM orders WHERE id = ANY(v_group.order_ids) FOR UPDATE;
    END IF;

    UPDATE orders
    SET status = 'cancelled',
        cancelled_reason = 'payment_failed',
        refund_status = CASE WHEN payment_status = 'captured' THEN 'processing' ELSE refund_status END,
        updated_at = NOW()
    WHERE id = ANY(v_group.order_ids);
    
    IF v_group.cart_group_id IS NOT NULL THEN
      PERFORM reallocate_cancelled_delivery_fees(v_group.cart_group_id);
      PERFORM rebalance_active_delivery_fees(v_group.cart_group_id);
    END IF;
  END LOOP;

  -- 3. Ghosted Prep Orders Timeout
  FOR v_group IN 
    SELECT cart_group_id, array_agg(id) as order_ids, array_agg(payment_status) as payment_statuses
    FROM orders 
    WHERE status IN ('confirmed', 'preparing') 
      AND payment_deadline IS NOT NULL 
      AND payment_deadline < (NOW() - INTERVAL '1.5 hours')
    GROUP BY cart_group_id
    LIMIT 100
  LOOP
    IF v_group.cart_group_id IS NOT NULL THEN
      PERFORM id FROM orders WHERE cart_group_id = v_group.cart_group_id ORDER BY id FOR UPDATE;
    ELSE
      PERFORM id FROM orders WHERE id = ANY(v_group.order_ids) FOR UPDATE;
    END IF;

    UPDATE orders
    SET status = 'cancelled',
        cancelled_reason = 'Auto-cancelled: Seller ghosted preparation',
        refund_status = CASE WHEN payment_status = 'captured' THEN 'processing' ELSE refund_status END,
        updated_at = NOW()
    WHERE id = ANY(v_group.order_ids);
    
    IF v_group.cart_group_id IS NOT NULL THEN
      PERFORM reallocate_cancelled_delivery_fees(v_group.cart_group_id);
      PERFORM rebalance_active_delivery_fees(v_group.cart_group_id);
    END IF;
  END LOOP;

  -- 4. 100x Partial Rejection Decision Timeout (5 minutes)
  -- Only targets unhandled rejections where the customer has NOT already placed a replacement order.
  FOR v_group IN 
    SELECT cart_group_id, array_agg(id) as order_ids
    FROM orders
    WHERE cart_group_id IS NOT NULL
    GROUP BY cart_group_id
    HAVING 
      COUNT(CASE WHEN status IN ('awaiting_acceptance', 'awaiting_payment', 'pending') THEN 1 END) > 0
      AND 
      COUNT(CASE WHEN status IN ('seller_rejected', 'cancelled') THEN 1 END) > 0
      AND
      -- Exclude groups where a replacement order was already placed
      COUNT(CASE WHEN cancelled_reason = 'customer_replaced' THEN 1 END) = 0
      AND
      -- Calculate deadline from MAX(updated_at) of unhandled rejections
      MAX(CASE WHEN status IN ('seller_rejected', 'cancelled') AND COALESCE(cancelled_reason, '') != 'customer_replaced' THEN COALESCE(updated_at, created_at) END) + INTERVAL '5 minutes' < NOW()
    LIMIT 100
  LOOP
    PERFORM id FROM orders WHERE cart_group_id = v_group.cart_group_id ORDER BY id FOR UPDATE;

    UPDATE orders
    SET status = 'cancelled',
        cancelled_reason = 'timeout',
        refund_status = CASE WHEN payment_status = 'captured' THEN 'processing' ELSE refund_status END,
        updated_at = NOW()
    WHERE cart_group_id = v_group.cart_group_id
      AND status IN ('awaiting_acceptance', 'awaiting_payment', 'pending');
      
    PERFORM reallocate_cancelled_delivery_fees(v_group.cart_group_id);
    PERFORM rebalance_active_delivery_fees(v_group.cart_group_id);
  END LOOP;
END;
$function$;
