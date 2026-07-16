-- =============================================================================
-- Migration: 100x Admin Override Fortress (Phase 10)
-- Description:
--   1. Fixes a Catastrophic Double Refund Financial Exploit inside the 
--      highest privilege layer (`admin_cancel_order`).
--   2. Injects strict terminal state guards to prevent admins from cancelling
--      orders that were already rejected by sellers or timed out.
--   3. Injects the strict State-Aware Refund Guard to prevent blindly overwriting
--      `refund_status` back to `processing` on already refunded orders.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.admin_cancel_order(p_order_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_status text;
  v_payment_status text;
  v_cart_group_id uuid;
BEGIN
  -- Fetch cart_group_id first without locking
  SELECT cart_group_id INTO v_cart_group_id
  FROM orders WHERE id = p_order_id;

  -- Lock orders dynamically (deadlock safe)
  IF v_cart_group_id IS NOT NULL THEN
    PERFORM id FROM orders WHERE cart_group_id = v_cart_group_id ORDER BY id FOR UPDATE;
  ELSE
    PERFORM id FROM orders WHERE id = p_order_id FOR UPDATE;
  END IF;

  -- Get current status of the target order
  SELECT status, payment_status INTO v_status, v_payment_status
  FROM orders WHERE id = p_order_id;

  -- 100x STRESS TEST FIX (Phase 10): Prevent Admin Override of Terminal States
  IF v_status IN ('cancelled', 'seller_rejected', 'partner_rejected', 'timeout', 'verification_failed', 'shop_dispute_cancel', 'payment_failed') THEN
    RAISE EXCEPTION 'Order is already in a terminal cancellation state: %', v_status;
  END IF;

  -- 100x FIX: Do not hard-zero platform_fee, gst_platform, seller_payout, grand_total.
  -- The frontend relies on these existing values to render customer receipts.
  -- Revenue dashboards filter out refunded orders via `refund_status`.
  IF v_status IN ('picked_up', 'out_for_delivery', 'delivered') THEN
    UPDATE orders
    SET
      status           = 'cancelled',
      cancelled_reason = 'admin',
      -- 100x STRESS TEST FIX (Phase 10): Prevent Admin Double Refund
      refund_status    = CASE
                           WHEN v_payment_status = 'captured' AND COALESCE(refund_status, 'none') NOT IN ('processing', 'completed') THEN 'processing'
                           ELSE refund_status
                         END
    WHERE id = p_order_id;
  ELSE
    UPDATE orders
    SET
      status           = 'cancelled',
      cancelled_reason = 'admin',
      rider_earnings   = 0, -- Zero out only if rider did not physically transport it
      wait_time_penalty = 0,
      -- 100x STRESS TEST FIX (Phase 10): Prevent Admin Double Refund
      refund_status    = CASE
                           WHEN v_payment_status = 'captured' AND COALESCE(refund_status, 'none') NOT IN ('processing', 'completed') THEN 'processing'
                           ELSE refund_status
                         END
    WHERE id = p_order_id;
  END IF;

  -- Reallocate delivery fees for admin cancellations
  IF v_cart_group_id IS NOT NULL THEN
    PERFORM reallocate_cancelled_delivery_fees(v_cart_group_id);
  END IF;
END;
$function$;
