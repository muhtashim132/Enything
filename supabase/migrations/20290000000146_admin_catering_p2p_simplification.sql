-- ============================================================================
-- Migration 20290000000146: 100x Admin Catering P2P Simplification
--
-- Pure Direct Peer-to-Peer Model between Customer and Admin:
-- 0. Relax bulk_orders column nullability constraints.
-- 1. Fortify orders_status_check constraint to include all bulk_* statuses.
-- 2. Update validate_order_status_transition trigger to support bulk transitions.
-- 3. admin_appoint_catering_kitchen: Permits p_shop_id UUID DEFAULT NULL.
--    The admin can appoint ANY kitchen (external caterer, offline chef, banquet hall)
--    with a single tap without being forced to pick a registered app shop.
-- 4. admin_update_catering_packaging: Single-tap "Mark Food Ready" without micro-batches.
--    Self-heals bulk_orders metadata if missing.
-- 5. admin_dispatch_catering_order: Defaults to admin_self_delivery (In-House Team / Van)
--    with self-healing metadata.
-- 6. admin_complete_catering_delivery: Completes delivery via OTP or Super Admin Override.
-- ============================================================================

-- ── 0. Relax bulk_orders column nullability constraints ───────────────────────
ALTER TABLE public.bulk_orders ALTER COLUMN delivery_time_slot_start DROP NOT NULL;
ALTER TABLE public.bulk_orders ALTER COLUMN delivery_time_slot_end DROP NOT NULL;
ALTER TABLE public.bulk_orders ALTER COLUMN contact_person_name DROP NOT NULL;
ALTER TABLE public.bulk_orders ALTER COLUMN contact_person_phone DROP NOT NULL;

-- ── 1. Fortify orders_status_check constraint ─────────────────────────────────
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_status_check;
ALTER TABLE public.orders ADD CONSTRAINT orders_status_check
  CHECK (status = ANY (ARRAY[
    'awaiting_acceptance'::text,
    'awaiting_payment'::text,
    'pending'::text,
    'confirmed'::text,
    'preparing'::text,
    'ready_for_pickup'::text,
    'picked_up'::text,
    'out_for_delivery'::text,
    'delivered'::text,
    'cancelled'::text,
    'seller_rejected'::text,
    'partner_rejected'::text,
    'verification_failed'::text,
    'bulk_pending'::text,
    'bulk_confirmed'::text,
    'bulk_preparing'::text,
    'bulk_ready'::text,
    'bulk_dispatched'::text,
    'modification_proposed'::text,
    'shop_dispute_cancel'::text,
    'timeout'::text,
    'failed'::text,
    'returned'::text,
    'refunded'::text,
    'no_rider'::text
  ]));

-- ── 2. Update validate_order_status_transition for bulk lifecycle ────────────
CREATE OR REPLACE FUNCTION public.validate_order_status_transition()
RETURNS TRIGGER AS $$
BEGIN
    -- No restrictions on initial insertion (handled by RLS)
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
            IF NEW.status NOT IN ('pending', 'awaiting_payment', 'confirmed', 'seller_rejected', 'verification_failed', 'cancelled', 'timeout') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'pending' THEN
            IF NEW.status NOT IN ('confirmed', 'seller_rejected', 'verification_failed', 'cancelled', 'timeout', 'awaiting_acceptance', 'awaiting_payment') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'confirmed' THEN
            IF NEW.status NOT IN ('preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery', 'delivered', 'cancelled', 'seller_rejected', 'verification_failed') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'preparing' THEN
            IF NEW.status NOT IN ('ready_for_pickup', 'picked_up', 'out_for_delivery', 'delivered', 'cancelled', 'seller_rejected', 'verification_failed') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'ready_for_pickup' THEN
            IF NEW.status NOT IN ('picked_up', 'out_for_delivery', 'delivered', 'cancelled', 'seller_rejected') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'picked_up' THEN
            IF NEW.status NOT IN ('out_for_delivery', 'delivered', 'cancelled', 'shop_dispute') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'out_for_delivery' THEN
            IF NEW.status NOT IN ('delivered', 'cancelled', 'shop_dispute') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        WHEN 'shop_dispute' THEN
            IF NEW.status NOT IN ('cancelled', 'delivered', 'shop_dispute_cancel') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        -- Bulk & Custom Event Catering State Transitions
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
            IF NEW.status NOT IN ('delivered', 'cancelled') THEN
                RAISE EXCEPTION 'Invalid state transition from % to %', OLD.status, NEW.status;
            END IF;

        -- Terminal states cannot be changed
        WHEN 'delivered', 'cancelled', 'seller_rejected', 'verification_failed',
             'timeout', 'payment_failed', 'shop_dispute_cancel', 'no_rider',
             'partner_rejected', 'rider_rejected' THEN
            RAISE EXCEPTION 'Cannot change status of a terminal order (%) to %', OLD.status, NEW.status;

        ELSE
            RAISE EXCEPTION 'Unknown order status: %', OLD.status;
    END CASE;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ── 3. admin_appoint_catering_kitchen ─────────────────────────────────────────
DROP FUNCTION IF EXISTS public.admin_appoint_catering_kitchen(UUID, UUID, BOOLEAN, INTEGER);

CREATE OR REPLACE FUNCTION public.admin_appoint_catering_kitchen(
  p_order_id UUID,
  p_shop_id UUID DEFAULT NULL,
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
  v_new_status TEXT;
  v_shop_name TEXT := 'External / In-House Kitchen';
  v_shop_phone TEXT := NULL;
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

  -- 3. Validate Shop ONLY IF provided (otherwise offline/external kitchen is accepted)
  IF p_shop_id IS NOT NULL THEN
    SELECT * INTO v_shop FROM public.shops WHERE id = p_shop_id AND is_deleted = false;
    IF FOUND THEN
      v_shop_name := v_shop.name;
      v_shop_phone := v_shop.phone;
    ELSE
      v_shop_name := 'Partner Kitchen';
    END IF;
  END IF;

  -- 4. Determine new status
  IF p_auto_confirm = true THEN
    v_new_status := 'bulk_confirmed';
  ELSE
    v_new_status := 'bulk_pending';
  END IF;

  -- 5. Update orders table
  UPDATE public.orders
  SET shop_id = COALESCE(p_shop_id, shop_id),
      shop_phone = COALESCE(v_shop_phone, shop_phone),
      seller_accepted = p_auto_confirm,
      status = CASE
        WHEN status IN ('bulk_pending', 'pending', 'placed', 'awaiting_acceptance') THEN v_new_status
        ELSE status
      END,
      updated_at = now()
  WHERE id = p_order_id;

  -- 6. Upsert bulk_orders metadata record (self-healing)
  INSERT INTO public.bulk_orders (
    order_id,
    event_name,
    event_date,
    delivery_time_slot_start,
    delivery_time_slot_end,
    contact_person_name,
    contact_person_phone,
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
    now(),
    now() + interval '4 hours',
    'Customer',
    COALESCE(v_order.customer_phone, 'N/A'),
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
    actor_role,
    action,
    entity_type,
    entity_id,
    metadata,
    created_at
  ) VALUES (
    v_caller_id,
    'admin',
    'admin_appoint_catering_kitchen',
    'orders',
    p_order_id::text,
    jsonb_build_object(
      'shop_id', p_shop_id,
      'shop_name', v_shop_name,
      'auto_confirm', p_auto_confirm,
      'status', v_new_status,
      'total_batches', p_total_batches
    ),
    now()
  );

  -- 8. Customer & Admin Notifications
  BEGIN
    IF v_order.customer_id IS NOT NULL THEN
      INSERT INTO public.notifications (
        user_id,
        notif_key,
        title,
        body,
        order_id,
        created_at
      ) VALUES (
        v_order.customer_id,
        'bulk_kitchen_appointed_' || p_order_id::text,
        '👨‍🍳 Kitchen Confirmed & Cooking!',
        'Kitchen confirmed for your event "' || COALESCE(v_order.address_label, 'Catering') || '"! Chefs have begun preparing your dishes.',
        p_order_id,
        now()
      );
    END IF;

    IF v_caller_id IS NOT NULL THEN
      INSERT INTO public.notifications (
        user_id,
        notif_key,
        title,
        body,
        order_id,
        created_at
      ) VALUES (
        v_caller_id,
        'admin_kitchen_appointed_' || p_order_id::text,
        '👨‍🍳 Kitchen Appointed',
        'Kitchen appointed for Order #' || UPPER(SUBSTRING(p_order_id::text, 1, 8)) || '. Food preparation started.',
        p_order_id,
        now()
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN jsonb_build_object(
    'success', true,
    'order_id', p_order_id,
    'shop_id', p_shop_id,
    'shop_name', v_shop_name,
    'status', v_new_status,
    'auto_confirmed', p_auto_confirm
  );
END;
$$;

-- ── 4. admin_update_catering_packaging ────────────────────────────────────────
DROP FUNCTION IF EXISTS public.admin_update_catering_packaging(UUID, INTEGER, INTEGER);

CREATE OR REPLACE FUNCTION public.admin_update_catering_packaging(
  p_order_id UUID,
  p_batches_packed INTEGER DEFAULT 1,
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
  v_new_status TEXT;
  v_target_total INTEGER;
BEGIN
  -- 1. Authorization: Super Admin or Admin Team Member
  IF NOT (
    EXISTS (SELECT 1 FROM public.admin_team_members WHERE user_id = v_caller_id)
    OR EXISTS (SELECT 1 FROM public.profiles WHERE id = v_caller_id AND role IN ('super_admin', 'admin'))
  ) THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.orders o
      JOIN public.shops s ON o.shop_id = s.id
      WHERE o.id = p_order_id AND s.seller_id = v_caller_id
    ) THEN
      RAISE EXCEPTION 'UNAUTHORIZED: Admin privileges required to update food preparation';
    END IF;
  END IF;

  -- 2. Fetch order
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ORDER_NOT_FOUND: Order % does not exist', p_order_id;
  END IF;

  -- 3. Self-heal bulk_orders if missing
  INSERT INTO public.bulk_orders (
    order_id,
    event_name,
    event_date,
    delivery_time_slot_start,
    delivery_time_slot_end,
    contact_person_name,
    contact_person_phone,
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
    now(),
    now() + interval '4 hours',
    'Customer',
    COALESCE(v_order.customer_phone, 'N/A'),
    GREATEST(1, COALESCE(p_total_batches, 1)),
    0,
    'accepted',
    now(),
    now(),
    now()
  )
  ON CONFLICT (order_id) DO NOTHING;

  v_target_total := GREATEST(1, COALESCE(p_total_batches, 1));

  -- 4. Determine new status
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

  -- 5. Update bulk_orders
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

  -- 6. Update orders table
  UPDATE public.orders
  SET status = v_new_status,
      order_ready_time = CASE WHEN v_new_status = 'bulk_ready' THEN now() ELSE order_ready_time END,
      updated_at = now()
  WHERE id = p_order_id;

  -- 7. Audit log
  INSERT INTO public.audit_logs (
    actor_id,
    actor_role,
    action,
    entity_type,
    entity_id,
    metadata,
    created_at
  ) VALUES (
    v_caller_id,
    'admin',
    'admin_update_catering_packaging',
    'orders',
    p_order_id::text,
    jsonb_build_object(
      'batches_packed', p_batches_packed,
      'total_batches', v_target_total,
      'previous_status', v_order.status,
      'new_status', v_new_status
    ),
    now()
  );

  -- 8. Customer & Admin Notifications
  BEGIN
    IF v_order.customer_id IS NOT NULL AND v_new_status = 'bulk_ready' THEN
      INSERT INTO public.notifications (
        user_id,
        notif_key,
        title,
        body,
        order_id,
        created_at
      ) VALUES (
        v_order.customer_id,
        'bulk_food_ready_' || p_order_id::text,
        '🍱 All Food Prepared & Ready!',
        'Your event feast for "' || COALESCE(v_order.address_label, 'Catering') || '" is fully prepared and packed for venue transport.',
        p_order_id,
        now()
      );
    END IF;

    IF v_caller_id IS NOT NULL AND v_new_status = 'bulk_ready' THEN
      INSERT INTO public.notifications (
        user_id,
        notif_key,
        title,
        body,
        order_id,
        created_at
      ) VALUES (
        v_caller_id,
        'admin_food_ready_' || p_order_id::text,
        '🍱 Food Ready for Dispatch',
        'All food for Order #' || UPPER(SUBSTRING(p_order_id::text, 1, 8)) || ' is prepared and packed.',
        p_order_id,
        now()
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN jsonb_build_object(
    'success', true,
    'order_id', p_order_id,
    'batches_packed', p_batches_packed,
    'total_batches', v_target_total,
    'status', v_new_status
  );
END;
$$;

-- ── 5. admin_dispatch_catering_order ──────────────────────────────────────────
DROP FUNCTION IF EXISTS public.admin_dispatch_catering_order(UUID, TEXT, UUID, TEXT, TEXT, JSONB);

CREATE OR REPLACE FUNCTION public.admin_dispatch_catering_order(
  p_order_id UUID,
  p_dispatch_type TEXT DEFAULT 'admin_self_delivery',
  p_rider_id UUID DEFAULT NULL,
  p_driver_name TEXT DEFAULT 'In-House Team',
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
  v_group_id UUID;
BEGIN
  -- 1. Authorization
  IF NOT (
    EXISTS (SELECT 1 FROM public.admin_team_members WHERE user_id = v_caller_id)
    OR EXISTS (SELECT 1 FROM public.profiles WHERE id = v_caller_id AND role IN ('super_admin', 'admin'))
  ) THEN
    RAISE EXCEPTION 'UNAUTHORIZED: Admin privileges required for dispatch';
  END IF;

  -- 2. Fetch order
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
    COALESCE(p_driver_name, 'In-House Team'),
    p_driver_phone,
    'in_transit',
    now(),
    now(),
    now()
  )
  RETURNING id INTO v_group_id;

  -- 4. Rider assignment if selected, otherwise admin self-delivery
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
    UPDATE public.orders
    SET status = 'bulk_dispatched',
        partner_accepted = true,
        updated_at = now()
    WHERE id = p_order_id;
  END IF;

  -- 5. Self-heal and update bulk_orders
  INSERT INTO public.bulk_orders (
    order_id,
    event_name,
    event_date,
    delivery_time_slot_start,
    delivery_time_slot_end,
    contact_person_name,
    contact_person_phone,
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
    now(),
    now() + interval '4 hours',
    'Customer',
    COALESCE(v_order.customer_phone, 'N/A'),
    1,
    1,
    'accepted',
    now(),
    now(),
    now()
  )
  ON CONFLICT (order_id) DO NOTHING;

  UPDATE public.bulk_orders
  SET bulk_dispatch_group_id = v_group_id,
      delivery_method = CASE WHEN p_dispatch_type = 'admin_self_delivery' THEN 'merchant_delivery' ELSE 'platform_fleet' END,
      updated_at = now()
  WHERE order_id = p_order_id;

  -- 6. Audit log
  INSERT INTO public.audit_logs (
    actor_id,
    actor_role,
    action,
    entity_type,
    entity_id,
    metadata,
    created_at
  ) VALUES (
    v_caller_id,
    'admin',
    'admin_dispatch_catering_order',
    'orders',
    p_order_id::text,
    jsonb_build_object(
      'dispatch_type', p_dispatch_type,
      'rider_id', p_rider_id,
      'driver_name', p_driver_name,
      'dispatch_group_id', v_group_id
    ),
    now()
  );

  -- 7. Customer & Admin Notifications
  BEGIN
    IF v_order.customer_id IS NOT NULL THEN
      INSERT INTO public.notifications (
        user_id,
        notif_key,
        title,
        body,
        order_id,
        created_at
      ) VALUES (
        v_order.customer_id,
        'bulk_dispatched_' || p_order_id::text,
        '🚗 Feast Out for Delivery!',
        'In-house team is en route with your feast for "' || COALESCE(v_order.address_label, 'Catering') || '"! Handover OTP: ' || COALESCE(v_order.delivery_otp, 'N/A'),
        p_order_id,
        now()
      );
    END IF;

    IF v_caller_id IS NOT NULL THEN
      INSERT INTO public.notifications (
        user_id,
        notif_key,
        title,
        body,
        order_id,
        created_at
      ) VALUES (
        v_caller_id,
        'admin_dispatched_' || p_order_id::text,
        '🚗 Order Out for Delivery',
        'Order #' || UPPER(SUBSTRING(p_order_id::text, 1, 8)) || ' dispatched via in-house team.',
        p_order_id,
        now()
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN jsonb_build_object(
    'success', true,
    'order_id', p_order_id,
    'dispatch_group_id', v_group_id,
    'status', 'bulk_dispatched',
    'dispatch_type', p_dispatch_type
  );
END;
$$;

-- ── 6. admin_complete_catering_delivery ───────────────────────────────────────
DROP FUNCTION IF EXISTS public.admin_complete_catering_delivery(UUID, TEXT, BOOLEAN);

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
  IF FOUND AND v_bulk.bulk_dispatch_group_id IS NOT NULL THEN
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
    actor_role,
    action,
    entity_type,
    entity_id,
    metadata,
    created_at
  ) VALUES (
    v_caller_id,
    'admin',
    'admin_complete_catering_delivery',
    'orders',
    p_order_id::text,
    jsonb_build_object(
      'admin_override', p_admin_override,
      'otp_provided', p_otp IS NOT NULL
    ),
    now()
  );

  -- 8. Customer & Admin Notifications
  BEGIN
    IF v_order.customer_id IS NOT NULL THEN
      INSERT INTO public.notifications (
        user_id,
        notif_key,
        title,
        body,
        order_id,
        created_at
      ) VALUES (
        v_order.customer_id,
        'bulk_delivered_' || p_order_id::text,
        '🎉 Catering Feast Delivered!',
        'Delivery handover verified with OTP for "' || COALESCE(v_order.address_label, 'Catering') || '". Have a wonderful celebration!',
        p_order_id,
        now()
      );
    END IF;

    IF v_caller_id IS NOT NULL THEN
      INSERT INTO public.notifications (
        user_id,
        notif_key,
        title,
        body,
        order_id,
        created_at
      ) VALUES (
        v_caller_id,
        'admin_delivered_' || p_order_id::text,
        '🎉 Catering Order Completed',
        'Order #' || UPPER(SUBSTRING(p_order_id::text, 1, 8)) || ' delivery verified via OTP.',
        p_order_id,
        now()
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN jsonb_build_object(
    'success', true,
    'order_id', p_order_id,
    'status', 'delivered'
  );
END;
$$;

-- ── 7. Permissions ────────────────────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION public.admin_appoint_catering_kitchen(UUID, UUID, BOOLEAN, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_catering_packaging(UUID, INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_dispatch_catering_order(UUID, TEXT, UUID, TEXT, TEXT, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_complete_catering_delivery(UUID, TEXT, BOOLEAN) TO authenticated;
