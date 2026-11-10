-- =============================================================================
-- Migration: 20290000000189_100x_deep_forensic_remediation_fortress.sql
-- Description: 100x Deep Forensic Edge-Case Remediation Fortress:
--   1. admin_get_dispatch_feed: Strict admin RBAC authorization barrier.
--   2. cancel_order: Acquire advisory lock before row locks to prevent deadlocks.
--   3. admin_proxy_accept_seller & admin_proxy_accept_rider: Advisory lock key unification & audit log column fix.
--   4. acknowledge_partial_rejection: Single-store IDOR & cart group null compatibility.
--   5. check_rider_has_stacked_orders: Fix false-positive stacked orders on single-store deliveries.
--   6. decline_order_items_seller: Drop obsolete overloads, unify signature & enforce advisory lock order.
--   7. validate_order_status_transition: Remove status regression from ready_for_pickup.
--   8. get_seller_balance & request_seller_withdrawal: Protect merchant earnings on partial refunds.
--   9. trg_sync_shop_hours: Synchronize is_open := is_accepting_orders.
-- =============================================================================

-- ── 1. Secure admin_get_dispatch_feed with Strict RBAC Barrier ───────────────
CREATE OR REPLACE FUNCTION public.admin_get_dispatch_feed(
  p_admin_lat DOUBLE PRECISION DEFAULT NULL,
  p_admin_lng DOUBLE PRECISION DEFAULT NULL,
  p_radius_km DOUBLE PRECISION DEFAULT NULL, -- NULL = Unlimited
  p_include_riders BOOLEAN DEFAULT TRUE,
  p_include_sellers BOOLEAN DEFAULT TRUE
)
RETURNS TABLE (
  order_id UUID,
  cart_group_id UUID,
  status TEXT,
  seller_accepted BOOLEAN,
  partner_accepted BOOLEAN,
  delivery_partner_id UUID,
  payment_status TEXT,
  total_amount NUMERIC,
  customer_id UUID,
  customer_name TEXT,
  customer_phone TEXT,
  shop_id UUID,
  shop_name TEXT,
  shop_lat DOUBLE PRECISION,
  shop_lng DOUBLE PRECISION,
  distance_km DOUBLE PRECISION,
  created_at TIMESTAMPTZ,
  acceptance_deadline TIMESTAMPTZ,
  item_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
BEGIN
  -- Strict Admin Authorization Check (Zero PII Leak)
  IF v_caller_id IS NULL OR NOT (
    public.is_super_admin(v_caller_id) 
    OR public.is_active_admin(v_caller_id) 
    OR public.has_permission(v_caller_id, 'dispatch.view_feed')
  ) THEN
    RAISE EXCEPTION 'UNAUTHORIZED: Dispatch feed is restricted to authorized platform administrators.';
  END IF;

  RETURN QUERY
  SELECT 
    o.id AS order_id,
    o.cart_group_id,
    o.status,
    COALESCE(o.seller_accepted, false) AS seller_accepted,
    COALESCE(o.partner_accepted, false) AS partner_accepted,
    o.delivery_partner_id,
    o.payment_status,
    o.total_amount,
    o.customer_id,
    COALESCE(p.full_name, 'Customer') AS customer_name,
    COALESCE(p.phone, '') AS customer_phone,
    o.shop_id,
    COALESCE(s.name, 'Shop') AS shop_name,
    COALESCE(o.shop_lat::double precision, ST_Y(s.location::geometry)) AS shop_lat,
    COALESCE(o.shop_lng::double precision, ST_X(s.location::geometry)) AS shop_lng,
    CASE 
      WHEN p_admin_lat IS NOT NULL AND p_admin_lng IS NOT NULL AND s.location IS NOT NULL THEN
        ST_Distance(s.location::geography, ST_SetSRID(ST_MakePoint(p_admin_lng, p_admin_lat), 4326)::geography) / 1000.0
      ELSE 0.0
    END AS distance_km,
    o.created_at,
    o.acceptance_deadline,
    (SELECT COUNT(*) FROM order_items oi WHERE oi.order_id = o.id) AS item_count
  FROM orders o
  JOIN shops s ON o.shop_id = s.id
  LEFT JOIN profiles p ON o.customer_id = p.id
  WHERE o.status IN ('awaiting_acceptance', 'pending')
    AND (
      (p_include_sellers AND NOT COALESCE(o.seller_accepted, false))
      OR
      (p_include_riders AND (NOT COALESCE(o.partner_accepted, false) OR o.delivery_partner_id IS NULL))
    )
    AND (
      p_radius_km IS NULL 
      OR p_admin_lat IS NULL 
      OR p_admin_lng IS NULL 
      OR s.location IS NULL
      OR ST_DWithin(s.location::geography, ST_SetSRID(ST_MakePoint(p_admin_lng, p_admin_lat), 4326)::geography, p_radius_km * 1000.0)
    )
  ORDER BY o.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_get_dispatch_feed(DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, BOOLEAN, BOOLEAN) TO authenticated;


-- ── 2. Deadlock-Proof cancel_order (Advisory Lock Before Row Locks) ───────────
CREATE OR REPLACE FUNCTION public.cancel_order(
  p_order_id UUID,
  p_reason TEXT,
  p_cancel_entire_group BOOLEAN DEFAULT true
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_customer_id uuid;
  v_cart_group_id uuid;
  v_rec record;
  v_is_customer boolean;
BEGIN
  -- Read uncommitted / unlocked metadata to determine group
  SELECT customer_id, cart_group_id INTO v_customer_id, v_cart_group_id
  FROM public.orders WHERE id = p_order_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  v_is_customer := (auth.uid() = v_customer_id);

  -- Authorization check
  IF auth.uid() IS NULL OR (NOT COALESCE(v_is_customer, false) AND NOT public.is_active_admin(auth.uid())) THEN
    RAISE EXCEPTION 'Unauthorized: Only the customer or an admin can cancel this order.';
  END IF;

  -- 100x FORENSIC DEADLOCK SHIELD:
  -- Acquire transaction advisory lock BEFORE row locking to prevent deadlocks with accept/swap RPCs
  PERFORM pg_advisory_xact_lock(hashtext('cart_group_' || COALESCE(v_cart_group_id, p_order_id)::text));

  IF v_cart_group_id IS NOT NULL AND p_cancel_entire_group THEN
    -- Cancel ALL active/pending orders in the cart group
    FOR v_rec IN 
      SELECT id, status, payment_status, refund_status 
      FROM public.orders 
      WHERE cart_group_id = v_cart_group_id 
      ORDER BY id FOR UPDATE 
    LOOP
      IF COALESCE(v_is_customer, false) AND v_rec.status NOT IN (
        'awaiting_acceptance', 'awaiting_payment', 'pending',
        'cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel'
      ) THEN
        RAISE EXCEPTION 'Order cannot be cancelled at this stage by customer';
      END IF;
      
      IF v_rec.status IN ('awaiting_acceptance', 'awaiting_payment', 'pending') THEN
        UPDATE public.orders
        SET 
          status = 'cancelled',
          cancelled_reason = p_reason,
          refund_status = CASE 
                            WHEN v_rec.payment_status = 'captured' AND COALESCE(v_rec.refund_status, 'none') NOT IN ('processing', 'completed') THEN 'processing' 
                            ELSE v_rec.refund_status 
                          END,
          updated_at = NOW()
        WHERE id = v_rec.id;
      END IF;
    END LOOP;
    
    PERFORM public.reallocate_cancelled_delivery_fees(v_cart_group_id);
    PERFORM public.rebalance_active_delivery_fees(v_cart_group_id);
    
  ELSE
    -- Selective single order cancellation
    FOR v_rec IN 
      SELECT id, status, payment_status, refund_status 
      FROM public.orders 
      WHERE id = p_order_id 
      FOR UPDATE 
    LOOP
      IF COALESCE(v_is_customer, false) AND v_rec.status NOT IN (
        'awaiting_acceptance', 'awaiting_payment', 'pending',
        'cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel'
      ) THEN
        RAISE EXCEPTION 'Order cannot be cancelled at this stage by customer';
      END IF;

      IF v_rec.status IN ('awaiting_acceptance', 'awaiting_payment', 'pending') THEN
        UPDATE public.orders
        SET 
          status = 'cancelled',
          cancelled_reason = p_reason,
          refund_status = CASE 
                            WHEN v_rec.payment_status = 'captured' AND COALESCE(v_rec.refund_status, 'none') NOT IN ('processing', 'completed') THEN 'processing' 
                            ELSE v_rec.refund_status 
                          END,
          updated_at = NOW()
        WHERE id = v_rec.id;
      END IF;
    END LOOP;

    IF v_cart_group_id IS NOT NULL THEN
      PERFORM public.reallocate_cancelled_delivery_fees(v_cart_group_id);
      PERFORM public.rebalance_active_delivery_fees(v_cart_group_id);
    END IF;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.cancel_order(UUID, TEXT, BOOLEAN) TO authenticated;


-- ── 3. Unify Advisory Lock & Fix Audit Columns in admin_proxy_accept_seller ───
CREATE OR REPLACE FUNCTION public.admin_proxy_accept_seller(
  p_order_id UUID,
  p_prep_time_minutes INT DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_status TEXT;
  v_shop_id UUID;
  v_partner_accepted BOOLEAN;
  v_payment_status TEXT;
  v_cart_group_id UUID;
  v_new_status TEXT;
  v_all_group_shops_accepted BOOLEAN := TRUE;
  v_sibling_record RECORD;
  v_caller_role TEXT := 'admin';
BEGIN
  IF NOT (
    public.is_super_admin(v_caller_id) 
    OR public.is_active_admin(v_caller_id) 
    OR public.has_permission(v_caller_id, 'dispatch.proxy_seller_accept')
  ) THEN
    RAISE EXCEPTION 'UNAUTHORIZED: You do not have permission to proxy-accept orders for sellers.';
  END IF;

  SELECT cart_group_id INTO v_cart_group_id FROM orders WHERE id = p_order_id;
  
  -- Unify advisory lock key with all cart group operations ('cart_group_')
  PERFORM pg_advisory_xact_lock(hashtext('cart_group_' || COALESCE(v_cart_group_id, p_order_id)::text));

  IF v_cart_group_id IS NOT NULL THEN
    PERFORM id FROM orders WHERE cart_group_id = v_cart_group_id ORDER BY id FOR UPDATE;
  ELSE
    PERFORM id FROM orders WHERE id = p_order_id FOR UPDATE;
  END IF;

  SELECT status, shop_id, partner_accepted, payment_status, cart_group_id 
  INTO v_status, v_shop_id, v_partner_accepted, v_payment_status, v_cart_group_id
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ORDER_NOT_FOUND';
  END IF;

  IF v_status = 'cancelled' THEN
    RAISE EXCEPTION 'ORDER_CANCELLED';
  END IF;

  IF v_status = 'seller_rejected' THEN
    RAISE EXCEPTION 'ORDER_ALREADY_REJECTED';
  END IF;

  IF v_status NOT IN ('awaiting_acceptance', 'pending') THEN
    RAISE EXCEPTION 'INVALID_STATE_TRANSITION: Order is in status %', v_status;
  END IF;

  IF v_cart_group_id IS NOT NULL THEN
    SELECT bool_and(COALESCE(seller_accepted, false))
    INTO v_all_group_shops_accepted
    FROM orders
    WHERE cart_group_id = v_cart_group_id 
      AND id != p_order_id
      AND status NOT IN ('cancelled', 'delivered', 'returned', 'refunded', 'seller_rejected', 'partner_rejected', 'rider_rejected');
    v_all_group_shops_accepted := COALESCE(v_all_group_shops_accepted, true);
  ELSE
    v_all_group_shops_accepted := TRUE;
  END IF;

  IF v_partner_accepted = TRUE AND v_all_group_shops_accepted = TRUE THEN
    IF v_payment_status = 'captured' THEN
      v_new_status := 'preparing';
    ELSE
      v_new_status := 'awaiting_payment';
    END IF;
  ELSE
    v_new_status := v_status;
  END IF;

  UPDATE orders
  SET 
    seller_accepted = true,
    status = v_new_status,
    payment_deadline = CASE WHEN v_partner_accepted = true AND v_all_group_shops_accepted = true AND v_payment_status != 'captured' THEN (now() AT TIME ZONE 'utc') + interval '10 minutes' ELSE payment_deadline END,
    shop_prep_time_snapshot = COALESCE(p_prep_time_minutes, shop_prep_time_snapshot),
    updated_at = NOW()
  WHERE id = p_order_id;

  IF v_partner_accepted = TRUE AND v_all_group_shops_accepted = TRUE AND v_cart_group_id IS NOT NULL THEN
    UPDATE orders
    SET 
      status = v_new_status,
      payment_deadline = CASE WHEN v_payment_status != 'captured' THEN (now() AT TIME ZONE 'utc') + interval '10 minutes' ELSE payment_deadline END,
      updated_at = NOW()
    WHERE cart_group_id = v_cart_group_id
      AND status IN ('awaiting_acceptance', 'pending');
  END IF;

  -- Correct audit logs schema (actor_id, actor_role, action, entity_type, entity_id, metadata)
  BEGIN
    INSERT INTO public.audit_logs (
      actor_id, actor_role, action, entity_type, entity_id, metadata
    ) VALUES (
      v_caller_id,
      v_caller_role,
      'proxy_seller_accept',
      'order',
      p_order_id::text,
      jsonb_build_object(
        'cart_group_id', v_cart_group_id,
        'new_status', v_new_status,
        'all_shops_accepted', v_all_group_shops_accepted
      )
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_proxy_accept_seller(UUID, INT) TO authenticated;


-- ── 4. Unify Advisory Lock in admin_proxy_accept_rider ───────────────────────
CREATE OR REPLACE FUNCTION public.admin_proxy_accept_rider(
  p_order_id UUID,
  p_rider_id UUID DEFAULT NULL,
  p_shop_lat DOUBLE PRECISION DEFAULT NULL,
  p_shop_lng DOUBLE PRECISION DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_caller_role TEXT := 'admin';
  v_status TEXT;
  v_seller_accepted BOOLEAN;
  v_partner_accepted BOOLEAN;
  v_payment_status TEXT;
  v_cart_group_id UUID;
  v_target_rider_id UUID;
  v_target_name TEXT;
  v_target_phone TEXT;
  v_is_admin_delivery BOOLEAN := FALSE;
  v_admin_name TEXT;
  v_admin_phone TEXT;
  v_existing_rider_id UUID;
  v_existing_rider_name TEXT;
  v_new_status TEXT;
  v_order_record RECORD;
  v_return_both_accepted BOOLEAN := FALSE;
  v_all_group_shops_accepted BOOLEAN := TRUE;
  v_resolved_shop_lat DOUBLE PRECISION;
  v_resolved_shop_lng DOUBLE PRECISION;
BEGIN
  -- 1. Authorization Barrier
  IF NOT (
    public.is_super_admin(v_caller_id) 
    OR public.is_active_admin(v_caller_id) 
    OR public.has_permission(v_caller_id, 'dispatch.proxy_rider_accept')
  ) THEN
    RAISE EXCEPTION 'UNAUTHORIZED: You do not have permission to proxy-accept orders for riders.';
  END IF;

  -- 2. Target Rider Resolution
  IF p_rider_id IS NOT NULL THEN
    v_target_rider_id := p_rider_id;
    SELECT COALESCE(p.full_name, 'Rider'), COALESCE(p.phone, '')
    INTO v_target_name, v_target_phone
    FROM profiles p
    WHERE p.id = v_target_rider_id;

    IF v_target_name IS NULL THEN
      RAISE EXCEPTION 'RIDER_NOT_FOUND: The specified delivery partner does not exist.';
    END IF;
  ELSE
    -- Self-delivery mode
    v_target_rider_id := v_caller_id;
    v_is_admin_delivery := TRUE;

    SELECT COALESCE(p.full_name, 'Admin'), COALESCE(p.phone, '')
    INTO v_admin_name, v_admin_phone
    FROM profiles p
    WHERE p.id = v_caller_id;

    v_target_name := 'Admin ' || COALESCE(v_admin_name, 'Delivery');
    v_target_phone := COALESCE(v_admin_phone, '');

    INSERT INTO delivery_partners (
      id, full_name, phone, vehicle_type, is_active, is_verified, approval_status, is_online, updated_at
    ) VALUES (
      v_caller_id, v_target_name, v_target_phone, 'bike', true, true, 'approved', true, NOW()
    )
    ON CONFLICT (id) DO UPDATE SET
      is_active = true,
      is_online = true,
      approval_status = 'approved',
      updated_at = NOW();
  END IF;

  -- 3. Row & State Fetch
  SELECT status, seller_accepted, partner_accepted, payment_status, cart_group_id, delivery_partner_id, rider_name
  INTO v_status, v_seller_accepted, v_partner_accepted, v_payment_status, v_cart_group_id, v_existing_rider_id, v_existing_rider_name
  FROM orders WHERE id = p_order_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ORDER_NOT_FOUND';
  END IF;

  IF v_status = 'cancelled' THEN
    RAISE EXCEPTION 'ORDER_CANCELLED';
  END IF;

  IF v_status = 'seller_rejected' THEN
    RAISE EXCEPTION 'ORDER_ALREADY_REJECTED';
  END IF;

  IF v_partner_accepted = true AND v_existing_rider_id IS NOT NULL AND v_existing_rider_id != v_target_rider_id THEN
    RAISE EXCEPTION 'ORDER_ACCEPTED_BY_OTHER_RIDER: Order was already accepted by %', v_existing_rider_name;
  END IF;

  IF v_status NOT IN ('awaiting_acceptance', 'pending', 'awaiting_payment', 'confirmed', 'preparing', 'ready_for_pickup') THEN
    RAISE EXCEPTION 'INVALID_STATE_TRANSITION: Order is in status %', v_status;
  END IF;

  -- 4. Cart Group Advisory Lock (Unified key 'cart_group_')
  PERFORM pg_advisory_xact_lock(hashtext('cart_group_' || COALESCE(v_cart_group_id, p_order_id)::text));

  -- Check if all shops in the cart group have accepted
  IF v_cart_group_id IS NOT NULL THEN
    SELECT bool_and(COALESCE(o.seller_accepted, false))
    INTO v_all_group_shops_accepted
    FROM orders o
    WHERE o.cart_group_id = v_cart_group_id
      AND o.status NOT IN ('cancelled', 'delivered', 'returned', 'refunded', 'seller_rejected', 'partner_rejected');
    v_all_group_shops_accepted := COALESCE(v_all_group_shops_accepted, true);
  ELSE
    v_all_group_shops_accepted := COALESCE(v_seller_accepted, false);
  END IF;

  -- 5. Atomic Cart Group Assignment Loop
  FOR v_order_record IN 
    SELECT o.id, o.status, o.seller_accepted, o.payment_status, o.payment_deadline, o.order_ready_time, o.shop_id, o.shop_lat, o.shop_lng
    FROM orders o
    WHERE COALESCE(o.cart_group_id, o.id) = COALESCE(v_cart_group_id, p_order_id)
      AND o.status NOT IN ('cancelled', 'delivered', 'returned', 'refunded', 'seller_rejected', 'partner_rejected', 'shop_dispute_cancel', 'timeout', 'failed')
    ORDER BY o.id
    FOR UPDATE
  LOOP
    IF v_order_record.status IN ('confirmed', 'preparing', 'ready_for_pickup') THEN
      v_new_status := v_order_record.status;
      v_return_both_accepted := TRUE;
    ELSIF v_all_group_shops_accepted = true THEN
      IF v_order_record.payment_status = 'captured' THEN
        IF v_order_record.order_ready_time IS NOT NULL THEN
          v_new_status := 'ready_for_pickup';
        ELSE
          v_new_status := 'preparing';
        END IF;
      ELSE
        v_new_status := 'awaiting_payment';
      END IF;
      v_return_both_accepted := TRUE;
    ELSE
      v_new_status := v_order_record.status;
    END IF;

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
      delivery_partner_id = v_target_rider_id,
      rider_name = v_target_name,
      rider_phone = COALESCE(v_target_phone, rider_phone),
      is_admin_delivery = v_is_admin_delivery,
      status = v_new_status,
      payment_deadline = CASE 
        WHEN v_order_record.seller_accepted = true AND v_order_record.payment_status != 'captured' 
        THEN (now() AT TIME ZONE 'utc') + interval '10 minutes' 
        ELSE v_order_record.payment_deadline 
      END,
      shop_lat = COALESCE(v_resolved_shop_lat, v_order_record.shop_lat),
      shop_lng = COALESCE(v_resolved_shop_lng, v_order_record.shop_lng),
      updated_at = NOW()
    WHERE id = v_order_record.id;
  END LOOP;

  -- 6. Immutable Audit Trail
  BEGIN
    SELECT COALESCE(r.slug, 'admin') INTO v_caller_role
    FROM admin_users au
    LEFT JOIN roles r ON r.id = au.role_id
    WHERE au.id = v_caller_id;
  EXCEPTION WHEN OTHERS THEN
    v_caller_role := 'admin';
  END;

  INSERT INTO public.audit_logs (actor_id, actor_role, action, entity_type, entity_id, metadata)
  VALUES (
    v_caller_id, 
    v_caller_role, 
    'proxy_rider_accept', 
    'order', 
    p_order_id::text, 
    jsonb_build_object(
      'target_rider_id', v_target_rider_id,
      'target_rider_name', v_target_name,
      'is_admin_delivery', v_is_admin_delivery,
      'cart_group_id', v_cart_group_id,
      'both_accepted', v_return_both_accepted
    )
  );

  RETURN v_return_both_accepted;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_proxy_accept_rider(UUID, UUID, DOUBLE PRECISION, DOUBLE PRECISION) TO authenticated;


-- ── 5. Single-Store IDOR & Null Safety in acknowledge_partial_rejection ───────
CREATE OR REPLACE FUNCTION public.acknowledge_partial_rejection(
  p_cart_group_id UUID,
  p_action TEXT DEFAULT 'proceeded',
  p_resolution TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_effective_action TEXT;
  v_caller_id UUID := auth.uid();
BEGIN
  IF p_cart_group_id IS NULL THEN
    RETURN;
  END IF;

  -- 100x IDOR SECURITY SHIELD (Supports both multi-shop cart groups & single-shop orders)
  IF v_caller_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.orders 
    WHERE (cart_group_id = p_cart_group_id OR id = p_cart_group_id)
      AND (customer_id = v_caller_id OR public.is_active_admin(v_caller_id))
  ) THEN
    RAISE EXCEPTION 'Unauthorized: You do not own this order group.';
  END IF;

  v_effective_action := COALESCE(p_resolution, p_action, 'proceeded');

  PERFORM pg_advisory_xact_lock(hashtext('cart_group_' || p_cart_group_id::text));
  PERFORM id FROM public.orders 
  WHERE (cart_group_id = p_cart_group_id OR id = p_cart_group_id)
  ORDER BY id FOR UPDATE;

  UPDATE public.orders
  SET 
    cancelled_reason = 'customer_' || v_effective_action || CASE WHEN cancelled_reason IS NOT NULL AND cancelled_reason != '' THEN '_' || cancelled_reason ELSE '' END,
    updated_at = NOW()
  WHERE (cart_group_id = p_cart_group_id OR id = p_cart_group_id)
    AND status IN ('seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'cancelled', 'timeout', 'payment_failed', 'shop_dispute_cancel')
    AND COALESCE(cancelled_reason, '') NOT LIKE 'customer%';

  UPDATE public.order_items
  SET status = 'cancelled', updated_at = NOW()
  WHERE order_id IN (
    SELECT id FROM public.orders 
    WHERE (cart_group_id = p_cart_group_id OR id = p_cart_group_id)
      AND status IN ('seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'cancelled', 'timeout', 'payment_failed', 'shop_dispute_cancel')
  ) AND status != 'cancelled';
END;
$$;

GRANT EXECUTE ON FUNCTION public.acknowledge_partial_rejection(UUID, TEXT, TEXT) TO authenticated, service_role;


-- ── 6. Fix check_rider_has_stacked_orders False-Positive on Single-Store ─────
CREATE OR REPLACE FUNCTION public.check_rider_has_stacked_orders(
  p_rider_id UUID,
  p_my_cart_group_id TEXT DEFAULT NULL,
  p_my_order_id UUID DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_has_stacked boolean := false;
BEGIN
  IF p_rider_id IS NULL THEN
    RETURN false;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM orders
    WHERE delivery_partner_id = p_rider_id
      AND status IN ('confirmed', 'preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery')
      -- Must not match current customer's order ID
      AND (p_my_order_id IS NULL OR id != p_my_order_id)
      -- Must not match current customer's cart group ID
      AND (
        p_my_cart_group_id IS NULL 
        OR (cart_group_id IS NOT NULL AND cart_group_id::text != p_my_cart_group_id)
        OR (cart_group_id IS NULL AND id::text != p_my_cart_group_id)
      )
  ) INTO v_has_stacked;

  RETURN v_has_stacked;
END;
$$;

GRANT EXECUTE ON FUNCTION public.check_rider_has_stacked_orders(UUID, TEXT, UUID) TO authenticated, anon;


-- ── 7. Unified decline_order_items_seller & Drop Obsolete Overloads ───────────
DROP FUNCTION IF EXISTS public.decline_order_items_seller(UUID, UUID[], TEXT, TEXT);
DROP FUNCTION IF EXISTS public.decline_order_items_seller(UUID, UUID[], TEXT);

CREATE OR REPLACE FUNCTION public.decline_order_items_seller(
  p_order_id UUID,
  p_order_item_ids UUID[],
  p_reason TEXT DEFAULT 'out_of_stock',
  p_message TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_order RECORD;
  v_caller_id UUID := auth.uid();
  v_cart_group_id UUID;
  v_declined_subtotal NUMERIC := 0;
  v_new_active_subtotal NUMERIC := 0;
  v_shop_cat TEXT;
  v_is_food BOOLEAN;
  v_gst_rate NUMERIC;
  v_comm_rate NUMERIC := 5.0;
  v_comm_key TEXT;
  v_comm_val NUMERIC;
  v_item RECORD;
  v_item_subtotal NUMERIC;
  v_item_gst NUMERIC;
  v_new_s9_5 NUMERIC := 0;
  v_new_non_food_gst NUMERIC := 0;
  v_item_comm NUMERIC;
  v_new_enything_commission NUMERIC := 0;
  v_new_tcs NUMERIC := 0;
  v_new_tds NUMERIC := 0;
  v_new_gst_item_total NUMERIC := 0;
  v_new_seller_payout NUMERIC := 0;
  v_active_count INT;
  v_declined_prod_ids UUID[];
  v_surviving_subtotal NUMERIC := 0;
  v_new_grand_total NUMERIC := 0;
  v_refund_amount NUMERIC := 0;
BEGIN
  SELECT cart_group_id INTO v_cart_group_id FROM orders WHERE id = p_order_id;

  -- 100x FORENSIC LOCK ORDER: Acquire cart group advisory lock BEFORE row locks
  PERFORM pg_advisory_xact_lock(hashtext('cart_group_' || COALESCE(v_cart_group_id, p_order_id)::text));

  IF v_cart_group_id IS NOT NULL THEN
    PERFORM id FROM orders WHERE cart_group_id = v_cart_group_id ORDER BY id FOR UPDATE;
  ELSE
    PERFORM id FROM orders WHERE id = p_order_id FOR UPDATE;
  END IF;

  SELECT * INTO v_order FROM orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  -- Authorization check: shop owner or admin
  IF v_caller_id IS NULL OR NOT (
    EXISTS (SELECT 1 FROM shops WHERE id = v_order.shop_id AND seller_id = v_caller_id)
    OR public.is_active_admin(v_caller_id)
  ) THEN
    RAISE EXCEPTION 'Unauthorized: You are not the merchant for this order.';
  END IF;

  IF v_order.status NOT IN ('pending', 'awaiting_acceptance', 'confirmed', 'preparing') THEN
    RAISE EXCEPTION 'Cannot decline items when order is in status %', v_order.status;
  END IF;

  -- Collect product IDs for soft-delete inventory sync
  SELECT array_agg(DISTINCT product_id) INTO v_declined_prod_ids
  FROM order_items
  WHERE order_id = p_order_id 
    AND id = ANY(p_order_item_ids) 
    AND status = 'active';

  -- Mark declined items
  UPDATE order_items
  SET 
    status = 'declined',
    declined_reason = COALESCE(p_message, p_reason),
    updated_at = NOW()
  WHERE order_id = p_order_id 
    AND id = ANY(p_order_item_ids) 
    AND status = 'active';

  -- Inventory sync: mark declined items out of stock
  IF v_declined_prod_ids IS NOT NULL AND array_length(v_declined_prod_ids, 1) > 0 THEN
    UPDATE products
    SET 
      is_available = false,
      total_quantity = 0,
      updated_at = NOW()
    WHERE id = ANY(v_declined_prod_ids)
      AND is_deleted = false;
  END IF;

  -- Recalculate remaining active items
  SELECT category INTO v_shop_cat FROM shops WHERE id = v_order.shop_id;
  v_is_food := (v_shop_cat IN ('restaurant', 'food', 'bakery', 'cafe', 'fast_food', 'sweet_shop'));
  v_gst_rate := CASE WHEN v_is_food THEN 0.05 ELSE 0.18 END;

  v_comm_key := 'commission_percent_' || COALESCE(v_shop_cat, 'default');
  BEGIN
    SELECT value::numeric INTO v_comm_val FROM platform_config WHERE key = v_comm_key;
    IF v_comm_val IS NOT NULL THEN v_comm_rate := v_comm_val; END IF;
  EXCEPTION WHEN OTHERS THEN
    v_comm_rate := 5.0;
  END;

  FOR v_item IN
    SELECT price, quantity
    FROM order_items
    WHERE order_id = p_order_id AND status = 'active'
  LOOP
    v_item_subtotal := v_item.price * v_item.quantity;
    v_new_active_subtotal := v_new_active_subtotal + v_item_subtotal;

    v_item_gst := ROUND((v_item_subtotal * v_gst_rate)::numeric, 2);
    IF v_is_food THEN
      v_new_s9_5 := v_new_s9_5 + v_item_gst;
    ELSE
      v_new_non_food_gst := v_new_non_food_gst + v_item_gst;
    END IF;

    v_item_comm := ROUND((v_item_subtotal * (v_comm_rate / 100.0))::numeric, 2);
    v_new_enything_commission := v_new_enything_commission + v_item_comm;
    v_new_tcs := v_new_tcs + ROUND((v_item_subtotal * 0.005)::numeric, 2);
    v_new_tds := v_new_tds + ROUND((v_item_subtotal * 0.001)::numeric, 2);
  END LOOP;

  v_new_gst_item_total := v_new_s9_5 + v_new_non_food_gst;
  v_new_seller_payout := v_new_active_subtotal + v_new_non_food_gst - v_new_enything_commission - v_new_tcs - v_new_tds;

  SELECT COUNT(*) INTO v_active_count FROM order_items WHERE order_id = p_order_id AND status = 'active';

  IF v_active_count = 0 THEN
    -- All items declined -> cancel store's order
    UPDATE orders
    SET 
      status = 'seller_rejected',
      cancelled_reason = 'all_items_declined: ' || COALESCE(p_message, p_reason),
      total_amount = 0,
      grand_total = 0,
      seller_payout = 0,
      updated_at = NOW()
    WHERE id = p_order_id;
  ELSE
    -- Partial decline: update order line items
    v_new_grand_total := v_new_active_subtotal + v_new_gst_item_total
      + COALESCE(v_order.delivery_charges, 0)
      + COALESCE(v_order.platform_fee, 0)
      + COALESCE(v_order.multi_shop_surcharge, 0)
      + COALESCE(v_order.small_cart_fee, 0)
      + COALESCE(v_order.heavy_order_fee, 0)
      - COALESCE(v_order.coupon_discount, 0);

    UPDATE orders
    SET 
      total_amount = v_new_active_subtotal,
      grand_total = v_new_grand_total,
      s9_5_gst_amount = v_new_s9_5,
      non_food_gst_amount = v_new_non_food_gst,
      gst_item_total = v_new_gst_item_total,
      enything_commission = v_new_enything_commission,
      tcs_amount = v_new_tcs,
      tds_amount = v_new_tds,
      seller_payout = v_new_seller_payout,
      updated_at = NOW()
    WHERE id = p_order_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'order_id', p_order_id,
    'surviving_items_count', v_active_count,
    'new_subtotal', v_new_active_subtotal,
    'new_seller_payout', v_new_seller_payout
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.decline_order_items_seller(UUID, UUID[], TEXT, TEXT) TO authenticated, service_role;


-- ── 8. Status Regression Guard in validate_order_status_transition ────────────
CREATE OR REPLACE FUNCTION public.validate_order_status_transition()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        RETURN NEW;
    END IF;

    -- Only validate if status is actually changing
    IF NEW.status = OLD.status THEN
        RETURN NEW;
    END IF;

    CASE OLD.status
        WHEN 'awaiting_payment' THEN
            IF NEW.status NOT IN ('awaiting_acceptance', 'cancelled', 'pending', 'confirmed', 'payment_failed', 'verification_failed', 'seller_rejected') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'awaiting_acceptance' THEN
            IF NEW.status NOT IN ('pending', 'awaiting_payment', 'confirmed', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'cancelled', 'timeout') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'pending' THEN
            IF NEW.status NOT IN ('confirmed', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'cancelled', 'timeout', 'awaiting_acceptance', 'awaiting_payment') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'confirmed' THEN
            IF NEW.status NOT IN ('preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery', 'delivered', 'cancelled', 'seller_rejected', 'verification_failed', 'awaiting_acceptance') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'preparing' THEN
            IF NEW.status NOT IN ('ready_for_pickup', 'picked_up', 'out_for_delivery', 'delivered', 'cancelled', 'seller_rejected', 'verification_failed', 'awaiting_acceptance') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'ready_for_pickup' THEN
            -- Cannot regress to awaiting_acceptance once food is cooked and ready
            IF NEW.status NOT IN ('picked_up', 'out_for_delivery', 'delivered', 'cancelled', 'seller_rejected') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'picked_up' THEN
            IF NEW.status NOT IN ('out_for_delivery', 'delivered', 'cancelled', 'shop_dispute', 'shop_dispute_cancel') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'out_for_delivery' THEN
            IF NEW.status NOT IN ('delivered', 'cancelled', 'shop_dispute', 'shop_dispute_cancel') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'shop_dispute' THEN
            IF NEW.status NOT IN ('cancelled', 'delivered', 'shop_dispute_cancel') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'bulk_pending' THEN
            IF NEW.status NOT IN ('bulk_confirmed', 'bulk_preparing', 'bulk_ready', 'bulk_dispatched', 'delivered', 'cancelled', 'seller_rejected') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'bulk_confirmed' THEN
            IF NEW.status NOT IN ('bulk_preparing', 'bulk_ready', 'bulk_dispatched', 'delivered', 'cancelled', 'seller_rejected') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'bulk_preparing' THEN
            IF NEW.status NOT IN ('bulk_ready', 'bulk_dispatched', 'delivered', 'cancelled', 'seller_rejected') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'bulk_ready' THEN
            IF NEW.status NOT IN ('bulk_dispatched', 'delivered', 'cancelled', 'seller_rejected') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'bulk_dispatched' THEN
            IF NEW.status NOT IN ('delivered', 'cancelled', 'shop_dispute', 'shop_dispute_cancel') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'delivered' THEN
            RAISE EXCEPTION 'Terminal state: Cannot transition from delivered to %', NEW.status;

        WHEN 'cancelled' THEN
            RAISE EXCEPTION 'Terminal state: Cannot transition from cancelled to %', NEW.status;

        WHEN 'seller_rejected' THEN
            RAISE EXCEPTION 'Terminal state: Cannot transition from seller_rejected to %', NEW.status;

        WHEN 'partner_rejected' THEN
            IF NEW.status NOT IN ('awaiting_acceptance', 'pending', 'cancelled') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'rider_rejected' THEN
            IF NEW.status NOT IN ('awaiting_acceptance', 'pending', 'cancelled') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'verification_failed' THEN
            RAISE EXCEPTION 'Terminal state: Cannot transition from verification_failed to %', NEW.status;

        WHEN 'timeout' THEN
            RAISE EXCEPTION 'Terminal state: Cannot transition from timeout to %', NEW.status;

        WHEN 'payment_failed' THEN
            RAISE EXCEPTION 'Terminal state: Cannot transition from payment_failed to %', NEW.status;

        WHEN 'shop_dispute_cancel' THEN
            RAISE EXCEPTION 'Terminal state: Cannot transition from shop_dispute_cancel to %', NEW.status;

        ELSE
            -- Default fallback
            NULL;
    END CASE;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- ── 9. Protect Merchant Earnings on Partial Refunds in get_seller_balance ────
CREATE OR REPLACE FUNCTION get_seller_balance(p_seller_id UUID)
RETURNS JSON AS $$
DECLARE
  v_total_earned NUMERIC := 0;
  v_total_paid NUMERIC := 0;
  v_available_balance NUMERIC := 0;
BEGIN
  IF (auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_seller_id) AND NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: Cannot access financial data for another user.';
  END IF;

  SELECT COALESCE(SUM(
    CASE 
      -- Full order refund: exclude entire payout
      WHEN COALESCE(refund_status, 'none') IN ('processing', 'processed', 'completed') 
           AND (COALESCE(total_refunded, 0) >= COALESCE(grand_total, 0) OR COALESCE(grand_total, 0) = 0) THEN 0 
      -- Partial order refund or normal delivered order: payout is already recomputed net of declined items
      ELSE COALESCE(seller_payout, 0) 
    END 
    - COALESCE(wait_time_penalty, 0)
  ), 0) INTO v_total_earned
  FROM orders
  WHERE status = 'delivered'
  AND shop_id IN (SELECT id FROM shops WHERE seller_id = p_seller_id);

  SELECT COALESCE(SUM(amount), 0) INTO v_total_paid
  FROM withdrawals
  WHERE user_id = p_seller_id
  AND user_role = 'seller'
  AND status != 'rejected';

  v_available_balance := v_total_earned - v_total_paid;

  RETURN json_build_object(
    'total_earned', v_total_earned,
    'total_paid', v_total_paid,
    'available_balance', v_available_balance
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.get_seller_balance(UUID) TO authenticated;


CREATE OR REPLACE FUNCTION request_seller_withdrawal(
  p_amount NUMERIC,
  p_upi_id TEXT DEFAULT NULL,
  p_bank_account_number TEXT DEFAULT NULL,
  p_bank_ifsc TEXT DEFAULT NULL,
  p_bank_account_holder TEXT DEFAULT NULL
)
RETURNS JSON AS $$
DECLARE
  v_seller_id UUID := auth.uid();
  v_total_earned NUMERIC := 0;
  v_total_paid NUMERIC := 0;
  v_available_balance NUMERIC := 0;
  v_withdrawal_id UUID;
BEGIN
  IF v_seller_id IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Must be logged in to request withdrawal.';
  END IF;

  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Invalid withdrawal amount: Must be greater than 0.';
  END IF;

  SELECT COALESCE(SUM(
    CASE 
      WHEN COALESCE(refund_status, 'none') IN ('processing', 'processed', 'completed') 
           AND (COALESCE(total_refunded, 0) >= COALESCE(grand_total, 0) OR COALESCE(grand_total, 0) = 0) THEN 0 
      ELSE COALESCE(seller_payout, 0) 
    END 
    - COALESCE(wait_time_penalty, 0)
  ), 0) INTO v_total_earned
  FROM orders
  WHERE status = 'delivered'
  AND shop_id IN (SELECT id FROM shops WHERE seller_id = v_seller_id);

  SELECT COALESCE(SUM(amount), 0) INTO v_total_paid
  FROM withdrawals
  WHERE user_id = v_seller_id
  AND user_role = 'seller'
  AND status != 'rejected';

  v_available_balance := v_total_earned - v_total_paid;

  IF p_amount > v_available_balance THEN
    RAISE EXCEPTION 'Insufficient balance: Available balance is %, requested %', v_available_balance, p_amount;
  END IF;

  INSERT INTO withdrawals (
    user_id,
    user_role,
    amount,
    upi_id,
    bank_account_number,
    bank_ifsc,
    bank_account_holder,
    status,
    created_at,
    updated_at
  ) VALUES (
    v_seller_id,
    'seller',
    p_amount,
    p_upi_id,
    p_bank_account_number,
    p_bank_ifsc,
    p_bank_account_holder,
    'pending',
    NOW(),
    NOW()
  ) RETURNING id INTO v_withdrawal_id;

  RETURN json_build_object(
    'success', true,
    'withdrawal_id', v_withdrawal_id,
    'amount', p_amount,
    'remaining_balance', v_available_balance - p_amount
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.request_seller_withdrawal(NUMERIC, TEXT, TEXT, TEXT, TEXT) TO authenticated;


-- ── 10. Synchronize is_open in trg_sync_shop_hours ────────────────────────────
CREATE OR REPLACE FUNCTION public.trg_sync_shop_hours()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_now   time;
    v_open  time;
    v_close time;
BEGIN
    v_now   := (current_timestamp AT TIME ZONE 'Asia/Kolkata')::time;
    v_open  := public.safe_cast_time(COALESCE(NEW.open_time, NEW.opening_time)::text);
    v_close := public.safe_cast_time(COALESCE(NEW.close_time, NEW.closing_time)::text);

    IF NEW.open_time IS NOT NULL AND NEW.opening_time IS NULL THEN
        NEW.opening_time := NEW.open_time;
    ELSIF NEW.opening_time IS NOT NULL AND NEW.open_time IS NULL THEN
        NEW.open_time := NEW.opening_time;
    END IF;

    IF NEW.close_time IS NOT NULL AND NEW.closing_time IS NULL THEN
        NEW.closing_time := NEW.close_time;
    ELSIF NEW.closing_time IS NOT NULL AND NEW.close_time IS NULL THEN
        NEW.close_time := NEW.closing_time;
    END IF;

    IF (NEW.open_time IS DISTINCT FROM OLD.open_time OR NEW.close_time IS DISTINCT FROM OLD.close_time)
       OR (NEW.opening_time IS DISTINCT FROM OLD.opening_time OR NEW.closing_time IS DISTINCT FROM OLD.closing_time) THEN
        NEW.is_manually_closed := false;
    END IF;

    IF NEW.is_manually_closed = true AND v_open IS NOT NULL AND v_close IS NOT NULL THEN
        IF v_open <= v_close THEN
            IF v_now < v_open OR v_now > v_close THEN
                NEW.is_manually_closed := false;
            END IF;
        ELSE
            IF v_now < v_open AND v_now > v_close THEN
                NEW.is_manually_closed := false;
            END IF;
        END IF;
    END IF;

    -- Explicit toggle synchronization:
    IF NEW.is_accepting_orders IS DISTINCT FROM OLD.is_accepting_orders THEN
        NEW.is_manually_closed := NOT NEW.is_accepting_orders;
    ELSE
        IF NEW.is_active = false THEN
            NEW.is_accepting_orders := false;
        ELSIF v_open IS NOT NULL AND v_close IS NOT NULL THEN
            IF NEW.is_manually_closed = true THEN
                NEW.is_accepting_orders := false;
            ELSE
                IF v_open <= v_close THEN
                    NEW.is_accepting_orders := ( v_now >= v_open AND v_now <= v_close );
                ELSE
                    NEW.is_accepting_orders := ( v_now >= v_open OR  v_now <= v_close );
                END IF;
            END IF;
        END IF;
    END IF;

    -- Guarantee 1:1 synchronization between is_accepting_orders and is_open
    NEW.is_open := NEW.is_accepting_orders;

    RETURN NEW;
END;
$$;
