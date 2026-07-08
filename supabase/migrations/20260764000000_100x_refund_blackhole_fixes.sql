-- =============================================================================
-- Migration: 100x Refund Blackhole Fixes
-- Description:
--   1. Fixes the "Refund Blackhole" in auto_cancel_ghost_prep_orders where 
--      ghosted orders were cancelled without triggering a refund for captured payments.
--   2. Fixes the "Refund Blackhole" in set_shop_dispute where riders cancelling 
--      an order after a shop dispute failed to trigger a refund for captured payments.
-- =============================================================================

-- 1. Fix auto_cancel_ghost_prep_orders
CREATE OR REPLACE FUNCTION auto_cancel_ghost_prep_orders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Automatically cancel orders stuck in confirmed or preparing for > 1.5 hours
  -- after the payment deadline, indicating someone ghosted.
  -- 100x FIX: Conditionally set refund_status to 'processing' if payment was captured.
  UPDATE orders
  SET 
    status = 'cancelled',
    cancelled_reason = 'timeout',
    refund_status = CASE WHEN payment_status = 'captured' THEN 'processing' ELSE refund_status END
  WHERE 
    status IN ('confirmed', 'preparing') 
    AND payment_deadline IS NOT NULL 
    AND payment_deadline < (NOW() - INTERVAL '1.5 hours');
END;
$$;

-- 2. Fix set_shop_dispute
CREATE OR REPLACE FUNCTION set_shop_dispute(p_order_id UUID, p_cancel boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
  v_payment_status text;
BEGIN
  SELECT status, payment_status INTO v_status, v_payment_status
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF v_status IN ('picked_up', 'out_for_delivery', 'delivered', 'cancelled', 'seller_rejected', 'verification_failed') THEN
    RAISE EXCEPTION 'Cannot open shop dispute at this stage: %', v_status;
  END IF;

  IF p_cancel = true THEN
    -- 100x FIX: Conditionally set refund_status to 'processing' if payment was captured.
    UPDATE orders
    SET 
      status = 'cancelled', 
      cancelled_reason = 'shop_dispute', 
      wait_time_disputed = true,
      refund_status = CASE WHEN v_payment_status = 'captured' THEN 'processing' ELSE refund_status END
    WHERE id = p_order_id;
  ELSE
    UPDATE orders
    SET status = 'shop_dispute'
    WHERE id = p_order_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION set_shop_dispute(UUID, boolean) TO authenticated;
