-- =============================================================================
-- Migration: 20290000000185_100x_partial_order_rejection_and_replacement_fortress.sql
-- Description:
--   1. Fixes chk_order_items_status check constraint to permit 'swapped'.
--   2. Fortifies customer_swap_order_item with double-dip refund prevention,
--      15.0 kg weight ceiling enforcement, grand_total & pending_refund updates,
--      and rebalance_active_delivery_fees trigger.
--   3. Secures place_orders_transaction with strict BOLA authorization on
--      p_order_id_to_cancel and populates shop_lat/shop_lng in orders table.
--   4. Eliminates ghost stock resuscitation in restore_product_stock_on_cancel_stmt
--      by strictly filtering oi.status = 'active'.
--   5. Fixes acknowledge_partial_rejection to guarantee cancelled_reason is always
--      prefixed with 'customer_', permanently disarming 5-min auto-cancel paradox.
--   6. Introduces admin_proxy_acknowledge_partial_rejection for dispatch tower.
--   7. Fixes seller reporting (get_seller_daily_stats & get_seller_ca_report)
--      to preserve seller payout and statutory GST on partially declined delivered orders.
--   8. Preserves grand_total_collected in decline_order_items_seller.
--   9. Enhances admin_issue_refund to handle orders with existing partial refunds.
-- =============================================================================

-- ── 1. Fix chk_order_items_status Constraint ─────────────────────────────────
ALTER TABLE public.order_items DROP CONSTRAINT IF EXISTS chk_order_items_status;
ALTER TABLE public.order_items 
  ADD CONSTRAINT chk_order_items_status 
  CHECK (status IN ('active', 'declined', 'cancelled', 'swapped'));

-- ── 2. Fortify customer_swap_order_item ──────────────────────────────────────
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
BEGIN
  IF p_quantity <= 0 THEN
    RAISE EXCEPTION 'Quantity must be positive';
  END IF;

  -- Strict customer authorization
  SELECT * INTO v_order FROM orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF auth.uid() IS NULL OR (v_order.customer_id != auth.uid() AND NOT public.is_active_admin(auth.uid())) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_order.status NOT IN ('awaiting_acceptance', 'awaiting_payment', 'pending', 'confirmed', 'preparing') THEN
    RAISE EXCEPTION 'Order cannot be modified at status %', v_order.status;
  END IF;

  -- Verify declined item exists and belongs to this order
  SELECT * INTO v_declined_item FROM order_items WHERE id = p_declined_item_id AND order_id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Declined item not found';
  END IF;

  IF v_declined_item.status NOT IN ('declined', 'active') THEN
    RAISE EXCEPTION 'Item cannot be replaced in status %', v_declined_item.status;
  END IF;

  -- Verify replacement product belongs to the same shop and is active
  SELECT * INTO v_prod FROM products 
  WHERE id = p_replacement_product_id 
    AND shop_id = v_order.shop_id 
    AND is_available = true 
    AND is_deleted = false;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Replacement product is unavailable or belongs to another shop';
  END IF;

  -- Stock check on replacement
  IF v_prod.total_quantity IS NOT NULL AND v_prod.total_quantity < p_quantity THEN
    RAISE EXCEPTION 'Insufficient stock for replacement product';
  END IF;

  -- 100x CANONICAL UNIT WEIGHT PARITY
  v_replacement_unit_weight_kg := COALESCE(v_prod.weight_per_unit, 0.5);
  v_clean_unit := lower(trim(COALESCE(v_prod.unit, '')));
  IF v_clean_unit != '' THEN
    IF v_clean_unit ~ '^\d+(\.\d+)?\s*g(ram)?s?$' THEN
      v_replacement_unit_weight_kg := (regexp_replace(v_clean_unit, '[^\d.]', '', 'g'))::numeric / 1000.0;
    ELSIF v_clean_unit ~ '^\d+(\.\d+)?\s*kg$' THEN
      v_replacement_unit_weight_kg := (regexp_replace(v_clean_unit, '[^\d.]', '', 'g'))::numeric;
    ELSIF v_clean_unit ~ '^\d+(\.\d+)?\s*m[lL]$' THEN
      v_replacement_unit_weight_kg := (regexp_replace(v_clean_unit, '[^\d.]', '', 'g'))::numeric / 1000.0;
    ELSIF v_clean_unit ~ '^\d+(\.\d+)?\s*[lL](itre)?s?$' THEN
      v_replacement_unit_weight_kg := (regexp_replace(v_clean_unit, '[^\d.]', '', 'g'))::numeric;
    END IF;
  END IF;

  IF v_replacement_unit_weight_kg <= 0 THEN
    v_replacement_unit_weight_kg := 0.5;
  END IF;

  -- Price calculation
  v_replacement_price := v_prod.price;
  IF p_replacement_variant_name IS NOT NULL AND v_prod.variants IS NOT NULL THEN
    SELECT (elem->>'price')::numeric INTO v_variant_price
    FROM jsonb_array_elements(v_prod.variants) AS elem
    WHERE elem->>'name' = p_replacement_variant_name;
    IF v_variant_price IS NOT NULL AND v_variant_price > 0 THEN
      v_replacement_price := v_variant_price;
    END IF;
  END IF;

  v_old_item_subtotal := v_declined_item.price * v_declined_item.quantity;
  v_new_item_subtotal := v_replacement_price * p_quantity;
  v_price_delta := v_new_item_subtotal - v_old_item_subtotal;

  -- If order is captured and replacement is more expensive, block direct swap (requires checkout for extra payment)
  IF v_order.payment_status = 'captured' AND v_price_delta > 0.01 THEN
    RAISE EXCEPTION 'REPLACEMENT_PRICE_EXCEEDS_ORIGINAL: Replacement item costs ₹% more than original item. Please select an item of equal or lower price.', v_price_delta;
  END IF;

  -- Insert new replacement order item
  INSERT INTO order_items (
    id, order_id, product_id, product_name, variant_name,
    quantity, price, unit_price, total_price, status, weight_kg, created_at
  ) VALUES (
    v_new_item_id, p_order_id, p_replacement_product_id, v_prod.name, p_replacement_variant_name,
    p_quantity, v_replacement_price, v_replacement_price, v_new_item_subtotal, 'active', v_replacement_unit_weight_kg, NOW()
  );

  -- Mark old item as swapped
  UPDATE order_items 
  SET status = 'swapped', declined_reason = 'customer_replaced'
  WHERE id = p_declined_item_id;

  -- 100x PHYSICAL TWO-WHEELER PAYLOAD LIMIT GUARD (15.0 KG)
  SELECT COALESCE(SUM(quantity * COALESCE(weight_kg, 0.5)), 0)
  INTO v_order_total_weight_kg
  FROM order_items
  WHERE order_id = p_order_id AND status = 'active';

  IF v_order_total_weight_kg > 15.0 THEN
    RAISE EXCEPTION 'PHYSICAL_WEIGHT_LIMIT_EXCEEDED: Swapping this item brings order weight to % kg, exceeding the 15.0 kg two-wheeler limit.', round(v_order_total_weight_kg::numeric, 2);
  END IF;

  -- Recalculate true active subtotal
  SELECT COALESCE(SUM(price * quantity), 0)
  INTO v_new_active_subtotal
  FROM order_items
  WHERE order_id = p_order_id AND status = 'active';

  -- 100x DOUBLE-DIP REFUND FORTRESS:
  -- When the customer receives a replacement item, deduct replacement cost from pending_refund_amount!
  IF v_order.payment_status = 'captured' THEN
    UPDATE orders
    SET 
      total_amount = v_new_active_subtotal,
      grand_total = grand_total + v_price_delta,
      pending_refund_amount = GREATEST(0, COALESCE(pending_refund_amount, 0) - v_new_item_subtotal),
      refund_status = CASE 
        WHEN GREATEST(0, COALESCE(pending_refund_amount, 0) - v_new_item_subtotal) <= 0.01 THEN 'none'
        ELSE refund_status
      END,
      updated_at = NOW()
    WHERE id = p_order_id;
  ELSE
    UPDATE orders
    SET 
      total_amount = v_new_active_subtotal,
      grand_total = grand_total + v_price_delta,
      grand_total_collected = grand_total_collected + v_price_delta,
      updated_at = NOW()
    WHERE id = p_order_id;
  END IF;

  -- Rebalance multi-shop delivery fees and weights if part of a cart group
  IF v_order.cart_group_id IS NOT NULL THEN
    PERFORM public.rebalance_active_delivery_fees(v_order.cart_group_id);
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'new_item_id', v_new_item_id,
    'price_delta', v_price_delta,
    'new_subtotal', v_new_active_subtotal,
    'total_weight_kg', v_order_total_weight_kg
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.customer_swap_order_item(UUID, UUID, UUID, TEXT, INT) TO authenticated, service_role;


-- ── 3. Fortify place_orders_transaction (BOLA Guard & shop_lat/lng Insertion) ──
CREATE OR REPLACE FUNCTION public.place_orders_transaction(
  p_orders jsonb,
  p_items jsonb,
  p_cart_group_id uuid,
  p_coupon_id uuid DEFAULT NULL::uuid,
  p_idempotency_key text DEFAULT NULL::text,
  p_order_id_to_cancel uuid DEFAULT NULL::uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_customer_id uuid;
  v_inserted_ids uuid[] := '{}';
  v_order jsonb;
  v_item jsonb;
  v_prod record;
  v_order_id uuid;
  v_expected_total_amount numeric;
  v_client_total_amount numeric;
  v_expected_grand_total numeric;
  v_client_grand_total numeric;
  v_item_price numeric;
  v_variant_price numeric;
  v_expected_discount numeric := 0;
  v_num_orders int;
  v_order_seq int := 0;
  v_is_replacement boolean := false;
  v_acceptance_deadline timestamptz;

  v_platform_fee_config numeric := 2.0;
  v_platform_gst_rate numeric := 0.18;
  v_server_gst_platform numeric;
  v_delivery_gst_rate numeric := 0.18;
  v_server_gst_delivery numeric;
  v_rider_commission_percent numeric := 80.0;
  v_server_rider_earnings numeric;
  v_server_seller_payout numeric;
  v_server_enything_commission numeric;
  v_tcs_rate numeric := 0.005;
  v_tds_rate numeric := 0.001;
  v_tcs_amount numeric := 0.0;
  v_tds_amount numeric := 0.0;
  v_gw_deduct numeric := 0.0;
  v_seller_gw_share numeric := 0.0;
  v_item_weight_kg numeric;
  v_clean_unit text;
  v_order_total_weight_kg numeric;
  v_group_total_weight_kg numeric := 0.0;
  v_existing_group_weight numeric := 0.0;

  v_s9_5_gst numeric := 0.0;
  v_non_food_gst numeric := 0.0;
  v_pure_commission numeric := 0.0;
  v_item_subtotal numeric := 0.0;
  v_item_gst numeric := 0.0;
  v_item_commission numeric := 0.0;
  v_item_is_food boolean := false;
  v_item_gst_rate numeric := 0.0;
  v_item_comm_rate numeric := 5.0;

  v_shop_cat text;
  v_comm_key text;
  v_comm_val numeric;

  v_existing_rider_id uuid;
  v_existing_rider_phone text;
  v_existing_partner_accepted boolean;
  v_secure_order jsonb;
  v_active_cart_groups_count int;
  v_rider_cap int := 3;

  v_shop_lat double precision;
  v_shop_lng double precision;
BEGIN
  v_customer_id := auth.uid();
  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required to place orders';
  END IF;

  IF p_cart_group_id IS NULL THEN
    RAISE EXCEPTION 'cart_group_id is strictly required';
  END IF;

  -- 100x BOLA IDOR SECURITY GUARD: Verify cancellation target belongs to caller
  IF p_order_id_to_cancel IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM orders 
      WHERE id = p_order_id_to_cancel 
        AND customer_id = v_customer_id 
        AND cart_group_id = p_cart_group_id
    ) THEN
      RAISE EXCEPTION 'Unauthorized: Cancellation target order does not belong to your cart group';
    END IF;
  END IF;

  -- Acquire exclusive transaction lock on cart_group_id
  PERFORM pg_advisory_xact_lock(hashtext(p_cart_group_id::text));

  -- 1. Idempotency Check
  IF p_idempotency_key IS NOT NULL THEN
    SELECT array_agg(id) INTO v_inserted_ids
    FROM orders
    WHERE idempotency_key = p_idempotency_key;
    IF v_inserted_ids IS NOT NULL AND array_length(v_inserted_ids, 1) > 0 THEN
      RETURN jsonb_build_object(
        'success', true,
        'order_ids', to_jsonb(v_inserted_ids),
        'cart_group_id', p_cart_group_id,
        'idempotent_replay', true
      );
    END IF;
  END IF;

  -- Check if this transaction replaces a rejected order
  IF p_order_id_to_cancel IS NOT NULL THEN
    v_is_replacement := true;
  ELSE
    SELECT EXISTS (
      SELECT 1 FROM orders
      WHERE cart_group_id = p_cart_group_id
        AND status IN ('seller_rejected', 'partner_rejected', 'rider_rejected', 'shop_dispute_cancel')
    ) INTO v_is_replacement;
  END IF;

  v_num_orders := jsonb_array_length(p_orders);
  IF v_num_orders = 0 THEN
    RAISE EXCEPTION 'No orders provided';
  END IF;

  -- 2. Fetch platform config values
  SELECT COALESCE((value#>>'{}')::numeric, 2.0) INTO v_platform_fee_config
  FROM platform_config WHERE key = 'platform_fee';
  SELECT COALESCE((value#>>'{}')::numeric, 0.18) INTO v_platform_gst_rate
  FROM platform_config WHERE key = 'platform_fee_gst_rate';
  SELECT COALESCE((value#>>'{}')::numeric, 0.18) INTO v_delivery_gst_rate
  FROM platform_config WHERE key = 'delivery_gst_rate';
  SELECT COALESCE((value#>>'{}')::numeric, 80.0) INTO v_rider_commission_percent
  FROM platform_config WHERE key = 'rider_commission_percent';

  -- 3. Calculate Existing Group Active Weight
  SELECT COALESCE(SUM(oi.quantity * COALESCE(oi.weight_kg, 0.5)), 0)
  INTO v_existing_group_weight
  FROM orders o
  JOIN order_items oi ON o.id = oi.order_id
  WHERE o.cart_group_id = p_cart_group_id
    AND o.status NOT IN ('delivered', 'cancelled', 'seller_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel', 'no_rider', 'partner_rejected', 'rider_rejected', 'failed', 'returned', 'refunded')
    AND oi.status = 'active'
    AND (p_order_id_to_cancel IS NULL OR o.id != p_order_id_to_cancel);

  v_group_total_weight_kg := v_existing_group_weight;

  -- Check existing assigned rider
  SELECT delivery_partner_id, rider_phone, partner_accepted
  INTO v_existing_rider_id, v_existing_rider_phone, v_existing_partner_accepted
  FROM orders
  WHERE cart_group_id = p_cart_group_id
    AND delivery_partner_id IS NOT NULL
    AND status NOT IN ('delivered', 'cancelled', 'seller_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel', 'no_rider', 'partner_rejected', 'rider_rejected', 'failed', 'returned', 'refunded')
  LIMIT 1;

  -- 4. Rider Hoarding Ceiling Guard
  IF v_existing_rider_id IS NOT NULL THEN
    SELECT count(DISTINCT COALESCE(cart_group_id, id))
    INTO v_active_cart_groups_count
    FROM public.orders
    WHERE delivery_partner_id = v_existing_rider_id
      AND status IN ('confirmed', 'preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery')
      AND COALESCE(cart_group_id, id) != p_cart_group_id;

    IF v_active_cart_groups_count >= v_rider_cap THEN
      v_existing_rider_id := NULL;
      v_existing_rider_phone := NULL;
      v_existing_partner_accepted := false;
    END IF;
  END IF;

  -- 5. Validate Coupon if provided
  IF p_coupon_id IS NOT NULL THEN
    DECLARE
      v_coupon record;
    BEGIN
      SELECT * INTO v_coupon FROM coupons WHERE id = p_coupon_id AND is_active = true;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'Coupon invalid or inactive';
      END IF;
      IF v_coupon.valid_until IS NOT NULL AND v_coupon.valid_until < NOW() THEN
        RAISE EXCEPTION 'Coupon expired';
      END IF;
      IF v_coupon.usage_limit IS NOT NULL AND v_coupon.times_used >= v_coupon.usage_limit THEN
        RAISE EXCEPTION 'Coupon usage limit exceeded';
      END IF;
      IF EXISTS (SELECT 1 FROM user_coupon_usage WHERE user_id = v_customer_id AND coupon_id = p_coupon_id) THEN
        RAISE EXCEPTION 'Coupon already used by this customer';
      END IF;
      v_expected_discount := COALESCE(v_coupon.discount_amount, 0);
    END;
  END IF;

  -- 6. Loop through each order and validate
  FOR v_order IN SELECT * FROM jsonb_array_elements(p_orders) LOOP
    v_order_seq := v_order_seq + 1;
    v_order_id := (v_order->>'id')::uuid;
    v_expected_total_amount := 0;
    v_s9_5_gst := 0.0;
    v_non_food_gst := 0.0;
    v_pure_commission := 0.0;
    v_tcs_amount := 0.0;
    v_tds_amount := 0.0;
    v_order_total_weight_kg := 0.0;

    SELECT category INTO v_shop_cat FROM shops WHERE id = (v_order->>'shop_id')::uuid;

    -- Resolve exact shop location coordinates for PostGIS routing
    SELECT ST_Y(location::geometry), ST_X(location::geometry) 
    INTO v_shop_lat, v_shop_lng 
    FROM shops 
    WHERE id = (v_order->>'shop_id')::uuid;

    -- Validate items
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
      WHERE (v_item->>'order_id')::uuid = v_order_id
    LOOP
      SELECT * INTO v_prod FROM products
      WHERE id = (v_item->>'product_id')::uuid
        AND shop_id = (v_order->>'shop_id')::uuid
        AND is_available = true
        AND is_deleted = false;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'Product % unavailable or belongs to another shop', v_item->>'product_id';
      END IF;

      -- Stock availability
      IF v_prod.total_quantity IS NOT NULL AND v_prod.total_quantity < (v_item->>'quantity')::int THEN
        RAISE EXCEPTION 'Insufficient stock for product %', v_prod.name;
      END IF;

      -- 100x Canonical Unit Weight Resolution
      v_item_weight_kg := COALESCE(v_prod.weight_per_unit, 0.5);
      v_clean_unit := lower(trim(COALESCE(v_prod.unit, '')));
      IF v_clean_unit != '' THEN
        IF v_clean_unit ~ '^\d+(\.\d+)?\s*g(ram)?s?$' THEN
          v_item_weight_kg := (regexp_replace(v_clean_unit, '[^\d.]', '', 'g'))::numeric / 1000.0;
        ELSIF v_clean_unit ~ '^\d+(\.\d+)?\s*kg$' THEN
          v_item_weight_kg := (regexp_replace(v_clean_unit, '[^\d.]', '', 'g'))::numeric;
        ELSIF v_clean_unit ~ '^\d+(\.\d+)?\s*m[lL]$' THEN
          v_item_weight_kg := (regexp_replace(v_clean_unit, '[^\d.]', '', 'g'))::numeric / 1000.0;
        ELSIF v_clean_unit ~ '^\d+(\.\d+)?\s*[lL](itre)?s?$' THEN
          v_item_weight_kg := (regexp_replace(v_clean_unit, '[^\d.]', '', 'g'))::numeric;
        END IF;
      END IF;
      IF v_item_weight_kg <= 0 THEN v_item_weight_kg := 0.5; END IF;

      v_order_total_weight_kg := v_order_total_weight_kg + (v_item_weight_kg * (v_item->>'quantity')::int);

      -- Price resolution
      v_item_price := v_prod.price;
      IF v_item->>'variant_name' IS NOT NULL AND v_prod.variants IS NOT NULL THEN
        SELECT (elem->>'price')::numeric INTO v_variant_price
        FROM jsonb_array_elements(v_prod.variants) AS elem
        WHERE elem->>'name' = v_item->>'variant_name';
        IF v_variant_price IS NOT NULL AND v_variant_price > 0 THEN
          v_item_price := v_variant_price;
        END IF;
      END IF;

      v_item_subtotal := v_item_price * (v_item->>'quantity')::int;
      v_expected_total_amount := v_expected_total_amount + v_item_subtotal;

      -- Tax classification
      v_item_is_food := (
        lower(trim(COALESCE(v_prod.category, ''))) IN ('food', 'restaurant', 'fast food', 'bakery', 'sweets & mithai', 'ice cream', 'beverages')
        OR lower(trim(COALESCE(v_shop_cat, ''))) IN ('food', 'restaurant', 'fast food', 'bakery', 'sweets & mithai', 'ice cream', 'cafe')
      );

      IF v_item_is_food THEN
        v_item_gst_rate := 0.05;
        v_item_gst := ROUND(v_item_subtotal * v_item_gst_rate, 2);
        v_s9_5_gst := v_s9_5_gst + v_item_gst;
      ELSE
        v_item_gst_rate := COALESCE(v_prod.gst_rate, 0.18);
        IF v_item_gst_rate > 1.0 THEN v_item_gst_rate := v_item_gst_rate / 100.0; END IF;
        v_item_gst := ROUND(v_item_subtotal * v_item_gst_rate, 2);
        v_non_food_gst := v_non_food_gst + v_item_gst;
        v_tcs_amount := v_tcs_amount + ROUND(v_item_subtotal * v_tcs_rate, 2);
      END IF;

      v_tds_amount := v_tds_amount + ROUND(v_item_subtotal * v_tds_rate, 2);

      -- Commission resolution
      v_comm_key := 'commission_percent_' || COALESCE(v_prod.category, v_shop_cat, 'Other');
      SELECT (value#>>'{}')::numeric INTO v_comm_val FROM platform_config WHERE key = v_comm_key;
      IF v_comm_val IS NULL THEN
        v_comm_key := 'commission_percent_' || COALESCE(v_shop_cat, 'Other');
        SELECT (value#>>'{}')::numeric INTO v_comm_val FROM platform_config WHERE key = v_comm_key;
      END IF;
      IF v_comm_val IS NULL THEN
        SELECT COALESCE((value#>>'{}')::numeric, 5.0) INTO v_comm_val FROM platform_config WHERE key = 'commission_percent';
      END IF;
      v_item_comm_rate := COALESCE(v_comm_val, 5.0);
      v_item_commission := ROUND(v_item_subtotal * (v_item_comm_rate / 100.0), 2);
      v_pure_commission := v_pure_commission + v_item_commission;
    END LOOP;

    -- 100x Payload Limit Enforcement (15.0 kg Two-Wheeler Limit)
    v_group_total_weight_kg := v_group_total_weight_kg + v_order_total_weight_kg;
    IF v_group_total_weight_kg > 15.0 THEN
      RAISE EXCEPTION 'PHYSICAL_WEIGHT_LIMIT_EXCEEDED: Cart group weight is % kg, exceeding the 15.0 kg two-wheeler limit.', round(v_group_total_weight_kg::numeric, 2);
    END IF;

    -- Validate subtotal
    v_client_total_amount := (v_order->>'total_amount')::numeric;
    IF ABS(v_expected_total_amount - v_client_total_amount) > 1.0 THEN
      RAISE EXCEPTION 'Total amount mismatch: expected %, got %', v_expected_total_amount, v_client_total_amount;
    END IF;

    -- Calculate grand total
    v_expected_grand_total := v_expected_total_amount 
      + (v_s9_5_gst + v_non_food_gst)
      + COALESCE((v_order->>'platform_fee')::numeric, 0)
      + COALESCE((v_order->>'delivery_charges')::numeric, 0)
      + COALESCE((v_order->>'small_cart_fee')::numeric, 0)
      - COALESCE((v_order->>'coupon_discount')::numeric, 0);

    v_client_grand_total := (v_order->>'grand_total')::numeric;
    IF ABS(v_expected_grand_total - v_client_grand_total) > 1.5 THEN
      RAISE EXCEPTION 'Grand total mismatch: expected %, got %', v_expected_grand_total, v_client_grand_total;
    END IF;

    -- Statutory platform & delivery deductions
    v_server_gst_platform := ROUND(COALESCE((v_order->>'platform_fee')::numeric, 0) * (v_platform_gst_rate / (1.0 + v_platform_gst_rate)), 2);
    v_server_gst_delivery := ROUND(COALESCE((v_order->>'delivery_charges')::numeric, 0) * (v_delivery_gst_rate / (1.0 + v_delivery_gst_rate)), 2);
    v_server_rider_earnings := ROUND(COALESCE((v_order->>'delivery_charges')::numeric, 0) * (v_rider_commission_percent / 100.0), 2);
    v_server_enything_commission := ROUND(v_pure_commission, 2);

    v_gw_deduct := COALESCE((v_order->>'gateway_deduction')::numeric, 0);
    IF v_expected_grand_total > 0 THEN
      v_seller_gw_share := ROUND(v_gw_deduct * (v_expected_total_amount / v_expected_grand_total), 2);
    ELSE
      v_seller_gw_share := 0;
    END IF;

    v_server_seller_payout := GREATEST(0, v_expected_total_amount + v_non_food_gst - v_server_enything_commission - v_tcs_amount - v_tds_amount - v_seller_gw_share);

    IF v_order_seq = 1 THEN
      v_acceptance_deadline := NOW() + INTERVAL '3 minutes';
    ELSE
      v_acceptance_deadline := NOW() + ((v_order_seq * 3) || ' minutes')::interval;
    END IF;

    v_secure_order := v_order || jsonb_build_object(
      'total_amount', v_expected_total_amount,
      's9_5_gst_amount', v_s9_5_gst,
      'non_food_gst_amount', v_non_food_gst,
      'gst_item_total', v_s9_5_gst + v_non_food_gst,
      'tcs_amount', v_tcs_amount,
      'tds_amount', v_tds_amount,
      'grand_total', v_expected_grand_total,
      'grand_total_collected', v_expected_grand_total,
      'gst_platform', v_server_gst_platform,
      'gst_delivery', v_server_gst_delivery,
      'gateway_deduction', v_gw_deduct,
      'seller_payout', v_server_seller_payout,
      'enything_commission', v_server_enything_commission,
      'rider_earnings', v_server_rider_earnings,
      'acceptance_deadline', v_acceptance_deadline,
      'delivery_partner_id', COALESCE(v_existing_rider_id, (v_order->>'delivery_partner_id')::uuid),
      'rider_phone', COALESCE(v_existing_rider_phone, v_order->>'rider_phone'),
      'partner_accepted', COALESCE(v_existing_partner_accepted, (v_order->>'partner_accepted')::boolean, false)
    );

    -- 100x ROUTE MAP PARITY: Insert shop_lat and shop_lng directly into orders row!
    INSERT INTO orders (
      id, customer_id, shop_id, payment_method, payment_status, status,
      seller_accepted, partner_accepted, delivery_partner_id, rider_phone,
      address, address_label, delivery_lat, delivery_lng, delivery_notes,
      shop_lat, shop_lng,
      estimated_distance_km, acceptance_deadline, cart_group_id, idempotency_key,
      created_at, updated_at, total_amount, s9_5_gst_amount, non_food_gst_amount,
      gst_item_total, tcs_amount, tds_amount, platform_fee, delivery_charges,
      multi_shop_surcharge, small_cart_fee, heavy_order_fee, grand_total,
      grand_total_collected, gst_platform, gst_delivery,
      gateway_deduction, seller_payout, enything_commission, rider_earnings,
      coupon_id, coupon_discount, gst_rate_snapshot, prescription_urls,
      shop_prep_time_snapshot
    ) VALUES (
      (v_secure_order->>'id')::uuid, (v_secure_order->>'customer_id')::uuid, (v_secure_order->>'shop_id')::uuid,
      v_secure_order->>'payment_method', v_secure_order->>'payment_status', v_secure_order->>'status',
      (v_secure_order->>'seller_accepted')::boolean, (v_secure_order->>'partner_accepted')::boolean,
      (v_secure_order->>'delivery_partner_id')::uuid, v_secure_order->>'rider_phone',
      v_secure_order->>'address', v_secure_order->>'address_label',
      (v_secure_order->>'delivery_lat')::numeric, (v_secure_order->>'delivery_lng')::numeric,
      v_secure_order->>'delivery_notes',
      v_shop_lat, v_shop_lng,
      (v_secure_order->>'estimated_distance_km')::numeric,
      (v_secure_order->>'acceptance_deadline')::timestamptz, (v_secure_order->>'cart_group_id')::uuid,
      v_secure_order->>'idempotency_key', (v_secure_order->>'created_at')::timestamptz,
      (v_secure_order->>'updated_at')::timestamptz, (v_secure_order->>'total_amount')::numeric,
      (v_secure_order->>'s9_5_gst_amount')::numeric, (v_secure_order->>'non_food_gst_amount')::numeric,
      (v_secure_order->>'gst_item_total')::numeric, (v_secure_order->>'tcs_amount')::numeric,
      (v_secure_order->>'tds_amount')::numeric, (v_secure_order->>'platform_fee')::numeric,
      (v_secure_order->>'delivery_charges')::numeric, (v_secure_order->>'multi_shop_surcharge')::numeric,
      (v_secure_order->>'small_cart_fee')::numeric, (v_secure_order->>'heavy_order_fee')::numeric,
      (v_secure_order->>'grand_total')::numeric, (v_secure_order->>'grand_total_collected')::numeric,
      (v_secure_order->>'gst_platform')::numeric, (v_secure_order->>'gst_delivery')::numeric,
      (v_secure_order->>'gateway_deduction')::numeric, (v_secure_order->>'seller_payout')::numeric,
      (v_secure_order->>'enything_commission')::numeric, (v_secure_order->>'rider_earnings')::numeric,
      (v_secure_order->>'coupon_id')::uuid, (v_secure_order->>'coupon_discount')::numeric,
      v_secure_order->'gst_rate_snapshot',
      CASE WHEN v_secure_order->'prescription_urls' IS NOT NULL THEN (SELECT array_agg(x)::text[] FROM jsonb_array_elements_text(v_secure_order->'prescription_urls') x) ELSE NULL END,
      (v_secure_order->>'shop_prep_time_snapshot')::int
    );

    v_inserted_ids := array_append(v_inserted_ids, v_order_id);
  END LOOP;

  -- 7. Insert Items
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    SELECT * INTO v_prod FROM products WHERE id = (v_item->>'product_id')::uuid;

    v_item_price := v_prod.price;
    IF v_item->>'variant_name' IS NOT NULL AND v_prod.variants IS NOT NULL THEN
      SELECT (elem->>'price')::numeric INTO v_variant_price
      FROM jsonb_array_elements(v_prod.variants) AS elem
      WHERE elem->>'name' = v_item->>'variant_name';
      IF v_variant_price IS NOT NULL AND v_variant_price > 0 THEN
        v_item_price := v_variant_price;
      END IF;
    END IF;

    -- Canonical unit weight resolution
    v_item_weight_kg := COALESCE(v_prod.weight_per_unit, 0.5);
    v_clean_unit := lower(trim(COALESCE(v_prod.unit, '')));
    IF v_clean_unit != '' THEN
      IF v_clean_unit ~ '^\d+(\.\d+)?\s*g(ram)?s?$' THEN
        v_item_weight_kg := (regexp_replace(v_clean_unit, '[^\d.]', '', 'g'))::numeric / 1000.0;
      ELSIF v_clean_unit ~ '^\d+(\.\d+)?\s*kg$' THEN
        v_item_weight_kg := (regexp_replace(v_clean_unit, '[^\d.]', '', 'g'))::numeric;
      ELSIF v_clean_unit ~ '^\d+(\.\d+)?\s*m[lL]$' THEN
        v_item_weight_kg := (regexp_replace(v_clean_unit, '[^\d.]', '', 'g'))::numeric / 1000.0;
      ELSIF v_clean_unit ~ '^\d+(\.\d+)?\s*[lL](itre)?s?$' THEN
        v_item_weight_kg := (regexp_replace(v_clean_unit, '[^\d.]', '', 'g'))::numeric;
      END IF;
    END IF;
    IF v_item_weight_kg <= 0 THEN v_item_weight_kg := 0.5; END IF;

    INSERT INTO order_items (
      id, order_id, product_id, product_name, variant_name,
      quantity, price, unit_price, total_price, status, weight_kg, created_at
    ) VALUES (
      COALESCE((v_item->>'id')::uuid, gen_random_uuid()),
      (v_item->>'order_id')::uuid,
      (v_item->>'product_id')::uuid,
      v_prod.name,
      v_item->>'variant_name',
      (v_item->>'quantity')::int,
      v_item_price,
      v_item_price,
      v_item_price * (v_item->>'quantity')::int,
      'active',
      v_item_weight_kg,
      NOW()
    );

    -- Decrement inventory
    UPDATE products
    SET total_quantity = total_quantity - (v_item->>'quantity')::int
    WHERE id = (v_item->>'product_id')::uuid
      AND total_quantity IS NOT NULL;
  END LOOP;

  -- 8. Record Coupon Usage
  IF p_coupon_id IS NOT NULL THEN
    INSERT INTO user_coupon_usage (user_id, coupon_id, order_id, discount_applied)
    VALUES (v_customer_id, p_coupon_id, v_inserted_ids[1], v_expected_discount);
  END IF;

  -- 9. Replacement Order Cleanup & Delivery Fee Rebalancing
  IF p_order_id_to_cancel IS NOT NULL OR v_is_replacement THEN
    IF p_order_id_to_cancel IS NOT NULL THEN
      UPDATE orders
      SET status = CASE 
            WHEN status IN ('delivered', 'cancelled', 'seller_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel', 'no_rider', 'partner_rejected', 'rider_rejected', 'failed', 'returned', 'refunded') THEN status
            ELSE 'cancelled'
          END,
          cancelled_reason = 'customer_replaced',
          updated_at = NOW()
      WHERE id = p_order_id_to_cancel
        AND customer_id = v_customer_id
        AND cart_group_id = p_cart_group_id;
    END IF;

    UPDATE orders
    SET cancelled_reason = 'customer_replaced',
        updated_at = NOW()
    WHERE cart_group_id = p_cart_group_id
      AND status IN ('seller_rejected', 'partner_rejected', 'rider_rejected', 'shop_dispute_cancel')
      AND (cancelled_reason IS NULL OR cancelled_reason != 'customer_replaced');

    UPDATE orders
    SET acceptance_deadline = NOW() + INTERVAL '3 minutes',
        payment_deadline = NOW() + INTERVAL '10 minutes',
        updated_at = NOW()
    WHERE cart_group_id = p_cart_group_id
      AND status IN ('awaiting_acceptance', 'pending', 'awaiting_payment');

    PERFORM rebalance_active_delivery_fees(p_cart_group_id);
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'order_ids', to_jsonb(v_inserted_ids),
    'cart_group_id', p_cart_group_id,
    'is_replacement', v_is_replacement,
    'total_weight_kg', v_group_total_weight_kg
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.place_orders_transaction(jsonb, jsonb, uuid, uuid, text, uuid) TO authenticated, service_role;


-- ── 4. Fix Ghost Stock Resuscitation in restore_product_stock_on_cancel_stmt ──
CREATE OR REPLACE FUNCTION public.restore_product_stock_on_cancel_stmt()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_item RECORD;
BEGIN
  -- 100x FIX: Aggregate only strictly ACTIVE items!
  -- Out-of-stock items that were declined by the seller or swapped by the customer
  -- must NEVER be restored to inventory upon order cancellation/rejection.
  FOR v_item IN
    SELECT oi.product_id, SUM(oi.quantity) as total_restored
    FROM new_orders n
    JOIN old_orders o ON n.id = o.id
    JOIN order_items oi ON oi.order_id = n.id
    JOIN products p ON p.id = oi.product_id AND p.shop_id = n.shop_id
    WHERE n.status IN ('cancelled', 'seller_rejected', 'verification_failed', 'no_rider', 'payment_failed', 'timeout', 'shop_dispute', 'shop_dispute_cancel')
      AND o.status NOT IN ('cancelled', 'seller_rejected', 'verification_failed', 'no_rider', 'payment_failed', 'timeout', 'shop_dispute', 'shop_dispute_cancel')
      AND o.status NOT IN ('picked_up', 'out_for_delivery', 'delivered')
      AND oi.status = 'active'
    GROUP BY oi.product_id
    ORDER BY oi.product_id
  LOOP
    UPDATE products
    SET total_quantity = total_quantity + v_item.total_restored
    WHERE id = v_item.product_id
      AND total_quantity IS NOT NULL;
  END LOOP;

  RETURN NULL;
END;
$function$;


-- ── 5. Fix acknowledge_partial_rejection Tagging ─────────────────────────────
CREATE OR REPLACE FUNCTION public.acknowledge_partial_rejection(
  p_cart_group_id UUID,
  p_action TEXT DEFAULT 'proceeded'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF p_cart_group_id IS NULL THEN
    RETURN;
  END IF;

  -- Lock orders in group to prevent race conditions
  PERFORM id FROM public.orders 
  WHERE cart_group_id = p_cart_group_id 
  ORDER BY id FOR UPDATE;

  -- 100x GUARANTEED PREFIX: Prepend 'customer_' to whatever reason was there,
  -- ensuring safe_auto_cancel_expired_orders() recognizes that customer acknowledged.
  UPDATE public.orders
  SET 
    cancelled_reason = 'customer_' || p_action || CASE WHEN cancelled_reason IS NOT NULL AND cancelled_reason != '' THEN '_' || cancelled_reason ELSE '' END,
    updated_at = NOW()
  WHERE cart_group_id = p_cart_group_id
    AND status IN ('seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'cancelled', 'timeout', 'payment_failed', 'shop_dispute_cancel')
    AND COALESCE(cancelled_reason, '') NOT LIKE 'customer%';
END;
$$;

GRANT EXECUTE ON FUNCTION public.acknowledge_partial_rejection(UUID, TEXT) TO authenticated, service_role;


-- ── 6. Admin Proxy Acknowledge Partial Rejection (Dispatch Tower) ────────────
CREATE OR REPLACE FUNCTION public.admin_proxy_acknowledge_partial_rejection(
  p_cart_group_id UUID,
  p_action TEXT DEFAULT 'proceeded'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_admin_id UUID := auth.uid();
  v_affected_count INT;
BEGIN
  IF v_admin_id IS NULL OR NOT public.is_active_admin(v_admin_id) THEN
    RAISE EXCEPTION 'Unauthorized: Only platform administrators or dispatchers can invoke proxy rejection acknowledgement';
  END IF;

  IF p_cart_group_id IS NULL THEN
    RAISE EXCEPTION 'cart_group_id is required';
  END IF;

  -- Lock orders
  PERFORM id FROM public.orders WHERE cart_group_id = p_cart_group_id ORDER BY id FOR UPDATE;

  UPDATE public.orders
  SET 
    cancelled_reason = 'customer_' || p_action || '_by_admin',
    updated_at = NOW()
  WHERE cart_group_id = p_cart_group_id
    AND status IN ('seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'cancelled', 'timeout', 'payment_failed', 'shop_dispute_cancel')
    AND COALESCE(cancelled_reason, '') NOT LIKE 'customer%';

  GET DIAGNOSTICS v_affected_count = ROW_COUNT;

  -- Disarm timer and extend active orders
  UPDATE public.orders
  SET 
    acceptance_deadline = NOW() + INTERVAL '3 minutes',
    payment_deadline = NOW() + INTERVAL '10 minutes',
    updated_at = NOW()
  WHERE cart_group_id = p_cart_group_id
    AND status IN ('awaiting_acceptance', 'pending', 'awaiting_payment');

  -- Log to audit trail
  BEGIN
    INSERT INTO public.audit_logs (actor_id, actor_role, action, target_type, target_id, metadata, created_at)
    VALUES (
      v_admin_id,
      'admin',
      'proxy_acknowledge_partial_rejection',
      'cart_group',
      p_cart_group_id,
      jsonb_build_object('action', p_action, 'affected_orders', v_affected_count),
      NOW()
    );
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN jsonb_build_object(
    'success', true,
    'cart_group_id', p_cart_group_id,
    'affected_orders', v_affected_count
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_proxy_acknowledge_partial_rejection(UUID, TEXT) TO authenticated, service_role;


-- ── 7. Fortify decline_order_items_seller (Preserve grand_total_collected) ───
CREATE OR REPLACE FUNCTION public.decline_order_items_seller(
  p_order_id UUID,
  p_order_item_ids UUID[],
  p_reason TEXT DEFAULT 'out_of_stock',
  p_message TEXT DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_status TEXT;
  v_shop_id UUID;
  v_seller_id UUID;
  v_payment_status TEXT;
  v_refund_status TEXT;
  v_cart_group_id UUID;
  
  v_old_total_amount NUMERIC;
  v_old_grand_total NUMERIC;
  v_old_s9_5 NUMERIC;
  v_old_non_food_gst NUMERIC;
  v_old_enything_commission NUMERIC;
  v_old_tcs NUMERIC;
  v_old_tds NUMERIC;
  v_delivery_charges NUMERIC;
  v_platform_fee NUMERIC;
  v_multi_shop_surcharge NUMERIC;
  v_small_cart_fee NUMERIC;
  v_heavy_order_fee NUMERIC;
  v_coupon_discount NUMERIC;
  
  v_active_items_count INT;
  v_declined_target_count INT;
  v_pending_refund_amount NUMERIC := 0.0;
  v_new_heavy_order_fee NUMERIC := 0.0;
  v_refund_delta NUMERIC := 0.0;
  
  v_new_active_subtotal NUMERIC := 0.0;
  v_new_active_weight NUMERIC := 0.0;
  v_ratio NUMERIC := 1.0;
  v_new_s9_5 NUMERIC := 0.0;
  v_new_non_food_gst NUMERIC := 0.0;
  v_new_gst_item_total NUMERIC := 0.0;
  v_new_enything_commission NUMERIC := 0.0;
  v_new_tcs NUMERIC := 0.0;
  v_new_tds NUMERIC := 0.0;
  v_new_seller_payout NUMERIC := 0.0;
  v_new_grand_total NUMERIC := 0.0;
  v_new_refund_status TEXT;
  v_declined_prod_ids UUID[];
BEGIN
  IF p_order_item_ids IS NULL OR array_length(p_order_item_ids, 1) = 0 THEN
    RAISE EXCEPTION 'p_order_item_ids cannot be empty';
  END IF;

  SELECT 
    status, shop_id, payment_status, refund_status, cart_group_id,
    total_amount, grand_total, s9_5_gst_amount, non_food_gst_amount,
    enything_commission, tcs_amount, tds_amount,
    delivery_charges, platform_fee, multi_shop_surcharge, small_cart_fee,
    heavy_order_fee, coupon_discount, pending_refund_amount
  INTO 
    v_status, v_shop_id, v_payment_status, v_refund_status, v_cart_group_id,
    v_old_total_amount, v_old_grand_total, v_old_s9_5, v_old_non_food_gst,
    v_old_enything_commission, v_old_tcs, v_old_tds,
    v_delivery_charges, v_platform_fee, v_multi_shop_surcharge, v_small_cart_fee,
    v_heavy_order_fee, v_coupon_discount, v_pending_refund_amount
  FROM orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  SELECT seller_id INTO v_seller_id FROM shops WHERE id = v_shop_id;
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
    AND id = ANY(p_order_item_ids)
    AND status = 'active';

  IF v_declined_target_count = 0 THEN
    RETURN jsonb_build_object(
      'success', true,
      'all_items_declined', false,
      'message', 'Items were already declined or not found',
      'active_items_count', v_active_items_count
    );
  END IF;

  -- CASE A: ALL active items declined -> Order becomes seller_rejected
  IF v_declined_target_count >= v_active_items_count THEN
    UPDATE order_items
    SET status = 'declined',
        declined_reason = p_reason,
        declined_at = NOW()
    WHERE order_id = p_order_id AND id = ANY(p_order_item_ids);

    IF v_declined_prod_ids IS NOT NULL AND array_length(v_declined_prod_ids, 1) > 0 THEN
      UPDATE products
      SET is_available = false,
          total_quantity = CASE WHEN total_quantity IS NOT NULL THEN 0 ELSE total_quantity END
      WHERE id = ANY(v_declined_prod_ids)
        AND shop_id = v_shop_id
        AND is_deleted = false;
    END IF;

    UPDATE orders
    SET 
      status = CASE WHEN p_reason = 'prescription' THEN 'verification_failed' ELSE 'seller_rejected' END,
      seller_accepted = false,
      partner_accepted = false,
      delivery_partner_id = null,
      rejection_message = substring(p_message from 1 for 500),
      refund_status = CASE 
        WHEN v_payment_status = 'captured' AND COALESCE(v_refund_status, 'none') NOT IN ('processing', 'completed') 
        THEN 'processing' 
        ELSE v_refund_status 
      END,
      updated_at = NOW()
    WHERE id = p_order_id;

    IF v_cart_group_id IS NOT NULL THEN
      PERFORM reallocate_cancelled_delivery_fees(v_cart_group_id);
      PERFORM rebalance_active_delivery_fees(v_cart_group_id);

      -- 100x STRANDED SIBLING PROMOTION:
      IF EXISTS (
        SELECT 1 FROM orders
        WHERE cart_group_id = v_cart_group_id
          AND status IN ('awaiting_acceptance', 'pending')
          AND seller_accepted = true
          AND (partner_accepted = true OR delivery_partner_id IS NOT NULL)
      ) AND NOT EXISTS (
        SELECT 1 FROM orders
        WHERE cart_group_id = v_cart_group_id
          AND status NOT IN (
            'cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected',
            'verification_failed', 'shop_dispute_cancel', 'timeout', 'failed', 'returned', 'refunded'
          )
          AND seller_accepted = false
      ) THEN
        UPDATE orders
        SET 
          status = 'awaiting_payment',
          payment_deadline = (now() AT TIME ZONE 'utc') + interval '10 minutes',
          updated_at = NOW()
        WHERE cart_group_id = v_cart_group_id
          AND status IN ('awaiting_acceptance', 'pending');
      END IF;
    END IF;

    RETURN jsonb_build_object(
      'success', true,
      'all_items_declined', true,
      'order_status', 'seller_rejected',
      'active_items_count', 0
    );
  END IF;

  -- CASE B: PARTIAL Item Decline
  UPDATE order_items
  SET status = 'declined',
      declined_reason = p_reason,
      declined_at = NOW()
  WHERE order_id = p_order_id 
    AND id = ANY(p_order_item_ids)
    AND status = 'active';

  IF v_declined_prod_ids IS NOT NULL AND array_length(v_declined_prod_ids, 1) > 0 THEN
    UPDATE products
    SET is_available = false,
        total_quantity = CASE WHEN total_quantity IS NOT NULL THEN 0 ELSE total_quantity END
    WHERE id = ANY(v_declined_prod_ids)
      AND shop_id = v_shop_id
      AND is_deleted = false;
  END IF;

  -- Recalculate remaining active items
  SELECT 
    COUNT(*),
    COALESCE(SUM(price * quantity), 0),
    COALESCE(SUM(COALESCE(weight_kg, 0.5) * quantity), 0)
  INTO 
    v_active_items_count,
    v_new_active_subtotal,
    v_new_active_weight
  FROM order_items
  WHERE order_id = p_order_id AND status = 'active';

  IF COALESCE(v_old_total_amount, 0) > 0 THEN
    v_ratio := v_new_active_subtotal / v_old_total_amount;
  ELSE
    v_ratio := 1.0;
  END IF;

  v_new_s9_5 := ROUND((COALESCE(v_old_s9_5, 0) * v_ratio)::numeric, 2);
  v_new_non_food_gst := ROUND((COALESCE(v_old_non_food_gst, 0) * v_ratio)::numeric, 2);
  v_new_gst_item_total := v_new_s9_5 + v_new_non_food_gst;

  v_new_enything_commission := ROUND((COALESCE(v_old_enything_commission, 0) * v_ratio)::numeric, 2);
  v_new_tcs := ROUND((COALESCE(v_old_tcs, 0) * v_ratio)::numeric, 2);
  v_new_tds := ROUND((COALESCE(v_old_tds, 0) * v_ratio)::numeric, 2);
  v_new_seller_payout := v_new_active_subtotal + v_new_non_food_gst - v_new_enything_commission - v_new_tcs - v_new_tds;

  -- Recalculate heavy order fee if applicable
  IF COALESCE(v_heavy_order_fee, 0) > 0 THEN
    IF v_new_active_weight <= 10.0 THEN
      v_new_heavy_order_fee := 0.0;
    ELSE
      v_new_heavy_order_fee := LEAST(v_heavy_order_fee, ROUND((20.0 * CEIL(v_new_active_weight - 10.0))::numeric, 2));
    END IF;
  ELSE
    v_new_heavy_order_fee := 0.0;
  END IF;

  IF v_cart_group_id IS NULL AND COALESCE(v_heavy_order_fee, 0) > v_new_heavy_order_fee THEN
    v_delivery_charges := GREATEST(0, v_delivery_charges - ((v_heavy_order_fee - v_new_heavy_order_fee) * (1.0 + 0.18)));
  END IF;

  v_new_grand_total := GREATEST(0, v_new_active_subtotal 
    + v_new_gst_item_total 
    + COALESCE(v_platform_fee, 0) 
    + COALESCE(v_delivery_charges, 0) 
    - LEAST(COALESCE(v_coupon_discount, 0), v_new_active_subtotal));

  v_new_refund_status := v_refund_status;
  IF v_payment_status = 'captured' AND v_old_grand_total > v_new_grand_total THEN
    v_refund_delta := v_old_grand_total - v_new_grand_total;
    v_pending_refund_amount := COALESCE(v_pending_refund_amount, 0) + v_refund_delta;
    IF COALESCE(v_refund_status, 'none') NOT IN ('completed') THEN
      v_new_refund_status := 'processing';
    END IF;
  END IF;

  -- 100x FIX: Do NOT overwrite grand_total_collected! Preserve historical collected amount!
  UPDATE orders
  SET 
    total_amount = v_new_active_subtotal,
    s9_5_gst_amount = v_new_s9_5,
    non_food_gst_amount = v_new_non_food_gst,
    gst_item_total = v_new_gst_item_total,
    enything_commission = v_new_enything_commission,
    tcs_amount = v_new_tcs,
    tds_amount = v_new_tds,
    seller_payout = v_new_seller_payout,
    delivery_charges = v_delivery_charges,
    heavy_order_fee = v_new_heavy_order_fee,
    coupon_discount = LEAST(COALESCE(v_coupon_discount, 0), v_new_active_subtotal),
    grand_total = v_new_grand_total,
    pending_refund_amount = v_pending_refund_amount,
    refund_status = v_new_refund_status,
    updated_at = NOW()
  WHERE id = p_order_id;

  IF v_cart_group_id IS NOT NULL THEN
    PERFORM rebalance_active_delivery_fees(v_cart_group_id);
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'all_items_declined', false,
    'declined_count', v_declined_target_count,
    'remaining_active_count', v_active_items_count,
    'new_subtotal', v_new_active_subtotal,
    'new_grand_total', v_new_grand_total,
    'pending_refund_amount', v_pending_refund_amount,
    'refund_status', v_new_refund_status
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.decline_order_items_seller(UUID, UUID[], TEXT, TEXT) TO authenticated, service_role;


-- ── 8. Fortify get_seller_daily_stats (Partial Refund Preservation) ───────────
CREATE OR REPLACE FUNCTION public.get_seller_daily_stats(p_shop_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_seller_id    uuid;
    v_total_orders  integer := 0;
    v_pending_orders integer := 0;
    v_todays_earning numeric := 0.0;
    v_products       integer := 0;
BEGIN
  SELECT seller_id INTO v_seller_id FROM public.shops WHERE id = p_shop_id;

  IF v_seller_id IS NULL THEN
    RAISE EXCEPTION 'Shop not found.';
  END IF;

  IF auth.uid() != v_seller_id AND NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: You can only view stats for your own shop.';
  END IF;

  SELECT count(*) INTO v_total_orders
  FROM orders
  WHERE shop_id = p_shop_id
    AND status NOT IN ('cancelled', 'seller_rejected');

  SELECT count(*) INTO v_pending_orders
  FROM orders
  WHERE shop_id = p_shop_id
    AND status IN ('pending', 'awaiting_acceptance');

  -- 100x FIX: Only zero payout if full cancellation/refund!
  -- On partial item declines where order was delivered, the seller legitimately earned seller_payout!
  SELECT COALESCE(SUM(
    CASE
      WHEN status IN ('cancelled', 'seller_rejected', 'partner_rejected', 'shop_dispute_cancel', 'timeout', 'failed', 'returned', 'refunded') THEN 0
      WHEN COALESCE(refund_status, 'none') IN ('processing', 'completed') AND COALESCE(pending_refund_amount, 0) >= COALESCE(grand_total_collected, grand_total, 0) THEN 0
      ELSE COALESCE(seller_payout, 0)
    END
    - COALESCE(wait_time_penalty, 0)
  ), 0.0) INTO v_todays_earning
  FROM orders
  WHERE shop_id = p_shop_id
    AND status = 'delivered'
    AND DATE(updated_at AT TIME ZONE 'Asia/Kolkata') = DATE(CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Kolkata');

  SELECT count(*) INTO v_products
  FROM products
  WHERE shop_id = p_shop_id AND is_deleted = false;

  RETURN json_build_object(
      'total_orders',   v_total_orders,
      'pending_orders', v_pending_orders,
      'todays_earning', v_todays_earning,
      'products',       v_products
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_seller_daily_stats(uuid) TO authenticated, service_role;


-- ── 9. Fortify get_seller_ca_report (Partial Refund Preservation) ─────────────
CREATE OR REPLACE FUNCTION public.get_seller_ca_report(
  p_shop_id uuid,
  p_start_date timestamptz,
  p_end_date timestamptz
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_seller_id uuid;
  v_result record;
BEGIN
  SELECT seller_id INTO v_seller_id FROM shops WHERE id = p_shop_id;
  
  IF (auth.uid() IS NULL OR v_seller_id IS DISTINCT FROM auth.uid()) AND NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  -- 100x FIX: Only exclude fully cancelled/refunded orders from base sales & taxes!
  -- Delivered orders with partial refunds must report their active delivered items!
  SELECT 
    COALESCE(SUM(CASE 
      WHEN status IN ('cancelled', 'seller_rejected', 'partner_rejected', 'shop_dispute_cancel', 'timeout', 'failed', 'returned', 'refunded') THEN 0
      WHEN COALESCE(refund_status, 'none') IN ('processing', 'processed', 'completed') AND COALESCE(pending_refund_amount, 0) >= COALESCE(grand_total_collected, grand_total, 0) THEN 0 
      ELSE total_amount 
    END), 0) as total_base_sales,

    COALESCE(SUM(CASE 
      WHEN status IN ('cancelled', 'seller_rejected', 'partner_rejected', 'shop_dispute_cancel', 'timeout', 'failed', 'returned', 'refunded') THEN 0
      WHEN COALESCE(refund_status, 'none') IN ('processing', 'processed', 'completed') AND COALESCE(pending_refund_amount, 0) >= COALESCE(grand_total_collected, grand_total, 0) THEN 0 
      ELSE non_food_gst_amount 
    END), 0) as non_food_gst,

    COALESCE(SUM(CASE 
      WHEN status IN ('cancelled', 'seller_rejected', 'partner_rejected', 'shop_dispute_cancel', 'timeout', 'failed', 'returned', 'refunded') THEN 0
      WHEN COALESCE(refund_status, 'none') IN ('processing', 'processed', 'completed') AND COALESCE(pending_refund_amount, 0) >= COALESCE(grand_total_collected, grand_total, 0) THEN 0 
      ELSE s9_5_gst_amount 
    END), 0) as s9_5_gst,

    COALESCE(SUM(gst_delivery), 0) as delivery_gst,
    COALESCE(SUM(gst_platform), 0) as platform_gst,

    COALESCE(SUM(CASE 
      WHEN status IN ('cancelled', 'seller_rejected', 'partner_rejected', 'shop_dispute_cancel', 'timeout', 'failed', 'returned', 'refunded') THEN 0
      WHEN COALESCE(refund_status, 'none') IN ('processing', 'processed', 'completed') AND COALESCE(pending_refund_amount, 0) >= COALESCE(grand_total_collected, grand_total, 0) THEN 0 
      ELSE tcs_amount 
    END), 0) as tcs_deducted,

    COALESCE(SUM(CASE 
      WHEN status IN ('cancelled', 'seller_rejected', 'partner_rejected', 'shop_dispute_cancel', 'timeout', 'failed', 'returned', 'refunded') THEN 0
      WHEN COALESCE(refund_status, 'none') IN ('processing', 'processed', 'completed') AND COALESCE(pending_refund_amount, 0) >= COALESCE(grand_total_collected, grand_total, 0) THEN 0 
      ELSE tds_amount 
    END), 0) as tds_deducted,

    COALESCE(SUM(CASE 
      WHEN status IN ('cancelled', 'seller_rejected', 'partner_rejected', 'shop_dispute_cancel', 'timeout', 'failed', 'returned', 'refunded') THEN 0
      WHEN COALESCE(refund_status, 'none') IN ('processing', 'processed', 'completed') AND COALESCE(pending_refund_amount, 0) >= COALESCE(grand_total_collected, grand_total, 0) THEN 0 
      ELSE enything_commission 
    END), 0) as commission,

    COALESCE(SUM(
      CASE 
        WHEN status IN ('cancelled', 'seller_rejected', 'partner_rejected', 'shop_dispute_cancel', 'timeout', 'failed', 'returned', 'refunded') THEN 0
        WHEN COALESCE(refund_status, 'none') IN ('processing', 'processed', 'completed') AND COALESCE(pending_refund_amount, 0) >= COALESCE(grand_total_collected, grand_total, 0) THEN 0 
        ELSE COALESCE(seller_payout, 0) 
      END 
      - COALESCE(wait_time_penalty, 0)
    ), 0) as seller_payout,

    COALESCE(SUM(CASE 
      WHEN status IN ('cancelled', 'seller_rejected', 'partner_rejected', 'shop_dispute_cancel', 'timeout', 'failed', 'returned', 'refunded') THEN 0
      WHEN COALESCE(refund_status, 'none') IN ('processed', 'completed') AND COALESCE(pending_refund_amount, 0) >= COALESCE(grand_total_collected, grand_total, 0) THEN 0 
      ELSE grand_total_collected 
    END), 0) as grand_collected,

    COALESCE(SUM(gateway_deduction), 0) as gateway_fees,
    COUNT(*) as delivered_orders
  INTO v_result
  FROM orders
  WHERE shop_id = p_shop_id
    AND status = 'delivered'
    AND updated_at >= p_start_date
    AND updated_at < p_end_date;

  RETURN json_build_object(
    'total_base_sales', v_result.total_base_sales,
    'non_food_gst', v_result.non_food_gst,
    's9_5_gst', v_result.s9_5_gst,
    'delivery_gst', v_result.delivery_gst,
    'platform_gst', v_result.platform_gst,
    'tcs_deducted', v_result.tcs_deducted,
    'tds_deducted', v_result.tds_deducted,
    'commission', v_result.commission,
    'seller_payout', v_result.seller_payout,
    'grand_collected', v_result.grand_collected,
    'gateway_fees', v_result.gateway_fees,
    'delivered_orders', v_result.delivered_orders
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_seller_ca_report(UUID, TIMESTAMPTZ, TIMESTAMPTZ) TO authenticated, service_role;


-- ── 10. Fortify admin_issue_refund (Handle Partial Refunds Gracefully) ────────
CREATE OR REPLACE FUNCTION public.admin_issue_refund(p_order_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
  v_payment_status text;
  v_refund_status text;
  v_cart_group_id uuid;
  v_grand_total_collected numeric;
BEGIN
  IF NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;

  SELECT cart_group_id INTO v_cart_group_id FROM orders WHERE id = p_order_id;
  
  IF v_cart_group_id IS NOT NULL THEN
    PERFORM id FROM orders WHERE cart_group_id = v_cart_group_id ORDER BY id FOR UPDATE;
  ELSE
    PERFORM id FROM orders WHERE id = p_order_id FOR UPDATE;
  END IF;

  SELECT status, payment_status, refund_status, grand_total_collected 
  INTO v_status, v_payment_status, v_refund_status, v_grand_total_collected
  FROM orders WHERE id = p_order_id;

  IF v_status = 'delivered' THEN
    RAISE EXCEPTION 'Cannot refund a delivered order directly without dispute';
  END IF;

  -- 100x FIX: If refund is already completed, disallow duplicate
  IF v_refund_status = 'completed' THEN
    RAISE EXCEPTION 'Refund is already completed. Cannot trigger duplicate refund.';
  END IF;

  IF v_payment_status != 'captured' THEN
    RAISE EXCEPTION 'Order % has no captured payment to refund.', p_order_id;
  END IF;

  -- Update order to cancelled and set full pending refund amount
  UPDATE orders
  SET 
    status = 'cancelled',
    cancelled_reason = 'admin',
    refund_status = 'processing',
    pending_refund_amount = COALESCE(v_grand_total_collected, grand_total, 0),
    rider_earnings = CASE WHEN v_status IN ('picked_up', 'out_for_delivery') THEN rider_earnings ELSE 0 END,
    wait_time_penalty = 0,
    updated_at = NOW()
  WHERE id = p_order_id;

  -- Rebalance delivery fees for surviving siblings
  IF v_cart_group_id IS NOT NULL THEN
    PERFORM public.rebalance_active_delivery_fees(v_cart_group_id);
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_issue_refund(UUID) TO authenticated, service_role;
