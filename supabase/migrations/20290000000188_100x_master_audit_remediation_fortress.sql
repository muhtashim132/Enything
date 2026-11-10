-- ==============================================================================
-- 100x Master Forensic Audit Remediation Fortress Migration
-- File: 20290000000188_100x_master_audit_remediation_fortress.sql
--
-- DIRECTIVES ENFORCED:
-- 1. accept_order_seller: Advance to 'preparing' if payment captured (no status trapping)
-- 2. update_order_status: Wait-time penalty dispute immunity (wait_time_disputed = false)
-- 3. decline_order_items_seller: Synchronized advisory lock acquisition (deadlock elimination)
-- 4. customer_swap_order_item: Remove ancillary fee double-counting from authoritative grand total
-- 5. acknowledge_partial_rejection: Strict IDOR ownership check & 3m/10m deadline extensions
-- 6. admin_get_dispatch_feed: Return delivery_partner_id UUID in table projection
-- 7. admin_proxy_accept_seller: Atomic cart group advisory lock
-- 8. trg_sync_shop_hours: Synchronize is_manually_closed on explicit is_accepting_orders mutations
-- ==============================================================================

-- ── 1. Fortify accept_order_seller (Paid Order State Preservation) ─────────────
CREATE OR REPLACE FUNCTION public.accept_order_seller(p_order_id UUID)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
  v_payment_status text;
  v_shop_id uuid;
  v_seller_id uuid;
  v_partner_accepted boolean;
  v_delivery_partner_id uuid;
  v_cart_group_id uuid;
  v_all_siblings_accepted boolean := true;
  v_target_status text;
BEGIN
  -- Fetch cart_group_id first
  SELECT cart_group_id INTO v_cart_group_id FROM orders WHERE id = p_order_id;

  -- Acquire unified transaction advisory lock
  IF v_cart_group_id IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(hashtext('cart_group_' || v_cart_group_id::text));
    PERFORM id FROM orders WHERE cart_group_id = v_cart_group_id ORDER BY id FOR UPDATE;
  ELSE
    PERFORM id FROM orders WHERE id = p_order_id FOR UPDATE;
  END IF;

  -- Verify order exists and lock row
  SELECT status, payment_status, shop_id, partner_accepted, delivery_partner_id, cart_group_id
  INTO v_status, v_payment_status, v_shop_id, v_partner_accepted, v_delivery_partner_id, v_cart_group_id
  FROM orders WHERE id = p_order_id FOR UPDATE;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  -- Authorization check
  SELECT seller_id INTO v_seller_id FROM shops WHERE id = v_shop_id;
  IF v_seller_id != auth.uid() AND NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: Only the shop owner can accept this order';
  END IF;

  -- Shop active verification
  IF EXISTS (
    SELECT 1 FROM shops 
    WHERE id = v_shop_id 
      AND (is_active = false OR (verification_status IS NOT NULL AND verification_status NOT IN ('verified', 'approved')))
  ) THEN
    RAISE EXCEPTION 'SHOP_SUSPENDED: This shop is suspended or unverified and cannot accept orders.';
  END IF;

  IF v_status = 'cancelled' THEN
    RAISE EXCEPTION 'ORDER_CANCELLED';
  END IF;

  IF v_status != 'awaiting_acceptance' AND v_status != 'pending' THEN
    RAISE EXCEPTION 'Invalid state transition from %', v_status;
  END IF;

  -- Compute correct target status: If customer already paid online, advance to 'preparing'!
  v_target_status := CASE WHEN v_payment_status = 'captured' THEN 'preparing' ELSE 'awaiting_payment' END;

  -- Mark this specific order as seller_accepted = true
  UPDATE orders
  SET seller_accepted = true, updated_at = NOW()
  WHERE id = p_order_id;

  -- In a multi-shop cart group, inspect all sibling active orders
  IF v_cart_group_id IS NOT NULL THEN
    -- Check if any sibling active shop has NOT accepted yet
    SELECT EXISTS (
      SELECT 1 FROM orders
      WHERE cart_group_id = v_cart_group_id
        AND id != p_order_id
        AND status NOT IN (
          'cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected',
          'verification_failed', 'shop_dispute_cancel', 'timeout', 'failed', 'returned', 'refunded'
        )
        AND seller_accepted = false
    ) INTO v_all_siblings_accepted;
    
    -- If any active sibling is unaccepted, v_all_siblings_accepted becomes false
    v_all_siblings_accepted := NOT v_all_siblings_accepted;

    -- If a rider is assigned AND ALL active shops have accepted:
    IF (v_partner_accepted = true OR v_delivery_partner_id IS NOT NULL) AND v_all_siblings_accepted THEN
      UPDATE orders
      SET 
        status = v_target_status,
        payment_deadline = CASE WHEN v_payment_status = 'captured' THEN payment_deadline ELSE (now() AT TIME ZONE 'utc') + interval '10 minutes' END,
        updated_at = NOW()
      WHERE cart_group_id = v_cart_group_id
        AND status IN ('awaiting_acceptance', 'pending');
      RETURN true;
    END IF;
  ELSE
    -- Single-shop order: advance if rider has accepted
    IF v_partner_accepted = true OR v_delivery_partner_id IS NOT NULL THEN
      UPDATE orders
      SET 
        status = v_target_status,
        payment_deadline = CASE WHEN v_payment_status = 'captured' THEN payment_deadline ELSE (now() AT TIME ZONE 'utc') + interval '10 minutes' END,
        updated_at = NOW()
      WHERE id = p_order_id;
      RETURN true;
    END IF;
  END IF;

  RETURN false;
END;
$$;

GRANT EXECUTE ON FUNCTION public.accept_order_seller(UUID) TO authenticated;


-- ── 2. Fortify update_order_status with Wait-Time Dispute Immunity ────────────
CREATE OR REPLACE FUNCTION public.update_order_status(
    p_order_id uuid, 
    p_new_status text, 
    p_ready_time timestamptz DEFAULT NULL, 
    p_wait_penalty numeric DEFAULT 0,
    p_rider_lat numeric DEFAULT NULL,
    p_rider_lng numeric DEFAULT NULL,
    p_delivery_otp text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_status text;
  v_shop_id uuid;
  v_seller_id uuid;
  v_rider_id uuid;
  v_arrived_at_shop_time timestamptz;
  v_shop_prep_time_snapshot int;
  v_seller_payout numeric;
  v_calculated_wait_penalty numeric := 0;
  v_actual_ready_time timestamptz;
  v_wait_mins numeric;
  v_shop_category text;
  v_wait_penalty_rate numeric;
  v_customer_lat numeric;
  v_customer_lng numeric;
  v_distance_to_customer numeric;
  v_delivery_otp text;
  v_wait_time_disputed boolean;
BEGIN
  -- Strict row locking with wait_time_disputed selection
  SELECT status, shop_id, delivery_partner_id, arrived_at_shop_time, shop_prep_time_snapshot, seller_payout, delivery_otp, COALESCE(wait_time_disputed, false)
  INTO v_current_status, v_shop_id, v_rider_id, v_arrived_at_shop_time, v_shop_prep_time_snapshot, v_seller_payout, v_delivery_otp, v_wait_time_disputed
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF p_new_status NOT IN ('preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery', 'delivered') THEN
    RAISE EXCEPTION 'Invalid status for this RPC: %', p_new_status;
  END IF;

  IF p_new_status IN ('preparing', 'ready_for_pickup') THEN
    SELECT seller_id INTO v_seller_id FROM shops WHERE id = v_shop_id;
    IF (auth.uid() IS NULL OR v_seller_id IS DISTINCT FROM auth.uid()) AND NOT public.is_active_admin(auth.uid()) THEN
      RAISE EXCEPTION 'Unauthorized: Only the shop owner can mark preparing or ready for pickup';
    END IF;
  ELSIF p_new_status IN ('picked_up', 'out_for_delivery', 'delivered') THEN
    IF (auth.uid() IS NULL OR v_rider_id IS DISTINCT FROM auth.uid()) AND NOT public.is_active_admin(auth.uid()) THEN
      RAISE EXCEPTION 'Unauthorized: Only the assigned delivery partner can update delivery progress';
    END IF;

    IF p_new_status = 'delivered' THEN
        IF p_delivery_otp IS NULL OR trim(p_delivery_otp) = '' THEN
            RAISE EXCEPTION 'OTP_REQUIRED: A valid 4-digit customer delivery OTP is mandatory to complete delivery.';
        END IF;

        IF v_delivery_otp IS NOT NULL AND v_delivery_otp != trim(p_delivery_otp) THEN
            RAISE EXCEPTION 'INVALID_OTP: The delivery OTP provided does not match customer verification token.';
        END IF;

        IF NOT public.is_active_admin(auth.uid()) THEN
            IF p_rider_lat IS NOT NULL AND p_rider_lng IS NOT NULL THEN
                SELECT delivery_lat, delivery_lng INTO v_customer_lat, v_customer_lng FROM orders WHERE id = p_order_id;
                IF v_customer_lat IS NOT NULL AND v_customer_lng IS NOT NULL THEN
                    v_distance_to_customer := ST_Distance(
                        ST_SetSRID(ST_MakePoint(p_rider_lng, p_rider_lat), 4326)::geography,
                        ST_SetSRID(ST_MakePoint(v_customer_lng, v_customer_lat), 4326)::geography
                    );
                    IF v_distance_to_customer > 500 THEN
                        RAISE EXCEPTION 'GEO_FENCE_FAILED: Rider is % meters away from destination. Must be within 500m.', round(v_distance_to_customer::numeric, 1);
                    END IF;
                END IF;
            ELSE
                RAISE EXCEPTION 'GEO_FENCE_FAILED: Rider GPS coordinates are required to mark delivered.';
            END IF;
        END IF;
    END IF;
  END IF;

  IF (p_new_status = 'ready_for_pickup' OR p_new_status = 'picked_up') AND (v_current_status != 'ready_for_pickup') THEN
    v_actual_ready_time := now() AT TIME ZONE 'utc';
    
    -- 100x FORENSIC IMMUNITY: Suppress wait-time penalty if wait time was disputed!
    IF v_arrived_at_shop_time IS NOT NULL AND v_wait_time_disputed = false THEN
      v_wait_mins := (EXTRACT(EPOCH FROM (v_actual_ready_time - v_arrived_at_shop_time)) / 60.0)::numeric;
      IF v_wait_mins > COALESCE(v_shop_prep_time_snapshot, 0) THEN
        SELECT category INTO v_shop_category FROM shops WHERE id = v_shop_id;
        BEGIN
          SELECT value::numeric INTO v_wait_penalty_rate FROM platform_config WHERE key = 'wait_penalty_per_min_' || v_shop_category;
        EXCEPTION WHEN OTHERS THEN 
          v_wait_penalty_rate := NULL; 
        END;

        IF v_wait_penalty_rate IS NULL THEN
          BEGIN
            SELECT value::numeric INTO v_wait_penalty_rate FROM platform_config WHERE key = 'wait_penalty_per_min';
          EXCEPTION WHEN OTHERS THEN 
            v_wait_penalty_rate := 2.0; 
          END;
        END IF;

        IF v_wait_penalty_rate IS NULL THEN
          v_wait_penalty_rate := 2.0;
        END IF;

        v_calculated_wait_penalty := ROUND(GREATEST(0::numeric, (v_wait_mins - COALESCE(v_shop_prep_time_snapshot, 0)::numeric)) * v_wait_penalty_rate, 2);
        
        IF v_calculated_wait_penalty > COALESCE(v_seller_payout, 0) THEN
          v_calculated_wait_penalty := COALESCE(v_seller_payout, 0);
        END IF;
      END IF;
    ELSE
      v_calculated_wait_penalty := 0.0;
    END IF;

    UPDATE orders
    SET 
      status = p_new_status,
      order_ready_time = v_actual_ready_time,
      wait_time_penalty = v_calculated_wait_penalty,
      updated_at = NOW()
    WHERE id = p_order_id;
  ELSE
    UPDATE orders
    SET 
      status = p_new_status,
      updated_at = NOW()
    WHERE id = p_order_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_order_status(uuid, text, timestamptz, numeric, numeric, numeric, text) TO authenticated, service_role;


-- ── 3. Fortify decline_order_items_seller (Deadlock Elimination) ──────────────
CREATE OR REPLACE FUNCTION public.decline_order_items_seller(
  p_order_id UUID,
  p_declined_item_ids UUID[],
  p_declined_reason TEXT DEFAULT 'out_of_stock'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cart_group_id UUID;
  v_order RECORD;
  v_seller_id UUID;
  v_shop_id UUID;
  v_status TEXT;
  v_payment_status TEXT;
  v_active_items_count INT;
  v_declined_target_count INT;
  v_declined_prod_ids UUID[];

  v_item RECORD;
  v_new_active_subtotal NUMERIC := 0.0;
  v_new_s9_5 NUMERIC := 0.0;
  v_new_non_food_gst NUMERIC := 0.0;
  v_new_gst_item_total NUMERIC := 0.0;
  v_new_enything_commission NUMERIC := 0.0;
  v_new_tcs NUMERIC := 0.0;
  v_new_tds NUMERIC := 0.0;
  v_new_seller_payout NUMERIC := 0.0;
  v_authoritative_grand_total NUMERIC := 0.0;
  v_pending_refund NUMERIC := 0.0;

  v_shop_cat TEXT;
  v_is_food BOOLEAN := false;
  v_gst_rate NUMERIC := 0.0;
  v_comm_rate NUMERIC := 5.0;
  v_comm_key TEXT;
  v_comm_val NUMERIC;
  v_item_subtotal NUMERIC;
  v_item_gst NUMERIC;
  v_item_comm NUMERIC;
BEGIN
  IF p_declined_item_ids IS NULL OR array_length(p_declined_item_ids, 1) = 0 THEN
    RAISE EXCEPTION 'No item IDs provided to decline';
  END IF;

  -- 100x DEADLOCK SHIELD:
  -- Read cart_group_id UNLOCKED first, then acquire transaction advisory lock
  -- BEFORE any row-level locks, matching customer_swap_order_item lock order exactly!
  SELECT cart_group_id, shop_id INTO v_cart_group_id, v_shop_id FROM orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF v_cart_group_id IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(hashtext('cart_group_' || v_cart_group_id::text));
    PERFORM id FROM orders WHERE cart_group_id = v_cart_group_id ORDER BY id FOR UPDATE;
  ELSE
    PERFORM id FROM orders WHERE id = p_order_id FOR UPDATE;
  END IF;

  -- Re-fetch full order row inside lock
  SELECT * INTO v_order FROM orders WHERE id = p_order_id FOR UPDATE;
  v_status := v_order.status;
  v_payment_status := v_order.payment_status;

  SELECT seller_id INTO v_seller_id FROM shops WHERE id = v_order.shop_id;
  IF v_seller_id IS NULL OR (v_seller_id IS DISTINCT FROM auth.uid() AND NOT public.is_active_admin(auth.uid())) THEN
    RAISE EXCEPTION 'Unauthorized: Only the shop owner or admin can decline items';
  END IF;

  IF v_status NOT IN ('awaiting_acceptance', 'awaiting_payment', 'pending', 'confirmed', 'preparing') THEN
    RAISE EXCEPTION 'Order cannot have items declined at status "%"', v_status;
  END IF;

  PERFORM id FROM order_items WHERE order_id = p_order_id ORDER BY id FOR UPDATE;

  SELECT COUNT(*) INTO v_active_items_count
  FROM order_items
  WHERE order_id = p_order_id AND status = 'active';

  SELECT COUNT(*), array_agg(DISTINCT product_id)
  INTO v_declined_target_count, v_declined_prod_ids
  FROM order_items
  WHERE order_id = p_order_id 
    AND id = ANY(p_declined_item_ids) 
    AND status = 'active';

  IF v_declined_target_count = 0 THEN
    RETURN jsonb_build_object(
      'success', true,
      'order_id', p_order_id,
      'declined_count', 0,
      'message', 'Items were already declined or not found'
    );
  END IF;

  -- Mark line items as declined
  UPDATE order_items
  SET 
    status = 'declined',
    declined_reason = p_declined_reason
  WHERE order_id = p_order_id
    AND id = ANY(p_declined_item_ids)
    AND status = 'active';

  -- Soft-delete inviolability: mark declined products out of stock
  IF v_declined_prod_ids IS NOT NULL AND array_length(v_declined_prod_ids, 1) > 0 THEN
    UPDATE products
    SET 
      is_available = false,
      total_quantity = 0,
      updated_at = NOW()
    WHERE id = ANY(v_declined_prod_ids)
      AND is_deleted = false;
  END IF;

  -- Determine shop category for GST / Commission
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

  -- Line-item recalculation of surviving active items
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

  -- Authoritative grand total: delivery_charges already embeds small_cart, heavy_order, and surcharge!
  v_authoritative_grand_total := GREATEST(0,
    v_new_active_subtotal
    + v_new_gst_item_total
    + COALESCE(v_order.platform_fee, 0)
    + COALESCE(v_order.delivery_charges, 0)
    - LEAST(COALESCE(v_order.coupon_discount, 0), v_new_active_subtotal)
  );

  IF v_payment_status = 'captured' THEN
    v_pending_refund := GREATEST(0.0,
      (COALESCE(v_order.grand_total_collected, 0) - v_authoritative_grand_total)
      - COALESCE(v_order.total_refunded, 0)
    );
  ELSE
    v_pending_refund := 0.0;
  END IF;

  UPDATE orders
  SET 
    total_amount = v_new_active_subtotal,
    grand_total = v_authoritative_grand_total,
    s9_5_gst_amount = v_new_s9_5,
    non_food_gst_amount = v_new_non_food_gst,
    total_gst_amount = v_new_gst_item_total,
    enything_commission = v_new_enything_commission,
    tcs_amount = v_new_tcs,
    tds_amount = v_new_tds,
    seller_payout = v_new_seller_payout,
    pending_refund_amount = v_pending_refund,
    refund_status = CASE 
      WHEN v_payment_status = 'captured' AND v_pending_refund > 0.01 THEN 'pending_customer_decision'
      ELSE refund_status
    END,
    updated_at = NOW()
  WHERE id = p_order_id;

  -- Rebalance delivery fees across cart group if applicable
  IF v_cart_group_id IS NOT NULL THEN
    PERFORM public.rebalance_active_delivery_fees(v_cart_group_id);
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'order_id', p_order_id,
    'declined_count', v_declined_target_count,
    'new_subtotal', v_new_active_subtotal,
    'new_grand_total', v_authoritative_grand_total,
    'pending_refund_amount', v_pending_refund
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.decline_order_items_seller(UUID, UUID[], TEXT) TO authenticated;


-- ── 4. Fortify customer_swap_order_item (Fee Double-Counting Fix) ─────────────
CREATE OR REPLACE FUNCTION public.customer_swap_order_item(
  p_order_id UUID,
  p_declined_item_id UUID,
  p_replacement_product_id UUID,
  p_replacement_variant_name TEXT DEFAULT NULL,
  p_quantity INT DEFAULT 1
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_order record;
  v_declined_item record;
  v_prod record;
  v_variant_price numeric;
  v_replacement_price numeric;
  v_price_delta numeric;
  v_new_item_id uuid := gen_random_uuid();
  v_old_item_subtotal numeric;
  v_new_item_subtotal numeric;
  v_new_active_subtotal numeric;
  v_clean_unit text;
  v_replacement_unit_weight_kg numeric;
  v_order_total_weight_kg numeric;
  v_group_total_weight_kg numeric;

  v_shop_cat text;
  v_is_food boolean := false;
  v_gst_rate numeric := 0.0;
  v_comm_rate numeric := 5.0;
  v_comm_key text;
  v_comm_val numeric;

  v_new_s9_5 numeric := 0.0;
  v_new_non_food_gst numeric := 0.0;
  v_new_gst_item_total numeric := 0.0;
  v_new_enything_commission numeric := 0.0;
  v_new_tcs numeric := 0.0;
  v_new_tds numeric := 0.0;
  v_new_seller_payout numeric := 0.0;

  v_item_subtotal numeric;
  v_item_gst numeric;
  v_item_comm numeric;

  v_authoritative_grand_total numeric;
  v_pending_refund numeric := 0.0;
  oi_rec record;
BEGIN
  IF p_quantity <= 0 THEN
    RAISE EXCEPTION 'Quantity must be positive';
  END IF;

  SELECT * INTO v_order FROM orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  -- Unified transaction-level advisory lock
  IF v_order.cart_group_id IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(hashtext('cart_group_' || v_order.cart_group_id::text));
    PERFORM id FROM orders WHERE cart_group_id = v_order.cart_group_id ORDER BY id FOR UPDATE;
  ELSE
    PERFORM id FROM orders WHERE id = p_order_id FOR UPDATE;
  END IF;

  SELECT * INTO v_order FROM orders WHERE id = p_order_id FOR UPDATE;

  IF auth.uid() IS NULL OR (v_order.customer_id != auth.uid() AND NOT public.is_active_admin(auth.uid())) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_order.status NOT IN ('awaiting_acceptance', 'awaiting_payment', 'pending', 'confirmed', 'preparing') THEN
    RAISE EXCEPTION 'Order cannot be modified at status %', v_order.status;
  END IF;

  -- Double-dip / Premature cash refund check:
  IF v_order.payment_status = 'captured' AND (
    COALESCE(v_order.refund_status, 'none') IN ('processed', 'completed') 
    OR COALESCE(v_order.total_refunded, 0) > 0
  ) THEN
    RAISE EXCEPTION 'ALREADY_REFUNDED: A cash refund has already been completed for this order. In-place item swap is disabled.';
  END IF;

  SELECT * INTO v_declined_item 
  FROM order_items 
  WHERE id = p_declined_item_id AND order_id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Declined item not found in this order';
  END IF;

  IF v_declined_item.status != 'declined' THEN
    RAISE EXCEPTION 'Item is not in declined status (current status: %)', v_declined_item.status;
  END IF;

  -- Fetch replacement product strictly enforcing soft-delete rule
  SELECT * INTO v_prod 
  FROM products 
  WHERE id = p_replacement_product_id 
    AND shop_id = v_order.shop_id 
    AND is_available = true
    AND is_deleted = false
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Replacement product not found, unavailable, or belongs to another store';
  END IF;

  IF v_prod.total_quantity IS NOT NULL AND v_prod.total_quantity < p_quantity THEN
    RAISE EXCEPTION 'Insufficient stock for replacement product';
  END IF;

  -- Resolve variant price if variant requested
  v_replacement_price := v_prod.price;
  IF p_replacement_variant_name IS NOT NULL AND v_prod.variants IS NOT NULL THEN
    BEGIN
      SELECT (elem->>'price')::numeric INTO v_variant_price
      FROM jsonb_array_elements(v_prod.variants::jsonb) AS elem
      WHERE elem->>'name' = p_replacement_variant_name
      LIMIT 1;

      IF v_variant_price IS NOT NULL AND v_variant_price > 0 THEN
        v_replacement_price := v_variant_price;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      v_replacement_price := v_prod.price;
    END;
  END IF;

  v_old_item_subtotal := v_declined_item.price * v_declined_item.quantity;
  v_new_item_subtotal := v_replacement_price * p_quantity;
  v_price_delta := v_new_item_subtotal - v_old_item_subtotal;

  IF v_order.payment_status = 'captured' AND v_price_delta > 0.01 THEN
    RAISE EXCEPTION 'REPLACEMENT_PRICE_EXCEEDS_ORIGINAL: Replacement item costs ₹% more than original item. Please select an item of equal or lower price.', v_price_delta;
  END IF;

  -- Unit weight calculation for replacement
  v_clean_unit := lower(trim(COALESCE(v_prod.unit, v_prod.unit_type, '')));
  v_replacement_unit_weight_kg := CASE
    WHEN v_clean_unit IN ('kg', 'kilogram', 'kilograms') THEN COALESCE(v_prod.weight_per_unit, 1.0)
    WHEN v_clean_unit IN ('g', 'gm', 'gms', 'gram', 'grams') THEN COALESCE(v_prod.weight_per_unit, 500.0) / 1000.0
    WHEN v_clean_unit IN ('l', 'litre', 'litres', 'liter', 'liters') THEN COALESCE(v_prod.weight_per_unit, 1.0)
    WHEN v_clean_unit IN ('ml', 'millilitre', 'millilitres') THEN COALESCE(v_prod.weight_per_unit, 500.0) / 1000.0
    ELSE COALESCE(v_prod.weight_per_unit, 0.5)
  END;
  IF v_replacement_unit_weight_kg <= 0 THEN
    v_replacement_unit_weight_kg := 0.5;
  END IF;

  -- 15.0 kg Hard Weight Stop Verification
  IF v_order.cart_group_id IS NOT NULL THEN
    SELECT COALESCE(SUM(oi.quantity * COALESCE(oi.weight_kg, 0.5)), 0)
    INTO v_group_total_weight_kg
    FROM order_items oi
    JOIN orders o ON o.id = oi.order_id
    WHERE o.cart_group_id = v_order.cart_group_id
      AND o.status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'shop_dispute_cancel', 'timeout', 'failed', 'returned', 'refunded')
      AND oi.status = 'active';

    v_group_total_weight_kg := v_group_total_weight_kg + (p_quantity * v_replacement_unit_weight_kg);

    IF v_group_total_weight_kg > 15.0 THEN
      RAISE EXCEPTION 'PHYSICAL_WEIGHT_LIMIT_EXCEEDED: Total delivery weight % kg exceeds the 15.0 kg two-wheeler limit.', round(v_group_total_weight_kg::numeric, 2);
    END IF;
  ELSE
    SELECT COALESCE(SUM(quantity * COALESCE(weight_kg, 0.5)), 0)
    INTO v_order_total_weight_kg
    FROM order_items
    WHERE order_id = p_order_id AND status = 'active';

    v_order_total_weight_kg := v_order_total_weight_kg + (p_quantity * v_replacement_unit_weight_kg);

    IF v_order_total_weight_kg > 15.0 THEN
      RAISE EXCEPTION 'PHYSICAL_WEIGHT_LIMIT_EXCEEDED: Total delivery weight % kg exceeds the 15.0 kg two-wheeler limit.', round(v_order_total_weight_kg::numeric, 2);
    END IF;
  END IF;

  -- Mark declined item as swapped
  UPDATE order_items
  SET 
    status = 'swapped',
    declined_reason = COALESCE(declined_reason, 'declined') || ':swapped_for_' || v_new_item_id::text
  WHERE id = p_declined_item_id;

  -- Insert replacement active item
  INSERT INTO order_items (
    id, order_id, product_id, product_name, quantity, price, status,
    weight_kg, selected_variant_name
  ) VALUES (
    v_new_item_id,
    p_order_id,
    p_replacement_product_id,
    v_prod.name || CASE WHEN p_replacement_variant_name IS NOT NULL THEN ' (' || p_replacement_variant_name || ')' ELSE '' END,
    p_quantity,
    v_replacement_price,
    'active',
    v_replacement_unit_weight_kg,
    p_replacement_variant_name
  );

  -- Decrement stock if managed
  IF v_prod.total_quantity IS NOT NULL THEN
    UPDATE products 
    SET total_quantity = GREATEST(0, total_quantity - p_quantity),
        is_available = CASE WHEN total_quantity - p_quantity <= 0 THEN false ELSE is_available END,
        updated_at = NOW()
    WHERE id = p_replacement_product_id
      AND is_deleted = false;
  END IF;

  -- Determine statutory taxes & commission
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

  v_new_active_subtotal := 0.0;
  FOR oi_rec IN
    SELECT price, quantity
    FROM order_items
    WHERE order_id = p_order_id AND status = 'active'
  LOOP
    v_item_subtotal := oi_rec.price * oi_rec.quantity;
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

  -- 100x FORENSIC FIX: Authoritative Grand Total
  -- Delivery charges already embeds heavy_order_fee, small_cart_fee, and multi_shop_surcharge!
  -- DO NOT add them a second time!
  v_authoritative_grand_total := GREATEST(0,
    v_new_active_subtotal
    + v_new_gst_item_total
    + COALESCE(v_order.platform_fee, 0)
    + COALESCE(v_order.delivery_charges, 0)
    - LEAST(COALESCE(v_order.coupon_discount, 0), v_new_active_subtotal)
  );

  IF v_order.payment_status = 'captured' THEN
    v_pending_refund := GREATEST(0.0, 
      (COALESCE(v_order.grand_total_collected, 0) - v_authoritative_grand_total) 
      - COALESCE(v_order.total_refunded, 0)
    );
  ELSE
    v_pending_refund := 0.0;
  END IF;

  UPDATE orders
  SET
    total_amount = v_new_active_subtotal,
    grand_total = v_authoritative_grand_total,
    s9_5_gst_amount = v_new_s9_5,
    non_food_gst_amount = v_new_non_food_gst,
    total_gst_amount = v_new_gst_item_total,
    enything_commission = v_new_enything_commission,
    tcs_amount = v_new_tcs,
    tds_amount = v_new_tds,
    seller_payout = v_new_seller_payout,
    pending_refund_amount = v_pending_refund,
    refund_status = CASE 
      WHEN v_order.payment_status = 'captured' AND v_pending_refund > 0.01 THEN 'pending_customer_decision'
      WHEN v_order.payment_status = 'captured' AND v_pending_refund <= 0.01 THEN 'none'
      ELSE refund_status
    END,
    updated_at = NOW()
  WHERE id = p_order_id;

  IF v_order.cart_group_id IS NOT NULL THEN
    PERFORM public.rebalance_active_delivery_fees(v_order.cart_group_id);
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'order_id', p_order_id,
    'old_item_id', p_declined_item_id,
    'new_item_id', v_new_item_id,
    'replacement_product_id', p_replacement_product_id,
    'replacement_price', v_replacement_price,
    'new_subtotal', v_new_active_subtotal,
    'new_grand_total', v_authoritative_grand_total,
    'pending_refund_amount', v_pending_refund,
    'refund_status', CASE 
      WHEN v_order.payment_status = 'captured' AND v_pending_refund > 0.01 THEN 'pending_customer_decision'
      WHEN v_order.payment_status = 'captured' AND v_pending_refund <= 0.01 THEN 'none'
      ELSE v_order.refund_status
    END
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.customer_swap_order_item(UUID, UUID, UUID, TEXT, INT) TO authenticated;


-- ── 5. Fortify acknowledge_partial_rejection (IDOR Check & Timer Extension) ───
CREATE OR REPLACE FUNCTION public.acknowledge_partial_rejection(
  p_cart_group_id UUID,
  p_action TEXT DEFAULT 'proceeded',
  p_resolution TEXT DEFAULT NULL
)
RETURNS void
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

  -- 100x IDOR SECURITY SHIELD:
  IF v_caller_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.orders 
    WHERE cart_group_id = p_cart_group_id 
      AND (customer_id = v_caller_id OR public.is_active_admin(v_caller_id))
  ) THEN
    RAISE EXCEPTION 'Unauthorized: You do not own this order group.';
  END IF;

  v_effective_action := COALESCE(p_resolution, p_action, 'proceeded');

  PERFORM pg_advisory_xact_lock(hashtext('cart_group_' || p_cart_group_id::text));
  PERFORM id FROM public.orders 
  WHERE cart_group_id = p_cart_group_id 
  ORDER BY id FOR UPDATE;

  UPDATE public.orders
  SET 
    cancelled_reason = 'customer_' || v_effective_action || CASE WHEN cancelled_reason IS NOT NULL AND cancelled_reason != '' THEN '_' || cancelled_reason ELSE '' END,
    updated_at = NOW()
  WHERE cart_group_id = p_cart_group_id
    AND status IN ('seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'cancelled', 'timeout', 'payment_failed', 'shop_dispute_cancel')
    AND COALESCE(cancelled_reason, '') NOT LIKE 'customer%';

  UPDATE public.order_items
  SET status = 'cancelled', 
      declined_reason = COALESCE(declined_reason, '') || ':customer_' || v_effective_action
  WHERE order_id IN (SELECT id FROM public.orders WHERE cart_group_id = p_cart_group_id)
    AND status = 'declined';

  -- 100x WATCHDOG EXTENSION: Give surviving active merchants & customer time to complete lifecycle
  UPDATE public.orders
  SET 
    acceptance_deadline = NOW() + INTERVAL '3 minutes',
    payment_deadline = NOW() + INTERVAL '10 minutes',
    updated_at = NOW()
  WHERE cart_group_id = p_cart_group_id
    AND status IN ('awaiting_acceptance', 'pending', 'awaiting_payment');

  IF v_effective_action = 'proceeded' THEN
    UPDATE public.orders
    SET refund_status = 'processing',
        updated_at = NOW()
    WHERE cart_group_id = p_cart_group_id
      AND payment_status = 'captured'
      AND refund_status = 'pending_customer_decision';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.acknowledge_partial_rejection(UUID, TEXT, TEXT) TO authenticated, service_role;


-- ── 6. Fortify admin_get_dispatch_feed (delivery_partner_id Projection) ───────
DROP FUNCTION IF EXISTS public.admin_get_dispatch_feed(DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, BOOLEAN, BOOLEAN);

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
BEGIN
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


-- ── 7. Fortify admin_proxy_accept_seller with Advisory Locking ────────────────
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
  IF v_cart_group_id IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(hashtext('cart_group_accept_' || v_cart_group_id::text));
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

  BEGIN
    INSERT INTO public.audit_logs (
      actor_id, actor_role, action, target_type, target_id, details
    ) VALUES (
      v_caller_id,
      v_caller_role,
      'proxy_seller_accept',
      'order',
      p_order_id,
      json_build_object(
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


-- ── 8. Fortify trg_sync_shop_hours with is_manually_closed Sync ───────────────
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

    RETURN NEW;
END;
$$;

