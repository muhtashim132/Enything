-- =============================================================================
-- Migration: 20290000000143_manual_quote_rpcs.sql
-- Description: Phase 1 Backend RPCs for Manual Quotation System (100x Offline Fortress)
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. submit_quote_request
-- Customer submits custom event catering requirements & phone number
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.submit_quote_request(
  p_data JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer_id UUID := auth.uid();
  v_customer_phone TEXT;
  v_customer_name TEXT;
  v_event_name TEXT;
  v_event_type TEXT;
  v_event_date DATE;
  v_guests INTEGER;
  v_requirements TEXT;
  v_dietary TEXT;
  v_venue_address TEXT;
  v_venue_lat DOUBLE PRECISION;
  v_venue_lng DOUBLE PRECISION;
  v_venue_notes TEXT;
  v_pref_time TEXT;
  v_contact_name TEXT;
  v_contact_phone TEXT;
  v_sec_phone TEXT;
  v_gate_pass TEXT;
  v_shop_id UUID;
  v_shop_name TEXT;
  v_active_count INTEGER;
  v_quote_id UUID;
  v_existing_id UUID;
BEGIN
  -- 1. Authentication check
  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED: Must be logged in to submit a quote request';
  END IF;

  -- 2. Extract & sanitize inputs
  v_customer_phone := trim(COALESCE(p_data->>'customer_phone', ''));
  v_customer_name  := trim(COALESCE(p_data->>'customer_name', ''));
  v_event_name     := trim(COALESCE(p_data->>'event_name', ''));
  v_event_type     := lower(trim(COALESCE(p_data->>'event_type', 'custom')));
  v_event_date     := (p_data->>'event_date')::date;
  v_guests         := COALESCE((p_data->>'estimated_guest_count')::int, 0);
  v_requirements   := trim(COALESCE(p_data->>'requirements_description', ''));
  v_dietary        := trim(COALESCE(p_data->>'dietary_preferences', ''));
  v_venue_address  := trim(COALESCE(p_data->>'venue_address', ''));
  v_venue_lat      := (p_data->>'venue_lat')::double precision;
  v_venue_lng      := (p_data->>'venue_lng')::double precision;
  v_venue_notes    := trim(COALESCE(p_data->>'venue_delivery_notes', ''));
  v_pref_time      := trim(COALESCE(p_data->>'preferred_delivery_time', ''));
  v_contact_name   := trim(COALESCE(p_data->>'contact_person_name', v_customer_name));
  v_contact_phone  := trim(COALESCE(p_data->>'contact_person_phone', v_customer_phone));
  v_sec_phone      := trim(COALESCE(p_data->>'secondary_contact_phone', ''));
  v_gate_pass      := trim(COALESCE(p_data->>'gate_pass_instructions', ''));
  v_shop_id        := (p_data->>'preferred_shop_id')::uuid;
  v_shop_name      := trim(COALESCE(p_data->>'preferred_shop_name', ''));

  -- Fallbacks for profile info
  IF v_customer_phone = '' THEN
    SELECT phone, full_name INTO v_customer_phone, v_customer_name
    FROM public.profiles WHERE id = v_customer_id;
  END IF;

  -- 3. Validation fortress
  IF v_customer_phone IS NULL OR length(v_customer_phone) < 8 THEN
    RAISE EXCEPTION 'INVALID_PHONE: A valid customer phone number is required';
  END IF;

  IF v_contact_phone IS NULL OR length(v_contact_phone) < 8 THEN
    v_contact_phone := v_customer_phone;
  END IF;

  IF v_contact_name IS NULL OR length(v_contact_name) < 2 THEN
    v_contact_name := COALESCE(v_customer_name, 'Guest Host');
  END IF;

  IF v_event_name = '' THEN
    RAISE EXCEPTION 'INVALID_EVENT_NAME: Event name is required';
  END IF;

  IF v_event_date IS NULL OR v_event_date <= CURRENT_DATE THEN
    RAISE EXCEPTION 'INVALID_EVENT_DATE: Event date must be at least 1 day in the future';
  END IF;

  IF v_guests <= 0 OR v_guests > 10000 THEN
    RAISE EXCEPTION 'INVALID_GUESTS: Guest count must be between 1 and 10,000';
  END IF;

  IF length(v_requirements) < 5 THEN
    RAISE EXCEPTION 'INVALID_REQUIREMENTS: Please describe your catering requirements (at least 5 characters)';
  END IF;

  IF v_event_type NOT IN ('birthday', 'wedding', 'corporate', 'house_party', 'religious', 'school_event', 'custom') THEN
    v_event_type := 'custom';
  END IF;

  -- 4. Rate limit check (max 5 active requests per customer)
  SELECT COUNT(*) INTO v_active_count
  FROM public.bulk_quote_requests
  WHERE customer_id = v_customer_id
    AND quote_status IN ('pending_review', 'quoted', 'customer_accepted');

  IF v_active_count >= 5 THEN
    RAISE EXCEPTION 'RATE_LIMIT_EXCEEDED: You have 5 active quote requests pending. Please wait for an existing quote to resolve.';
  END IF;

  -- 5. Anti-spam / duplicate submission guard (within last 10 minutes)
  SELECT id INTO v_existing_id
  FROM public.bulk_quote_requests
  WHERE customer_id = v_customer_id
    AND event_name = v_event_name
    AND event_date = v_event_date
    AND created_at > (now() - INTERVAL '10 minutes')
    AND quote_status != 'cancelled'
  LIMIT 1;

  IF v_existing_id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', true,
      'quote_id', v_existing_id,
      'is_duplicate', true,
      'message', 'Your request has already been received and our team will call you shortly.'
    );
  END IF;

  -- 6. Insert quote request
  INSERT INTO public.bulk_quote_requests (
    customer_id,
    customer_name,
    customer_phone,
    event_name,
    event_type,
    event_date,
    estimated_guest_count,
    dietary_preferences,
    requirements_description,
    venue_address,
    venue_lat,
    venue_lng,
    venue_delivery_notes,
    preferred_delivery_time,
    contact_person_name,
    contact_person_phone,
    secondary_contact_phone,
    gate_pass_instructions,
    preferred_shop_id,
    preferred_shop_name,
    quote_status,
    created_at,
    updated_at
  ) VALUES (
    v_customer_id,
    v_customer_name,
    v_customer_phone,
    v_event_name,
    v_event_type,
    v_event_date,
    v_guests,
    NULLIF(v_dietary, ''),
    v_requirements,
    NULLIF(v_venue_address, ''),
    v_venue_lat,
    v_venue_lng,
    NULLIF(v_venue_notes, ''),
    NULLIF(v_pref_time, ''),
    v_contact_name,
    v_contact_phone,
    NULLIF(v_sec_phone, ''),
    NULLIF(v_gate_pass, ''),
    v_shop_id,
    NULLIF(v_shop_name, ''),
    'pending_review',
    now(),
    now()
  ) RETURNING id INTO v_quote_id;

  -- 7. Notify all active admin users
  INSERT INTO public.notifications (user_id, notif_key, title, body, created_at)
  SELECT
    au.id,
    'quote_new_' || v_quote_id::text || '_' || au.id::text,
    '📋 New Catering Quote',
    COALESCE(v_customer_name, 'A customer') || ' requested catering for ' || v_guests || ' guests on ' || to_char(v_event_date, 'Mon DD, YYYY') || '. 📞 ' || v_customer_phone,
    now()
  FROM public.admin_users au
  WHERE au.is_active = true AND (au.is_suspended IS DISTINCT FROM true)
  ON CONFLICT (user_id, notif_key) DO NOTHING;

  RETURN jsonb_build_object(
    'success', true,
    'quote_id', v_quote_id,
    'message', 'Your catering quote request has been submitted. Our team will review and call you shortly.'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.submit_quote_request(JSONB) TO authenticated;


-- ─────────────────────────────────────────────────────────────────────────────
-- 2. admin_submit_quote
-- Admin sets the agreed price (after phone call with customer)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_submit_quote(
  p_quote_id UUID,
  p_quoted_amount NUMERIC,
  p_notes TEXT DEFAULT NULL,
  p_valid_hours INTEGER DEFAULT 48,
  p_line_items JSONB DEFAULT '[]'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_quote RECORD;
  v_valid_hours INTEGER := GREATEST(1, COALESCE(p_valid_hours, 48));
  v_valid_until TIMESTAMPTZ;
BEGIN
  -- 1. Authorization check
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED: Must be logged in';
  END IF;

  IF NOT (
    public.is_super_admin(v_caller_id)
    OR (SELECT is_active FROM public.admin_users WHERE id = v_caller_id AND is_active = true AND is_suspended IS DISTINCT FROM true)
  ) THEN
    RAISE EXCEPTION 'UNAUTHORIZED: Admin privileges required to price quote requests';
  END IF;

  -- 2. Sanity on price
  IF p_quoted_amount IS NULL OR p_quoted_amount <= 0 OR p_quoted_amount > 1000000.0 THEN
    RAISE EXCEPTION 'INVALID_AMOUNT: Quoted amount must be between ₹1 and ₹10,00,000';
  END IF;

  -- 3. Lock row and validate status
  SELECT * INTO v_quote
  FROM public.bulk_quote_requests
  WHERE id = p_quote_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'QUOTE_NOT_FOUND: Quote request % does not exist', p_quote_id;
  END IF;

  IF v_quote.quote_status NOT IN ('pending_review', 'quoted') THEN
    RAISE EXCEPTION 'INVALID_STATE: Quote is in status %, cannot re-quote', v_quote.quote_status;
  END IF;

  IF v_quote.event_date < CURRENT_DATE THEN
    RAISE EXCEPTION 'EVENT_PASSED: Cannot quote for an event date in the past';
  END IF;

  v_valid_until := now() + (v_valid_hours || ' hours')::interval;

  -- 4. Update quote
  UPDATE public.bulk_quote_requests
  SET quote_status = 'quoted',
      quoted_amount = ROUND(p_quoted_amount::numeric, 2),
      quoted_notes = trim(p_notes),
      quoted_valid_until = v_valid_until,
      quoted_line_items = COALESCE(p_line_items, '[]'::jsonb),
      reviewed_by = v_caller_id,
      reviewed_at = now()
  WHERE id = p_quote_id;

  -- 5. Notify customer
  INSERT INTO public.notifications (user_id, notif_key, title, body, created_at)
  VALUES (
    v_quote.customer_id,
    'quote_ready_' || p_quote_id::text || '_' || extract(epoch from now())::text,
    '🧾 Your Catering Quote is Ready!',
    '₹' || to_char(p_quoted_amount, 'FM999,99,999.00') || ' quoted for ' || v_quote.event_name || '. Tap to review and accept.',
    now()
  )
  ON CONFLICT (user_id, notif_key) DO NOTHING;

  RETURN jsonb_build_object(
    'success', true,
    'quote_id', p_quote_id,
    'quote_status', 'quoted',
    'quoted_amount', p_quoted_amount,
    'valid_until', v_valid_until
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_submit_quote(UUID, NUMERIC, TEXT, INTEGER, JSONB) TO authenticated;


-- ─────────────────────────────────────────────────────────────────────────────
-- 3. customer_respond_to_quote
-- Customer accepts or declines the quoted price in-app
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.customer_respond_to_quote(
  p_quote_id UUID,
  p_accept BOOLEAN,
  p_rejection_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer_id UUID := auth.uid();
  v_quote RECORD;
BEGIN
  -- 1. Authentication check
  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED: Must be logged in';
  END IF;

  -- 2. Lock quote row
  SELECT * INTO v_quote
  FROM public.bulk_quote_requests
  WHERE id = p_quote_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'QUOTE_NOT_FOUND: Quote % does not exist', p_quote_id;
  END IF;

  IF v_quote.customer_id != v_customer_id THEN
    RAISE EXCEPTION 'UNAUTHORIZED: You do not own this quote request';
  END IF;

  IF v_quote.quote_status != 'quoted' THEN
    RAISE EXCEPTION 'INVALID_STATE: Quote is currently in status %, not open for response', v_quote.quote_status;
  END IF;

  -- 3. Process acceptance or rejection
  IF p_accept IS TRUE THEN
    -- Expiry check
    IF v_quote.quoted_valid_until IS NOT NULL AND v_quote.quoted_valid_until < now() THEN
      UPDATE public.bulk_quote_requests SET quote_status = 'expired' WHERE id = p_quote_id;
      RAISE EXCEPTION 'QUOTE_EXPIRED: This quote has expired. Please submit a new request.';
    END IF;

    IF v_quote.event_date < CURRENT_DATE THEN
      RAISE EXCEPTION 'EVENT_PASSED: Event date has passed';
    END IF;

    UPDATE public.bulk_quote_requests
    SET quote_status = 'customer_accepted',
        customer_response_at = now()
    WHERE id = p_quote_id;

    -- Notify all active admins with customer's phone number for immediate callback!
    INSERT INTO public.notifications (user_id, notif_key, title, body, created_at)
    SELECT
      au.id,
      'quote_acc_' || p_quote_id::text || '_' || au.id::text,
      '✅ Quote Accepted! Call to arrange payment',
      COALESCE(v_quote.customer_name, 'Customer') || ' accepted ₹' || to_char(v_quote.quoted_amount, 'FM999,99,999') || ' for ' || v_quote.event_name || '. 📞 ' || v_quote.customer_phone,
      now()
    FROM public.admin_users au
    WHERE au.is_active = true AND (au.is_suspended IS DISTINCT FROM true)
    ON CONFLICT (user_id, notif_key) DO NOTHING;

    RETURN jsonb_build_object(
      'success', true,
      'quote_id', p_quote_id,
      'status', 'customer_accepted',
      'message', 'Quote accepted! Our team will call you shortly to arrange payment.'
    );
  ELSE
    -- Rejection
    UPDATE public.bulk_quote_requests
    SET quote_status = 'customer_rejected',
        customer_response_at = now(),
        customer_rejection_reason = trim(p_rejection_reason)
    WHERE id = p_quote_id;

    -- Notify admins
    INSERT INTO public.notifications (user_id, notif_key, title, body, created_at)
    SELECT
      au.id,
      'quote_rej_' || p_quote_id::text || '_' || au.id::text,
      '❌ Quote Declined',
      COALESCE(v_quote.customer_name, 'Customer') || ' declined quote for ' || v_quote.event_name || COALESCE(': ' || p_rejection_reason, ''),
      now()
    FROM public.admin_users au
    WHERE au.is_active = true AND (au.is_suspended IS DISTINCT FROM true)
    ON CONFLICT (user_id, notif_key) DO NOTHING;

    RETURN jsonb_build_object(
      'success', true,
      'quote_id', p_quote_id,
      'status', 'customer_rejected',
      'message', 'Quote declined.'
    );
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.customer_respond_to_quote(UUID, BOOLEAN, TEXT) TO authenticated;


-- ─────────────────────────────────────────────────────────────────────────────
-- 4. admin_mark_quote_paid
-- Admin confirms offline payment received (UPI/bank/cash) and creates order
-- ─────────────────────────────────────────────────────────────────────────────
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
    OR (SELECT is_active FROM public.admin_users WHERE id = v_caller_id AND is_active = true AND is_suspended IS DISTINCT FROM true)
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

  -- Idempotency check: if order already created, return it
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
    'offline',
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


-- ─────────────────────────────────────────────────────────────────────────────
-- 5. cancel_quote_request
-- Customer cancels quote request before payment
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.cancel_quote_request(
  p_quote_id UUID,
  p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer_id UUID := auth.uid();
  v_quote RECORD;
BEGIN
  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED: Must be logged in';
  END IF;

  SELECT * INTO v_quote
  FROM public.bulk_quote_requests
  WHERE id = p_quote_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'QUOTE_NOT_FOUND: Quote % does not exist', p_quote_id;
  END IF;

  IF v_quote.customer_id != v_customer_id AND NOT (
    public.is_super_admin(v_customer_id)
    OR (SELECT is_active FROM public.admin_users WHERE id = v_customer_id AND is_active = true)
  ) THEN
    RAISE EXCEPTION 'UNAUTHORIZED: You do not own this quote request';
  END IF;

  IF v_quote.quote_status NOT IN ('pending_review', 'quoted') THEN
    RAISE EXCEPTION 'INVALID_STATE: Cannot cancel quote in status %', v_quote.quote_status;
  END IF;

  UPDATE public.bulk_quote_requests
  SET quote_status = 'cancelled',
      customer_rejection_reason = trim(p_reason),
      customer_response_at = now()
  WHERE id = p_quote_id;

  -- Notify admins
  INSERT INTO public.notifications (user_id, notif_key, title, body, created_at)
  SELECT
    au.id,
    'quote_cancel_' || p_quote_id::text || '_' || au.id::text,
    '🚫 Quote Cancelled',
    COALESCE(v_quote.customer_name, 'Customer') || ' cancelled quote request for ' || v_quote.event_name,
    now()
  FROM public.admin_users au
  WHERE au.is_active = true AND (au.is_suspended IS DISTINCT FROM true)
  ON CONFLICT (user_id, notif_key) DO NOTHING;

  RETURN jsonb_build_object('success', true, 'status', 'cancelled');
END;
$$;

GRANT EXECUTE ON FUNCTION public.cancel_quote_request(UUID, TEXT) TO authenticated;


-- ─────────────────────────────────────────────────────────────────────────────
-- 6. admin_get_quote_requests
-- Admin feed query with status filtering & search
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_get_quote_requests(
  p_status_filter TEXT DEFAULT NULL
)
RETURNS TABLE (
  id UUID,
  customer_id UUID,
  customer_name TEXT,
  customer_phone TEXT,
  event_name TEXT,
  event_type TEXT,
  event_date DATE,
  estimated_guest_count INTEGER,
  dietary_preferences TEXT,
  requirements_description TEXT,
  venue_address TEXT,
  venue_lat DOUBLE PRECISION,
  venue_lng DOUBLE PRECISION,
  venue_delivery_notes TEXT,
  preferred_delivery_time TEXT,
  contact_person_name TEXT,
  contact_person_phone TEXT,
  secondary_contact_phone TEXT,
  gate_pass_instructions TEXT,
  preferred_shop_id UUID,
  preferred_shop_name TEXT,
  quote_status TEXT,
  reviewed_by UUID,
  reviewed_at TIMESTAMPTZ,
  quoted_amount NUMERIC,
  quoted_notes TEXT,
  quoted_valid_until TIMESTAMPTZ,
  quoted_line_items JSONB,
  customer_response_at TIMESTAMPTZ,
  customer_rejection_reason TEXT,
  payment_method TEXT,
  payment_reference TEXT,
  payment_received_at TIMESTAMPTZ,
  payment_confirmed_by UUID,
  resulting_order_id UUID,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
BEGIN
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'UNAUTHENTICATED: Must be logged in';
  END IF;

  IF NOT (
    public.is_super_admin(v_caller_id)
    OR (SELECT is_active FROM public.admin_users WHERE id = v_caller_id AND is_active = true AND is_suspended IS DISTINCT FROM true)
  ) THEN
    RAISE EXCEPTION 'UNAUTHORIZED: Admin privileges required';
  END IF;

  RETURN QUERY
  SELECT
    b.id,
    b.customer_id,
    b.customer_name,
    b.customer_phone,
    b.event_name,
    b.event_type,
    b.event_date,
    b.estimated_guest_count,
    b.dietary_preferences,
    b.requirements_description,
    b.venue_address,
    b.venue_lat,
    b.venue_lng,
    b.venue_delivery_notes,
    b.preferred_delivery_time,
    b.contact_person_name,
    b.contact_person_phone,
    b.secondary_contact_phone,
    b.gate_pass_instructions,
    b.preferred_shop_id,
    b.preferred_shop_name,
    b.quote_status,
    b.reviewed_by,
    b.reviewed_at,
    b.quoted_amount,
    b.quoted_notes,
    b.quoted_valid_until,
    b.quoted_line_items,
    b.customer_response_at,
    b.customer_rejection_reason,
    b.payment_method,
    b.payment_reference,
    b.payment_received_at,
    b.payment_confirmed_by,
    b.resulting_order_id,
    b.created_at,
    b.updated_at
  FROM public.bulk_quote_requests b
  WHERE (
    p_status_filter IS NULL 
    OR (p_status_filter = 'active' AND b.quote_status IN ('pending_review', 'quoted', 'customer_accepted'))
    OR (p_status_filter = 'pending' AND b.quote_status = 'pending_review')
    OR (p_status_filter = 'quoted' AND b.quote_status IN ('quoted', 'customer_accepted'))
    OR (p_status_filter = 'done' AND b.quote_status IN ('order_placed', 'customer_rejected', 'expired', 'cancelled'))
    OR (b.quote_status = p_status_filter)
  )
  ORDER BY b.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_get_quote_requests(TEXT) TO authenticated;
