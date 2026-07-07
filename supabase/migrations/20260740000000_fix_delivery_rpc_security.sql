-- =============================================================================
-- Migration: Fix Delivery RPC Security
-- Description: Adds authorization checks to reject_order_rider to prevent 
-- arbitrary users from dropping orders assigned to other riders.
-- =============================================================================

CREATE OR REPLACE FUNCTION reject_order_rider(p_order_id UUID, p_reason text DEFAULT NULL, p_penalty numeric DEFAULT 0, p_disputed boolean DEFAULT false)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
  v_delivery_partner_id uuid;
BEGIN
  SELECT status, delivery_partner_id INTO v_status, v_delivery_partner_id
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  -- Security Check: Ensure caller is the assigned rider
  IF v_delivery_partner_id IS NOT NULL AND v_delivery_partner_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: Only assigned rider can drop this order';
  END IF;

  IF v_status NOT IN ('awaiting_acceptance', 'pending', 'awaiting_payment') THEN
    RAISE EXCEPTION 'Invalid state transition from %', v_status;
  END IF;

  UPDATE orders
  SET 
    status = 'awaiting_acceptance',
    partner_accepted = false,
    delivery_partner_id = null,
    wait_time_penalty = COALESCE(p_penalty, 0),
    wait_time_disputed = COALESCE(p_disputed, false)
  WHERE id = p_order_id;
END;
$$;
