-- Migration 20260896000000_fix_cancel_order_rpc.sql
-- Additive fix: Remove terminal states (seller_rejected, rider_rejected) from being updated to 'cancelled' in cancel_order RPC
-- This prevents the tr_guard_order_status_transitions trigger from throwing a P0001 error when cancelling a cart group with partial rejections.

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
      
      -- ADDITIVE FIX: Removed 'seller_rejected' and 'rider_rejected' to prevent terminal-state update violations
      IF v_rec.status IN ('awaiting_acceptance', 'awaiting_payment', 'pending') THEN
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

      -- ADDITIVE FIX: Removed 'seller_rejected' and 'rider_rejected'
      IF v_rec.status IN ('awaiting_acceptance', 'awaiting_payment', 'pending') THEN
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
