-- Migration: 20290000000150_100x_admin_dispatch_rider_and_self_delivery_fortress.sql
-- Description: 100% Additive backend infrastructure for Admin Dispatch Hub,
--   Admin Self-Delivery Lifecycle ("By Our Own"), Customer VIP Operations Badge,
--   Courier Concurrency Exclusion Shield, and Multi-Shop Cart Group Sibling Synchronization.

-- =============================================================================
-- 1. ADD COLUMNS & INDEXES TO ORDERS TABLE
-- =============================================================================

ALTER TABLE public.orders 
ADD COLUMN IF NOT EXISTS rider_name TEXT;

ALTER TABLE public.orders 
ADD COLUMN IF NOT EXISTS is_admin_delivery BOOLEAN DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS idx_orders_is_admin_delivery 
ON public.orders (is_admin_delivery) 
WHERE is_admin_delivery = TRUE;

CREATE INDEX IF NOT EXISTS idx_orders_delivery_partner_status 
ON public.orders (delivery_partner_id, status);


-- =============================================================================
-- 2. FORTIFIED ADMIN PROXY ACCEPT RIDER
-- =============================================================================

DROP FUNCTION IF EXISTS public.admin_proxy_accept_rider(UUID, UUID, TEXT, NUMERIC, NUMERIC);
DROP FUNCTION IF EXISTS public.admin_proxy_accept_rider(UUID, UUID, TEXT, NUMERIC, NUMERIC, BOOLEAN);

CREATE OR REPLACE FUNCTION public.admin_proxy_accept_rider(
  p_order_id UUID,
  p_rider_id UUID DEFAULT NULL,
  p_rider_phone TEXT DEFAULT NULL,
  p_shop_lat NUMERIC DEFAULT NULL,
  p_shop_lng NUMERIC DEFAULT NULL,
  p_force_reassign BOOLEAN DEFAULT FALSE
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
  v_target_name TEXT;
  v_is_admin_delivery BOOLEAN := FALSE;
  v_admin_name TEXT;
  v_admin_phone TEXT;
  v_profile_name TEXT;
  v_profile_phone TEXT;
  v_cart_group_id UUID;
  v_status TEXT;
  v_existing_rider_id UUID;
  v_existing_rider_name TEXT;
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
  v_support_phone TEXT := '+91 9999999999';
BEGIN
  -- 1. Authorization Guard
  IF NOT (
    public.is_super_admin(v_caller_id) 
    OR public.is_active_admin(v_caller_id) 
    OR public.has_permission(v_caller_id, 'dispatch.proxy_rider_accept')
  ) THEN
    RAISE EXCEPTION 'UNAUTHORIZED: You do not have permission to proxy-accept orders for riders.';
  END IF;

  -- 2. Target Rider & Identity Resolution
  IF p_rider_id IS NOT NULL THEN
    -- Assigning to an active delivery courier
    IF NOT EXISTS (
      SELECT 1 FROM delivery_partners 
      WHERE id = p_rider_id 
        AND (is_active = true OR is_active IS NULL)
    ) THEN
      RAISE EXCEPTION 'INVALID_RIDER: Selected delivery partner is inactive or not found.';
    END IF;
    
    v_target_rider_id := p_rider_id;
    v_is_admin_delivery := FALSE;
    
    SELECT full_name, phone INTO v_profile_name, v_profile_phone 
    FROM profiles WHERE id = p_rider_id;
    
    v_target_name := COALESCE(NULLIF(v_profile_name, ''), 'Courier Partner');
    v_target_phone := COALESCE(NULLIF(p_rider_phone, ''), NULLIF(v_profile_phone, ''), '');
  ELSE
    -- Admin self-assigns to personally deliver the order ("Deliver by Myself")
    v_target_rider_id := v_caller_id;
    v_is_admin_delivery := TRUE;
    
    -- Query admin_users first
    SELECT full_name, phone INTO v_admin_name, v_admin_phone 
    FROM admin_users WHERE id = v_caller_id;
    
    -- Fallback to profiles
    SELECT full_name, phone INTO v_profile_name, v_profile_phone 
    FROM profiles WHERE id = v_caller_id;
    
    -- Fallback support phone from platform config if available
    BEGIN
      SELECT (value#>>'{}') INTO v_support_phone 
      FROM platform_config WHERE key = 'support_phone';
      IF v_support_phone IS NULL OR v_support_phone = '' THEN
        v_support_phone := '+91 9999999999';
      END IF;
    EXCEPTION WHEN OTHERS THEN
      v_support_phone := '+91 9999999999';
    END;

    v_target_name := COALESCE(NULLIF(v_admin_name, ''), NULLIF(v_profile_name, ''), 'Operations Admin');
    -- Prefix with Admin for complete customer transparency
    IF NOT v_target_name ILIKE 'Admin%' THEN
      v_target_name := 'Admin ' || v_target_name;
    END IF;

    v_target_phone := COALESCE(NULLIF(p_rider_phone, ''), NULLIF(v_admin_phone, ''), NULLIF(v_profile_phone, ''), v_support_phone);

    -- Self-Healing: Ensure caller has valid delivery_partners record
    INSERT INTO public.delivery_partners (
      id, name, phone, is_active, is_available, is_accepting_orders, is_verified, verification_status, vehicle_type
    ) VALUES (
      v_caller_id, v_target_name, v_target_phone, true, true, true, true, 'verified', 'Admin Dispatch Fleet'
    )
    ON CONFLICT (id) DO UPDATE SET 
      is_active = true, 
      is_verified = true, 
      verification_status = 'verified',
      is_accepting_orders = true,
      name = COALESCE(EXCLUDED.name, delivery_partners.name),
      phone = COALESCE(NULLIF(EXCLUDED.phone, ''), delivery_partners.phone);

    -- Self-Healing: Ensure caller has valid profiles record
    INSERT INTO public.profiles (id, full_name, phone, role)
    VALUES (v_caller_id, v_target_name, v_target_phone, 'admin')
    ON CONFLICT (id) DO UPDATE SET 
      full_name = COALESCE(EXCLUDED.full_name, profiles.full_name),
      phone = COALESCE(NULLIF(EXCLUDED.phone, ''), profiles.phone);
  END IF;

  -- 3. Row Lock Initial Order
  SELECT status, seller_accepted, payment_status, order_ready_time, cart_group_id, delivery_partner_id
  INTO v_status, v_seller_accepted, v_payment_status, v_order_ready_time, v_cart_group_id, v_existing_rider_id
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

  -- 4. Race Condition Check: Prevent accidental courier overwrite unless explicitly forced
  IF v_existing_rider_id IS NOT NULL 
     AND v_existing_rider_id != v_target_rider_id 
     AND NOT COALESCE(p_force_reassign, FALSE) THEN
    SELECT COALESCE(full_name, 'another courier') INTO v_existing_rider_name 
    FROM profiles WHERE id = v_existing_rider_id;
    RAISE EXCEPTION 'ORDER_ACCEPTED_BY_OTHER_RIDER: Order was already accepted by %', v_existing_rider_name;
  END IF;

  IF v_status NOT IN ('awaiting_acceptance', 'pending', 'awaiting_payment', 'confirmed', 'preparing', 'ready_for_pickup') THEN
    RAISE EXCEPTION 'INVALID_STATE_TRANSITION: Order is in status %', v_status;
  END IF;

  -- 5. Cart Group Advisory Lock
  PERFORM pg_advisory_xact_lock(hashtext('cart_group_accept_' || COALESCE(v_cart_group_id, p_order_id)::text));

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

  -- 6. Atomic Cart Group Assignment Loop
  FOR v_order_record IN 
    SELECT o.id, o.status, o.seller_accepted, o.payment_status, o.payment_deadline, o.order_ready_time, o.shop_id, o.shop_lat, o.shop_lng
    FROM orders o
    WHERE COALESCE(o.cart_group_id, o.id) = COALESCE(v_cart_group_id, p_order_id)
      AND o.status NOT IN ('cancelled', 'delivered', 'returned', 'refunded', 'seller_rejected', 'partner_rejected', 'shop_dispute_cancel', 'timeout', 'failed')
    ORDER BY o.id
    FOR UPDATE
  LOOP
    -- Compute state transition
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

  -- 7. Immutable Audit Trail
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

GRANT EXECUTE ON FUNCTION public.admin_proxy_accept_rider(UUID, UUID, TEXT, NUMERIC, NUMERIC, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_proxy_accept_rider(UUID, UUID, TEXT, NUMERIC, NUMERIC, BOOLEAN) TO service_role;


-- =============================================================================
-- 3. FORTIFIED ACCEPT_ORDER_RIDER (FOR REGULAR COURIERS)
-- =============================================================================

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
  v_rider_name text;
  v_rider_phone text;
  v_return_seller_accepted boolean := false;
  v_all_group_shops_accepted boolean := true;
BEGIN
  IF length(p_rider_phone) > 20 THEN
    RAISE EXCEPTION 'Rider phone string too long (Max 20 chars)';
  END IF;

  -- Suspension check
  IF EXISTS (
    SELECT 1 FROM delivery_partners 
    WHERE id = auth.uid() 
      AND (is_active = false OR (verification_status IS NOT NULL AND verification_status NOT IN ('verified', 'approved')))
  ) THEN
    RAISE EXCEPTION 'RIDER_SUSPENDED: Your delivery partner account is currently suspended or unverified.';
  END IF;

  -- Resolve courier name and phone
  SELECT full_name, phone INTO v_rider_name, v_rider_phone 
  FROM profiles WHERE id = auth.uid();
  v_rider_name := COALESCE(NULLIF(v_rider_name, ''), 'Delivery Partner');
  v_rider_phone := COALESCE(NULLIF(p_rider_phone, ''), NULLIF(v_rider_phone, ''), '');

  -- Transaction-level Advisory Lock for Rider Concurrency
  PERFORM pg_advisory_xact_lock(hashtext('rider_acceptance_' || COALESCE(auth.uid()::text, 'system_admin')));

  -- Strict row locking & fetch initial order metadata
  SELECT status, seller_accepted, payment_status, payment_deadline, order_ready_time, cart_group_id, delivery_partner_id
  INTO v_status, v_seller_accepted, v_payment_status, v_payment_deadline, v_order_ready_time, v_cart_group_id, v_delivery_partner_id
  FROM orders WHERE id = p_order_id FOR UPDATE;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;
  
  IF v_status = 'cancelled' THEN
    RAISE EXCEPTION 'ORDER_CANCELLED';
  END IF;

  IF v_status = 'seller_rejected' THEN
    RAISE EXCEPTION 'ORDER_ALREADY_REJECTED';
  END IF;

  -- Race condition check: already accepted by another rider
  IF v_delivery_partner_id IS NOT NULL AND v_delivery_partner_id != auth.uid() THEN
    RAISE EXCEPTION 'ORDER_ACCEPTED_BY_OTHER_RIDER';
  END IF;

  -- Permit acceptance in awaiting_acceptance, pending, or downstream states from dropped/reassigned orders
  IF v_status NOT IN ('awaiting_acceptance', 'pending', 'confirmed', 'preparing', 'ready_for_pickup') THEN
    RAISE EXCEPTION 'Invalid state transition from %', v_status;
  END IF;

  -- Advisory lock on cart group scope
  PERFORM pg_advisory_xact_lock(hashtext('cart_group_accept_' || COALESCE(v_cart_group_id, p_order_id)::text));

  -- Enforce Max 3 Active Cart Groups Hoarding Limit (couriers only)
  SELECT COUNT(DISTINCT COALESCE(cart_group_id, id)) INTO v_active_cart_groups_count
  FROM orders
  WHERE delivery_partner_id = auth.uid()
    AND status NOT IN (
      'delivered', 'cancelled', 'seller_rejected', 'partner_rejected', 
      'returned', 'refunded', 'failed', 'payment_failed', 'timeout', 
      'verification_failed', 'no_rider', 'shop_dispute_cancel'
    )
    AND COALESCE(cart_group_id, id) IS DISTINCT FROM COALESCE(v_cart_group_id, p_order_id);

  IF v_active_cart_groups_count >= 3 THEN
    RAISE EXCEPTION 'MAX_ORDERS_REACHED: You can only accept orders from up to 3 different customers at a time.';
  END IF;

  -- Check all sibling shops in cart group
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

  -- Atomic Cart Group Assignment Loop
  FOR v_order_record IN 
    SELECT o.id, o.status, o.seller_accepted, o.payment_status, o.payment_deadline, o.order_ready_time, o.delivery_partner_id, o.shop_id, o.shop_lat, o.shop_lng, o.rider_phone
    FROM orders o
    WHERE COALESCE(o.cart_group_id, o.id) = COALESCE(v_cart_group_id, p_order_id)
      AND o.status NOT IN ('cancelled', 'delivered', 'returned', 'refunded', 'seller_rejected', 'partner_rejected', 'shop_dispute_cancel', 'timeout', 'failed')
    ORDER BY o.id
    FOR UPDATE
  LOOP
    IF v_order_record.delivery_partner_id IS NOT NULL AND v_order_record.delivery_partner_id != auth.uid() THEN
      RAISE EXCEPTION 'ORDER_ACCEPTED_BY_OTHER_RIDER';
    END IF;

    -- Preserve downstream progress for dropped/reassigned orders
    IF v_order_record.status IN ('confirmed', 'preparing', 'ready_for_pickup') THEN
      v_new_status := v_order_record.status;
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
      rider_name = v_rider_name,
      rider_phone = COALESCE(NULLIF(v_rider_phone, ''), v_order_record.rider_phone),
      is_admin_delivery = FALSE,
      status = v_new_status,
      payment_deadline = CASE 
        WHEN v_all_group_shops_accepted = true AND v_order_record.payment_status != 'captured' 
        THEN (now() AT TIME ZONE 'utc') + interval '10 minutes' 
        ELSE v_order_record.payment_deadline 
      END,
      shop_lat = COALESCE(v_resolved_shop_lat, v_order_record.shop_lat),
      shop_lng = COALESCE(v_resolved_shop_lng, v_order_record.shop_lng),
      updated_at = NOW()
    WHERE id = v_order_record.id;

    IF v_order_record.id = p_order_id THEN
      v_return_seller_accepted := (v_all_group_shops_accepted = true);
    END IF;
  END LOOP;

  RETURN v_return_seller_accepted;
END;
$$;

GRANT EXECUTE ON FUNCTION public.accept_order_rider(UUID, text, numeric, numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.accept_order_rider(UUID, text, numeric, numeric) TO service_role;


-- =============================================================================
-- 4. FORTIFIED GET_NEARBY_UNASSIGNED_ORDERS (COURIER RADAR DISCOVERY)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_nearby_unassigned_orders(
    p_rider_lat double precision DEFAULT NULL, 
    p_rider_lng double precision DEFAULT NULL, 
    p_radius_km double precision DEFAULT 15.0
)
RETURNS SETOF public.orders
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_max_radius double precision;
BEGIN
    IF p_rider_lat IS NULL OR p_rider_lng IS NULL THEN
        RETURN;
    END IF;

    BEGIN
      SELECT (value#>>'{}')::double precision INTO v_admin_max_radius 
      FROM public.platform_config 
      WHERE key = 'rider_notification_radius_km';

      IF v_admin_max_radius IS NULL THEN
        SELECT (value#>>'{}')::double precision INTO v_admin_max_radius 
        FROM public.platform_config 
        WHERE key = 'max_delivery_radius_km';
      END IF;

      IF v_admin_max_radius IS NULL THEN 
        v_admin_max_radius := 15.0; 
      END IF;
    EXCEPTION WHEN OTHERS THEN 
      v_admin_max_radius := 15.0;
    END;
    
    p_radius_km := LEAST(COALESCE(p_radius_km, 15.0), v_admin_max_radius);
    p_radius_km := GREATEST(p_radius_km, 1.0);

    RETURN QUERY
    WITH eligible_groups AS (
      SELECT COALESCE(o.cart_group_id, o.id) as group_id, MIN(o.created_at) as created_at
      FROM public.orders o
      JOIN public.shops s ON o.shop_id = s.id
      WHERE o.delivery_partner_id IS NULL
        AND (
          o.status IN ('awaiting_acceptance', 'pending')
          OR (o.status IN ('confirmed', 'preparing', 'ready_for_pickup') AND o.payment_status = 'captured')
        )
        AND s.location IS NOT NULL
        AND ST_DWithin(
            s.location::geography, 
            ST_SetSRID(ST_MakePoint(p_rider_lng, p_rider_lat), 4326)::geography, 
            p_radius_km * 1000
        )
        -- EXCLUSIVE RIDER AFFINITY: Ensure no other courier holds sibling
        AND NOT EXISTS (
            SELECT 1 FROM public.orders siblings
            WHERE COALESCE(siblings.cart_group_id, siblings.id) = COALESCE(o.cart_group_id, o.id)
              AND siblings.delivery_partner_id IS NOT NULL
              AND siblings.delivery_partner_id != auth.uid()
              AND siblings.status NOT IN ('cancelled', 'delivered', 'returned', 'refunded', 'seller_rejected', 'partner_rejected', 'shop_dispute_cancel')
        )
      GROUP BY COALESCE(o.cart_group_id, o.id)
      ORDER BY MIN(o.created_at) ASC
      LIMIT 50
    )
    SELECT o.*
    FROM public.orders o
    JOIN eligible_groups eg ON COALESCE(o.cart_group_id, o.id) = eg.group_id
    WHERE o.delivery_partner_id IS NULL
      AND (
        o.status IN ('awaiting_acceptance', 'pending')
        OR (o.status IN ('confirmed', 'preparing', 'ready_for_pickup') AND o.payment_status = 'captured')
      )
    ORDER BY o.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_nearby_unassigned_orders(double precision, double precision, double precision) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_nearby_unassigned_orders(double precision, double precision, double precision) TO service_role;


-- =============================================================================
-- 5. ATOMIC DUAL ACCEPTANCE (SELLER + RIDER) WITH CART GROUP SIBLING SYNC
-- =============================================================================

DROP FUNCTION IF EXISTS public.admin_proxy_accept_both(UUID, UUID, INT);
DROP FUNCTION IF EXISTS public.admin_proxy_accept_both(UUID, UUID, INT, BOOLEAN);

CREATE OR REPLACE FUNCTION public.admin_proxy_accept_both(
  p_order_id UUID,
  p_rider_id UUID DEFAULT NULL,
  p_prep_time_minutes INT DEFAULT NULL,
  p_accept_all_cart_group_shops BOOLEAN DEFAULT FALSE
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cart_group_id UUID;
  v_sibling_record RECORD;
BEGIN
  SELECT cart_group_id INTO v_cart_group_id FROM orders WHERE id = p_order_id;

  -- 1. Perform seller accept
  IF COALESCE(p_accept_all_cart_group_shops, FALSE) = TRUE AND v_cart_group_id IS NOT NULL THEN
    FOR v_sibling_record IN 
      SELECT id FROM orders 
      WHERE cart_group_id = v_cart_group_id 
        AND status NOT IN ('cancelled', 'delivered', 'returned', 'refunded', 'seller_rejected', 'partner_rejected')
    LOOP
      PERFORM public.admin_proxy_accept_seller(v_sibling_record.id, p_prep_time_minutes);
    END LOOP;
  ELSE
    PERFORM public.admin_proxy_accept_seller(p_order_id, p_prep_time_minutes);
  END IF;

  -- 2. Perform rider accept (unlimited admin capacity, self-healing profile)
  RETURN public.admin_proxy_accept_rider(p_order_id, p_rider_id, NULL, NULL, NULL, TRUE);
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_proxy_accept_both(UUID, UUID, INT, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_proxy_accept_both(UUID, UUID, INT, BOOLEAN) TO service_role;


-- =============================================================================
-- 6. REASSIGN OR RELEASE ORDER RPC (ADMIN DISPATCH)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.admin_reassign_order_rider(
  p_order_id UUID,
  p_new_rider_id UUID DEFAULT NULL,
  p_reason TEXT DEFAULT 'Reassigned by operations'
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_cart_group_id UUID;
  v_status TEXT;
  v_seller_accepted BOOLEAN;
  v_new_rider_name TEXT;
  v_new_rider_phone TEXT;
  v_is_admin_delivery BOOLEAN := FALSE;
  v_order_record RECORD;
  v_caller_role TEXT := 'admin';
BEGIN
  -- Authorization guard
  IF NOT (
    public.is_super_admin(v_caller_id) 
    OR public.is_active_admin(v_caller_id) 
    OR public.has_permission(v_caller_id, 'dispatch.proxy_rider_accept')
  ) THEN
    RAISE EXCEPTION 'UNAUTHORIZED: You do not have permission to reassign orders.';
  END IF;

  SELECT status, seller_accepted, cart_group_id
  INTO v_status, v_seller_accepted, v_cart_group_id
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ORDER_NOT_FOUND';
  END IF;

  IF v_status IN ('delivered', 'cancelled', 'returned', 'refunded', 'failed') THEN
    RAISE EXCEPTION 'INVALID_ORDER_STATE: Cannot reassign order in status %', v_status;
  END IF;

  -- Advisory lock
  PERFORM pg_advisory_xact_lock(hashtext('cart_group_accept_' || COALESCE(v_cart_group_id, p_order_id)::text));

  IF p_new_rider_id IS NOT NULL THEN
    -- Verify target courier is active
    IF NOT EXISTS (
      SELECT 1 FROM delivery_partners 
      WHERE id = p_new_rider_id 
        AND (is_active = true OR is_active IS NULL)
    ) THEN
      RAISE EXCEPTION 'INVALID_RIDER: Selected delivery partner is inactive or not found.';
    END IF;

    -- Assign to new courier
    SELECT full_name, phone INTO v_new_rider_name, v_new_rider_phone 
    FROM profiles WHERE id = p_new_rider_id;
    v_new_rider_name := COALESCE(NULLIF(v_new_rider_name, ''), 'Courier Partner');
    v_is_admin_delivery := FALSE;

    FOR v_order_record IN 
      SELECT id FROM orders 
      WHERE COALESCE(cart_group_id, id) = COALESCE(v_cart_group_id, p_order_id)
        AND status NOT IN ('delivered', 'cancelled', 'returned', 'refunded', 'failed')
      FOR UPDATE
    LOOP
      UPDATE orders
      SET 
        delivery_partner_id = p_new_rider_id,
        rider_name = v_new_rider_name,
        rider_phone = COALESCE(NULLIF(v_new_rider_phone, ''), rider_phone),
        is_admin_delivery = FALSE,
        partner_accepted = TRUE,
        updated_at = NOW()
      WHERE id = v_order_record.id;
    END LOOP;
  ELSE
    -- Release back to public courier pool
    FOR v_order_record IN 
      SELECT id, status, seller_accepted, payment_status FROM orders 
      WHERE COALESCE(cart_group_id, id) = COALESCE(v_cart_group_id, p_order_id)
        AND status NOT IN ('delivered', 'cancelled', 'returned', 'refunded', 'failed')
      FOR UPDATE
    LOOP
      UPDATE orders
      SET 
        delivery_partner_id = NULL,
        partner_accepted = FALSE,
        rider_name = NULL,
        rider_phone = NULL,
        is_admin_delivery = FALSE,
        -- If awaiting_payment without payment capture, revert to awaiting_acceptance so pool sees it
        status = CASE 
          WHEN v_order_record.status = 'awaiting_payment' THEN 'awaiting_acceptance'
          ELSE v_order_record.status 
        END,
        updated_at = NOW()
      WHERE id = v_order_record.id;
    END LOOP;
  END IF;

  -- Audit Log
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
    'admin_reassign_rider', 
    'order', 
    p_order_id::text, 
    jsonb_build_object(
      'new_rider_id', p_new_rider_id,
      'new_rider_name', v_new_rider_name,
      'released_to_pool', (p_new_rider_id IS NULL),
      'reason', p_reason
    )
  );

  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_reassign_order_rider(UUID, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_reassign_order_rider(UUID, UUID, TEXT) TO service_role;


-- =============================================================================
-- 7. ADMIN ACTIVE DELIVERIES FEED ("MY DELIVERIES" TAB)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.admin_get_active_deliveries(
  p_admin_id UUID DEFAULT NULL
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
  customer_address TEXT,
  delivery_lat DOUBLE PRECISION,
  delivery_lng DOUBLE PRECISION,
  shop_id UUID,
  shop_name TEXT,
  shop_phone TEXT,
  shop_lat DOUBLE PRECISION,
  shop_lng DOUBLE PRECISION,
  rider_name TEXT,
  rider_phone TEXT,
  is_admin_delivery BOOLEAN,
  arrived_at_shop_time TIMESTAMPTZ,
  order_ready_time TIMESTAMPTZ,
  shop_prep_time_snapshot INT,
  delivery_otp TEXT,
  created_at TIMESTAMPTZ,
  item_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_target_id UUID := COALESCE(p_admin_id, auth.uid());
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
    COALESCE(NULLIF(o.customer_phone, ''), COALESCE(p.phone, '')) AS customer_phone,
    COALESCE(o.address, 'Customer Address') AS customer_address,
    o.delivery_lat,
    o.delivery_lng,
    o.shop_id,
    COALESCE(s.name, 'Shop') AS shop_name,
    COALESCE(NULLIF(o.shop_phone, ''), COALESCE(s.phone, '')) AS shop_phone,
    COALESCE(o.shop_lat::double precision, ST_Y(s.location::geometry)) AS shop_lat,
    COALESCE(o.shop_lng::double precision, ST_X(s.location::geometry)) AS shop_lng,
    o.rider_name,
    o.rider_phone,
    COALESCE(o.is_admin_delivery, false) AS is_admin_delivery,
    o.arrived_at_shop_time,
    o.order_ready_time,
    o.shop_prep_time_snapshot,
    o.delivery_otp,
    o.created_at,
    (SELECT COUNT(*) FROM order_items oi WHERE oi.order_id = o.id) AS item_count
  FROM orders o
  JOIN shops s ON o.shop_id = s.id
  LEFT JOIN profiles p ON o.customer_id = p.id
  WHERE (
    (v_target_id IS NOT NULL AND o.delivery_partner_id = v_target_id)
    OR (v_target_id IS NULL AND o.is_admin_delivery = TRUE)
  )
  AND o.status IN (
    'awaiting_payment',
    'confirmed',
    'preparing',
    'ready_for_pickup',
    'picked_up',
    'out_for_delivery'
  )
  ORDER BY o.created_at DESC
  LIMIT 50;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_get_active_deliveries(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_active_deliveries(UUID) TO service_role;


-- =============================================================================
-- 8. FORTIFIED ADMIN MARK ARRIVED AT SHOP RPC (CLUSTERED SHOP STOP MATCHING)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.admin_mark_arrived_at_shop(p_order_id UUID)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cart_group_id UUID;
  v_shop_id UUID;
BEGIN
  IF NOT (
    public.is_super_admin(auth.uid()) 
    OR public.is_active_admin(auth.uid()) 
    OR public.has_permission(auth.uid(), 'dispatch.proxy_rider_accept')
  ) THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;

  SELECT cart_group_id, shop_id INTO v_cart_group_id, v_shop_id 
  FROM orders WHERE id = p_order_id;

  -- 100x Clustered Shop Stop Matching: mark arrival only for orders matching the same physical store
  UPDATE orders
  SET 
    arrived_at_shop_time = NOW(),
    updated_at = NOW()
  WHERE (
    id = p_order_id 
    OR (v_cart_group_id IS NOT NULL AND cart_group_id = v_cart_group_id AND shop_id = v_shop_id)
  )
  AND arrived_at_shop_time IS NULL;

  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_mark_arrived_at_shop(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_mark_arrived_at_shop(UUID) TO service_role;
