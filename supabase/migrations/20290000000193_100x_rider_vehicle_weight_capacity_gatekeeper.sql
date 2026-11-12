-- ============================================================================
-- 20290000000193_100x_rider_vehicle_weight_capacity_gatekeeper.sql
-- 100x RIDER VEHICLE WEIGHT CAPACITY GATEKEEPER & PHANTOM CONTACT SHIELD
--
-- ARCHITECTURAL GOALS:
--   1. Enforce Two-Wheeler Vehicle Payload Ceiling (20.0 kg max per CMVR Rule 123)
--      across up to 3 distinct customer cart groups.
--   2. Dual-Constraint Engine:
--      Constraint A (Slots):  |ActiveCartGroups| <= 3
--      Constraint B (Weight): W_committed + W_incoming <= W_max (default 20.0 kg)
--   3. Concurrency Protection: Level 1 Advisory Lock on rider ID
--      PERFORM pg_advisory_xact_lock(hashtext('rider_acceptance_' || auth.uid()::text));
--   4. Weight Exemption on Intermediate Hand-off: Delivered orders physically offload
--      cargo, expanding remaining capacity for onwards pickups.
--   5. Phantom Contact Shield: reject_order_rider guarantees rider_phone = NULL,
--      preventing orphaned 'Call Rider' buttons on customer tracking maps.
-- ============================================================================

-- ── 1. Fortify accept_order_rider with Weight Capacity Gatekeeper ─────────────
CREATE OR REPLACE FUNCTION public.accept_order_rider(
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
  v_all_shops_accepted boolean := true;
  v_current_committed_weight NUMERIC := 0.0;
  v_incoming_order_weight NUMERIC := 0.0;
  v_max_vehicle_payload NUMERIC := 20.0;
BEGIN
  IF length(p_rider_phone) > 20 THEN
    RAISE EXCEPTION 'Rider phone string too long (Max 20 chars)';
  END IF;

  -- Delivery partner active & verification check
  IF EXISTS (
    SELECT 1 FROM delivery_partners 
    WHERE id = auth.uid() 
      AND (is_active = false OR (verification_status IS NOT NULL AND verification_status NOT IN ('verified', 'approved')))
  ) THEN
    RAISE EXCEPTION 'RIDER_SUSPENDED: Your delivery partner account is currently suspended or unverified.';
  END IF;

  -- 1. Level 1 Transaction Advisory Lock on rider acceptance to serialize concurrent accepts
  PERFORM pg_advisory_xact_lock(hashtext('rider_acceptance_' || COALESCE(auth.uid()::text, 'system_admin')));

  -- 2. Cart Group Advisory Lock and row locking
  SELECT cart_group_id INTO v_cart_group_id FROM orders WHERE id = p_order_id;
  IF v_cart_group_id IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(hashtext('cart_group_' || v_cart_group_id::text));
    PERFORM id FROM orders WHERE cart_group_id = v_cart_group_id ORDER BY id FOR UPDATE;
  END IF;

  SELECT status, seller_accepted, payment_status, payment_deadline, order_ready_time, cart_group_id
  INTO v_status, v_seller_accepted, v_payment_status, v_payment_deadline, v_order_ready_time, v_cart_group_id
  FROM orders WHERE id = p_order_id FOR UPDATE;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;
  
  IF v_status = 'cancelled' THEN
    RAISE EXCEPTION 'ORDER_CANCELLED';
  END IF;

  -- 3. Slot Capacity Ceiling Check (max 3 distinct customer cart groups)
  SELECT COUNT(DISTINCT COALESCE(cart_group_id, id)) INTO v_active_cart_groups_count
  FROM orders
  WHERE delivery_partner_id = auth.uid()
    AND status NOT IN (
      'delivered', 'cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected',
      'returned', 'refunded', 'failed', 'payment_failed', 'timeout', 
      'verification_failed', 'no_rider', 'shop_dispute_cancel'
    )
    AND COALESCE(cart_group_id, id) IS DISTINCT FROM COALESCE(v_cart_group_id, p_order_id);

  IF v_active_cart_groups_count >= 3 AND NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'MAX_ORDERS_REACHED: You can only accept orders from up to 3 different customers at a time.';
  END IF;

  -- 4. Weight Capacity Ceiling Check (max 20.0 kg payload on two-wheeler)
  -- Lookup platform configuration or default to 20.0 kg
  SELECT COALESCE((value->>'max_rider_payload_kg')::numeric, 20.0)
  INTO v_max_vehicle_payload
  FROM public.platform_config
  WHERE key = 'delivery_settings';
  IF v_max_vehicle_payload IS NULL OR v_max_vehicle_payload <= 0 THEN
    v_max_vehicle_payload := 20.0;
  END IF;

  -- Compute current committed physical weight across all active in-flight orders held by this rider
  -- Notice: Excludes 'delivered' because weight is physically offloaded at customer doorstep
  SELECT COALESCE(SUM(
    COALESCE(
      CASE 
        WHEN jsonb_typeof(i->'weight_kg') = 'number' THEN (i->>'weight_kg')::numeric
        ELSE 0.25
      END, 0.25
    ) * COALESCE(
      CASE 
        WHEN jsonb_typeof(i->'quantity') = 'number' THEN (i->>'quantity')::numeric
        ELSE 1
      END, 1
    )
  ), 0.0)
  INTO v_current_committed_weight
  FROM orders o,
  LATERAL jsonb_array_elements(
    CASE 
      WHEN jsonb_typeof(o.items) = 'array' THEN o.items 
      ELSE '[]'::jsonb 
    END
  ) i
  WHERE o.delivery_partner_id = auth.uid()
    AND o.status IN ('awaiting_payment', 'confirmed', 'preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery')
    AND o.status != 'delivered'
    AND COALESCE(o.cart_group_id, o.id) IS DISTINCT FROM COALESCE(v_cart_group_id, p_order_id);

  -- Compute incoming physical weight of the new order / cart group
  SELECT COALESCE(SUM(
    COALESCE(
      CASE 
        WHEN jsonb_typeof(i->'weight_kg') = 'number' THEN (i->>'weight_kg')::numeric
        ELSE 0.25
      END, 0.25
    ) * COALESCE(
      CASE 
        WHEN jsonb_typeof(i->'quantity') = 'number' THEN (i->>'quantity')::numeric
        ELSE 1
      END, 1
    )
  ), 0.5)
  INTO v_incoming_order_weight
  FROM orders o,
  LATERAL jsonb_array_elements(
    CASE 
      WHEN jsonb_typeof(o.items) = 'array' THEN o.items 
      ELSE '[]'::jsonb 
    END
  ) i
  WHERE (
    (v_cart_group_id IS NOT NULL AND o.cart_group_id = v_cart_group_id)
    OR (v_cart_group_id IS NULL AND o.id = p_order_id)
  )
  AND o.status NOT IN (
    'delivered', 'cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected',
    'verification_failed', 'shop_dispute_cancel', 'timeout', 'failed', 'returned', 'refunded',
    'payment_failed', 'no_rider'
  );

  IF (v_current_committed_weight + v_incoming_order_weight) > v_max_vehicle_payload AND NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'WEIGHT_LIMIT_EXCEEDED: Exceeds vehicle weight limit (% kg active + % kg incoming > % kg max capacity)',
      ROUND(v_current_committed_weight, 1), ROUND(v_incoming_order_weight, 1), ROUND(v_max_vehicle_payload, 1);
  END IF;

  -- 5. Verify whether all shops in cart group have accepted
  IF v_cart_group_id IS NOT NULL THEN
    SELECT NOT EXISTS (
      SELECT 1 FROM orders
      WHERE cart_group_id = v_cart_group_id
        AND status NOT IN (
          'cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected',
          'verification_failed', 'shop_dispute_cancel', 'timeout', 'failed', 'returned', 'refunded'
        )
        AND seller_accepted = false
    ) INTO v_all_shops_accepted;
  ELSE
    v_all_shops_accepted := v_seller_accepted;
  END IF;

  -- 6. Determine target status
  IF v_payment_status = 'captured' THEN
    IF v_order_ready_time IS NOT NULL THEN
      v_new_status := 'ready_for_pickup';
    ELSE
      v_new_status := 'preparing';
    END IF;
  ELSIF v_all_shops_accepted = true THEN
    v_new_status := 'awaiting_payment';
  ELSE
    v_new_status := v_status;
  END IF;

  -- 7. Update target orders atomically, strictly excluding terminal/dead sub-orders
  IF v_cart_group_id IS NOT NULL THEN
    UPDATE orders
    SET 
      partner_accepted = true,
      delivery_partner_id = auth.uid(),
      status = CASE 
        WHEN status IN ('confirmed', 'preparing', 'ready_for_pickup') THEN status
        ELSE v_new_status 
      END,
      payment_deadline = CASE 
        WHEN v_all_shops_accepted = true AND v_payment_status != 'captured' 
        THEN (now() AT TIME ZONE 'utc') + interval '10 minutes' 
        ELSE payment_deadline 
      END,
      rider_phone = COALESCE(p_rider_phone, rider_phone),
      shop_lat = COALESCE(p_shop_lat, shop_lat),
      shop_lng = COALESCE(p_shop_lng, shop_lng),
      updated_at = NOW()
    WHERE cart_group_id = v_cart_group_id
      AND (delivery_partner_id IS NULL OR delivery_partner_id = auth.uid())
      AND status NOT IN (
        'delivered', 'cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected',
        'verification_failed', 'shop_dispute_cancel', 'timeout', 'failed', 'returned', 'refunded',
        'payment_failed', 'no_rider'
      );
  ELSE
    UPDATE orders
    SET 
      partner_accepted = true,
      delivery_partner_id = auth.uid(),
      status = CASE 
        WHEN status IN ('confirmed', 'preparing', 'ready_for_pickup') THEN status
        ELSE v_new_status 
      END,
      payment_deadline = CASE 
        WHEN v_all_shops_accepted = true AND v_payment_status != 'captured' 
        THEN (now() AT TIME ZONE 'utc') + interval '10 minutes' 
        ELSE v_payment_deadline 
      END,
      rider_phone = COALESCE(p_rider_phone, rider_phone),
      shop_lat = COALESCE(p_shop_lat, shop_lat),
      shop_lng = COALESCE(p_shop_lng, shop_lng),
      updated_at = NOW()
    WHERE id = p_order_id AND (delivery_partner_id IS NULL OR delivery_partner_id = auth.uid());
  END IF;

  GET DIAGNOSTICS v_rows_affected = ROW_COUNT;
  IF v_rows_affected = 0 THEN
    RAISE EXCEPTION 'ORDER_ACCEPTED_BY_OTHER_RIDER';
  END IF;

  RETURN v_all_shops_accepted;
END;
$$;

GRANT EXECUTE ON FUNCTION public.accept_order_rider(UUID, text, numeric, numeric) TO authenticated;

-- ── 2. Fortify reject_order_rider (Phantom Contact & Weight Re-balance Shield) ─
CREATE OR REPLACE FUNCTION public.reject_order_rider(
  p_order_id UUID, 
  p_reason TEXT DEFAULT NULL,
  p_disputed BOOLEAN DEFAULT false
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_delivery_partner_id uuid;
  v_shop_id uuid;
  v_status text;
  v_cart_group_id uuid;
BEGIN
  SELECT delivery_partner_id, shop_id, status, cart_group_id 
  INTO v_delivery_partner_id, v_shop_id, v_status, v_cart_group_id
  FROM orders 
  WHERE id = p_order_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  -- Transaction-level Advisory Lock
  PERFORM pg_advisory_xact_lock(hashtext('cart_group_' || COALESCE(v_cart_group_id, p_order_id)::text));

  IF v_cart_group_id IS NOT NULL THEN
    PERFORM id FROM orders WHERE cart_group_id = v_cart_group_id ORDER BY id FOR UPDATE;
  ELSE
    PERFORM id FROM orders WHERE id = p_order_id FOR UPDATE;
  END IF;

  -- Re-fetch critical fields post-lock
  SELECT delivery_partner_id, status 
  INTO v_delivery_partner_id, v_status
  FROM orders 
  WHERE id = p_order_id;

  IF v_delivery_partner_id IS NULL OR (v_delivery_partner_id IS DISTINCT FROM auth.uid() AND NOT public.is_active_admin(auth.uid())) THEN
    RAISE EXCEPTION 'Unauthorized: You are not assigned to this order.';
  END IF;

  IF v_status NOT IN ('awaiting_acceptance', 'pending', 'confirmed', 'preparing', 'ready_for_pickup', 'awaiting_payment') THEN
    RAISE EXCEPTION 'CRITICAL: Cannot drop an order after it has been picked up or delivered (Status: %). Contact platform support.', v_status;
  END IF;

  -- Atomic Cart Group Drop: Reset rider_phone and rider_name to prevent ghost contact buttons
  IF v_cart_group_id IS NOT NULL THEN
    UPDATE orders
    SET 
      partner_accepted = false,
      delivery_partner_id = NULL,
      rider_phone = NULL,
      rider_name = NULL,
      status = CASE 
        WHEN status IN ('confirmed', 'preparing', 'ready_for_pickup') THEN status
        WHEN status = 'awaiting_payment' THEN 'awaiting_payment'
        ELSE 'awaiting_acceptance' 
      END,
      acceptance_deadline = NOW() + interval '5 minutes',
      updated_at = NOW()
    WHERE cart_group_id = v_cart_group_id
      AND status NOT IN ('delivered', 'cancelled', 'seller_rejected', 'partner_rejected', 'shop_dispute_cancel');
  ELSE
    UPDATE orders
    SET 
      partner_accepted = false,
      delivery_partner_id = NULL,
      rider_phone = NULL,
      rider_name = NULL,
      status = CASE 
        WHEN status IN ('confirmed', 'preparing', 'ready_for_pickup') THEN status
        WHEN status = 'awaiting_payment' THEN 'awaiting_payment'
        ELSE 'awaiting_acceptance' 
      END,
      acceptance_deadline = NOW() + interval '5 minutes',
      updated_at = NOW()
    WHERE id = p_order_id;
  END IF;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.reject_order_rider(UUID, TEXT, BOOLEAN) TO authenticated;

