-- =============================================================================
-- Migration 20290000000129: 100x Rider Cart Group Atomic Assignment & GPS Fix
-- Description:
--   1. Restores the atomic cart group assignment loop in accept_order_rider
--      so accepting any order in a multi-shop cart assigns ALL sibling orders
--      in that cart group atomically, while strictly preserving Migration 124's
--      security guards (admin suspension check, verification status guard,
--      string bloat protection, transaction advisory lock, and max 3 cart groups limit).
--   2. Fortifies set_arrived_at_shop with automatic cross-group shared shop
--      arrival cascade: when a rider arrives at a shop for one order, all active
--      orders assigned to that rider from the same shop are marked arrived,
--      preventing the 300m geofence lockout trap.
-- =============================================================================

-- 1. accept_order_rider(UUID, text, numeric, numeric)
CREATE OR REPLACE FUNCTION public.accept_order_rider(
  p_order_id UUID,
  p_rider_phone text DEFAULT '',
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
  v_delivery_partner_id uuid;
  v_active_cart_groups_count INT;
  v_cart_group_id UUID;
  v_order_record RECORD;
  v_resolved_shop_lat numeric;
  v_resolved_shop_lng numeric;
  v_return_seller_accepted boolean := false;
BEGIN
  -- String Bloat Protection (from Migration 124)
  IF length(p_rider_phone) > 20 THEN
    RAISE EXCEPTION 'Rider phone string too long (Max 20 chars)';
  END IF;

  -- Admin Suspension & Verification Guard for Delivery Partners (from Migration 124)
  IF EXISTS (
    SELECT 1 FROM delivery_partners 
    WHERE id = auth.uid() 
      AND (is_active = false OR (verification_status IS NOT NULL AND verification_status NOT IN ('verified', 'approved')))
  ) THEN
    RAISE EXCEPTION 'RIDER_SUSPENDED: Your delivery partner account is currently suspended or unverified.';
  END IF;

  -- Transaction-level Advisory Lock for Rider Concurrency (from Migration 124)
  PERFORM pg_advisory_xact_lock(hashtext('rider_acceptance_' || COALESCE(auth.uid()::text, 'system_admin')));

  -- Strict row locking & fetch initial order metadata
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

  -- Race condition check: already accepted by another rider
  IF v_delivery_partner_id IS NOT NULL AND v_delivery_partner_id != auth.uid() THEN
    RAISE EXCEPTION 'ORDER_ACCEPTED_BY_OTHER_RIDER';
  END IF;

  IF v_status NOT IN ('awaiting_acceptance', 'pending') THEN
    RAISE EXCEPTION 'Invalid state transition from %', v_status;
  END IF;

  -- Advisory lock on cart group scope
  PERFORM pg_advisory_xact_lock(hashtext('cart_group_accept_' || COALESCE(v_cart_group_id, p_order_id)::text));

  -- Enforce Max 3 Active Cart Groups Hoarding Limit
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

  -- Atomic Cart Group Assignment Loop (restoring and hardening Migration 59 loop)
  FOR v_order_record IN 
    SELECT o.id, o.status, o.seller_accepted, o.payment_status, o.payment_deadline, o.order_ready_time, o.delivery_partner_id, o.shop_id, o.shop_lat, o.shop_lng, o.rider_phone
    FROM orders o
    WHERE COALESCE(o.cart_group_id, o.id) = COALESCE(v_cart_group_id, p_order_id)
      AND o.status NOT IN ('cancelled', 'delivered', 'returned', 'refunded', 'seller_rejected', 'partner_rejected', 'shop_dispute_cancel', 'timeout', 'failed')
    ORDER BY o.id
    FOR UPDATE
  LOOP
    -- Double-check assignment under lock for sibling sub-orders
    IF v_order_record.delivery_partner_id IS NOT NULL AND v_order_record.delivery_partner_id != auth.uid() THEN
      RAISE EXCEPTION 'ORDER_ACCEPTED_BY_OTHER_RIDER';
    END IF;

    -- Compute state transition for this sibling order
    IF v_order_record.seller_accepted = true THEN
      IF v_order_record.payment_status = 'captured' THEN
        IF v_order_record.order_ready_time IS NOT NULL THEN
          v_new_status := 'ready_for_pickup';
        ELSE
          v_new_status := 'preparing';
        END IF;
      ELSE
        v_new_status := 'awaiting_payment';
      END IF;
    ELSE
      v_new_status := v_order_record.status;
    END IF;

    -- Resolve shop coordinates
    IF v_order_record.id = p_order_id AND p_shop_lat IS NOT NULL AND p_shop_lat != 0 THEN
      v_resolved_shop_lat := p_shop_lat;
      v_resolved_shop_lng := p_shop_lng;
    ELSIF v_order_record.shop_lat IS NOT NULL AND v_order_record.shop_lat != 0 THEN
      v_resolved_shop_lat := v_order_record.shop_lat;
      v_resolved_shop_lng := v_order_record.shop_lng;
    ELSE
      SELECT ST_Y(location::geometry), ST_X(location::geometry)
      INTO v_resolved_shop_lat, v_resolved_shop_lng
      FROM shops WHERE id = v_order_record.shop_id;
    END IF;

    UPDATE orders
    SET 
      partner_accepted = true,
      delivery_partner_id = auth.uid(),
      status = v_new_status,
      payment_deadline = CASE WHEN v_order_record.seller_accepted = true AND v_order_record.payment_status != 'captured' THEN (now() AT TIME ZONE 'utc') + interval '10 minutes' ELSE v_order_record.payment_deadline END,
      rider_phone = COALESCE(NULLIF(p_rider_phone, ''), v_order_record.rider_phone),
      shop_lat = COALESCE(v_resolved_shop_lat, v_order_record.shop_lat),
      shop_lng = COALESCE(v_resolved_shop_lng, v_order_record.shop_lng),
      updated_at = NOW()
    WHERE id = v_order_record.id;

    IF v_order_record.id = p_order_id THEN
      v_return_seller_accepted := COALESCE(v_order_record.seller_accepted, false);
    END IF;
  END LOOP;

  RETURN v_return_seller_accepted;
END;
$$;

GRANT EXECUTE ON FUNCTION public.accept_order_rider(UUID, text, numeric, numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.accept_order_rider(UUID, text, numeric, numeric) TO service_role;

-- Overload: 1-parameter version for backward compatibility
CREATE OR REPLACE FUNCTION public.accept_order_rider(p_order_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM accept_order_rider(p_order_id, '', NULL, NULL);
END;
$$;

GRANT EXECUTE ON FUNCTION public.accept_order_rider(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.accept_order_rider(UUID) TO service_role;


-- =============================================================================
-- 2. set_arrived_at_shop: Fortified with Cross-Group Shared Shop Cascade
-- =============================================================================
CREATE OR REPLACE FUNCTION public.set_arrived_at_shop(
  p_order_id UUID, 
  p_rider_lat numeric DEFAULT NULL, 
  p_rider_lng numeric DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
  v_shop_lat numeric;
  v_shop_lng numeric;
  v_distance double precision;
  v_arrived_at timestamptz;
  v_delivery_partner_id uuid;
  v_shop_id uuid;
BEGIN
  -- Strict row locking
  SELECT status, arrived_at_shop_time, delivery_partner_id, shop_lat, shop_lng, shop_id
  INTO v_status, v_arrived_at, v_delivery_partner_id, v_shop_lat, v_shop_lng, v_shop_id
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF v_delivery_partner_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'UNAUTHORIZED: You are not assigned to this order.';
  END IF;

  -- Idempotent check
  IF v_arrived_at IS NOT NULL THEN
    RETURN;
  END IF;

  -- Allow early arrival while status is 'confirmed', 'preparing', or 'ready_for_pickup'
  IF v_status NOT IN ('confirmed', 'preparing', 'ready_for_pickup') THEN
    RAISE EXCEPTION 'INVALID_STATE: Cannot mark arrived when order status is %.', v_status;
  END IF;

  -- Fallback to shop master table coordinates if orders table coords are null
  IF (v_shop_lat IS NULL OR v_shop_lat = 0 OR v_shop_lng IS NULL OR v_shop_lng = 0) AND v_shop_id IS NOT NULL THEN
    SELECT ST_Y(location::geometry), ST_X(location::geometry)
    INTO v_shop_lat, v_shop_lng
    FROM shops WHERE id = v_shop_id;
  END IF;

  IF p_rider_lat IS NOT NULL AND p_rider_lng IS NOT NULL AND v_shop_lat IS NOT NULL AND v_shop_lng IS NOT NULL THEN
    v_distance := 6371000 * 2 * ASIN(LEAST(1.0::double precision, SQRT(GREATEST(0.0::double precision, 
        POWER(SIN((p_rider_lat - v_shop_lat) * pi()/180 / 2), 2) +
        COS(v_shop_lat * pi()/180) * COS(p_rider_lat * pi()/180) *
        POWER(SIN((p_rider_lng - v_shop_lng) * pi()/180 / 2), 2)
    ))));
    IF v_distance > 300 THEN
      RAISE EXCEPTION 'GEO_FENCE_FAILED: You are % meters away from the shop. Max allowed is 300m.', v_distance::int;
    END IF;
  ELSE
    IF v_shop_lat IS NOT NULL AND v_shop_lng IS NOT NULL THEN
      RAISE EXCEPTION 'GEO_FENCE_FAILED: Rider GPS coordinates are required to mark arrival.';
    END IF;
  END IF;

  -- Update target order AND cascade arrival to any other active order assigned to this
  -- rider at the same physical shop, avoiding the 300m geofence lockout trap.
  UPDATE orders
  SET 
    arrived_at_shop_time = NOW(),
    updated_at = NOW()
  WHERE (
    id = p_order_id 
    OR (
      delivery_partner_id = auth.uid() 
      AND shop_id = v_shop_id 
      AND arrived_at_shop_time IS NULL 
      AND status IN ('confirmed', 'preparing', 'ready_for_pickup')
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_arrived_at_shop(UUID, numeric, numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_arrived_at_shop(UUID, numeric, numeric) TO service_role;
