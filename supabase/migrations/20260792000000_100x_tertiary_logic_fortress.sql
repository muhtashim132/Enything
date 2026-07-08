-- =============================================================================
-- Migration: 100x Tertiary Logic Fortress (Deep Edge Cases & Blackholes)
-- Description:
--   1. Patches admin_issue_refund to trigger delivery fee reallocation.
--   2. Patches set_shop_dispute to trigger delivery fee reallocation on cancel.
-- =============================================================================

-- 1. Patch admin_issue_refund (Admin Refund Blackhole)
CREATE OR REPLACE FUNCTION admin_issue_refund(p_order_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
  v_payment_status text;
  v_cart_group_id uuid;
BEGIN
  -- Strict Authorization Barrier
  IF NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;

  SELECT cart_group_id INTO v_cart_group_id FROM orders WHERE id = p_order_id;
  
  -- Strict Deterministic Locking
  IF v_cart_group_id IS NOT NULL THEN
    PERFORM id FROM orders WHERE cart_group_id = v_cart_group_id ORDER BY id FOR UPDATE;
  ELSE
    PERFORM id FROM orders WHERE id = p_order_id FOR UPDATE;
  END IF;

  SELECT status, payment_status INTO v_status, v_payment_status
  FROM orders WHERE id = p_order_id;

  IF v_status = 'delivered' THEN
    RAISE EXCEPTION 'Cannot refund a delivered order directly without dispute';
  END IF;

  IF v_status IN ('cancelled', 'seller_rejected', 'verification_failed', 'shop_dispute', 'shop_dispute_cancel') THEN
    IF v_payment_status != 'captured' THEN
      RAISE EXCEPTION 'Order % has no captured payment to refund.', p_order_id;
    END IF;
    UPDATE orders
    SET refund_status = 'processing'
    WHERE id = p_order_id;
  ELSE
    UPDATE orders
    SET
      status           = 'cancelled',
      refund_status    = 'processing',
      cancelled_reason = 'admin_refund'
    WHERE id = p_order_id;
    
    -- 100x FIX: Trigger reallocation if order is newly cancelled
    IF v_cart_group_id IS NOT NULL THEN
      PERFORM reallocate_cancelled_delivery_fees(v_cart_group_id);
    END IF;
  END IF;
END;
$$;


-- 2. Patch set_shop_dispute (Dispute Cancellation Blackhole)
CREATE OR REPLACE FUNCTION set_shop_dispute(p_order_id UUID, p_cancel boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
  v_payment_status text;
  v_cart_group_id uuid;
BEGIN
  SELECT cart_group_id INTO v_cart_group_id FROM orders WHERE id = p_order_id;
  
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
    
    -- 100x FIX: Trigger reallocation if order is cancelled via dispute
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
