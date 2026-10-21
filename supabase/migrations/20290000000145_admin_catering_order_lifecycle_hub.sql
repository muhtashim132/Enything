-- ============================================================================
-- Migration 20290000000145: 100x Admin Catering & Event Order Lifecycle Hub
--
-- Provides complete administrative command over Custom Event & Manual Quote
-- catering orders:
--   1. admin_appoint_catering_kitchen (Appoint restaurant/kitchen, auto-confirm)
--   2. admin_update_catering_packaging (Advance batches 0/1 -> 1/1, mark ready)
--   3. admin_dispatch_catering_order (Rider assignment OR Admin self-delivery)
--   4. admin_complete_catering_delivery (OTP verification & delivery completion)
-- ============================================================================

-- ── 1. admin_appoint_catering_kitchen ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_appoint_catering_kitchen(
  p_order_id UUID,
  p_shop_id UUID,
  p_auto_confirm BOOLEAN DEFAULT true,
  p_total_batches INTEGER DEFAULT 1
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_order RECORD;
  v_shop RECORD;
  v_bulk RECORD;
  v_new_status TEXT;
BEGIN
  -- 1. Authorization: Super Admin or Admin Team Member
  IF NOT (
    EXISTS (SELECT 1 FROM public.admin_team_members WHERE user_id = v_caller_id)
    OR EXISTS (SELECT 1 FROM public.profiles WHERE id = v_caller_id AND role IN ('super_admin', 'admin'))
  ) THEN
    RAISE EXCEPTION 'UNAUTHORIZED: Admin privileges required to appoint catering kitchen';
  END IF;

  -- 2. Validate Order
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ORDER_NOT_FOUND: Order % does not exist', p_order_id;
  END IF;

  -- 3. Validate Shop (enforce soft delete rule)
  SELECT * INTO v_shop FROM public.shops WHERE id = p_shop_id AND is_deleted = false;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'SHOP_NOT_FOUND: Active shop % does not exist', p_shop_id;
  END IF;

  -- 4. Determine status
  IF p_auto_confirm = true THEN
    v_new_status := 'bulk_confirmed';
  ELSE
    v_new_status := 'bulk_pending';
  END IF;

  -- 5. Update orders table
  UPDATE public.orders
  SET shop_id = p_shop_id,
      shop_phone = v_shop.phone,
      seller_accepted = p_auto_confirm,
      status = CASE
        WHEN status IN ('bulk_pending', 'pending', 'placed', 'awaiting_acceptance') THEN v_new_status
        ELSE status
      END,
      updated_at = now()
  WHERE id = p_order_id;

  -- 6. Upsert bulk_orders metadata record (self-healing for manual quote orders)
  INSERT INTO public.bulk_orders (
    order_id,
    event_name,
    event_date,
    total_batches,
    batches_packed,
    seller_response_status,
    seller_response_at,
    created_at,
    updated_at
  ) VALUES (
    p_order_id,
    COALESCE(v_order.address_label, 'Event Catering'),
    COALESCE(v_order.created_at::date, CURRENT_DATE),
    GREATEST(1, COALESCE(p_total_batches, 1)),
    0,
    CASE WHEN p_auto_confirm THEN 'accepted' ELSE 'pending' END,
    CASE WHEN p_auto_confirm THEN now() ELSE NULL END,
    now(),
    now()
  )
  ON CONFLICT (order_id) DO UPDATE
  SET total_batches = GREATEST(1, COALESCE(p_total_batches, bulk_orders.total_batches, 1)),
      seller_response_status = CASE WHEN p_auto_confirm THEN 'accepted' ELSE bulk_orders.seller_response_status END,
      seller_response_at = CASE WHEN p_auto_confirm THEN now() ELSE bulk_orders.seller_response_at END,
      updated_at = now();

  -- 7. Audit log
  INSERT INTO public.audit_logs (
    actor_id,
    action,
    target_type,
    target_id,
    metadata,
    created_at
  ) VALUES (
    v_caller_id,
    'admin_appoint_catering_kitchen',
    'orders',
    p_order_id,
    jsonb_build_object(
      'shop_id', p_shop_id,
      'shop_name', v_shop.name,
      'auto_confirm', p_auto_confirm,
      'status', v_new_status,
      'total_batches', p_total_batches
    ),
    now()
  );

  RETURN jsonb_build_object(
    'success', true,
    'order_id', p_order_id,
    'shop_id', p_shop_id,
    'shop_name', v_shop.name,
    'status', v_new_status,
    'auto_confirmed', p_auto_confirm
  );
END;
$$;

-- ── 2. admin_update_catering_packaging ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_update_catering_packaging(
  p_order_id UUID,
  p_batches_packed INTEGER,
  p_total_batches INTEGER DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_order RECORD;
  v_bulk RECORD;
  v_new_status TEXT;
  v_target_total INTEGER;
BEGIN
  -- 1. Authorization
  IF NOT (
    EXISTS (SELECT 1 FROM public.admin_team_members WHERE user_id = v_caller_id)
    OR EXISTS (SELECT 1 FROM public.profiles WHERE id = v_caller_id AND role IN ('super_admin', 'admin'))
  ) THEN
    -- Also allow the assigned shop's seller
    IF NOT EXISTS (
      SELECT 1 FROM public.orders o
      JOIN public.shops s ON o.shop_id = s.id
      WHERE o.id = p_order_id AND s.seller_id = v_caller_id
    ) THEN
      RAISE EXCEPTION 'UNAUTHORIZED: Only admin or assigned kitchen seller can update packaging';
    END IF;
  END IF;

  -- 2. Fetch order and bulk_orders
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ORDER_NOT_FOUND: Order % does not exist', p_order_id;
  END IF;

  SELECT * INTO v_bulk FROM public.bulk_orders WHERE order_id = p_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'BULK_METADATA_NOT_FOUND: Bulk metadata missing for order %', p_order_id;
  END IF;

  v_target_total := GREATEST(1, COALESCE(p_total_batches, v_bulk.total_batches, 1));

  IF p_batches_packed < 0 OR p_batches_packed > v_target_total THEN
    RAISE EXCEPTION 'INVALID_BATCH_COUNT: Batches packed must be between 0 and %', v_target_total;
  END IF;

  -- 3. Determine new status
  IF p_batches_packed >= v_target_total THEN
    v_new_status := 'bulk_ready';
  ELSIF p_batches_packed > 0 THEN
    v_new_status := 'bulk_preparing';
  ELSE
    v_new_status := CASE
      WHEN v_order.status = 'bulk_pending' THEN 'bulk_confirmed'
      ELSE v_order.status
    END;
  END IF;

  -- 4. Update bulk_orders
  UPDATE public.bulk_orders
  SET total_batches = v_target_total,
      batches_packed = p_batches_packed,
      prep_started_at = CASE
        WHEN prep_started_at IS NULL AND p_batches_packed > 0 THEN now()
        ELSE prep_started_at
      END,
      all_batches_packed_at = CASE
        WHEN p_batches_packed >= v_target_total THEN now()
        ELSE NULL
      END,
      updated_at = now()
  WHERE order_id = p_order_id;

  -- 5. Update orders table
  UPDATE public.orders
  SET status = v_new_status,
      updated_at = now()
  WHERE id = p_order_id;

  -- 6. Audit log
  INSERT INTO public.audit_logs (
    actor_id,
    action,
    target_type,
    target_id,
    metadata,
    created_at
  ) VALUES (
    v_caller_id,
    'admin_update_catering_packaging',
    'orders',
    p_order_id,
    jsonb_build_object(
      'batches_packed', p_batches_packed,
      'total_batches', v_target_total,
      'previous_status', v_order.status,
      'new_status', v_new_status
    ),
    now()
  );

  RETURN jsonb_build_object(
    'success', true,
    'order_id', p_order_id,
    'batches_packed', p_batches_packed,
    'total_batches', v_target_total,
    'status', v_new_status
  );
END;
$$;

-- ── 3. admin_dispatch_catering_order ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_dispatch_catering_order(
  p_order_id UUID,
  p_dispatch_type TEXT,
  p_rider_id UUID DEFAULT NULL,
  p_driver_name TEXT DEFAULT NULL,
  p_driver_phone TEXT DEFAULT NULL,
  p_vehicle_details JSONB DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_order RECORD;
  v_bulk RECORD;
  v_group_id UUID;
BEGIN
  -- 1. Authorization
  IF NOT (
    EXISTS (SELECT 1 FROM public.admin_team_members WHERE user_id = v_caller_id)
    OR EXISTS (SELECT 1 FROM public.profiles WHERE id = v_caller_id AND role IN ('super_admin', 'admin'))
  ) THEN
    RAISE EXCEPTION 'UNAUTHORIZED: Admin privileges required for fleet dispatch';
  END IF;

  -- 2. Fetch order and bulk
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ORDER_NOT_FOUND: Order % does not exist', p_order_id;
  END IF;

  IF v_order.status IN ('delivered', 'cancelled', 'seller_rejected') THEN
    RAISE EXCEPTION 'INVALID_STATE: Order is in terminal status %', v_order.status;
  END IF;

  -- 3. Upsert bulk_dispatch_groups
  INSERT INTO public.bulk_dispatch_groups (
    order_id,
    dispatch_type,
    total_riders_needed,
    riders_assigned,
    vehicle_type,
    vehicle_plate_number,
    driver_name,
    driver_phone,
    dispatch_status,
    dispatched_at,
    created_at,
    updated_at
  ) VALUES (
    p_order_id,
    CASE WHEN p_dispatch_type = 'admin_self_delivery' THEN 'merchant_delivery' ELSE 'multi_rider' END,
    1,
    CASE WHEN p_rider_id IS NOT NULL THEN 1 ELSE 0 END,
    p_vehicle_details->>'vehicle_type',
    p_vehicle_details->>'vehicle_plate_number',
    COALESCE(p_driver_name, CASE WHEN p_dispatch_type = 'admin_self_delivery' THEN 'In-House Team' ELSE 'Assigned Rider' END),
    p_driver_phone,
    'in_transit',
    now(),
    now(),
    now()
  )
  RETURNING id INTO v_group_id;

  -- 4. Handle Rider Assignment if specific rider selected
  IF p_dispatch_type = 'assign_rider' AND p_rider_id IS NOT NULL THEN
    INSERT INTO public.bulk_dispatch_riders (
      dispatch_group_id,
      rider_id,
      packages_assigned,
      status,
      assigned_at
    ) VALUES (
      v_group_id,
      p_rider_id,
      1,
      'in_transit',
      now()
    )
    ON CONFLICT (dispatch_group_id, rider_id) DO UPDATE
    SET status = 'in_transit';

    UPDATE public.orders
    SET delivery_partner_id = p_rider_id,
        partner_accepted = true,
        status = 'bulk_dispatched',
        updated_at = now()
    WHERE id = p_order_id;
  ELSE
    -- Admin self-delivery / in-house team
    UPDATE public.orders
    SET status = 'bulk_dispatched',
        partner_accepted = true,
        updated_at = now()
    WHERE id = p_order_id;
  END IF;

  -- 5. Update bulk_orders
  UPDATE public.bulk_orders
  SET bulk_dispatch_group_id = v_group_id,
      delivery_method = CASE WHEN p_dispatch_type = 'admin_self_delivery' THEN 'merchant_delivery' ELSE 'platform_fleet' END,
      updated_at = now()
  WHERE order_id = p_order_id;

  -- 6. Audit log
  INSERT INTO public.audit_logs (
    actor_id,
    action,
    target_type,
    target_id,
    metadata,
    created_at
  ) VALUES (
    v_caller_id,
    'admin_dispatch_catering_order',
    'orders',
    p_order_id,
    jsonb_build_object(
      'dispatch_type', p_dispatch_type,
      'rider_id', p_rider_id,
      'driver_name', p_driver_name,
      'dispatch_group_id', v_group_id
    ),
    now()
  );

  RETURN jsonb_build_object(
    'success', true,
    'order_id', p_order_id,
    'dispatch_group_id', v_group_id,
    'status', 'bulk_dispatched',
    'dispatch_type', p_dispatch_type
  );
END;
$$;

-- ── 4. admin_complete_catering_delivery ───────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_complete_catering_delivery(
  p_order_id UUID,
  p_otp TEXT DEFAULT NULL,
  p_admin_override BOOLEAN DEFAULT false
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_order RECORD;
  v_bulk RECORD;
BEGIN
  -- 1. Authorization
  IF NOT (
    EXISTS (SELECT 1 FROM public.admin_team_members WHERE user_id = v_caller_id)
    OR EXISTS (SELECT 1 FROM public.profiles WHERE id = v_caller_id AND role IN ('super_admin', 'admin'))
  ) THEN
    RAISE EXCEPTION 'UNAUTHORIZED: Admin privileges required to complete catering delivery';
  END IF;

  -- 2. Fetch order
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ORDER_NOT_FOUND: Order % does not exist', p_order_id;
  END IF;

  IF v_order.status = 'delivered' THEN
    RETURN jsonb_build_object('success', true, 'message', 'Order already delivered');
  END IF;

  -- 3. OTP verification (unless Super Admin override)
  IF NOT p_admin_override THEN
    IF v_order.delivery_otp IS NOT NULL AND v_order.delivery_otp != '' THEN
      IF p_otp IS NULL OR trim(p_otp) != trim(v_order.delivery_otp) THEN
        RAISE EXCEPTION 'INVALID_OTP: Entered OTP does not match customer delivery handover OTP';
      END IF;
    END IF;
  END IF;

  -- 4. Mark order delivered
  UPDATE public.orders
  SET status = 'delivered',
      updated_at = now()
  WHERE id = p_order_id;

  -- 5. Mark bulk_orders completed
  UPDATE public.bulk_orders
  SET updated_at = now()
  WHERE order_id = p_order_id;

  -- 6. Update dispatch group and riders if assigned
  SELECT * INTO v_bulk FROM public.bulk_orders WHERE order_id = p_order_id;
  IF v_bulk.bulk_dispatch_group_id IS NOT NULL THEN
    UPDATE public.bulk_dispatch_groups
    SET dispatch_status = 'delivered',
        delivered_at = now(),
        updated_at = now()
    WHERE id = v_bulk.bulk_dispatch_group_id;

    UPDATE public.bulk_dispatch_riders
    SET status = 'delivered'
    WHERE dispatch_group_id = v_bulk.bulk_dispatch_group_id;
  END IF;

  -- 7. Audit log
  INSERT INTO public.audit_logs (
    actor_id,
    action,
    target_type,
    target_id,
    metadata,
    created_at
  ) VALUES (
    v_caller_id,
    'admin_complete_catering_delivery',
    'orders',
    p_order_id,
    jsonb_build_object(
      'admin_override', p_admin_override,
      'otp_provided', p_otp IS NOT NULL
    ),
    now()
  );

  RETURN jsonb_build_object(
    'success', true,
    'order_id', p_order_id,
    'status', 'delivered'
  );
END;
$$;

-- Grant execution permissions
GRANT EXECUTE ON FUNCTION public.admin_appoint_catering_kitchen(UUID, UUID, BOOLEAN, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_catering_packaging(UUID, INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_dispatch_catering_order(UUID, TEXT, UUID, TEXT, TEXT, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_complete_catering_delivery(UUID, TEXT, BOOLEAN) TO authenticated;
