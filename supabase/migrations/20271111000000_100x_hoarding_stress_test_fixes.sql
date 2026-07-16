-- =============================================================================
-- Migration: 100x Extreme Edge Case Hoarding Fixes
-- Description:
--   1. Addresses a critical API concurrency vulnerability by wrapping rider acceptance
--      in a transaction-level advisory lock, completely preventing spam-based bypasses
--      of the MAX_ORDERS_REACHED threshold.
--   2. Includes 'timeout', 'verification_failed', 'no_rider', 'shop_dispute_cancel', 
--      and 'payment_failed' in the non-terminal exclusion list to prevent permanent
--      bricking of rider slots.
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
  v_active_cart_groups_count INT;
  v_cart_group_id UUID;
BEGIN
  -- 100x ARCHITECTURE FIX: Transaction-level Advisory Lock
  -- This physically serializes concurrent API spam from the same rider. 
  -- If 10 requests hit at the same millisecond, they are queued and evaluated sequentially,
  -- ensuring the COUNT(DISTINCT) check is always perfectly accurate.
  PERFORM pg_advisory_xact_lock(hashtext('rider_acceptance_' || auth.uid()::text));

  -- Strict row locking & fetch cart_group_id
  SELECT status, seller_accepted, payment_status, payment_deadline, order_ready_time, cart_group_id
  INTO v_status, v_seller_accepted, v_payment_status, v_payment_deadline, v_order_ready_time, v_cart_group_id
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

  -- 100x FIX: Hoarding Prevention Check
  -- Check active orders EXCLUDING all terminal/failed states to prevent slot bricking
  SELECT COUNT(DISTINCT cart_group_id) INTO v_active_cart_groups_count
  FROM orders
  WHERE delivery_partner_id = auth.uid()
    AND status NOT IN (
      'delivered', 
      'cancelled', 
      'seller_rejected', 
      'partner_rejected', 
      'returned', 
      'refunded', 
      'failed',
      'payment_failed',
      'timeout',
      'verification_failed',
      'no_rider',
      'shop_dispute_cancel'
    )
    AND cart_group_id IS DISTINCT FROM v_cart_group_id;

  IF v_active_cart_groups_count >= 3 THEN
    RAISE EXCEPTION 'MAX_ORDERS_REACHED: You can only accept orders from up to 3 different customers at a time.';
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
