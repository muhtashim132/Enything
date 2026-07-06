-- =============================================================================
-- Migration: Delivery Dashboard RPCs
-- Description: RPCs for location tracking and additional statuses.
-- =============================================================================

-- 8. RPC: Update Rider Order Location
CREATE OR REPLACE FUNCTION update_rider_order_location(p_order_ids UUID[], p_lat numeric, p_lng numeric)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Only update orders assigned to this rider
  UPDATE orders
  SET 
    rider_lat = p_lat,
    rider_lng = p_lng,
    rider_location_updated_at = now() AT TIME ZONE 'utc'
  WHERE id = ANY(p_order_ids) AND delivery_partner_id = auth.uid();
END;
$$;

GRANT EXECUTE ON FUNCTION update_rider_order_location(UUID[], numeric, numeric) TO authenticated;

-- 9. RPC: Reject Order Rider
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

GRANT EXECUTE ON FUNCTION reject_order_rider(UUID, text, numeric, boolean) TO authenticated;

-- 10. RPC: Shop Dispute
CREATE OR REPLACE FUNCTION set_shop_dispute(p_order_id UUID, p_cancel boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_delivery_partner_id uuid;
BEGIN
  SELECT delivery_partner_id INTO v_delivery_partner_id
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF v_delivery_partner_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF p_cancel = true THEN
    UPDATE orders
    SET status = 'cancelled', cancelled_reason = 'shop_dispute', wait_time_disputed = true
    WHERE id = p_order_id;
  ELSE
    UPDATE orders
    SET status = 'shop_dispute'
    WHERE id = p_order_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION set_shop_dispute(UUID, boolean) TO authenticated;

-- 11. RPC: Arrived at Shop
CREATE OR REPLACE FUNCTION set_arrived_at_shop(p_order_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_delivery_partner_id uuid;
BEGIN
  SELECT delivery_partner_id INTO v_delivery_partner_id
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF v_delivery_partner_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  UPDATE orders
  SET arrived_at_shop_time = now() AT TIME ZONE 'utc'
  WHERE id = p_order_id AND arrived_at_shop_time IS NULL;
END;
$$;

GRANT EXECUTE ON FUNCTION set_arrived_at_shop(UUID) TO authenticated;
