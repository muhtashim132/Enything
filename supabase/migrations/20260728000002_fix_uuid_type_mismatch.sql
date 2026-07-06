-- =============================================================================
-- Migration: Fix UUID Type Mismatch & Deadlocks in Dashboard RPCs
-- Description: 
-- 1. Fixes `operator does not exist: uuid = text` in cancel_order & retry_find_rider.
-- 2. Refactors group locking to ORDER BY id to completely eliminate deadlocks.
-- =============================================================================

-- 1. Fix cancel_order
CREATE OR REPLACE FUNCTION cancel_order(p_order_id UUID, p_reason text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer_id uuid;
  v_cart_group_id uuid;
  v_rec record;
  v_is_customer boolean;
BEGIN
  -- First find group ID without locking to avoid partial lock deadlocks
  SELECT customer_id, cart_group_id INTO v_customer_id, v_cart_group_id
  FROM orders WHERE id = p_order_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  v_is_customer := (auth.uid() = v_customer_id);

  IF v_cart_group_id IS NOT NULL THEN
    -- Lock all orders in group consistently ordered by ID
    FOR v_rec IN SELECT id, status, payment_status FROM orders WHERE cart_group_id = v_cart_group_id ORDER BY id FOR UPDATE LOOP
      IF v_is_customer AND v_rec.status NOT IN ('awaiting_acceptance', 'awaiting_payment') THEN
        -- If ANY order in the group has moved past payment, the customer cannot cancel the group
        RAISE EXCEPTION 'Order cannot be cancelled at this stage by customer';
      END IF;
      
      IF v_rec.status IN ('awaiting_acceptance', 'awaiting_payment', 'pending') THEN
        UPDATE orders
        SET 
          status = 'cancelled',
          cancelled_reason = p_reason,
          refund_status = CASE WHEN v_rec.payment_status = 'captured' THEN 'processing' ELSE refund_status END
        WHERE id = v_rec.id;
      END IF;
    END LOOP;
  ELSE
    -- Single order lock
    FOR v_rec IN SELECT id, status, payment_status FROM orders WHERE id = p_order_id FOR UPDATE LOOP
      IF v_is_customer AND v_rec.status NOT IN ('awaiting_acceptance', 'awaiting_payment') THEN
        RAISE EXCEPTION 'Order cannot be cancelled at this stage by customer';
      END IF;

      IF v_rec.status IN ('awaiting_acceptance', 'awaiting_payment', 'pending') THEN
        UPDATE orders
        SET 
          status = 'cancelled',
          cancelled_reason = p_reason,
          refund_status = CASE WHEN v_rec.payment_status = 'captured' THEN 'processing' ELSE refund_status END
        WHERE id = v_rec.id;
      END IF;
    END LOOP;
  END IF;
END;
$$;

-- 2. Fix retry_find_rider
CREATE OR REPLACE FUNCTION retry_find_rider(p_order_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer_id uuid;
  v_cart_group_id uuid;
  v_rec record;
BEGIN
  -- First, get the group ID without locking
  SELECT customer_id, cart_group_id INTO v_customer_id, v_cart_group_id 
  FROM orders WHERE id = p_order_id;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF v_customer_id != auth.uid() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;
  
  -- If it's a group, lock ALL orders in the group ordered by ID
  IF v_cart_group_id IS NOT NULL THEN
    FOR v_rec IN SELECT id, status, partner_accepted FROM orders WHERE cart_group_id = v_cart_group_id ORDER BY id FOR UPDATE LOOP
      IF v_rec.status NOT IN ('pending', 'awaiting_acceptance') THEN
        RAISE EXCEPTION 'Cannot retry finding rider from status %', v_rec.status;
      END IF;
      IF v_rec.partner_accepted = true THEN
        RAISE EXCEPTION 'Rider has already accepted, cannot retry';
      END IF;
    END LOOP;
    
    -- Clear assignment for the whole group
    UPDATE orders
    SET 
      status = 'awaiting_acceptance',
      cancelled_reason = null,
      partner_accepted = false,
      delivery_partner_id = null,
      rider_phone = null,
      rider_lat = null,
      rider_lng = null,
      acceptance_deadline = (now() AT TIME ZONE 'utc') + interval '3 minutes'
    WHERE cart_group_id = v_cart_group_id;
  ELSE
    FOR v_rec IN SELECT id, status, partner_accepted FROM orders WHERE id = p_order_id FOR UPDATE LOOP
      IF v_rec.status NOT IN ('pending', 'awaiting_acceptance') THEN
        RAISE EXCEPTION 'Cannot retry finding rider from status %', v_rec.status;
      END IF;
      IF v_rec.partner_accepted = true THEN
        RAISE EXCEPTION 'Rider has already accepted, cannot retry';
      END IF;
      
      UPDATE orders
      SET 
        status = 'awaiting_acceptance',
        cancelled_reason = null,
        partner_accepted = false,
        delivery_partner_id = null,
        rider_phone = null,
        rider_lat = null,
        rider_lng = null,
        acceptance_deadline = (now() AT TIME ZONE 'utc') + interval '3 minutes'
      WHERE id = p_order_id;
    END LOOP;
  END IF;
END;
$$;
