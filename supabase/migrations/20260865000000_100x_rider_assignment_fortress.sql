-- =============================================================================
-- Migration: 100x Rider Assignment Fortress (Phase 12)
-- Description:
--   1. Fixes a Catastrophic Cart-Tearing Exploit (Cascading Assignment Failure)
--      where riders were only assigned to a single fraction of a multi-shop cart,
--      leaving the rest of the cart floating, causing severe rider wage theft,
--      platform financial breakage, and ruined customer UX.
--   2. Enforces strict Atomic Cart Group Assignment, instantly binding the rider
--      to all un-cancelled shops in the cart group simultaneously, while gracefully
--      evaluating the independent state machine rules for each individual shop.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.accept_order_rider(
  p_order_id UUID, 
  p_rider_phone text DEFAULT NULL, 
  p_shop_lat numeric DEFAULT NULL, 
  p_shop_lng numeric DEFAULT NULL
)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  -- 100x ARCHITECTURE FIX: Transaction-level Advisory Lock with COALESCE NULL Protection
  PERFORM pg_advisory_xact_lock(hashtext('rider_acceptance_' || COALESCE(auth.uid()::text, 'system_admin')));

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

  -- 100x FIX: The Ultimate Null Pointer Cascading Fix
  -- Reinstating COALESCE(cart_group_id, id) so NULL cart groups are strictly counted
  SELECT COUNT(DISTINCT COALESCE(cart_group_id, id)) INTO v_active_cart_groups_count
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
    AND COALESCE(cart_group_id, id) IS DISTINCT FROM COALESCE(v_cart_group_id, p_order_id);

  IF v_active_cart_groups_count >= 3 THEN
    RAISE EXCEPTION 'MAX_ORDERS_REACHED: You can only accept orders from up to 3 different customers at a time.';
  END IF;

  -- State Transition Logic (Fallback for single order)
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

  -- 100x STRESS TEST FIX (Phase 12): Atomic Cart Group Assignment
  IF v_cart_group_id IS NOT NULL THEN
    UPDATE orders
    SET 
      partner_accepted = true,
      delivery_partner_id = auth.uid(),
      status = CASE 
                 WHEN seller_accepted = true THEN 
                   CASE 
                     WHEN payment_status = 'captured' THEN 
                       CASE 
                         WHEN order_ready_time IS NOT NULL THEN 'ready_for_pickup' 
                         ELSE 'preparing' 
                       END
                     ELSE 'awaiting_payment' 
                   END
                 ELSE status 
               END,
      payment_deadline = CASE WHEN seller_accepted = true AND payment_status != 'captured' THEN (now() AT TIME ZONE 'utc') + interval '10 minutes' ELSE payment_deadline END,
      rider_phone = COALESCE(p_rider_phone, rider_phone),
      shop_lat = CASE WHEN id = p_order_id THEN COALESCE(p_shop_lat, shop_lat) ELSE shop_lat END,
      shop_lng = CASE WHEN id = p_order_id THEN COALESCE(p_shop_lng, shop_lng) ELSE shop_lng END
    WHERE cart_group_id = v_cart_group_id AND (delivery_partner_id IS NULL OR delivery_partner_id = auth.uid())
      AND status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected', 'timeout', 'verification_failed', 'shop_dispute_cancel', 'no_rider');
  ELSE
    -- Single Order Logic
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
  END IF;

  GET DIAGNOSTICS v_rows_affected = ROW_COUNT;
  IF v_rows_affected = 0 THEN
    RAISE EXCEPTION 'ORDER_ACCEPTED_BY_OTHER_RIDER';
  END IF;

  RETURN v_seller_accepted;
END;
$function$;
