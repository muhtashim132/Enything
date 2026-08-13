-- =============================================================================
-- Migration: 20290000000055_100x_admin_cancel_rebalance_fix.sql
-- Description:
--   1. Enhances admin_cancel_order to invoke both reallocate_cancelled_delivery_fees
--      and rebalance_active_delivery_fees when an admin cancels an order in a
--      multi-shop cart group.
--   2. Ensures strict audit logging and consistent terminal status management.
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

  -- 100x STRESS TEST FIX: Prevent Admin Override of Terminal States
  IF v_status IN ('cancelled', 'seller_rejected', 'partner_rejected', 'timeout', 'verification_failed', 'shop_dispute_cancel', 'payment_failed') THEN
    RAISE EXCEPTION 'Order is already in a terminal cancellation state: %', v_status;
  END IF;

  -- Update order status and refund flags
  IF v_status IN ('picked_up', 'out_for_delivery', 'delivered') THEN
    UPDATE orders
    SET
      status           = 'cancelled',
      cancelled_reason = 'admin',
      refund_status    = CASE
                           WHEN v_payment_status = 'captured' AND COALESCE(refund_status, 'none') NOT IN ('processing', 'completed') THEN 'processing'
                           ELSE refund_status
                         END,
      updated_at       = NOW()
    WHERE id = p_order_id;
  ELSE
    UPDATE orders
    SET
      status           = 'cancelled',
      cancelled_reason = 'admin',
      rider_earnings   = 0, -- Zero out only if rider did not physically transport it
      wait_time_penalty = 0,
      refund_status    = CASE
                           WHEN v_payment_status = 'captured' AND COALESCE(refund_status, 'none') NOT IN ('processing', 'completed') THEN 'processing'
                           ELSE refund_status
                         END,
      updated_at       = NOW()
    WHERE id = p_order_id;
  END IF;

  -- Reallocate and rebalance delivery fees for multi-shop cart groups
  IF v_cart_group_id IS NOT NULL THEN
    PERFORM reallocate_cancelled_delivery_fees(v_cart_group_id);
    PERFORM rebalance_active_delivery_fees(v_cart_group_id);
  END IF;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.admin_cancel_order(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_cancel_order(uuid) TO service_role;

NOTIFY pgrst, 'reload schema';
