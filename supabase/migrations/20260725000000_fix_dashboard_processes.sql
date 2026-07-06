-- =============================================================================
-- Migration: Fix Dashboard Processes & State Machine
-- Description: 
-- 1. Adds missing FOR UPDATE lock to accept_order_seller to prevent concurrency
--    race conditions when a rider and seller accept simultaneously.
-- 2. Modifies update_order_status to accept wait_time_penalty when a rider
--    directly transitions an order to 'picked_up' without it being 'ready_for_pickup'.
-- =============================================================================

-- 1. Fix accept_order_seller missing FOR UPDATE lock
CREATE OR REPLACE FUNCTION accept_order_seller(p_order_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
  v_shop_id uuid;
  v_seller_id uuid;
BEGIN
  -- Verify order exists and get status + shop WITH FOR UPDATE LOCK
  SELECT status, shop_id INTO v_status, v_shop_id 
  FROM orders WHERE id = p_order_id FOR UPDATE;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  -- Ensure the caller is the seller for this shop
  SELECT seller_id INTO v_seller_id FROM shops WHERE id = v_shop_id;
  IF v_seller_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: Only the shop owner can accept this order';
  END IF;

  -- State machine check
  IF v_status != 'awaiting_acceptance' AND v_status != 'pending' THEN
    RAISE EXCEPTION 'Invalid state transition from %', v_status;
  END IF;

  -- Update order
  UPDATE orders
  SET 
    seller_accepted = true,
    status = CASE WHEN partner_accepted = true THEN 'awaiting_payment' ELSE status END,
    payment_deadline = CASE WHEN partner_accepted = true THEN (now() AT TIME ZONE 'utc') + interval '10 minutes' ELSE payment_deadline END
  WHERE id = p_order_id;
END;
$$;

GRANT EXECUTE ON FUNCTION accept_order_seller(UUID) TO authenticated;

-- 2. Fix update_order_status ignoring wait time penalty for picked_up status
CREATE OR REPLACE FUNCTION update_order_status(p_order_id UUID, p_new_status text, p_ready_time timestamptz DEFAULT NULL, p_wait_penalty numeric DEFAULT 0)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_status text;
  v_shop_id uuid;
  v_seller_id uuid;
  v_rider_id uuid;
BEGIN
  SELECT status, shop_id, delivery_partner_id 
  INTO v_current_status, v_shop_id, v_rider_id
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  -- Ensure Caller is authorized
  -- Depending on the new status, it should be the seller or rider
  IF p_new_status IN ('preparing', 'ready_for_pickup') THEN
    SELECT seller_id INTO v_seller_id FROM shops WHERE id = v_shop_id;
    IF v_seller_id != auth.uid() THEN
      RAISE EXCEPTION 'Unauthorized: Only seller can update to %', p_new_status;
    END IF;
  ELSIF p_new_status IN ('picked_up', 'out_for_delivery', 'delivered') THEN
    IF v_rider_id != auth.uid() THEN
      RAISE EXCEPTION 'Unauthorized: Only assigned rider can update to %', p_new_status;
    END IF;
  END IF;

  -- State machine validations could be added here
  -- For now, we trust the authorized caller for the exact transition

  -- FIX: Allow 'picked_up' to also set order_ready_time and wait_time_penalty
  IF (p_new_status = 'ready_for_pickup' OR p_new_status = 'picked_up') AND p_ready_time IS NOT NULL THEN
    UPDATE orders
    SET 
      status = p_new_status,
      order_ready_time = p_ready_time,
      wait_time_penalty = p_wait_penalty
    WHERE id = p_order_id;
  ELSE
    UPDATE orders
    SET status = p_new_status
    WHERE id = p_order_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION update_order_status(UUID, text, timestamptz, numeric) TO authenticated;
