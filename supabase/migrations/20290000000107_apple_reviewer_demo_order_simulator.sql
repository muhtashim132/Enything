-- 20290000000107_apple_reviewer_demo_order_simulator.sql
-- Enables seamless demo order simulation exclusively for Apple App Review evaluation.

-- 0. Server-Side Instant Pre-Acceptance Trigger on orders INSERT
CREATE OR REPLACE FUNCTION public.tr_auto_accept_reviewer_orders_fn()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_demo_rider_id uuid;
  v_demo_rider_phone text;
  v_is_reviewer boolean := false;
BEGIN
  -- Check customer phone on the order
  IF COALESCE(NEW.customer_phone, '') LIKE '%999999999%' THEN
    v_is_reviewer := true;
  END IF;

  -- Check customer profile phone
  IF NOT v_is_reviewer AND NEW.customer_id IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM public.profiles WHERE id = NEW.customer_id AND phone LIKE '%999999999%') THEN
      v_is_reviewer := true;
    END IF;
  END IF;

  -- Check if order is from Apple Demo Store
  IF NOT v_is_reviewer AND NEW.shop_id IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM public.shops WHERE id = NEW.shop_id AND (phone LIKE '%999999999%' OR name ILIKE '%Apple Demo%')) THEN
      v_is_reviewer := true;
    END IF;
  END IF;

  -- If it's a reviewer/demo order, instantly pre-accept both merchant and rider!
  IF v_is_reviewer THEN
    -- Find demo delivery partner
    SELECT id, phone INTO v_demo_rider_id, v_demo_rider_phone
    FROM public.delivery_partners
    WHERE phone LIKE '%999999999%' AND is_active = true
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
    ELSE
      NEW.status := 'awaiting_payment';
      NEW.payment_deadline := (NOW() AT TIME ZONE 'utc') + INTERVAL '10 minutes';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_auto_accept_reviewer_orders ON public.orders;
CREATE TRIGGER tr_auto_accept_reviewer_orders
BEFORE INSERT ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.tr_auto_accept_reviewer_orders_fn();

-- 1. Function to simulate acceptance by both shop & rider
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
  -- 1. Fetch order
  SELECT o.id, o.status, o.customer_phone, o.customer_id, o.shop_id, o.cart_group_id, o.payment_status
  INTO v_order
  FROM public.orders o
  WHERE o.id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found');
  END IF;

  -- 2. Security Guard: Only allow if the customer or caller is a demo phone (999999999X) or demo shop
  IF NOT (
    COALESCE(v_order.customer_phone, '') LIKE '%999999999%' 
    OR EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND phone LIKE '%999999999%')
    OR EXISTS (SELECT 1 FROM public.shops WHERE id = v_order.shop_id AND (phone LIKE '%999999999%' OR name ILIKE '%Apple Demo%'))
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Demo simulator is only available for Apple Review accounts');
  END IF;

  -- 3. Only simulate if awaiting_acceptance or pending
  IF v_order.status NOT IN ('awaiting_acceptance', 'pending') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order is not awaiting acceptance');
  END IF;

  -- 4. Find demo delivery partner (prefer Apple Reviewer rider)
  SELECT id, phone INTO v_demo_rider_id, v_demo_rider_phone
  FROM public.delivery_partners
  WHERE phone LIKE '%999999999%' AND is_active = true
  LIMIT 1;

  IF v_demo_rider_id IS NULL THEN
    v_demo_rider_id := '821a4442-34da-4032-b31c-bc5a8d0fa06f';
    v_demo_rider_phone := '+919999999999';
  END IF;

  -- 5. Mark both seller & partner accepted, transition to awaiting_payment
  IF v_order.cart_group_id IS NOT NULL THEN
    UPDATE public.orders
    SET 
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

-- 2. Function to simulate subsequent delivery stages
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

  -- Security Guard
  IF NOT (
    COALESCE(v_order.customer_phone, '') LIKE '%999999999%' 
    OR EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND phone LIKE '%999999999%')
    OR EXISTS (SELECT 1 FROM public.shops WHERE id = v_order.shop_id AND (phone LIKE '%999999999%' OR name ILIKE '%Apple Demo%'))
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Demo simulator is only available for Apple Review accounts');
  END IF;

  -- State transitions
  IF p_target_status = 'confirmed' THEN
    UPDATE public.orders
    SET status = 'confirmed', payment_status = 'captured', updated_at = NOW()
    WHERE (id = p_order_id OR (cart_group_id IS NOT NULL AND cart_group_id = v_order.cart_group_id))
      AND status = 'awaiting_payment';

  ELSIF p_target_status = 'preparing' THEN
    UPDATE public.orders
    SET status = 'preparing', order_ready_time = (NOW() AT TIME ZONE 'utc') + INTERVAL '15 minutes', updated_at = NOW()
    WHERE (id = p_order_id OR (cart_group_id IS NOT NULL AND cart_group_id = v_order.cart_group_id))
      AND status = 'confirmed';

  ELSIF p_target_status = 'ready_for_pickup' THEN
    UPDATE public.orders
    SET status = 'ready_for_pickup', order_ready_time = NOW(), updated_at = NOW()
    WHERE (id = p_order_id OR (cart_group_id IS NOT NULL AND cart_group_id = v_order.cart_group_id))
      AND status IN ('confirmed', 'preparing');

  ELSIF p_target_status = 'out_for_delivery' THEN
    UPDATE public.orders
    SET status = 'out_for_delivery', 
        rider_lat = COALESCE(v_order.shop_lat, 34.4250),
        rider_lng = COALESCE(v_order.shop_lng, 74.6380),
        updated_at = NOW()
    WHERE (id = p_order_id OR (cart_group_id IS NOT NULL AND cart_group_id = v_order.cart_group_id))
      AND status IN ('confirmed', 'preparing', 'ready_for_pickup', 'picked_up');

  ELSIF p_target_status = 'delivered' THEN
    UPDATE public.orders
    SET status = 'delivered', 
        delivered_at = NOW(),
        updated_at = NOW()
    WHERE (id = p_order_id OR (cart_group_id IS NOT NULL AND cart_group_id = v_order.cart_group_id))
      AND status NOT IN ('delivered', 'cancelled');
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'Invalid target status');
  END IF;

  RETURN jsonb_build_object('success', true, 'status', p_target_status);
END;
$$;

GRANT EXECUTE ON FUNCTION public.simulate_reviewer_order_acceptance(uuid) TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.simulate_reviewer_order_advance(uuid, text) TO authenticated, anon, service_role;
