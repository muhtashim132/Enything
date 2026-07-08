-- =============================================================================
-- Migration: 100x Rider Hoarding Stress Test Fix
-- Description:
--   Addresses two extreme architecture edge cases in rider order acceptance:
--   1. TOCTOU Race Condition: Concurrent acceptance calls bypassed the 
--      COUNT() check. Fixed via pg_advisory_xact_lock on rider's auth.uid().
--   2. NULL cart_group_id Bypass: Orders with NULL cart_group_id evaded
--      the COUNT(DISTINCT) check, allowing infinite hoarding. Fixed by 
--      using COALESCE(cart_group_id, id).
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
  v_cart_group_id UUID;
  v_active_cart_groups_count INT;
BEGIN
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

  -- ==========================================================================
  -- 100x STRESS TEST FIX: Concurrency Serialization
  -- ==========================================================================
  -- Acquire an exclusive transaction-level advisory lock on the rider's ID.
  -- This forces concurrent accept_order_rider calls by the SAME rider to 
  -- execute sequentially, completely eliminating TOCTOU hoarding bypasses.
  PERFORM pg_advisory_xact_lock(hashtext('rider_accept_' || auth.uid()::text));

  -- ==========================================================================
  -- 100x STRESS TEST FIX: NULL cart_group_id vulnerability & Hoarding Check
  -- ==========================================================================
  -- Allow the rider to accept orders from up to 3 different customers at a time.
  -- We use COALESCE(cart_group_id, id) to ensure that legacy or single-item 
  -- orders without a cart group are correctly treated as distinct groups.
  SELECT COUNT(DISTINCT COALESCE(cart_group_id, id)) INTO v_active_cart_groups_count
  FROM orders
  WHERE delivery_partner_id = auth.uid()
    AND status NOT IN ('delivered', 'cancelled', 'seller_rejected', 'partner_rejected', 'returned', 'refunded', 'failed')
    AND COALESCE(cart_group_id, id) IS DISTINCT FROM COALESCE(v_cart_group_id, p_order_id);

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

  -- Strict Concurrency Update
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

  -- Verify the update actually applied to the row
  GET DIAGNOSTICS v_rows_affected = ROW_COUNT;
  IF v_rows_affected = 0 THEN
    -- Another rider claimed the order milliseconds before this transaction reached the UPDATE statement
    RAISE EXCEPTION 'ORDER_ACCEPTED_BY_OTHER_RIDER';
  END IF;

  RETURN v_seller_accepted;
END;
$$;

GRANT EXECUTE ON FUNCTION accept_order_rider(UUID, text, numeric, numeric) TO authenticated;
