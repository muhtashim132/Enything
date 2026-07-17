-- =============================================================================
-- Migration: 100x Customer Cancel Fortress (Phase 11)
-- Description:
--   1. Fixes a Catastrophic Customer-Triggered Double Refund Exploit (Money Printer).
--   2. Injects a strict State-Aware Refund Guard into the multi-shop iteration
--      logic of `cancel_order` to prevent the system from forcefully overwriting
--      `refund_status` back to `processing` on orders that were already refunded
--      (e.g., via a seller rejection) before the cart was cancelled.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.cancel_order(p_order_id uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_customer_id uuid;
  v_cart_group_id uuid;
  v_rec record;
  v_is_customer boolean;
BEGIN
  -- First find group ID without locking to avoid partial lock deadlocks
  SELECT customer_id, cart_group_id INTO v_customer_id, v_cart_group_id
  FROM orders WHERE id = p_order_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  v_is_customer := (auth.uid() = v_customer_id);

  -- 100x FIX: Prevent Global DoS Cancellation Exploit
  IF NOT v_is_customer AND NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: Only the customer or an admin can cancel this order.';
  END IF;

  IF v_cart_group_id IS NOT NULL THEN
    -- Lock all orders in group consistently ordered by ID
    FOR v_rec IN SELECT id, status, payment_status, refund_status FROM orders WHERE cart_group_id = v_cart_group_id ORDER BY id FOR UPDATE LOOP
      -- 100x FIX: Allow terminal states to exist in the cart group without blocking cancellation
      IF v_is_customer AND v_rec.status NOT IN (
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
          -- 100x STRESS TEST FIX (Phase 11): Prevent Customer-Triggered Double Refunds
          refund_status = CASE 
                            WHEN v_rec.payment_status = 'captured' AND COALESCE(v_rec.refund_status, 'none') NOT IN ('processing', 'completed') THEN 'processing' 
                            ELSE v_rec.refund_status 
                          END,
          updated_at = NOW()
        WHERE id = v_rec.id;
      END IF;
    END LOOP;
  ELSE
    -- Single order lock
    FOR v_rec IN SELECT id, status, payment_status, refund_status FROM orders WHERE id = p_order_id FOR UPDATE LOOP
      IF v_is_customer AND v_rec.status NOT IN (
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
          -- 100x STRESS TEST FIX (Phase 11): Prevent Customer-Triggered Double Refunds
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
$function$;
