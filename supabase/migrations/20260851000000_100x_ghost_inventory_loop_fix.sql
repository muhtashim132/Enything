CREATE OR REPLACE FUNCTION public.reject_order_seller(p_order_id uuid, p_reject_reason text, p_message text DEFAULT NULL::text)
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

  -- Now fetch the specific order and lock it (or re-lock it safely)
  SELECT status, shop_id, payment_status INTO v_status, v_shop_id, v_payment_status
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  SELECT seller_id INTO v_seller_id FROM shops WHERE id = v_shop_id;
  IF v_seller_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  -- Allow rejection even if confirmed or preparing
  IF v_status NOT IN ('awaiting_acceptance', 'awaiting_payment', 'pending', 'confirmed', 'preparing') THEN
    RAISE EXCEPTION 'Order cannot be rejected at this stage';
  END IF;

  -- 100x BUG FIX: Ghost Inventory Loop Preventer
  -- If the seller explicitly rejects because they are out of stock, we MUST mark the 
  -- items as unavailable. The airtight cancellation trigger will mathematically restore 
  -- the stock, but since is_available = false, customers cannot order these ghost products again.
  IF p_reject_reason = 'out_of_stock' THEN
    UPDATE products
    SET is_available = false
    WHERE id IN (SELECT product_id FROM order_items WHERE order_id = p_order_id);
  END IF;

  UPDATE orders
  SET 
    status = CASE WHEN p_reject_reason = 'prescription' THEN 'verification_failed' ELSE 'seller_rejected' END,
    seller_accepted = false,
    partner_accepted = false,
    delivery_partner_id = null,
    rejection_message = p_message,
    -- Trigger refund if payment was already captured
    refund_status = CASE WHEN v_payment_status = 'captured' THEN 'processing' ELSE refund_status END
  WHERE id = p_order_id;

  -- 100x BUG FIX: Reallocate the delivery fee fraction from this cancelled order to the remaining 
  -- active orders so that the customer is not refunded the delivery fee and the rider is paid in full.
  IF v_cart_group_id IS NOT NULL THEN
    PERFORM reallocate_cancelled_delivery_fees(v_cart_group_id);
  END IF;
END;
$function$;
