-- =============================================================================
-- Migration: Customer Dashboard Process Fixes
-- Description: 
-- 1. Fixes double coupon decrement on cancellation of multi-shop orders.
-- 2. Fixes concurrency lock in `retry_find_rider` to lock the whole cart group.
-- =============================================================================

-- 1. Fix Coupon Restoration Trigger
CREATE OR REPLACE FUNCTION restore_coupon_usage_on_cancel()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_first_order_id uuid;
BEGIN
  -- Only restore coupon when transitioning INTO a cancelled state
  IF NEW.status IN ('cancelled', 'seller_rejected', 'verification_failed', 'no_rider')
     AND OLD.status NOT IN ('cancelled', 'seller_rejected', 'verification_failed', 'no_rider') THEN

    IF NEW.coupon_id IS NOT NULL THEN
      IF NEW.cart_group_id IS NOT NULL THEN
        -- Only restore if this is the first order in the group to avoid multi-decrement
        SELECT id INTO v_first_order_id 
        FROM orders 
        WHERE cart_group_id = NEW.cart_group_id 
        ORDER BY created_at ASC, id ASC 
        LIMIT 1;
        
        IF NEW.id = v_first_order_id THEN
          UPDATE coupons
          SET used_count = GREATEST(used_count - 1, 0)
          WHERE id = NEW.coupon_id;
        END IF;
      ELSE
        UPDATE coupons
        SET used_count = GREATEST(used_count - 1, 0)
        WHERE id = NEW.coupon_id;
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- 2. Fix retry_find_rider Concurrency Lock
CREATE OR REPLACE FUNCTION retry_find_rider(p_order_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer_id uuid;
  v_status text;
  v_partner_accepted boolean;
  v_cart_group_id text;
  v_rec record;
BEGIN
  -- First, get the group ID
  SELECT cart_group_id INTO v_cart_group_id FROM orders WHERE id = p_order_id;
  
  -- If it's a group, lock ALL orders in the group to prevent partial acceptance races
  IF v_cart_group_id IS NOT NULL THEN
    -- Lock and verify
    FOR v_rec IN SELECT id, customer_id, status, partner_accepted FROM orders WHERE cart_group_id = v_cart_group_id FOR UPDATE LOOP
      IF v_rec.customer_id != auth.uid() THEN
        RAISE EXCEPTION 'Unauthorized';
      END IF;
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
    WHERE cart_group_id = v_cart_group_id AND partner_accepted = false;
  ELSE
    SELECT customer_id, status, partner_accepted INTO v_customer_id, v_status, v_partner_accepted
    FROM orders WHERE id = p_order_id FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Order not found';
    END IF;

    IF v_customer_id != auth.uid() THEN
      RAISE EXCEPTION 'Unauthorized';
    END IF;

    IF v_status NOT IN ('pending', 'awaiting_acceptance') THEN
      RAISE EXCEPTION 'Cannot retry finding rider from status %', v_status;
    END IF;
    
    IF v_partner_accepted = true THEN
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
    WHERE id = p_order_id AND partner_accepted = false;
  END IF;
END;
$$;
