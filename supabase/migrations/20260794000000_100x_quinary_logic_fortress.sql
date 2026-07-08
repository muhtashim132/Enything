-- =============================================================================
-- Migration: 100x Quinary Logic Fortress (Customer UX Lockout Fix)
-- Description:
--   1. Patches cancel_order to allow customer cancellations even if some legs
--      of a multi-shop cart group have already failed (e.g. seller_rejected).
-- =============================================================================

CREATE OR REPLACE FUNCTION cancel_order(p_order_id UUID, p_reason text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
  -- If the caller is not the customer, and not an active admin, block the cancellation.
  IF NOT v_is_customer AND NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: Only the customer or an admin can cancel this order.';
  END IF;

  IF v_cart_group_id IS NOT NULL THEN
    -- Lock all orders in group consistently ordered by ID
    FOR v_rec IN SELECT id, status, payment_status FROM orders WHERE cart_group_id = v_cart_group_id ORDER BY id FOR UPDATE LOOP
      -- 100x FIX: Allow terminal states to exist in the cart group without blocking cancellation
      IF v_is_customer AND v_rec.status NOT IN (
        'awaiting_acceptance', 'awaiting_payment', 'pending',
        'cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel'
      ) THEN
        -- If ANY order in the group has moved past payment, the customer cannot cancel the group
        RAISE EXCEPTION 'Order cannot be cancelled at this stage by customer';
      END IF;
      
      IF v_rec.status IN ('awaiting_acceptance', 'awaiting_payment', 'pending') THEN
        UPDATE orders
        SET 
          status = 'cancelled',
          cancelled_reason = p_reason,
          refund_status = CASE WHEN v_rec.payment_status = 'captured' THEN 'processing' ELSE refund_status END
        WHERE id = v_rec.id;
      END IF;
    END LOOP;
  ELSE
    -- Single order lock
    FOR v_rec IN SELECT id, status, payment_status FROM orders WHERE id = p_order_id FOR UPDATE LOOP
      -- 100x FIX: Same UX lockout fix for single orders
      IF v_is_customer AND v_rec.status NOT IN (
        'awaiting_acceptance', 'awaiting_payment', 'pending',
        'cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel'
      ) THEN
        RAISE EXCEPTION 'Order cannot be cancelled at this stage by customer';
      END IF;

      IF v_rec.status IN ('awaiting_acceptance', 'awaiting_payment', 'pending') THEN
        UPDATE orders
        SET 
          status = 'cancelled',
          cancelled_reason = p_reason,
          refund_status = CASE WHEN v_rec.payment_status = 'captured' THEN 'processing' ELSE refund_status END
        WHERE id = v_rec.id;
      END IF;
    END LOOP;
  END IF;
END;
$$;
