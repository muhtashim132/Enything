-- =============================================================================
-- Migration: 20290000000110_fix_demo_razorpay_phone_validation.sql
-- Description: Fix Razorpay phone number validation error for demo accounts.
--              Razorpay rejects '9999999999' as an invalid dummy Indian mobile number.
--              By maintaining profiles.phone as a valid-format 10-digit number ('+91987650000X')
--              while keeping orders.customer_phone as '+919999999999', Razorpay opens with
--              a valid pre-filled number with zero validation errors, while Flutter's
--              isOrderPlacedByDemo ('999999999') and demo simulation tools remain 100% active.
--              Real accounts are 100% unaffected.
-- =============================================================================

-- 1. Trigger function on public.profiles to normalize demo customer phone for Razorpay
CREATE OR REPLACE FUNCTION public.tr_demo_profile_phone_fix_fn()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_last_char text;
BEGIN
  IF NEW.phone LIKE '%999999999%' THEN
    v_last_char := RIGHT(NEW.phone, 1);
    IF v_last_char NOT BETWEEN '0' AND '9' THEN
      v_last_char := '9';
    END IF;
    NEW.phone := '+91987650000' || v_last_char;
  ELSIF NEW.id IN (
    '821a4442-34da-4032-b31c-bc5a8d0fa06f'::uuid,
    '00000000-0000-0000-0000-919999999999'::uuid
  ) THEN
    NEW.phone := '+919876500009';
  ELSIF NEW.id = '00000000-0000-0000-0000-919999999991'::uuid THEN
    NEW.phone := '+919876500001';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_demo_profile_phone_fix_tr ON public.profiles;
CREATE TRIGGER tr_demo_profile_phone_fix_tr
BEFORE INSERT OR UPDATE ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.tr_demo_profile_phone_fix_fn();

-- 2. Update tr_auto_accept_reviewer_orders_fn on public.orders
CREATE OR REPLACE FUNCTION public.tr_auto_accept_reviewer_orders_fn()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_demo_rider_id uuid;
  v_demo_rider_phone text;
  v_is_reviewer boolean := false;
BEGIN
  -- STRICT GUARD: ONLY demo reviewer accounts (999999999 or 987650000)
  IF COALESCE(NEW.customer_phone, '') LIKE '%999999999%' 
     OR COALESCE(NEW.customer_phone, '') LIKE '%987650000%' THEN
    v_is_reviewer := true;
  ELSIF NEW.customer_id IN (
    '821a4442-34da-4032-b31c-bc5a8d0fa06f'::uuid,
    '00000000-0000-0000-0000-919999999991'::uuid,
    '00000000-0000-0000-0000-919999999999'::uuid
  ) THEN
    v_is_reviewer := true;
  ELSIF NEW.customer_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.profiles 
    WHERE id = NEW.customer_id 
      AND (phone LIKE '%999999999%' OR phone LIKE '%987650000%')
  ) THEN
    v_is_reviewer := true;
  ELSIF NEW.customer_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM auth.users 
    WHERE id = NEW.customer_id 
      AND (
        email LIKE '%999999999%' 
        OR raw_user_meta_data->>'phone' LIKE '%999999999%'
        OR raw_user_meta_data->>'phone' LIKE '%987650000%'
      )
  ) THEN
    v_is_reviewer := true;
  END IF;

  -- If it's NOT a demo customer, exit immediately (normal order flow)
  IF NOT v_is_reviewer THEN
    RETURN NEW;
  END IF;

  -- CRITICAL: Always persist customer_phone on orders as '+919999999999'
  -- so Flutter's isOrderPlacedByDemo (orderPhone.contains('999999999')) evaluates to TRUE!
  NEW.customer_phone := '+919999999999';

  -- Find demo delivery partner
  SELECT id, phone INTO v_demo_rider_id, v_demo_rider_phone
  FROM public.delivery_partners
  WHERE (phone LIKE '%999999999%' OR phone LIKE '%987650000%') AND is_active = true
  LIMIT 1;

  IF v_demo_rider_id IS NULL THEN
    v_demo_rider_id := '821a4442-34da-4032-b31c-bc5a8d0fa06f';
    v_demo_rider_phone := '+919999999999';
  END IF;

  NEW.seller_accepted := true;
  NEW.partner_accepted := true;
  NEW.delivery_partner_id := COALESCE(NEW.delivery_partner_id, v_demo_rider_id);
  NEW.rider_phone := COALESCE(NEW.rider_phone, v_demo_rider_phone, '+919999999999');
  
  IF NEW.payment_method = 'cod' THEN
    NEW.status := 'confirmed';
    NEW.payment_status := 'captured';
  ELSE
    NEW.status := 'awaiting_payment';
    NEW.payment_deadline := (NOW() AT TIME ZONE 'utc') + INTERVAL '10 minutes';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_auto_accept_reviewer_orders ON public.orders;
CREATE TRIGGER tr_auto_accept_reviewer_orders
BEFORE INSERT ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.tr_auto_accept_reviewer_orders_fn();

-- 3. Update simulate_reviewer_order_acceptance
CREATE OR REPLACE FUNCTION public.simulate_reviewer_order_acceptance(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order RECORD;
  v_demo_rider_id uuid;
  v_demo_rider_phone text;
BEGIN
  SELECT o.id, o.status, o.customer_phone, o.customer_id, o.shop_id, o.cart_group_id, o.payment_status
  INTO v_order
  FROM public.orders o
  WHERE o.id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found');
  END IF;

  IF NOT (
    COALESCE(v_order.customer_phone, '') LIKE '%999999999%' 
    OR COALESCE(v_order.customer_phone, '') LIKE '%987650000%'
    OR v_order.customer_id IN (
      '821a4442-34da-4032-b31c-bc5a8d0fa06f'::uuid,
      '00000000-0000-0000-0000-919999999991'::uuid,
      '00000000-0000-0000-0000-919999999999'::uuid
    )
    OR EXISTS (
      SELECT 1 FROM public.profiles 
      WHERE id = auth.uid() AND (phone LIKE '%999999999%' OR phone LIKE '%987650000%')
    )
    OR EXISTS (
      SELECT 1 FROM auth.users 
      WHERE id = auth.uid() AND (
        email LIKE '%999999999%' 
        OR raw_user_meta_data->>'phone' LIKE '%999999999%'
        OR raw_user_meta_data->>'phone' LIKE '%987650000%'
      )
    )
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Demo simulator is only available for Apple Review demo accounts');
  END IF;

  IF v_order.status NOT IN ('awaiting_acceptance', 'pending') THEN
    RETURN jsonb_build_object('success', true, 'message', 'Order already accepted');
  END IF;

  SELECT id, phone INTO v_demo_rider_id, v_demo_rider_phone
  FROM public.delivery_partners
  WHERE (phone LIKE '%999999999%' OR phone LIKE '%987650000%') AND is_active = true
  LIMIT 1;

  IF v_demo_rider_id IS NULL THEN
    v_demo_rider_id := '821a4442-34da-4032-b31c-bc5a8d0fa06f';
    v_demo_rider_phone := '+919999999999';
  END IF;

  IF v_order.cart_group_id IS NOT NULL THEN
    UPDATE public.orders
    SET 
      customer_phone = '+919999999999',
      seller_accepted = true,
      partner_accepted = true,
      delivery_partner_id = v_demo_rider_id,
      rider_phone = v_demo_rider_phone,
      status = 'awaiting_payment',
      payment_deadline = (NOW() AT TIME ZONE 'utc') + INTERVAL '10 minutes',
      updated_at = NOW()
    WHERE cart_group_id = v_order.cart_group_id
      AND status IN ('awaiting_acceptance', 'pending');
  ELSE
    UPDATE public.orders
    SET 
      customer_phone = '+919999999999',
      seller_accepted = true,
      partner_accepted = true,
      delivery_partner_id = v_demo_rider_id,
      rider_phone = v_demo_rider_phone,
      status = 'awaiting_payment',
      payment_deadline = (NOW() AT TIME ZONE 'utc') + INTERVAL '10 minutes',
      updated_at = NOW()
    WHERE id = p_order_id
      AND status IN ('awaiting_acceptance', 'pending');
  END IF;

  RETURN jsonb_build_object('success', true, 'message', 'Order accepted by demo seller and rider');
END;
$$;

-- 4. Update simulate_reviewer_order_advance
CREATE OR REPLACE FUNCTION public.simulate_reviewer_order_advance(p_order_id uuid, p_target_status text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order RECORD;
BEGIN
  SELECT o.id, o.status, o.customer_phone, o.customer_id, o.shop_id, o.cart_group_id, o.shop_lat, o.shop_lng, o.delivery_lat, o.delivery_lng
  INTO v_order
  FROM public.orders o
  WHERE o.id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found');
  END IF;

  IF NOT (
    COALESCE(v_order.customer_phone, '') LIKE '%999999999%' 
    OR COALESCE(v_order.customer_phone, '') LIKE '%987650000%'
    OR v_order.customer_id IN (
      '821a4442-34da-4032-b31c-bc5a8d0fa06f'::uuid,
      '00000000-0000-0000-0000-919999999991'::uuid,
      '00000000-0000-0000-0000-919999999999'::uuid
    )
    OR EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND (phone LIKE '%999999999%' OR phone LIKE '%987650000%'))
    OR EXISTS (
      SELECT 1 FROM auth.users 
      WHERE id = auth.uid() AND (
        email LIKE '%999999999%' 
        OR raw_user_meta_data->>'phone' LIKE '%999999999%'
        OR raw_user_meta_data->>'phone' LIKE '%987650000%'
      )
    )
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Demo simulator is only available for Apple Review demo accounts');
  END IF;

  IF p_target_status = 'confirmed' THEN
    UPDATE public.orders
    SET status = 'confirmed', 
        payment_status = 'captured', 
        customer_phone = '+919999999999',
        seller_accepted = true,
        partner_accepted = true,
        updated_at = NOW()
    WHERE (id = p_order_id OR (cart_group_id IS NOT NULL AND cart_group_id = v_order.cart_group_id))
      AND status IN ('awaiting_payment', 'awaiting_acceptance', 'pending');

  ELSIF p_target_status = 'preparing' THEN
    UPDATE public.orders
    SET status = 'preparing', updated_at = NOW()
    WHERE (id = p_order_id OR (cart_group_id IS NOT NULL AND cart_group_id = v_order.cart_group_id))
      AND status = 'confirmed';

  ELSIF p_target_status = 'ready_for_pickup' THEN
    UPDATE public.orders
    SET status = 'ready_for_pickup', updated_at = NOW()
    WHERE (id = p_order_id OR (cart_group_id IS NOT NULL AND cart_group_id = v_order.cart_group_id))
      AND status IN ('confirmed', 'preparing');

  ELSIF p_target_status = 'out_for_delivery' THEN
    UPDATE public.orders
    SET status = 'out_for_delivery', 
        pickup_confirmed = true,
        dispatched_at = NOW(),
        updated_at = NOW()
    WHERE (id = p_order_id OR (cart_group_id IS NOT NULL AND cart_group_id = v_order.cart_group_id))
      AND status IN ('confirmed', 'preparing', 'ready_for_pickup');

  ELSIF p_target_status = 'delivered' THEN
    UPDATE public.orders
    SET status = 'delivered', 
        delivered_at = NOW(),
        updated_at = NOW()
    WHERE (id = p_order_id OR (cart_group_id IS NOT NULL AND cart_group_id = v_order.cart_group_id))
      AND status = 'out_for_delivery';
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'Unsupported target status: ' || p_target_status);
  END IF;

  RETURN jsonb_build_object(
    'success', true, 
    'order_id', p_order_id, 
    'status', p_target_status
  );
END;
$$;

-- 5. Apply phone update to active demo customer profiles
UPDATE public.profiles
SET phone = '+919876500009'
WHERE id = '821a4442-34da-4032-b31c-bc5a8d0fa06f'::uuid OR phone = '+919999999999';

UPDATE public.profiles
SET phone = '+919876500001'
WHERE id = '00000000-0000-0000-0000-919999999991'::uuid OR phone = '+919999999991';

UPDATE public.profiles
SET phone = '+919876500008'
WHERE id = '00000000-0000-0000-0000-919999999999'::uuid OR phone = '+919999999998';
