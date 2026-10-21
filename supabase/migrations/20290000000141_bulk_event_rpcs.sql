-- =============================================================================
-- Migration: 20290000000141_bulk_event_rpcs.sql
-- Description: Phase 1 Backend RPCs & Logic for Bulk & Event Catering (100x Fortress)
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. get_bulk_slot_availability
-- Returns available item capacity for each time slot on a given date
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_bulk_slot_availability(
  p_shop_id UUID,
  p_date DATE
)
RETURNS TABLE (
  slot_start TIME,
  slot_end TIME,
  items_booked INTEGER,
  max_capacity INTEGER,
  available_capacity INTEGER,
  is_available BOOLEAN
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_shop RECORD;
  v_slot_duration INTERVAL;
  v_curr_start TIME;
  v_curr_end TIME;
  v_open_time TIME;
  v_close_time TIME;
  v_max_cap INTEGER;
BEGIN
  -- 1. Fetch shop configuration
  SELECT
    open_time,
    close_time,
    accepts_bulk_orders,
    COALESCE(max_bulk_items_per_slot, 200) AS max_bulk_items_per_slot,
    COALESCE(bulk_slot_duration_minutes, 60) AS bulk_slot_duration_minutes
  INTO v_shop
  FROM public.shops
  WHERE id = p_shop_id AND is_active = true;

  IF NOT FOUND OR COALESCE(v_shop.accepts_bulk_orders, false) = false THEN
    RETURN;
  END IF;

  v_open_time := COALESCE(v_shop.open_time::time, '09:00'::time);
  v_close_time := COALESCE(v_shop.close_time::time, '22:00'::time);
  v_slot_duration := (v_shop.bulk_slot_duration_minutes || ' minutes')::interval;
  v_max_cap := v_shop.max_bulk_items_per_slot;

  v_curr_start := v_open_time;

  -- 2. Iterate through slots from open to close
  WHILE v_curr_start < v_close_time LOOP
    v_curr_end := (v_curr_start::interval + v_slot_duration)::time;
    IF v_curr_end > v_close_time OR v_curr_end < v_curr_start THEN
      v_curr_end := v_close_time;
    END IF;

    -- Look up booked capacity in bulk_order_slots
    SELECT COALESCE(s.total_items_booked, 0), COALESCE(s.max_items_capacity, v_max_cap)
    INTO items_booked, max_capacity
    FROM public.bulk_order_slots s
    WHERE s.shop_id = p_shop_id
      AND s.slot_date = p_date
      AND s.slot_start = v_curr_start;

    IF NOT FOUND THEN
      items_booked := 0;
      max_capacity := v_max_cap;
    END IF;

    slot_start := v_curr_start;
    slot_end := v_curr_end;
    available_capacity := GREATEST(0, max_capacity - items_booked);
    is_available := (available_capacity > 0);

    RETURN NEXT;

    IF v_curr_end >= v_close_time THEN
      EXIT;
    END IF;

    v_curr_start := v_curr_end;
  END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_bulk_slot_availability(UUID, DATE) TO authenticated, anon;


-- ─────────────────────────────────────────────────────────────────────────────
-- 2. place_bulk_order_transaction
-- Completely separate from place_orders_transaction.
-- Handles slot capacity locking, tiered price calculation, GST/TCS/TDS freezing,
-- and inserts into orders + order_items + bulk_orders.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.place_bulk_order_transaction(
  p_order JSONB,
  p_items JSONB,
  p_event_metadata JSONB,
  p_idempotency_key TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer_id UUID := auth.uid();
  v_shop_id UUID;
  v_shop RECORD;
  v_order_id UUID;
  v_bulk_order_id UUID;

  v_event_date DATE;
  v_slot_start_ts TIMESTAMPTZ;
  v_slot_end_ts TIMESTAMPTZ;
  v_slot_start_time TIME;
  v_min_lead_hours INTEGER;
  v_max_lead_hours INTEGER;

  v_item RECORD;
  v_total_items_count INTEGER := 0;
  v_total_weight_kg NUMERIC(10,3) := 0;
  v_subtotal NUMERIC(10,2) := 0;
  v_line_price NUMERIC(10,2);
  v_db_product RECORD;
  v_matched_tier RECORD;

  v_slot_booked INTEGER := 0;
  v_max_capacity INTEGER := 200;

  -- Financial variables matching platform standards
  v_default_comm NUMERIC := 5.0;
  v_cat_comm NUMERIC;
  v_commission_rate NUMERIC;
  v_delivery_charges NUMERIC(10,2);
  v_platform_fee NUMERIC(10,2);
  v_heavy_order_fee NUMERIC(10,2) := 0;
  v_grand_total NUMERIC(10,2);

  v_s9_5_gst NUMERIC(10,2) := 0;
  v_non_food_gst NUMERIC(10,2) := 0;
  v_gst_delivery NUMERIC(10,2) := 0;
  v_gst_platform NUMERIC(10,2) := 0;
  v_tcs_amount NUMERIC(10,2) := 0;
  v_tds_amount NUMERIC(10,2) := 0;
  v_enything_commission NUMERIC(10,2) := 0;
  v_seller_payout NUMERIC(10,2) := 0;
  v_gateway_deduction NUMERIC(10,2) := 0;
  v_rider_earnings NUMERIC(10,2) := 0;

  v_delivery_otp TEXT;
  v_total_packages INTEGER := 1;
  v_estimated_batches INTEGER := 1;
BEGIN
  -- 1. Authentication Check
  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED: Authentication required to place bulk order';
  END IF;

  -- 2. Idempotency Check
  IF p_idempotency_key IS NOT NULL AND p_idempotency_key != '' THEN
    SELECT id INTO v_order_id
    FROM public.orders
    WHERE customer_id = v_customer_id
      AND (idempotency_key::text = p_idempotency_key OR razorpay_order_id = p_idempotency_key)
    LIMIT 1;

    IF v_order_id IS NOT NULL THEN
      SELECT id INTO v_bulk_order_id FROM public.bulk_orders WHERE order_id = v_order_id;
      RETURN jsonb_build_object(
        'success', true,
        'order_id', v_order_id,
        'bulk_order_id', v_bulk_order_id,
        'is_duplicate', true
      );
    END IF;
  END IF;

  -- 3. Shop Validation
  v_shop_id := (p_order->>'shop_id')::UUID;
  IF v_shop_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_SHOP: Shop ID is required';
  END IF;

  SELECT * INTO v_shop
  FROM public.shops
  WHERE id = v_shop_id AND is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'SHOP_INACTIVE: This shop is not active';
  END IF;

  IF COALESCE(v_shop.accepts_bulk_orders, false) = false THEN
    RAISE EXCEPTION 'SHOP_BULK_DISABLED: This shop does not accept bulk catering orders';
  END IF;

  v_min_lead_hours := COALESCE(v_shop.min_bulk_lead_time_hours, 6);
  v_max_lead_hours := COALESCE(v_shop.max_bulk_lead_time_hours, 72);
  v_max_capacity := COALESCE(v_shop.max_bulk_items_per_slot, 200);

  -- 4. Date & Slot Extraction & Lead Time Validation
  v_event_date := (p_event_metadata->>'event_date')::DATE;
  v_slot_start_ts := (p_event_metadata->>'delivery_time_slot_start')::TIMESTAMPTZ;
  v_slot_end_ts := (p_event_metadata->>'delivery_time_slot_end')::TIMESTAMPTZ;

  IF v_event_date IS NULL OR v_slot_start_ts IS NULL OR v_slot_end_ts IS NULL THEN
    RAISE EXCEPTION 'INVALID_EVENT_TIME: Event date and delivery slot window are required';
  END IF;

  v_slot_start_time := v_slot_start_ts::time;

  -- Lead time verification
  IF v_slot_start_ts < (now() + (v_min_lead_hours || ' hours')::interval) THEN
    RAISE EXCEPTION 'MIN_LEAD_TIME_VIOLATION: Minimum % hours advance notice required for this shop', v_min_lead_hours;
  END IF;

  IF v_slot_start_ts > (now() + (v_max_lead_hours || ' hours')::interval) THEN
    RAISE EXCEPTION 'MAX_LEAD_TIME_VIOLATION: Advance booking allowed up to % hours in advance', v_max_lead_hours;
  END IF;

  -- 5. Atomic Lock on Slot Capacity (Advisory lock prevents concurrent overbooking)
  PERFORM pg_advisory_xact_lock(hashtext(v_shop_id::text || v_event_date::text || v_slot_start_time::text));

  -- 6. Validate items, check bulk-eligibility & compute tiered pricing
  IF jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'EMPTY_ITEMS: At least one item is required for bulk order';
  END IF;

  FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) AS x(
    product_id UUID,
    product_name TEXT,
    quantity INTEGER,
    price NUMERIC,
    weight_kg NUMERIC,
    special_instructions TEXT
  ) LOOP
    IF v_item.quantity <= 0 THEN
      RAISE EXCEPTION 'INVALID_QUANTITY: Item quantity must be positive';
    END IF;

    -- Query product with mandatory soft-delete guard
    SELECT * INTO v_db_product
    FROM public.products
    WHERE id = v_item.product_id
      AND shop_id = v_shop_id
      AND is_deleted = false;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'PRODUCT_NOT_FOUND: Product % is not available or deleted', v_item.product_name;
    END IF;

    IF COALESCE(v_db_product.bulk_eligible, false) = false THEN
      RAISE EXCEPTION 'PRODUCT_NOT_BULK_ELIGIBLE: % is not available for bulk catering', v_db_product.name;
    END IF;

    IF v_item.quantity < COALESCE(v_db_product.min_bulk_quantity, 20) THEN
      RAISE EXCEPTION 'MIN_BULK_QUANTITY_NOT_MET: Minimum quantity for % is %',
        v_db_product.name, COALESCE(v_db_product.min_bulk_quantity, 20);
    END IF;

    -- Secure backend tiered pricing calculation
    v_line_price := v_db_product.price;
    IF v_db_product.bulk_price_tiers IS NOT NULL AND jsonb_array_length(v_db_product.bulk_price_tiers) > 0 THEN
      SELECT (tier->>'price')::numeric INTO v_line_price
      FROM jsonb_array_elements(v_db_product.bulk_price_tiers) AS tier
      WHERE v_item.quantity >= (tier->>'min_qty')::int
      ORDER BY (tier->>'min_qty')::int DESC
      LIMIT 1;

      IF v_line_price IS NULL THEN
        v_line_price := v_db_product.price;
      END IF;
    END IF;

    v_total_items_count := v_total_items_count + v_item.quantity;
    v_total_weight_kg := v_total_weight_kg + (COALESCE(v_db_product.weight_per_unit, 0.5) * v_item.quantity);
    v_subtotal := v_subtotal + (v_line_price * v_item.quantity);
  END LOOP;

  -- 7. Slot Capacity Check
  SELECT COALESCE(total_items_booked, 0) INTO v_slot_booked
  FROM public.bulk_order_slots
  WHERE shop_id = v_shop_id AND slot_date = v_event_date AND slot_start = v_slot_start_time;

  IF (v_slot_booked + v_total_items_count) > v_max_capacity THEN
    RAISE EXCEPTION 'KITCHEN_CAPACITY_EXCEEDED: Slot capacity exceeded. Available: % items, Requested: % items',
      GREATEST(0, v_max_capacity - v_slot_booked), v_total_items_count;
  END IF;

  -- 8. Platform Financials & Rates
  SELECT COALESCE((value->>'rate')::numeric, v_default_comm) INTO v_cat_comm
  FROM public.platform_config
  WHERE key = 'category_commissions_' || LOWER(COALESCE(v_shop.category, 'default'));

  v_commission_rate := COALESCE(v_cat_comm, v_default_comm);

  v_delivery_charges := COALESCE((p_order->>'delivery_charges')::numeric, 150.0);
  v_platform_fee := COALESCE((p_order->>'platform_fee')::numeric, 25.0);

  IF v_total_weight_kg > 15.0 THEN
    v_heavy_order_fee := ROUND(((v_total_weight_kg - 15.0) * 5.0)::numeric, 2);
  END IF;

  v_grand_total := v_subtotal + v_delivery_charges + v_platform_fee + v_heavy_order_fee;

  -- GST & Tax Snapshot (Frozen)
  v_s9_5_gst := ROUND((v_subtotal * 0.05)::numeric, 2);
  v_gst_delivery := ROUND((v_delivery_charges * 0.18)::numeric, 2);
  v_gst_platform := ROUND((v_platform_fee * 0.18)::numeric, 2);
  v_tcs_amount := ROUND((v_subtotal * 0.005)::numeric, 2);
  v_tds_amount := ROUND((v_subtotal * 0.001)::numeric, 2);

  v_enything_commission := ROUND((v_subtotal * (v_commission_rate / 100.0))::numeric, 2);
  v_gateway_deduction := ROUND((v_grand_total * 0.02)::numeric, 2);
  v_seller_payout := v_subtotal - v_enything_commission - v_tcs_amount - v_tds_amount;
  v_rider_earnings := ROUND((v_delivery_charges * 0.85)::numeric, 2);

  -- 9. Delivery OTP Generation (4 digits)
  v_delivery_otp := LPAD(FLOOR(random() * 9000 + 1000)::text, 4, '0');
  v_total_packages := GREATEST(1, COALESCE((p_event_metadata->>'total_packages_estimate')::int, CEIL(v_total_items_count / 30.0)::int));
  v_estimated_batches := GREATEST(1, CEIL(v_total_items_count / 50.0)::int);

  -- 10. Insert into public.orders
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
    shop_lat,
    shop_lng,
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
    v_customer_id,
    v_shop_id,
    'bulk',
    'bulk_pending',
    v_subtotal,
    v_delivery_charges,
    v_rider_earnings,
    v_platform_fee,
    0.0,
    v_heavy_order_fee,
    COALESCE(p_event_metadata->>'venue_address', p_order->>'address'),
    COALESCE(p_order->>'address_label', 'Event Venue'),
    p_event_metadata->>'venue_delivery_notes',
    COALESCE(p_event_metadata->>'contact_person_phone', p_order->>'customer_phone'),
    v_shop.address,
    'razorpay',
    'pending',
    false,
    false,
    (p_order->>'delivery_lat')::double precision,
    (p_order->>'delivery_lng')::double precision,
    ST_Y(v_shop.location::geometry),
    ST_X(v_shop.location::geometry),
    v_s9_5_gst,
    v_s9_5_gst,
    0.0,
    v_gst_delivery,
    v_gst_platform,
    v_tcs_amount,
    v_tds_amount,
    v_enything_commission,
    v_seller_payout,
    v_gateway_deduction,
    v_grand_total,
    v_delivery_otp,
    now(),
    now()
  ) RETURNING id INTO v_order_id;

  -- 11. Insert into public.order_items
  FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) AS x(
    product_id UUID,
    product_name TEXT,
    quantity INTEGER,
    price NUMERIC,
    weight_kg NUMERIC,
    special_instructions TEXT
  ) LOOP
    SELECT * INTO v_db_product FROM public.products WHERE id = v_item.product_id;

    -- Tiered price lookup
    v_line_price := v_db_product.price;
    IF v_db_product.bulk_price_tiers IS NOT NULL AND jsonb_array_length(v_db_product.bulk_price_tiers) > 0 THEN
      SELECT (tier->>'price')::numeric INTO v_line_price
      FROM jsonb_array_elements(v_db_product.bulk_price_tiers) AS tier
      WHERE v_item.quantity >= (tier->>'min_qty')::int
      ORDER BY (tier->>'min_qty')::int DESC
      LIMIT 1;

      IF v_line_price IS NULL THEN
        v_line_price := v_db_product.price;
      END IF;
    END IF;

    INSERT INTO public.order_items (
      order_id,
      product_id,
      product_name,
      quantity,
      price,
      weight_kg,
      special_instructions
    ) VALUES (
      v_order_id,
      v_item.product_id,
      v_db_product.name,
      v_item.quantity,
      v_line_price,
      COALESCE(v_db_product.weight_per_unit, 0.5) * v_item.quantity,
      v_item.special_instructions
    );
  END LOOP;

  -- 12. Insert into public.bulk_orders
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
    total_packages_estimate,
    vehicle_type_required,
    seller_response_status,
    total_batches,
    batches_packed,
    created_at,
    updated_at
  ) VALUES (
    v_order_id,
    p_event_metadata->>'event_name',
    v_event_date,
    v_slot_start_ts,
    v_slot_end_ts,
    p_event_metadata->>'venue_address',
    p_event_metadata->>'venue_delivery_notes',
    p_event_metadata->>'contact_person_name',
    p_event_metadata->>'contact_person_phone',
    p_event_metadata->>'secondary_contact_phone',
    p_event_metadata->>'gate_pass_instructions',
    COALESCE(p_event_metadata->>'delivery_method', 'platform_fleet'),
    v_total_packages,
    COALESCE(p_event_metadata->>'vehicle_type_required', 'any'),
    'pending',
    v_estimated_batches,
    0,
    now(),
    now()
  ) RETURNING id INTO v_bulk_order_id;

  -- 13. Upsert into public.bulk_order_slots
  INSERT INTO public.bulk_order_slots (
    shop_id,
    slot_date,
    slot_start,
    slot_end,
    total_items_booked,
    max_items_capacity
  ) VALUES (
    v_shop_id,
    v_event_date,
    v_slot_start_time,
    v_slot_end_ts::time,
    v_total_items_count,
    v_max_capacity
  )
  ON CONFLICT (shop_id, slot_date, slot_start)
  DO UPDATE SET
    total_items_booked = bulk_order_slots.total_items_booked + EXCLUDED.total_items_booked;

  RETURN jsonb_build_object(
    'success', true,
    'order_id', v_order_id,
    'bulk_order_id', v_bulk_order_id,
    'grand_total', v_grand_total,
    'delivery_otp', v_delivery_otp,
    'total_items', v_total_items_count,
    'total_batches', v_estimated_batches
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.place_bulk_order_transaction(JSONB, JSONB, JSONB, TEXT) TO authenticated;


-- ─────────────────────────────────────────────────────────────────────────────
-- 3. respond_bulk_order_seller
-- Seller accepts, declines, or proposes modification to a bulk order
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.respond_bulk_order_seller(
  p_order_id UUID,
  p_response TEXT,
  p_notes TEXT DEFAULT NULL,
  p_modification JSONB DEFAULT NULL,
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
  v_shop RECORD;
  v_slot_date DATE;
  v_slot_start TIME;
  v_total_items INTEGER;
BEGIN
  -- 1. Fetch order and bulk_order
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ORDER_NOT_FOUND: Order % does not exist', p_order_id;
  END IF;

  SELECT * INTO v_bulk FROM public.bulk_orders WHERE order_id = p_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'BULK_METADATA_NOT_FOUND: Bulk metadata missing for order %', p_order_id;
  END IF;

  -- 2. Validate seller ownership
  SELECT * INTO v_shop FROM public.shops WHERE id = v_order.shop_id;
  IF v_shop.seller_id != v_caller_id AND NOT EXISTS (
    SELECT 1 FROM public.admin_team_members WHERE user_id = v_caller_id
  ) THEN
    RAISE EXCEPTION 'UNAUTHORIZED: Only the shop owner or admin can respond to this bulk order';
  END IF;

  -- 3. Validate current status
  IF v_order.status != 'bulk_pending' AND v_order.status != 'modification_proposed' THEN
    RAISE EXCEPTION 'INVALID_STATE: Order is in status %, cannot change response', v_order.status;
  END IF;

  IF p_response NOT IN ('accepted', 'declined', 'modification_proposed') THEN
    RAISE EXCEPTION 'INVALID_RESPONSE: Response must be accepted, declined, or modification_proposed';
  END IF;

  -- 4. Process Response
  IF p_response = 'accepted' THEN
    UPDATE public.bulk_orders
    SET seller_response_status = 'accepted',
        seller_response_at = now(),
        seller_notes = COALESCE(p_notes, seller_notes),
        total_batches = COALESCE(p_total_batches, total_batches, 1),
        updated_at = now()
    WHERE order_id = p_order_id;

    UPDATE public.orders
    SET status = 'bulk_confirmed',
        seller_accepted = true,
        updated_at = now()
    WHERE id = p_order_id;

    RETURN jsonb_build_object('success', true, 'status', 'bulk_confirmed');

  ELSIF p_response = 'declined' THEN
    UPDATE public.bulk_orders
    SET seller_response_status = 'declined',
        seller_response_at = now(),
        seller_notes = COALESCE(p_notes, seller_notes),
        updated_at = now()
    WHERE order_id = p_order_id;

    UPDATE public.orders
    SET status = 'seller_rejected',
        rejection_message = COALESCE(p_notes, 'Declined by seller'),
        updated_at = now()
    WHERE id = p_order_id;

    -- Release slot capacity
    v_slot_date := v_bulk.event_date;
    v_slot_start := v_bulk.delivery_time_slot_start::time;

    SELECT COALESCE(SUM(quantity), 0) INTO v_total_items
    FROM public.order_items
    WHERE order_id = p_order_id;

    UPDATE public.bulk_order_slots
    SET total_items_booked = GREATEST(0, total_items_booked - v_total_items)
    WHERE shop_id = v_order.shop_id AND slot_date = v_slot_date AND slot_start = v_slot_start;

    RETURN jsonb_build_object('success', true, 'status', 'seller_rejected', 'released_items', v_total_items);

  ELSIF p_response = 'modification_proposed' THEN
    IF p_modification IS NULL THEN
      RAISE EXCEPTION 'MODIFICATION_PAYLOAD_REQUIRED: Proposed changes required for modification_proposed';
    END IF;

    UPDATE public.bulk_orders
    SET seller_response_status = 'modification_proposed',
        seller_response_at = now(),
        seller_notes = COALESCE(p_notes, seller_notes),
        seller_modification_proposal = p_modification,
        customer_modification_response = NULL,
        updated_at = now()
    WHERE order_id = p_order_id;

    UPDATE public.orders
    SET status = 'modification_proposed',
        updated_at = now()
    WHERE id = p_order_id;

    RETURN jsonb_build_object('success', true, 'status', 'modification_proposed');
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.respond_bulk_order_seller(UUID, TEXT, TEXT, JSONB, INTEGER) TO authenticated;


-- ─────────────────────────────────────────────────────────────────────────────
-- 4. respond_bulk_order_customer_modification
-- Customer accepts or rejects the seller's proposed modifications
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.respond_bulk_order_customer_modification(
  p_order_id UUID,
  p_accept BOOLEAN
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
  v_total_items INTEGER;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ORDER_NOT_FOUND: Order % does not exist', p_order_id;
  END IF;

  IF v_order.customer_id != v_caller_id THEN
    RAISE EXCEPTION 'UNAUTHORIZED: Only customer can respond to modification proposal';
  END IF;

  SELECT * INTO v_bulk FROM public.bulk_orders WHERE order_id = p_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'BULK_METADATA_NOT_FOUND: Bulk metadata missing';
  END IF;

  IF v_order.status != 'modification_proposed' THEN
    RAISE EXCEPTION 'INVALID_STATE: Order is not awaiting customer modification decision';
  END IF;

  IF p_accept = true THEN
    UPDATE public.bulk_orders
    SET customer_modification_response = 'accepted',
        seller_response_status = 'accepted',
        updated_at = now()
    WHERE order_id = p_order_id;

    UPDATE public.orders
    SET status = 'bulk_confirmed',
        seller_accepted = true,
        updated_at = now()
    WHERE id = p_order_id;

    RETURN jsonb_build_object('success', true, 'status', 'bulk_confirmed');
  ELSE
    UPDATE public.bulk_orders
    SET customer_modification_response = 'rejected',
        updated_at = now()
    WHERE order_id = p_order_id;

    UPDATE public.orders
    SET status = 'cancelled',
        cancelled_reason = 'Customer rejected proposed modification',
        updated_at = now()
    WHERE id = p_order_id;

    -- Release slot capacity
    SELECT COALESCE(SUM(quantity), 0) INTO v_total_items
    FROM public.order_items
    WHERE order_id = p_order_id;

    UPDATE public.bulk_order_slots
    SET total_items_booked = GREATEST(0, total_items_booked - v_total_items)
    WHERE shop_id = v_order.shop_id
      AND slot_date = v_bulk.event_date
      AND slot_start = v_bulk.delivery_time_slot_start::time;

    RETURN jsonb_build_object('success', true, 'status', 'cancelled', 'released_items', v_total_items);
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.respond_bulk_order_customer_modification(UUID, BOOLEAN) TO authenticated;


-- ─────────────────────────────────────────────────────────────────────────────
-- 5. cancel_bulk_order
-- Customer cancellation with tiered refund calculation
-- >24h = 100% refund; 6-24h = 50% refund; <6h = 0% refund (delivery fee refunded)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.cancel_bulk_order(
  p_order_id UUID,
  p_reason TEXT DEFAULT NULL
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
  v_hours_until_event NUMERIC;
  v_cancellation_tier TEXT;
  v_refund_percent NUMERIC := 0.0;
  v_item_total NUMERIC(10,2);
  v_delivery_charges NUMERIC(10,2);
  v_refund_amount NUMERIC(10,2);
  v_total_items INTEGER;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ORDER_NOT_FOUND: Order % does not exist', p_order_id;
  END IF;

  IF v_order.customer_id != v_caller_id AND NOT EXISTS (
    SELECT 1 FROM public.admin_team_members WHERE user_id = v_caller_id
  ) THEN
    RAISE EXCEPTION 'UNAUTHORIZED: Only customer or admin can cancel bulk order';
  END IF;

  SELECT * INTO v_bulk FROM public.bulk_orders WHERE order_id = p_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'BULK_METADATA_NOT_FOUND: Bulk metadata missing';
  END IF;

  -- Check terminal states
  IF v_order.status IN ('delivered', 'cancelled', 'seller_rejected', 'failed') THEN
    RAISE EXCEPTION 'ORDER_ALREADY_TERMINAL: Cannot cancel order in status %', v_order.status;
  END IF;

  -- Calculate hours until delivery slot
  v_hours_until_event := EXTRACT(EPOCH FROM (v_bulk.delivery_time_slot_start - now())) / 3600.0;

  IF v_hours_until_event > 24.0 THEN
    v_cancellation_tier := 'full_refund';
    v_refund_percent := 1.0;
  ELSIF v_hours_until_event >= 6.0 THEN
    v_cancellation_tier := 'half_refund';
    v_refund_percent := 0.5;
  ELSE
    v_cancellation_tier := 'no_refund';
    v_refund_percent := 0.0;
  END IF;

  v_item_total := v_order.total_amount;
  v_delivery_charges := v_order.delivery_charges;

  -- Delivery charges are always refunded on cancellation
  v_refund_amount := ROUND(((v_item_total * v_refund_percent) + v_delivery_charges)::numeric, 2);

  UPDATE public.bulk_orders
  SET cancellation_tier = v_cancellation_tier,
      updated_at = now()
  WHERE order_id = p_order_id;

  UPDATE public.orders
  SET status = 'cancelled',
      cancelled_reason = COALESCE(p_reason, 'Bulk order cancelled by customer (' || v_cancellation_tier || ')'),
      updated_at = now()
  WHERE id = p_order_id;

  -- Release slot capacity
  SELECT COALESCE(SUM(quantity), 0) INTO v_total_items
  FROM public.order_items
  WHERE order_id = p_order_id;

  UPDATE public.bulk_order_slots
  SET total_items_booked = GREATEST(0, total_items_booked - v_total_items)
  WHERE shop_id = v_order.shop_id
    AND slot_date = v_bulk.event_date
    AND slot_start = v_bulk.delivery_time_slot_start::time;

  RETURN jsonb_build_object(
    'success', true,
    'order_id', p_order_id,
    'cancellation_tier', v_cancellation_tier,
    'hours_until_event', ROUND(v_hours_until_event, 1),
    'refund_amount', v_refund_amount,
    'refund_percent', (v_refund_percent * 100),
    'released_items', v_total_items
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.cancel_bulk_order(UUID, TEXT) TO authenticated;


-- ─────────────────────────────────────────────────────────────────────────────
-- 6. update_bulk_batch_status
-- Seller marks preparation batches packed
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.update_bulk_batch_status(
  p_order_id UUID,
  p_batches_packed INTEGER
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
  v_shop RECORD;
  v_new_status TEXT;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ORDER_NOT_FOUND: Order % does not exist', p_order_id;
  END IF;

  SELECT * INTO v_shop FROM public.shops WHERE id = v_order.shop_id;
  IF v_shop.seller_id != v_caller_id AND NOT EXISTS (
    SELECT 1 FROM public.admin_team_members WHERE user_id = v_caller_id
  ) THEN
    RAISE EXCEPTION 'UNAUTHORIZED: Only shop owner or admin can update batch status';
  END IF;

  SELECT * INTO v_bulk FROM public.bulk_orders WHERE order_id = p_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'BULK_METADATA_NOT_FOUND: Bulk metadata missing';
  END IF;

  IF p_batches_packed < 0 OR p_batches_packed > v_bulk.total_batches THEN
    RAISE EXCEPTION 'INVALID_BATCH_COUNT: Batches packed must be between 0 and %', v_bulk.total_batches;
  END IF;

  UPDATE public.bulk_orders
  SET batches_packed = p_batches_packed,
      prep_started_at = CASE
        WHEN prep_started_at IS NULL AND p_batches_packed > 0 THEN now()
        ELSE prep_started_at
      END,
      all_batches_packed_at = CASE
        WHEN p_batches_packed >= v_bulk.total_batches THEN now()
        ELSE NULL
      END,
      updated_at = now()
  WHERE order_id = p_order_id;

  -- Advance order status based on packaging progress
  IF p_batches_packed >= v_bulk.total_batches THEN
    v_new_status := 'bulk_ready';
  ELSIF p_batches_packed > 0 AND v_order.status = 'bulk_confirmed' THEN
    v_new_status := 'bulk_preparing';
  ELSE
    v_new_status := v_order.status;
  END IF;

  IF v_new_status != v_order.status THEN
    UPDATE public.orders
    SET status = v_new_status,
        updated_at = now()
    WHERE id = p_order_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'batches_packed', p_batches_packed,
    'total_batches', v_bulk.total_batches,
    'order_status', v_new_status
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_bulk_batch_status(UUID, INTEGER) TO authenticated;


-- ─────────────────────────────────────────────────────────────────────────────
-- 7. bulk_assign_fleet
-- Admin or dispatcher assigns multi-rider fleet or vehicle to a bulk order
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.bulk_assign_fleet(
  p_order_id UUID,
  p_dispatch_type TEXT,
  p_rider_assignments JSONB DEFAULT '[]'::jsonb,
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
  v_assignment RECORD;
  v_riders_count INTEGER := 0;
BEGIN
  -- Admin authorization check
  IF NOT EXISTS (SELECT 1 FROM public.admin_team_members WHERE user_id = v_caller_id) THEN
    -- Check if seller doing merchant delivery
    SELECT * INTO v_order FROM public.orders o
    JOIN public.shops s ON o.shop_id = s.id
    WHERE o.id = p_order_id AND s.seller_id = v_caller_id;

    IF NOT FOUND OR p_dispatch_type != 'merchant_delivery' THEN
      RAISE EXCEPTION 'UNAUTHORIZED: Admin privilege required for fleet dispatch';
    END IF;
  END IF;

  -- Upsert bulk_dispatch_groups
  INSERT INTO public.bulk_dispatch_groups (
    order_id,
    dispatch_type,
    total_riders_needed,
    vehicle_type,
    vehicle_plate_number,
    driver_name,
    driver_phone,
    dispatch_status,
    created_at,
    updated_at
  ) VALUES (
    p_order_id,
    p_dispatch_type,
    GREATEST(1, jsonb_array_length(p_rider_assignments)),
    p_vehicle_details->>'vehicle_type',
    p_vehicle_details->>'vehicle_plate_number',
    p_vehicle_details->>'driver_name',
    p_vehicle_details->>'driver_phone',
    'riders_assigned',
    now(),
    now()
  )
  RETURNING id INTO v_group_id;

  -- Link to bulk_orders
  UPDATE public.bulk_orders
  SET bulk_dispatch_group_id = v_group_id,
      delivery_method = CASE
        WHEN p_dispatch_type = 'merchant_delivery' THEN 'merchant_delivery'
        ELSE 'platform_fleet'
      END,
      updated_at = now()
  WHERE order_id = p_order_id;

  -- Process Rider Assignments
  IF p_dispatch_type = 'multi_rider' AND jsonb_array_length(p_rider_assignments) > 0 THEN
    FOR v_assignment IN SELECT * FROM jsonb_to_recordset(p_rider_assignments) AS x(
      rider_id UUID,
      packages INTEGER
    ) LOOP
      INSERT INTO public.bulk_dispatch_riders (
        dispatch_group_id,
        rider_id,
        packages_assigned,
        status,
        assigned_at
      ) VALUES (
        v_group_id,
        v_assignment.rider_id,
        COALESCE(v_assignment.packages, 1),
        'assigned',
        now()
      )
      ON CONFLICT (dispatch_group_id, rider_id)
      DO UPDATE SET
        packages_assigned = EXCLUDED.packages_assigned,
        status = 'assigned';

      v_riders_count := v_riders_count + 1;
    END LOOP;

    UPDATE public.bulk_dispatch_groups
    SET riders_assigned = v_riders_count
    WHERE id = v_group_id;
  END IF;

  UPDATE public.orders
  SET status = 'bulk_dispatched',
      updated_at = now()
  WHERE id = p_order_id;

  RETURN jsonb_build_object(
    'success', true,
    'dispatch_group_id', v_group_id,
    'riders_assigned', v_riders_count,
    'status', 'bulk_dispatched'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.bulk_assign_fleet(UUID, TEXT, JSONB, JSONB) TO authenticated;


-- ─────────────────────────────────────────────────────────────────────────────
-- 8. rider_update_bulk_dispatch_status
-- Rider updates status of their assigned packages in bulk dispatch
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rider_update_bulk_dispatch_status(
  p_dispatch_group_id UUID,
  p_status TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_rider_assignment RECORD;
  v_group RECORD;
  v_all_delivered BOOLEAN;
  v_any_picked_up BOOLEAN;
BEGIN
  SELECT * INTO v_rider_assignment
  FROM public.bulk_dispatch_riders
  WHERE dispatch_group_id = p_dispatch_group_id AND rider_id = v_caller_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ASSIGNMENT_NOT_FOUND: No assignment found for caller in this dispatch group';
  END IF;

  IF p_status NOT IN ('picked_up', 'in_transit', 'delivered', 'dropped') THEN
    RAISE EXCEPTION 'INVALID_STATUS: Status must be picked_up, in_transit, delivered, or dropped';
  END IF;

  UPDATE public.bulk_dispatch_riders
  SET status = p_status
  WHERE dispatch_group_id = p_dispatch_group_id AND rider_id = v_caller_id;

  SELECT * INTO v_group FROM public.bulk_dispatch_groups WHERE id = p_dispatch_group_id;

  -- Check if all riders have delivered
  SELECT (COUNT(*) = COUNT(*) FILTER (WHERE status = 'delivered')) INTO v_all_delivered
  FROM public.bulk_dispatch_riders
  WHERE dispatch_group_id = p_dispatch_group_id AND status != 'dropped';

  -- Check if any picked up
  SELECT (COUNT(*) FILTER (WHERE status IN ('picked_up', 'in_transit', 'delivered')) > 0) INTO v_any_picked_up
  FROM public.bulk_dispatch_riders
  WHERE dispatch_group_id = p_dispatch_group_id;

  IF v_all_delivered = true THEN
    UPDATE public.bulk_dispatch_groups
    SET dispatch_status = 'delivered',
        delivered_at = now(),
        updated_at = now()
    WHERE id = p_dispatch_group_id;

    UPDATE public.orders
    SET status = 'delivered',
        updated_at = now()
    WHERE id = v_group.order_id;
  ELSIF v_any_picked_up = true AND v_group.dispatch_status != 'in_transit' THEN
    UPDATE public.bulk_dispatch_groups
    SET dispatch_status = 'in_transit',
        dispatched_at = COALESCE(dispatched_at, now()),
        updated_at = now()
    WHERE id = p_dispatch_group_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'status', p_status,
    'all_delivered', COALESCE(v_all_delivered, false)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rider_update_bulk_dispatch_status(UUID, TEXT) TO authenticated;
