-- Migration: 20290000000139_100x_admin_order_dispatch_and_proxy_hub.sql
-- Description: 100% Additive backend infrastructure for Admin & Dispatcher Proxy Acceptance
--   1. Seeds 'dispatcher' role and dispatch.* permissions.
--   2. Binds dispatch permissions to 'dispatcher', 'admin', and 'super_admin'.
--   3. Implements admin_proxy_accept_rider with UNLIMITED rider acceptance capacity (bypassing the 3-cart-group limit).
--   4. Implements admin_proxy_accept_seller (bypassing shop.seller_id == auth.uid() check).
--   5. Implements admin_proxy_accept_both for atomic dual confirmation in one transaction.
--   6. Implements admin_get_dispatch_feed for live radar feed with radius / unlimited distance filtering.
--   7. Implements admin_get_online_riders for selecting online couriers.
--   8. Strictly logs all operations to public.audit_logs.

-- =============================================================================
-- 1. SEED PERMISSIONS AND DISPATCHER ROLE
-- =============================================================================

INSERT INTO public.permissions (code, name, description, module)
VALUES 
  ('dispatch.view', 'View Dispatch Hub', 'Access the live order dispatch hub and radar feed', 'Dispatch'),
  ('dispatch.proxy_rider_accept', 'Proxy Rider Accept', 'Accept deliveries on behalf of riders without hoarding caps', 'Dispatch'),
  ('dispatch.proxy_seller_accept', 'Proxy Seller Accept', 'Accept orders on behalf of merchants and restaurants', 'Dispatch'),
  ('dispatch.toggle_buzz', 'Toggle Dispatch Buzz', 'Control audio alarms and sound loops for incoming orders', 'Dispatch'),
  ('dispatch.override_limits', 'Bypass Dispatch Limits', 'Accept unlimited deliveries beyond standard courier limits', 'Dispatch')
ON CONFLICT (code) DO NOTHING;

INSERT INTO public.roles (name, slug, description, is_system, color, icon)
VALUES (
  'Order Dispatcher', 
  'dispatcher', 
  'Operations specialist who monitors live order queues and proxy-accepts on behalf of riders and merchants.', 
  TRUE, 
  '#FF9800', 
  'radar'
) ON CONFLICT (slug) DO NOTHING;

-- Bind dispatch permissions and orders.view to 'dispatcher'
DO $$
DECLARE
  v_role_id UUID;
  v_perm RECORD;
BEGIN
  SELECT id INTO v_role_id FROM public.roles WHERE slug = 'dispatcher';
  IF v_role_id IS NOT NULL THEN
    FOR v_perm IN 
      SELECT id FROM public.permissions 
      WHERE module = 'Dispatch' 
         OR code IN ('orders.view', 'dashboard.view') 
    LOOP
      INSERT INTO public.role_permissions (role_id, permission_id)
      VALUES (v_role_id, v_perm.id)
      ON CONFLICT DO NOTHING;
    END LOOP;
  END IF;

  -- Bind dispatch permissions to super_admin and admin
  FOR v_role_id IN 
    SELECT id FROM public.roles WHERE slug IN ('super_admin', 'superadmin', 'admin') 
  LOOP
    FOR v_perm IN SELECT id FROM public.permissions WHERE module = 'Dispatch' LOOP
      INSERT INTO public.role_permissions (role_id, permission_id)
      VALUES (v_role_id, v_perm.id)
      ON CONFLICT DO NOTHING;
    END LOOP;
  END LOOP;
END $$;


-- =============================================================================
-- 2. ADMIN PROXY ACCEPT RIDER (UNLIMITED CAPACITY)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.admin_proxy_accept_rider(
  p_order_id UUID,
  p_rider_id UUID DEFAULT NULL,
  p_rider_phone TEXT DEFAULT NULL,
  p_shop_lat NUMERIC DEFAULT NULL,
  p_shop_lng NUMERIC DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_target_rider_id UUID;
  v_target_phone TEXT;
  v_cart_group_id UUID;
  v_status TEXT;
  v_seller_accepted BOOLEAN;
  v_payment_status TEXT;
  v_order_ready_time TIMESTAMPTZ;
  v_new_status TEXT;
  v_order_record RECORD;
  v_return_both_accepted BOOLEAN := FALSE;
  v_resolved_shop_lat NUMERIC;
  v_resolved_shop_lng NUMERIC;
  v_caller_role TEXT := 'admin';
  v_all_group_shops_accepted BOOLEAN := TRUE;
BEGIN
  -- 1. Authorization Guard
  IF NOT (
    public.is_super_admin(v_caller_id) 
    OR public.is_active_admin(v_caller_id) 
    OR public.has_permission(v_caller_id, 'dispatch.proxy_rider_accept')
  ) THEN
    RAISE EXCEPTION 'UNAUTHORIZED: You do not have permission to proxy-accept orders for riders.';
  END IF;

  -- 2. Target Rider Resolution
  IF p_rider_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM delivery_partners 
      WHERE id = p_rider_id 
        AND (is_active = true OR is_active IS NULL)
    ) THEN
      RAISE EXCEPTION 'INVALID_RIDER: Selected delivery partner is inactive or not found.';
    END IF;
    v_target_rider_id := p_rider_id;
    IF p_rider_phone IS NULL OR p_rider_phone = '' THEN
      SELECT phone INTO v_target_phone FROM profiles WHERE id = p_rider_id;
    ELSE
      v_target_phone := p_rider_phone;
    END IF;
  ELSE
    v_target_rider_id := v_caller_id;
    IF p_rider_phone IS NULL OR p_rider_phone = '' THEN
      SELECT phone INTO v_target_phone FROM profiles WHERE id = v_caller_id;
    ELSE
      v_target_phone := p_rider_phone;
    END IF;
    v_target_phone := COALESCE(NULLIF(v_target_phone, ''), 'Admin Dispatch');

    -- Self-Healing: Ensure caller has delivery_partners record to satisfy fk_orders_delivery_partner
    INSERT INTO public.delivery_partners (id, is_active, is_available, is_verified, verification_status, vehicle_type)
    VALUES (v_caller_id, true, true, true, 'verified', 'Admin Dispatch Fleet')
    ON CONFLICT (id) DO UPDATE SET is_active = true, is_verified = true, verification_status = 'verified';
  END IF;

  -- 3. Row Lock Initial Order
  SELECT status, seller_accepted, payment_status, order_ready_time, cart_group_id
  INTO v_status, v_seller_accepted, v_payment_status, v_order_ready_time, v_cart_group_id
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ORDER_NOT_FOUND';
  END IF;

  IF v_status = 'cancelled' THEN
    RAISE EXCEPTION 'ORDER_CANCELLED';
  END IF;

  IF v_status NOT IN ('awaiting_acceptance', 'pending') THEN
    RAISE EXCEPTION 'INVALID_STATE_TRANSITION: Order is in status %', v_status;
  END IF;

  -- 4. Cart Group Advisory Lock
  PERFORM pg_advisory_xact_lock(hashtext('cart_group_accept_' || COALESCE(v_cart_group_id, p_order_id)::text));

  -- Notice: The standard v_active_cart_groups_count >= 3 check is intentionally BYPASSED
  -- for Admin / Dispatcher proxy acceptance, satisfying the Unlimited Capacity requirement.

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
    -- Compute state transition
    IF v_all_group_shops_accepted = true THEN
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
      delivery_partner_id = v_target_rider_id,
      status = v_new_status,
      payment_deadline = CASE WHEN v_order_record.seller_accepted = true AND v_order_record.payment_status != 'captured' THEN (now() AT TIME ZONE 'utc') + interval '10 minutes' ELSE v_order_record.payment_deadline END,
      rider_phone = COALESCE(v_target_phone, rider_phone),
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
      'cart_group_id', v_cart_group_id,
      'both_accepted', v_return_both_accepted
    )
  );

  RETURN v_return_both_accepted;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_proxy_accept_rider(UUID, UUID, TEXT, NUMERIC, NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_proxy_accept_rider(UUID, UUID, TEXT, NUMERIC, NUMERIC) TO service_role;


-- =============================================================================
-- 3. ADMIN PROXY ACCEPT SELLER
-- =============================================================================

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
  -- 1. Authorization Guard
  IF NOT (
    public.is_super_admin(v_caller_id) 
    OR public.is_active_admin(v_caller_id) 
    OR public.has_permission(v_caller_id, 'dispatch.proxy_seller_accept')
  ) THEN
    RAISE EXCEPTION 'UNAUTHORIZED: You do not have permission to proxy-accept orders for sellers.';
  END IF;

  -- 2. Lock Order
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

  -- 3. Check sibling stores if part of a multi-shop cart group
  IF v_cart_group_id IS NOT NULL THEN
    SELECT bool_and(COALESCE(seller_accepted, false))
    INTO v_all_group_shops_accepted
    FROM orders
    WHERE cart_group_id = v_cart_group_id 
      AND id != p_order_id
      AND status NOT IN ('cancelled', 'delivered', 'returned', 'refunded', 'seller_rejected', 'partner_rejected');
    v_all_group_shops_accepted := COALESCE(v_all_group_shops_accepted, true);
  ELSE
    v_all_group_shops_accepted := TRUE;
  END IF;

  -- 4. Compute state transition
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
    shop_prep_time_snapshot = COALESCE(p_prep_time_minutes, shop_prep_time_snapshot, 15),
    updated_at = NOW()
  WHERE id = p_order_id;

  -- If this acceptance completes the cart group, synchronize all sibling orders
  IF v_cart_group_id IS NOT NULL AND v_partner_accepted = TRUE AND v_all_group_shops_accepted = TRUE THEN
    UPDATE orders
    SET 
      status = v_new_status,
      payment_deadline = CASE WHEN v_payment_status != 'captured' THEN (now() AT TIME ZONE 'utc') + interval '10 minutes' ELSE payment_deadline END,
      updated_at = NOW()
    WHERE cart_group_id = v_cart_group_id 
      AND id != p_order_id
      AND status NOT IN ('cancelled', 'delivered', 'returned', 'refunded', 'seller_rejected', 'partner_rejected');
  END IF;

  -- 5. Write to Immutable Audit Trail
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
    'proxy_seller_accept', 
    'order', 
    p_order_id::text, 
    jsonb_build_object(
      'shop_id', v_shop_id,
      'partner_accepted', v_partner_accepted,
      'all_group_shops_accepted', v_all_group_shops_accepted,
      'prep_time_minutes', p_prep_time_minutes
    )
  );

  RETURN (v_partner_accepted = TRUE AND v_all_group_shops_accepted = TRUE);
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_proxy_accept_seller(UUID, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_proxy_accept_seller(UUID, INT) TO service_role;


-- =============================================================================
-- 4. 1-TAP ATOMIC DUAL ACCEPTANCE (SELLER + RIDER)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.admin_proxy_accept_both(
  p_order_id UUID,
  p_rider_id UUID DEFAULT NULL,
  p_prep_time_minutes INT DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- 1. Perform seller accept
  PERFORM public.admin_proxy_accept_seller(p_order_id, p_prep_time_minutes);
  -- 2. Perform rider accept (unlimited admin capacity)
  RETURN public.admin_proxy_accept_rider(p_order_id, p_rider_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_proxy_accept_both(UUID, UUID, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_proxy_accept_both(UUID, UUID, INT) TO service_role;


-- =============================================================================
-- 5. LIVE DISPATCH RADAR FEED QUERY
-- =============================================================================

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
BEGIN
  RETURN QUERY
  SELECT 
    o.id AS order_id,
    o.cart_group_id,
    o.status,
    COALESCE(o.seller_accepted, false) AS seller_accepted,
    COALESCE(o.partner_accepted, false) AS partner_accepted,
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
      (p_include_riders = TRUE AND (o.delivery_partner_id IS NULL OR o.partner_accepted IS NOT TRUE))
      OR
      (p_include_sellers = TRUE AND COALESCE(o.seller_accepted, false) = FALSE)
    )
    AND (
      p_radius_km IS NULL 
      OR p_admin_lat IS NULL 
      OR p_admin_lng IS NULL
      OR s.location IS NULL
      OR ST_DWithin(s.location::geography, ST_SetSRID(ST_MakePoint(p_admin_lng, p_admin_lat), 4326)::geography, p_radius_km * 1000)
    )
  ORDER BY o.created_at DESC
  LIMIT 100;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_get_dispatch_feed(DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, BOOLEAN, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_dispatch_feed(DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, BOOLEAN, BOOLEAN) TO service_role;


-- =============================================================================
-- 6. ACTIVE & ONLINE RIDERS RESOLVER (FOR ASSIGNMENT PICKER)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.admin_get_online_riders()
RETURNS TABLE (
  rider_id UUID,
  full_name TEXT,
  phone TEXT,
  vehicle_type TEXT,
  lat DOUBLE PRECISION,
  lng DOUBLE PRECISION,
  active_orders_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    dp.id AS rider_id,
    COALESCE(p.full_name, 'Delivery Partner') AS full_name,
    COALESCE(p.phone, '') AS phone,
    COALESCE(dp.vehicle_type, 'bike') AS vehicle_type,
    CASE WHEN dp.location IS NOT NULL THEN ST_Y(dp.location::geometry) ELSE NULL END AS lat,
    CASE WHEN dp.location IS NOT NULL THEN ST_X(dp.location::geometry) ELSE NULL END AS lng,
    (
      SELECT COUNT(DISTINCT COALESCE(o.cart_group_id, o.id))
      FROM orders o
      WHERE o.delivery_partner_id = dp.id
        AND o.status NOT IN (
          'delivered', 'cancelled', 'seller_rejected', 'partner_rejected', 
          'returned', 'refunded', 'failed', 'payment_failed', 'timeout', 
          'verification_failed', 'no_rider', 'shop_dispute_cancel'
        )
    ) AS active_orders_count
  FROM delivery_partners dp
  LEFT JOIN profiles p ON dp.id = p.id
  WHERE (dp.is_active = true OR dp.is_active IS NULL)
  ORDER BY p.full_name ASC
  LIMIT 50;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_get_online_riders() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_online_riders() TO service_role;
