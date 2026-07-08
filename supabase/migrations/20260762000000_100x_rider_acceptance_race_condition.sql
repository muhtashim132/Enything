-- =============================================================================
-- Migration: 100x Rider Acceptance Race Condition Fix
-- Description:
--   Fixes a critical physical-world concurrency vulnerability where two delivery 
--   partners accepting the same order at the exact same millisecond would both 
--   receive a success response, leading to multiple riders arriving at the shop.
--   Uses GET DIAGNOSTICS ROW_COUNT to ensure only the rider who actually updated 
--   the row succeeds.
-- =============================================================================

CREATE OR REPLACE FUNCTION accept_order_rider(
  p_order_id UUID, 
  p_rider_phone text DEFAULT NULL, 
  p_shop_lat numeric DEFAULT NULL, 
  p_shop_lng numeric DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
  v_seller_accepted boolean;
  v_payment_status text;
  v_payment_deadline timestamptz;
  v_order_ready_time timestamptz;
  v_new_status text;
  v_rows_affected INT;
BEGIN
  -- Strict row locking
  SELECT status, seller_accepted, payment_status, payment_deadline, order_ready_time 
  INTO v_status, v_seller_accepted, v_payment_status, v_payment_deadline, v_order_ready_time 
  FROM orders WHERE id = p_order_id FOR UPDATE;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;
  
  -- Graceful cancellation check
  IF v_status = 'cancelled' THEN
    RAISE EXCEPTION 'ORDER_CANCELLED';
  END IF;

  IF v_status NOT IN ('awaiting_acceptance', 'pending') THEN
    RAISE EXCEPTION 'Invalid state transition from %', v_status;
  END IF;

  -- State Transition Logic
  IF v_seller_accepted = true THEN
    IF v_payment_status = 'captured' THEN
      IF v_order_ready_time IS NOT NULL THEN
        v_new_status := 'ready_for_pickup';
      ELSE
        v_new_status := 'preparing';
      END IF;
    ELSE
      v_new_status := 'awaiting_payment';
    END IF;
  ELSE
    v_new_status := v_status;
  END IF;

  -- 100x BUG FIX: Strict Concurrency Update
  UPDATE orders
  SET 
    partner_accepted = true,
    delivery_partner_id = auth.uid(),
    status = v_new_status,
    payment_deadline = CASE WHEN v_seller_accepted = true AND v_payment_status != 'captured' THEN (now() AT TIME ZONE 'utc') + interval '10 minutes' ELSE v_payment_deadline END,
    rider_phone = COALESCE(p_rider_phone, rider_phone),
    shop_lat = COALESCE(p_shop_lat, shop_lat),
    shop_lng = COALESCE(p_shop_lng, shop_lng)
  WHERE id = p_order_id AND (delivery_partner_id IS NULL OR delivery_partner_id = auth.uid());

  -- 100x BUG FIX: Verify the update actually applied to the row
  GET DIAGNOSTICS v_rows_affected = ROW_COUNT;
  IF v_rows_affected = 0 THEN
    -- Another rider claimed the order milliseconds before this transaction reached the UPDATE statement
    RAISE EXCEPTION 'ORDER_ACCEPTED_BY_OTHER_RIDER';
  END IF;

  RETURN v_seller_accepted;
END;
$$;

GRANT EXECUTE ON FUNCTION accept_order_rider(UUID, text, numeric, numeric) TO authenticated;
