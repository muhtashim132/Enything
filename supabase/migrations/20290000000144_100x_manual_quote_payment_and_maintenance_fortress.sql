-- =============================================================================
-- Migration: 20290000000144_100x_manual_quote_payment_and_maintenance_fortress.sql
-- Description:
--   1. Fortifies orders_payment_method_check constraint to permit:
--      'cod', 'upi', 'offline', 'bank_transfer', 'cash'.
--   2. Fortifies orders_status_check constraint to include 'bulk_pending' and
--      all platform statuses.
--   3. Upgrades check_maintenance_mode_before_order() trigger to exempt:
--      - NEW.order_type = 'manual_quote'
--      - Super Admins and active admin users confirming quotes/fulfilling orders.
--   4. Fortifies public.admin_mark_quote_paid() RPC:
--      - Uses dynamic v_payment_method ('upi', 'bank_transfer', 'cash', 'offline')
--        instead of a hardcoded string.
--      - Idempotent and concurrency-locked.
--      - Updates quote_status = 'order_placed', links resulting_order_id,
--        and dispatches customer notification.
-- =============================================================================

-- ── 1. Update orders_payment_method_check ────────────────────────────────────
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_payment_method_check;
ALTER TABLE public.orders ADD CONSTRAINT orders_payment_method_check
  CHECK (payment_method = ANY (ARRAY[
    'cod'::text,
    'upi'::text,
    'offline'::text,
    'bank_transfer'::text,
    'cash'::text
  ]));

-- ── 2. Update orders_status_check (inclusive of bulk_pending) ────────────────
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
    'modification_proposed'::text,
    'shop_dispute_cancel'::text,
    'timeout'::text,
    'failed'::text,
    'returned'::text,
    'refunded'::text,
    'no_rider'::text
  ]));

-- ── 3. Upgrade check_maintenance_mode_before_order() ─────────────────────────
CREATE OR REPLACE FUNCTION check_maintenance_mode_before_order()
RETURNS TRIGGER AS $$
DECLARE
  v_enabled boolean := false;
  v_message text;
BEGIN
  -- 100x Fortress: Exempt manual quotes and admin users from maintenance mode
  IF NEW.order_type = 'manual_quote'
     OR (auth.uid() IS NOT NULL AND (
       public.is_super_admin(auth.uid()) 
       OR EXISTS (
         SELECT 1 FROM public.admin_users 
         WHERE id = auth.uid() AND is_active = true AND is_suspended IS DISTINCT FROM true
       )
     )) THEN
    RETURN NEW;
  END IF;

  -- Read the maintenance_mode flag safely from platform_config
  SELECT COALESCE(value #>> '{}' = 'true', false) INTO v_enabled
  FROM platform_config
  WHERE key = 'maintenance_mode';

  -- If maintenance mode is active, block customer orders
  IF COALESCE(v_enabled, false) THEN
    SELECT value #>> '{}' INTO v_message
    FROM platform_config
    WHERE key = 'maintenance_message';

    RAISE EXCEPTION 'MAINTENANCE_MODE_ACTIVE: %',
      COALESCE(v_message, 'Platform is temporarily under maintenance. Please try again later.')
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql STABLE;

-- ── 4. Fortify admin_mark_quote_paid RPC ─────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_mark_quote_paid(
  p_quote_id UUID,
  p_payment_method TEXT DEFAULT 'upi',
  p_payment_reference TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_quote RECORD;
  v_order_id UUID;
  v_delivery_otp TEXT;
  v_payment_method TEXT := lower(trim(COALESCE(p_payment_method, 'upi')));
BEGIN
  -- 1. Authorization check
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED: Must be logged in';
  END IF;

  IF NOT (
    public.is_super_admin(v_caller_id)
    OR EXISTS (
      SELECT 1 FROM public.admin_users 
      WHERE id = v_caller_id AND is_active = true AND is_suspended IS DISTINCT FROM true
    )
  ) THEN
    RAISE EXCEPTION 'UNAUTHORIZED: Admin privileges required to confirm payment';
  END IF;

  -- 2. Concurrency advisory lock per quote ID
  PERFORM pg_advisory_xact_lock(hashtext('manual_quote_' || p_quote_id::text));

  -- 3. Lock quote row
  SELECT * INTO v_quote
  FROM public.bulk_quote_requests
  WHERE id = p_quote_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'QUOTE_NOT_FOUND: Quote % does not exist', p_quote_id;
  END IF;

  -- Idempotency check: if order already created, return it cleanly
  IF v_quote.resulting_order_id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', true,
      'order_id', v_quote.resulting_order_id,
      'already_created', true,
      'message', 'Order already created for this quote'
    );
  END IF;

  IF v_quote.quote_status NOT IN ('customer_accepted', 'quoted') THEN
    RAISE EXCEPTION 'INVALID_STATE: Quote must be customer_accepted (current status: %)', v_quote.quote_status;
  END IF;

  IF v_payment_method NOT IN ('upi', 'bank_transfer', 'cash', 'offline') THEN
    v_payment_method := 'offline';
  END IF;

  -- 4. Generate 4-digit Delivery OTP
  v_delivery_otp := LPAD(FLOOR(random() * 9000 + 1000)::text, 4, '0');

  -- 5. Insert into public.orders (manual_quote, offline payment, captured)
  INSERT INTO public.orders (
    customer_id,
    shop_id,
    order_type,
    status,
    total_amount,
    delivery_charges,
    rider_earnings,
    platform_fee,
    small_cart_fee,
    heavy_order_fee,
    address,
    address_label,
    delivery_notes,
    customer_phone,
    shop_phone,
    payment_method,
    payment_status,
    seller_accepted,
    partner_accepted,
    delivery_lat,
    delivery_lng,
    gst_item_total,
    s9_5_gst_amount,
    non_food_gst_amount,
    gst_delivery,
    gst_platform,
    tcs_amount,
    tds_amount,
    enything_commission,
    seller_payout,
    gateway_deduction,
    grand_total_collected,
    delivery_otp,
    created_at,
    updated_at
  ) VALUES (
    v_quote.customer_id,
    v_quote.preferred_shop_id,
    'manual_quote',
    'bulk_pending',
    COALESCE(v_quote.quoted_amount, 0),
    0.0,
    0.0,
    0.0,
    0.0,
    0.0,
    COALESCE(v_quote.venue_address, 'Event Venue'),
    'Event Venue',
    v_quote.venue_delivery_notes,
    v_quote.customer_phone,
    NULL,
    v_payment_method,
    'captured',
    false,
    false,
    v_quote.venue_lat,
    v_quote.venue_lng,
    0.0,
    0.0,
    0.0,
    0.0,
    0.0,
    0.0,
    0.0,
    0.0,
    COALESCE(v_quote.quoted_amount, 0),
    0.0,
    COALESCE(v_quote.quoted_amount, 0),
    v_delivery_otp,
    now(),
    now()
  ) RETURNING id INTO v_order_id;

  -- 6. Insert into public.bulk_orders metadata
  INSERT INTO public.bulk_orders (
    order_id,
    event_name,
    event_date,
    delivery_time_slot_start,
    delivery_time_slot_end,
    venue_address,
    venue_delivery_notes,
    contact_person_name,
    contact_person_phone,
    secondary_contact_phone,
    gate_pass_instructions,
    delivery_method,
    seller_response_status,
    created_at,
    updated_at
  ) VALUES (
    v_order_id,
    v_quote.event_name,
    v_quote.event_date,
    (v_quote.event_date::text || ' 11:00:00+05:30')::timestamptz,
    (v_quote.event_date::text || ' 14:00:00+05:30')::timestamptz,
    v_quote.venue_address,
    v_quote.venue_delivery_notes,
    v_quote.contact_person_name,
    v_quote.contact_person_phone,
    v_quote.secondary_contact_phone,
    v_quote.gate_pass_instructions,
    'platform_fleet',
    'pending',
    now(),
    now()
  );

  -- 7. Update quote status to order_placed
  UPDATE public.bulk_quote_requests
  SET quote_status = 'order_placed',
      payment_method = v_payment_method,
      payment_reference = trim(p_payment_reference),
      payment_received_at = now(),
      payment_confirmed_by = v_caller_id,
      resulting_order_id = v_order_id
  WHERE id = p_quote_id;

  -- 8. Customer notification
  INSERT INTO public.notifications (user_id, notif_key, title, body, order_id, created_at)
  VALUES (
    v_quote.customer_id,
    'payment_confirmed_' || v_order_id::text,
    '💳 Payment Confirmed!',
    'Payment of ₹' || to_char(v_quote.quoted_amount, 'FM999,99,999') || ' received for ' || v_quote.event_name || '. Your catering order is now in preparation!',
    v_order_id,
    now()
  )
  ON CONFLICT (user_id, notif_key) DO NOTHING;

  RETURN jsonb_build_object(
    'success', true,
    'order_id', v_order_id,
    'quote_id', p_quote_id,
    'status', 'order_placed',
    'message', 'Payment confirmed and order placed successfully!'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_mark_quote_paid(UUID, TEXT, TEXT) TO authenticated;
