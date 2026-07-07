-- =============================================================================
-- Migration: Wait Time Dispute RPC
-- Description:
--   Allows a rider to dispute a seller's "ready_for_pickup" status if the food
--   is actually not ready, preventing wait-time penalty fraud.
-- =============================================================================

CREATE OR REPLACE FUNCTION dispute_wait_time(p_order_id UUID)
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

  IF v_delivery_partner_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized: Only assigned rider can dispute';
  END IF;

  IF v_status != 'ready_for_pickup' THEN
    RAISE EXCEPTION 'Order must be marked ready for pickup to dispute';
  END IF;

  UPDATE orders
  SET 
    wait_time_disputed = true,
    status = 'preparing',
    order_ready_time = null
  WHERE id = p_order_id;
END;
$$;

GRANT EXECUTE ON FUNCTION dispute_wait_time(UUID) TO authenticated;
