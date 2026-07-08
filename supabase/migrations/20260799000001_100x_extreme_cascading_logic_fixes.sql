-- =============================================================================
-- Migration: 100x Extreme Cascading Logic Fixes
-- Description:
--   Following a stress-test architecture review, this addresses 3 critical 
--   cascading logic failures and extreme edge cases:
--   1. Infinite Payment Extension Exploit: A rider could rapidly re-call 
--      accept_order_rider on an already accepted order, causing the 
--      payment_deadline to extend indefinitely by 10 minutes each time.
--      Fixed by strictly enforcing idempotency via delivery_partner_id check.
--   2. Deadlock Vulnerability: The previous pg_advisory_xact_lock was 
--      acquired AFTER row-level 'FOR UPDATE' locks. If logic ever expanded
--      to multi-row locks, lock inversion deadlocks could occur. Fixed by
--      hoisting the advisory lock to the absolute top of the transaction.
--   3. TOCTOU on delivery_partner_id: The UPDATE statement relied on a 
--      WHERE clause check for delivery_partner_id IS NULL. By checking this 
--      explicitly under the FOR UPDATE lock in memory, we prevent useless 
--      writes and immediately halt invalid state transitions gracefully.
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
  v_delivery_partner_id UUID;
  v_new_status text;
  v_rows_affected INT;
  v_cart_group_id UUID;
  v_active_cart_groups_count INT;
BEGIN
  -- ==========================================================================
  -- 100x ARCHITECTURE FIX: Lock Ordering & Deadlock Prevention
  -- ==========================================================================
  -- Hoisted to the very top. Always acquire broader, transaction-level 
  -- advisory locks BEFORE granular row-level FOR UPDATE locks. This entirely
  -- eliminates any possibility of lock-inversion deadlocks.
  PERFORM pg_advisory_xact_lock(hashtext('rider_accept_' || auth.uid()::text));

  -- Strict row locking & fetch state
  SELECT status, seller_accepted, payment_status, payment_deadline, order_ready_time, cart_group_id, delivery_partner_id
  INTO v_status, v_seller_accepted, v_payment_status, v_payment_deadline, v_order_ready_time, v_cart_group_id, v_delivery_partner_id
  FROM orders WHERE id = p_order_id FOR UPDATE;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;
  
  -- Graceful cancellation check
  IF v_status = 'cancelled' THEN
    RAISE EXCEPTION 'ORDER_CANCELLED';
  END IF;

  -- ==========================================================================
  -- 100x ARCHITECTURE FIX: Infinite Payment Extension & Idempotency Exploit
  -- ==========================================================================
  -- If the rider already owns the order, silently return success.
  -- This prevents malicious actors from repeatedly hitting the endpoint to
  -- trigger the `interval '10 minutes'` payment deadline extension over and over.
  IF v_delivery_partner_id IS NOT NULL THEN
    IF v_delivery_partner_id = auth.uid() THEN
      RETURN v_seller_accepted; -- Safely idempotent
    ELSE
      RAISE EXCEPTION 'ORDER_ACCEPTED_BY_OTHER_RIDER';
    END IF;
  END IF;

  IF v_status NOT IN ('awaiting_acceptance', 'pending') THEN
    RAISE EXCEPTION 'Invalid state transition from %', v_status;
  END IF;

  -- ==========================================================================
  -- Hoarding Check (Preserving the NULL fix)
  -- ==========================================================================
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

  -- Strict Concurrency Update (Simplified WHERE clause since we verified delivery_partner_id above)
  UPDATE orders
  SET 
    partner_accepted = true,
    delivery_partner_id = auth.uid(),
    status = v_new_status,
    payment_deadline = CASE WHEN v_seller_accepted = true AND v_payment_status != 'captured' THEN (now() AT TIME ZONE 'utc') + interval '10 minutes' ELSE v_payment_deadline END,
    rider_phone = COALESCE(p_rider_phone, rider_phone),
    shop_lat = COALESCE(p_shop_lat, shop_lat),
    shop_lng = COALESCE(p_shop_lng, shop_lng)
  WHERE id = p_order_id;

  RETURN v_seller_accepted;
END;
$$;

GRANT EXECUTE ON FUNCTION accept_order_rider(UUID, text, numeric, numeric) TO authenticated;
