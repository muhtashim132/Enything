-- =============================================================================
-- Migration: 20290000000060_unify_reject_order_seller_overload.sql
-- =============================================================================
-- Drop the obsolete 3-parameter overload of reject_order_seller to eliminate PostgREST PGRST203 overload ambiguity
DROP FUNCTION IF EXISTS public.reject_order_seller(uuid, text, text);

-- Ensure the 4-parameter unified version is active and granted
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

GRANT EXECUTE ON FUNCTION public.reject_order_seller(UUID, text, text, UUID) TO authenticated;
