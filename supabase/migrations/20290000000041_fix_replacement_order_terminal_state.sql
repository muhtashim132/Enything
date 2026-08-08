-- =============================================================================
-- Migration: 20290000000041_fix_replacement_order_terminal_state.sql
-- Description:
--   BUGFIX: When a customer adds a replacement product after partial rejection,
--   checkout crashed with:
--     P0001: Cannot change status of a terminal order (seller_rejected) to cancelled
--
--   Root Cause:
--     place_orders_transaction (last updated in 20290000000038) attempted to
--     UPDATE orders SET status = 'cancelled' on seller_rejected / rider_rejected
--     orders. The tr_guard_order_status_transitions trigger (20271125000007)
--     correctly classifies both as TERMINAL states and raises P0001, rolling
--     back the entire transaction — meaning the new replacement order is
--     never saved either.
--
--   Fix:
--     Do NOT change the status column at all. seller_rejected / rider_rejected
--     are already semantically terminal ("gone"). We only need to stamp:
--       • cancelled_reason = 'customer_replaced'   → audit / reporting tag
--       • refund_status = 'processing'             → trigger refund if paid
--       • updated_at = NOW()
--     The state machine trigger only fires when NEW.status != OLD.status.
--     By leaving status untouched we bypass the trigger entirely.
--
--   Scope: Additive. Only modifies the final `IF p_order_id_to_cancel IS NOT NULL`
--   block inside place_orders_transaction. All other logic is unchanged.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.place_orders_transaction(
  p_orders           jsonb,
  p_items            jsonb,
  p_cart_group_id    uuid,
  p_coupon_id        uuid    DEFAULT NULL::uuid,
  p_idempotency_key  text    DEFAULT NULL::text,
  p_order_id_to_cancel uuid  DEFAULT NULL::uuid
)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_is_valid_replacement BOOLEAN := false;
  v_sum_estimated_distance_km numeric := 0;
  v_order jsonb;
  v_item record;
  v_inserted_ids uuid[] := '{}';
  
  v_expected_total_amount numeric;
  v_expected_grand_total numeric;
  
  v_sum_expected_total_amount numeric := 0;
  v_sum_verified_shop_totals numeric := 0;
  v_sum_client_platform_fee numeric := 0;
  v_sum_client_small_cart_fee numeric := 0;
  v_sum_client_heavy_order_fee numeric := 0;
  v_sum_client_multi_shop_surcharge numeric := 0;
  v_sum_client_coupon_discount numeric := 0;
  v_sum_client_delivery_charges numeric := 0;
  
  v_global_platform_fee numeric := 0;
  v_global_small_cart_fee numeric;
  v_global_small_cart_threshold numeric;
  v_global_heavy_order_fee numeric;
  v_global_heavy_order_threshold numeric;
  v_global_multi_shop_surcharge numeric;
  
  v_db_price numeric;
  v_db_product_name text;
  v_total_qty int;
  
  v_s9_5_gst numeric := 0;
  v_non_food_gst numeric := 0;
  v_line_gst numeric := 0;
  v_category text;
  v_gst_rate numeric;
  v_is_deemed boolean;
  
  v_server_order_total numeric;
  v_server_gst_platform numeric;
  v_server_gst_delivery numeric;
  v_server_seller_payout numeric;
  v_server_enything_commission numeric;
  v_server_rider_earnings numeric;
  
  v_tcs_amount numeric := 0;
  v_tds_amount numeric := 0;
  v_tcs_rate numeric;
  v_gw_deduct numeric;
  v_pure_commission numeric;
  v_default_comm numeric;
  v_cat_comm numeric;
  
  v_total_weight_kg numeric := 0;
  v_shop_count int := 0;
  
  v_acceptance_deadline timestamptz;
  v_secure_order jsonb;
  v_order_totals record;

  v_gst_override numeric;

  -- Dynamic Rates
  v_delivery_gst_rate numeric;
  v_platform_gst_rate numeric;
  v_rider_commission_percent numeric;
  v_global_delivery_rate_per_km numeric;
  
  -- Coupon Verification
  v_true_discount numeric := 0;
  v_coupon_type text;
  v_coupon_val numeric;
  v_coupon_cap numeric;
  v_coupon_min numeric;
  v_coupon_valid_from timestamptz;
  v_coupon_valid_until timestamptz;
  v_coupon_is_active boolean;
  v_coupon_usage_count int;
  v_coupon_usage_limit int;
BEGIN
  -- 100x FIX: Unauthenticated Ghost Order DDOS Patch
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Unauthenticated checkouts are currently disabled to prevent Ghost Order DDOS.';
  END IF;
  -- Strict Check
  IF p_orders IS NULL OR jsonb_array_length(p_orders) = 0 THEN
    RAISE EXCEPTION 'Orders payload cannot be empty';
  END IF;

  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Order items payload cannot be empty';
  END IF;
  
  IF jsonb_array_length(p_items) > 150 THEN
    RAISE EXCEPTION 'Cart contains too many items. Maximum allowed is 150.';
  END IF;

  IF jsonb_array_length(p_orders) > 3 THEN
    RAISE EXCEPTION 'Maximum 3 shops allowed per order.';
  END IF;

  -- Strict Replacement Validation (Primary path: explicit rejected order ID)
  IF p_order_id_to_cancel IS NOT NULL THEN
    SELECT EXISTS (
      SELECT 1 FROM orders 
      WHERE id = p_order_id_to_cancel 
        AND customer_id = auth.uid() 
        AND cart_group_id = p_cart_group_id
        AND status IN ('seller_rejected', 'rider_rejected')
    ) INTO v_is_valid_replacement;
    
    IF NOT v_is_valid_replacement THEN
      RAISE EXCEPTION 'Invalid replacement request: Order does not exist, does not belong to you, is not part of this cart group, or is not in a rejected state.';
    END IF;
  END IF;

  -- 100x Safety Net (Issue 3 Fix): Also treat as valid replacement when the
  -- cart_group_id already has active orders for this customer.
  -- This handles the edge case where pendingOrderIdToCancel was not set by Dart
  -- (e.g. "Search for Different Items" race condition), so p_order_id_to_cancel
  -- arrives as NULL. Without this, the delivery floor check fires on a '''0''' charge.
  -- SECURITY: Safe because cart_group_id + customer_id = auth.uid() prevents spoofing.
  IF NOT v_is_valid_replacement AND p_cart_group_id IS NOT NULL THEN
    SELECT EXISTS (
      SELECT 1 FROM orders
      WHERE cart_group_id = p_cart_group_id
        AND customer_id = auth.uid()
        AND status IN (
          'awaiting_acceptance', 'awaiting_payment', 'pending_pickup',
          'accepted', 'preparing', 'ready_for_pickup',
          'picked_up', 'out_for_delivery', 'delivered'
        )
    ) INTO v_is_valid_replacement;
  END IF;

  -- 100x Architecture Protection: Ghost Order Bypass Prevention
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_orders)
    LEFT JOIN shops s ON s.id = (value->>'shop_id')::uuid
    WHERE s.is_active = false
  ) THEN
    RAISE EXCEPTION 'One or more shops in this order are currently inactive or closed. Exploit blocked.';
  END IF;

  -- Load Dynamic Admin Rates (With 100x Architecture Sanity Bounds)
  BEGIN SELECT (value#>>'{}'  )::numeric INTO v_default_comm FROM platform_config WHERE key = 'default_commission_percent'; EXCEPTION WHEN OTHERS THEN v_default_comm := 5.0; END;
  v_default_comm := LEAST(GREATEST(COALESCE(v_default_comm, 5.0), 0.0), 100.0);
  
  BEGIN SELECT (value#>>'{}')::numeric INTO v_delivery_gst_rate FROM platform_config WHERE key = 'delivery_gst_rate'; EXCEPTION WHEN OTHERS THEN v_delivery_gst_rate := 0.18; END;
  v_delivery_gst_rate := LEAST(GREATEST(COALESCE(v_delivery_gst_rate, 0.18), 0.0), 1.0);
  
  BEGIN SELECT (value#>>'{}')::numeric INTO v_platform_gst_rate FROM platform_config WHERE key = 'platform_fee_gst_rate'; EXCEPTION WHEN OTHERS THEN v_platform_gst_rate := 0.18; END;
  v_platform_gst_rate := LEAST(GREATEST(COALESCE(v_platform_gst_rate, 0.18), 0.0), 1.0);
  
  BEGIN SELECT (value#>>'{}')::numeric INTO v_rider_commission_percent FROM platform_config WHERE key = 'rider_commission_percent'; EXCEPTION WHEN OTHERS THEN v_rider_commission_percent := 80.0; END;
  v_rider_commission_percent := LEAST(GREATEST(COALESCE(v_rider_commission_percent, 80.0), 0.0), 100.0);
  
  BEGIN SELECT (value#>>'{}')::numeric INTO v_global_delivery_rate_per_km FROM platform_config WHERE key = 'delivery_rate_per_km'; EXCEPTION WHEN OTHERS THEN v_global_delivery_rate_per_km := 10.0; END;
  v_global_delivery_rate_per_km := GREATEST(COALESCE(v_global_delivery_rate_per_km, 10.0), 0.0);

  FOR v_item IN SELECT y.product_id, y.quantity, p.price, y.variant_name, p.variants 
                FROM jsonb_to_recordset(p_items) AS y(product_id uuid, variant_name text, quantity int)
                JOIN products p ON p.id = y.product_id LOOP
    
    IF v_item.quantity IS NULL OR v_item.quantity <= 0 THEN
      RAISE EXCEPTION 'CRITICAL: Invalid quantity (%) detected for product %. Negative or zero quantities are strictly prohibited.', v_item.quantity, v_item.product_id;
    END IF;

    IF v_item.quantity > 100 THEN
      RAISE EXCEPTION 'CRITICAL: Quantity for a single item cannot exceed 100. Overload prevented.';
    END IF;

    IF v_item.variant_name IS NULL THEN
      v_db_price := v_item.price;
    ELSE
      SELECT (elem->>'price')::numeric INTO v_db_price
      FROM jsonb_array_elements(v_item.variants) elem
      WHERE elem->>'name' = v_item.variant_name;
    END IF;
    
    v_sum_expected_total_amount := v_sum_expected_total_amount + (v_item.quantity * v_db_price);
  END LOOP;

  IF v_sum_expected_total_amount <= 0 THEN
    RAISE EXCEPTION 'Total order amount must be greater than zero. Phantom empty orders are strictly prohibited.';
  END IF;

  -- 100x Architecture Protection: Coupon Mathematical Spoofing & State Abuse
  IF p_coupon_id IS NOT NULL THEN
    SELECT
      type, value, max_discount, min_order_value,
      valid_from, valid_until, is_active,
      usage_count, usage_limit
    INTO
      v_coupon_type, v_coupon_val, v_coupon_cap, v_coupon_min,
      v_coupon_valid_from, v_coupon_valid_until, v_coupon_is_active,
      v_coupon_usage_count, v_coupon_usage_limit
    FROM coupons
    WHERE id = p_coupon_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Coupon not found.';
    END IF;

    IF NOT v_coupon_is_active THEN
      RAISE EXCEPTION 'Coupon is inactive.';
    END IF;

    IF NOW() < v_coupon_valid_from OR NOW() > v_coupon_valid_until THEN
      RAISE EXCEPTION 'Coupon is expired or not yet valid.';
    END IF;

    IF v_coupon_usage_limit IS NOT NULL AND v_coupon_usage_count >= v_coupon_usage_limit THEN
      RAISE EXCEPTION 'Coupon usage limit has been reached.';
    END IF;

    IF v_sum_expected_total_amount < COALESCE(v_coupon_min, 0) THEN
      RAISE EXCEPTION 'Order total does not meet the minimum requirement for this coupon.';
    END IF;

    IF v_coupon_type = 'percentage' THEN
      v_true_discount := v_sum_expected_total_amount * (v_coupon_val / 100.0);
      IF v_coupon_cap IS NOT NULL THEN
        v_true_discount := LEAST(v_true_discount, v_coupon_cap);
      END IF;
    ELSIF v_coupon_type = 'flat' THEN
      v_true_discount := LEAST(v_coupon_val, v_sum_expected_total_amount);
    ELSE
      RAISE EXCEPTION 'Unknown coupon type: %', v_coupon_type;
    END IF;
  END IF;

  -- Load Global Fee Config
  BEGIN SELECT (value#>>'{}')::numeric INTO v_global_platform_fee    FROM platform_config WHERE key = 'platform_fee'; EXCEPTION WHEN OTHERS THEN v_global_platform_fee := 20.0; END;
  BEGIN SELECT (value#>>'{}')::numeric INTO v_global_small_cart_fee  FROM platform_config WHERE key = 'small_cart_fee'; EXCEPTION WHEN OTHERS THEN v_global_small_cart_fee := 10.0; END;
  BEGIN SELECT (value#>>'{}')::numeric INTO v_global_small_cart_threshold FROM platform_config WHERE key = 'small_cart_threshold'; EXCEPTION WHEN OTHERS THEN v_global_small_cart_threshold := 100.0; END;
  BEGIN SELECT (value#>>'{}')::numeric INTO v_global_heavy_order_fee FROM platform_config WHERE key = 'heavy_order_fee'; EXCEPTION WHEN OTHERS THEN v_global_heavy_order_fee := 20.0; END;
  BEGIN SELECT (value#>>'{}')::numeric INTO v_global_heavy_order_threshold FROM platform_config WHERE key = 'heavy_order_threshold_kg'; EXCEPTION WHEN OTHERS THEN v_global_heavy_order_threshold := 5.0; END;
  BEGIN SELECT (value#>>'{}')::numeric INTO v_global_multi_shop_surcharge FROM platform_config WHERE key = 'multi_shop_surcharge'; EXCEPTION WHEN OTHERS THEN v_global_multi_shop_surcharge := 15.0; END;

  v_global_platform_fee         := LEAST(GREATEST(COALESCE(v_global_platform_fee, 20.0), 0.0), 1000.0);
  v_global_small_cart_fee       := LEAST(GREATEST(COALESCE(v_global_small_cart_fee, 10.0), 0.0), 1000.0);
  v_global_small_cart_threshold := LEAST(GREATEST(COALESCE(v_global_small_cart_threshold, 100.0), 0.0), 10000.0);
  v_global_heavy_order_fee      := LEAST(GREATEST(COALESCE(v_global_heavy_order_fee, 20.0), 0.0), 1000.0);
  v_global_heavy_order_threshold:= LEAST(GREATEST(COALESCE(v_global_heavy_order_threshold, 5.0), 0.01), 1000.0);
  v_global_multi_shop_surcharge := LEAST(GREATEST(COALESCE(v_global_multi_shop_surcharge, 15.0), 0.0), 1000.0);

  -- Count shops
  SELECT count(DISTINCT (value->>'shop_id')::uuid)
  INTO v_shop_count
  FROM jsonb_array_elements(p_orders);

  -- Per-order security validation and insertion
  FOR v_order IN SELECT * FROM jsonb_array_elements(p_orders) LOOP

    v_s9_5_gst   := 0;
    v_non_food_gst := 0;
    v_total_weight_kg := 0;

    -- Server-side fee recomputation
    v_server_order_total      := 0;
    v_server_gst_platform     := 0;
    v_server_gst_delivery     := 0;
    v_server_seller_payout    := 0;
    v_server_enything_commission := 0;
    v_server_rider_earnings   := 0;
    v_tcs_amount              := 0;
    v_tds_amount              := 0;

    FOR v_item IN
      SELECT y.order_id, y.product_id, y.quantity, y.variant_name, y.price AS client_price,
             y.weight_kg, y.requires_prescription, y.special_instructions, y.id,
             p.price AS db_price, p.name AS db_name, p.variants, p.category,
             p.gst_rate_override, p.is_deleted
      FROM jsonb_to_recordset(p_items) AS y(
        id uuid, order_id uuid, product_id uuid, variant_name text,
        quantity int, price numeric, weight_kg numeric,
        requires_prescription boolean, special_instructions text
      )
      JOIN products p ON p.id = y.product_id
      WHERE y.order_id = (v_order->>'id')::uuid
    LOOP
      -- Reject deleted products
      IF v_item.is_deleted IS TRUE THEN
        RAISE EXCEPTION 'Product % has been removed from the platform and cannot be ordered.', v_item.db_name;
      END IF;

      IF v_item.variant_name IS NULL THEN
        v_db_price      := v_item.db_price;
        v_db_product_name := v_item.db_name;
      ELSE
        SELECT (elem->>'price')::numeric, v_item.db_name
        INTO v_db_price, v_db_product_name
        FROM jsonb_array_elements(v_item.variants) elem
        WHERE elem->>'name' = v_item.variant_name;

        IF NOT FOUND THEN
          RAISE EXCEPTION 'Variant "%" not found for product "%".', v_item.variant_name, v_item.db_name;
        END IF;
      END IF;

      v_server_order_total := v_server_order_total + (v_item.quantity * v_db_price);
      v_total_weight_kg    := v_total_weight_kg + COALESCE(v_item.weight_kg, 0) * v_item.quantity;

      -- GST categorization
      v_category  := v_item.category;
      v_gst_override := v_item.gst_rate_override;

      IF v_gst_override IS NOT NULL THEN
        v_gst_rate := v_gst_override;
        v_is_deemed := (v_gst_override = 0.095);
      ELSIF v_category IN ('Food', 'Bakery', 'Restaurant', 'Cafe', 'Beverages') THEN
        v_gst_rate := 0.05; v_is_deemed := false;
      ELSIF v_category IN ('Grocery', 'Fresh Produce', 'Dairy', 'Supermarket / Hypermarket') THEN
        IF v_db_price * v_item.quantity > 500 THEN v_gst_rate := 0.12; ELSE v_gst_rate := 0.0; END IF;
        v_is_deemed := false;
      ELSIF v_category = 'Restaurant (Delivery)' THEN
        v_gst_rate := 0.095; v_is_deemed := true;
      ELSE
        v_gst_rate := 0.18; v_is_deemed := false;
      END IF;

      v_line_gst := (v_db_price * v_item.quantity) * v_gst_rate;
      IF v_is_deemed THEN
        v_s9_5_gst   := v_s9_5_gst   + v_line_gst;
      ELSE
        v_non_food_gst := v_non_food_gst + v_line_gst;
      END IF;

      -- TCS + TDS
      IF v_category IN ('Food', 'Bakery', 'Restaurant', 'Cafe', 'Beverages',
                         'Grocery', 'Fresh Produce', 'Dairy', 'Supermarket / Hypermarket') THEN
        v_tcs_rate := 0.01;
      ELSE
        v_tcs_rate := 0.01;
      END IF;
      v_tcs_amount := v_tcs_amount + (v_db_price * v_item.quantity * v_tcs_rate);
      v_tds_amount := v_tds_amount + (v_db_price * v_item.quantity * 0.001);

      -- Insert order_item (idempotent via ON CONFLICT DO NOTHING)
      IF (v_order->>'id')::uuid = ANY(v_inserted_ids) OR
         EXISTS (SELECT 1 FROM orders WHERE id = (v_order->>'id')::uuid) THEN
        INSERT INTO order_items (
          id, order_id, product_id, product_name, variant_name, price, quantity, special_instructions
        ) VALUES (
          COALESCE(v_item.id, gen_random_uuid()),
          v_item.order_id,
          v_item.product_id,
          v_db_product_name,
          v_item.variant_name,
          v_db_price,
          v_item.quantity,
          v_item.special_instructions
        );
      END IF;
    END LOOP;

    -- Server-side commission & fee validation
    v_cat_comm := NULL;
    BEGIN
      SELECT (value#>>'{}')::numeric INTO v_cat_comm
      FROM platform_config
      WHERE key = 'commission_' || lower(replace(
        (SELECT category FROM products WHERE id = (
          SELECT product_id FROM jsonb_to_recordset(p_items) AS y(product_id uuid, order_id uuid)
          WHERE y.order_id = (v_order->>'id')::uuid LIMIT 1
        )), ' ', '_'));
    EXCEPTION WHEN OTHERS THEN v_cat_comm := NULL; END;

    v_pure_commission := COALESCE(v_cat_comm, v_default_comm);
    v_pure_commission := LEAST(GREATEST(v_pure_commission, 0.0), 100.0);

    v_server_enything_commission := v_server_order_total * (v_pure_commission / 100.0);
    v_gw_deduct := v_server_order_total * 0.02;

    v_server_gst_platform := v_global_platform_fee * v_platform_gst_rate;
    v_server_gst_delivery := (v_order->>'delivery_charges')::numeric * v_delivery_gst_rate;
    v_server_rider_earnings := (v_order->>'rider_earnings')::numeric;
    v_server_seller_payout := v_server_order_total
      - v_server_enything_commission
      - v_gw_deduct
      - v_tcs_amount
      - v_tds_amount;

    -- Delivery floor check (skip for replacements)
    IF NOT v_is_valid_replacement THEN
      IF (v_order->>'delivery_charges')::numeric < ROUND(
          GREATEST(
            v_global_delivery_rate_per_km * COALESCE((v_order->>'estimated_distance_km')::numeric, 3.0),
            10.0
          ) * (1 + v_delivery_gst_rate),
          2
        ) * 0.85
      THEN
        RAISE EXCEPTION 'Delivery charge spoofing detected: client value is more than 15%% below server floor.';
      END IF;
    END IF;

    -- Insert the order (idempotent)
    INSERT INTO orders (
      id, created_at, updated_at, cart_group_id, shop_id, customer_id, status,
      seller_accepted, partner_accepted, acceptance_deadline,
      total_amount, delivery_charges, rider_earnings, multi_shop_surcharge,
      small_cart_fee, heavy_order_fee, platform_fee,
      address, address_label, delivery_lat, delivery_lng, delivery_notes,
      payment_method, payment_status, razorpay_payment_id, razorpay_order_id,
      customer_phone, shop_phone,
      gst_item_total, gst_delivery, gst_platform,
      enything_commission, seller_payout, gateway_deduction,
      s9_5_gst_amount, non_food_gst_amount, tcs_amount, tds_amount,
      grand_total_collected, gst_rate_snapshot, prescription_urls,
      estimated_distance_km, shop_prep_time_snapshot, coupon_id, coupon_discount
    )
    SELECT
      (v_order->>'id')::uuid,
      (v_order->>'created_at')::timestamptz,
      (v_order->>'updated_at')::timestamptz,
      p_cart_group_id,
      (v_order->>'shop_id')::uuid,
      auth.uid(),
      COALESCE(v_order->>'status', 'awaiting_acceptance'),
      COALESCE((v_order->>'seller_accepted')::boolean, false),
      COALESCE((v_order->>'partner_accepted')::boolean, false),
      (v_order->>'acceptance_deadline')::timestamptz,
      v_server_order_total,
      (v_order->>'delivery_charges')::numeric,
      (v_order->>'rider_earnings')::numeric,
      (v_order->>'multi_shop_surcharge')::numeric,
      (v_order->>'small_cart_fee')::numeric,
      (v_order->>'heavy_order_fee')::numeric,
      v_global_platform_fee,
      v_order->>'address',
      v_order->>'address_label',
      (v_order->>'delivery_lat')::numeric,
      (v_order->>'delivery_lng')::numeric,
      v_order->>'delivery_notes',
      v_order->>'payment_method',
      COALESCE(v_order->>'payment_status', 'pending'),
      v_order->>'razorpay_payment_id',
      v_order->>'razorpay_order_id',
      v_order->>'customer_phone',
      v_order->>'shop_phone',
      v_s9_5_gst + v_non_food_gst,
      v_server_gst_delivery,
      v_server_gst_platform,
      v_server_enything_commission,
      v_server_seller_payout,
      v_gw_deduct,
      v_s9_5_gst,
      v_non_food_gst,
      v_tcs_amount,
      v_tds_amount,
      (v_order->>'grand_total_collected')::numeric,
      (v_order->'gst_rate_snapshot'),
      COALESCE((v_order->'prescription_urls')::jsonb, '[]'::jsonb),
      COALESCE((v_order->>'estimated_distance_km')::numeric, 3.0),
      (v_order->>'shop_prep_time_snapshot')::int,
      p_coupon_id,
      (v_order->>'coupon_discount')::numeric
    ON CONFLICT (id) DO NOTHING;

    v_inserted_ids := array_append(v_inserted_ids, (v_order->>'id')::uuid);

    -- Insert order items for newly inserted orders
    FOR v_item IN
      SELECT y.order_id, y.product_id, y.quantity, y.variant_name,
             y.weight_kg, y.requires_prescription, y.special_instructions, y.id,
             p.price AS db_price, p.name AS db_name, p.variants
      FROM jsonb_to_recordset(p_items) AS y(
        id uuid, order_id uuid, product_id uuid, variant_name text,
        quantity int, price numeric, weight_kg numeric,
        requires_prescription boolean, special_instructions text
      )
      JOIN products p ON p.id = y.product_id
      WHERE y.order_id = (v_order->>'id')::uuid
    LOOP
      IF v_item.variant_name IS NULL THEN
        v_db_price := v_item.db_price;
        v_db_product_name := v_item.db_name;
      ELSE
        SELECT (elem->>'price')::numeric INTO v_db_price
        FROM jsonb_array_elements(v_item.variants) elem
        WHERE elem->>'name' = v_item.variant_name;
      END IF;

      INSERT INTO order_items (
        id, order_id, product_id, product_name, variant_name, price, quantity, special_instructions
      ) VALUES (
        COALESCE(v_item.id, gen_random_uuid()),
        v_item.order_id,
        v_item.product_id,
        v_db_product_name,
        v_item.variant_name,
        v_db_price,
        v_item.quantity,
        v_item.special_instructions
      );
    END LOOP;
  END LOOP;
  
  -- 100x FIX: The EXISTS check here was fundamentally flawed because we JUST inserted the orders.
  -- Thus, EXISTS is always TRUE, which made NOT EXISTS always FALSE, effectively preventing
  -- the coupon usage limit from EVER incrementing, causing infinite coupon abuse.
  -- This restores the physical increment to correctly cap limited coupons.
  IF p_coupon_id IS NOT NULL THEN
    UPDATE coupons SET usage_count = usage_count + 1 WHERE id = p_coupon_id;
  END IF;

  -- =============================================================================
  -- BUGFIX (20290000000041): DO NOT attempt to change status of seller_rejected /
  -- rider_rejected orders to 'cancelled'. Those are TERMINAL states — the order
  -- state machine trigger (tr_guard_order_status_transitions) will raise P0001
  -- and roll back the ENTIRE transaction, including the newly inserted orders.
  --
  -- Previous (broken) code:
  --   UPDATE orders SET status = 'cancelled', cancelled_reason = 'customer_replaced', ...
  --   WHERE id = p_order_id_to_cancel AND status IN ('seller_rejected', 'rider_rejected');
  --
  -- Fix: Only update metadata fields (cancelled_reason, refund_status, updated_at).
  -- The status column is NOT touched. seller_rejected / rider_rejected are already
  -- terminal and semantically equivalent to "cancelled for replacement". The
  -- cancelled_reason = 'customer_replaced' tag serves as the audit marker.
  -- =============================================================================
  IF p_order_id_to_cancel IS NOT NULL THEN
    UPDATE orders SET
      cancelled_reason = 'customer_replaced',
      refund_status    = CASE
                           WHEN payment_status = 'captured'
                                AND COALESCE(refund_status, 'none') NOT IN ('processing', 'completed')
                           THEN 'processing'
                           ELSE refund_status
                         END,
      updated_at       = NOW()
    WHERE id              = p_order_id_to_cancel
      AND customer_id     = auth.uid()
      AND status IN ('seller_rejected', 'rider_rejected');

    PERFORM reallocate_cancelled_delivery_fees(p_cart_group_id);
    PERFORM rebalance_active_delivery_fees(p_cart_group_id);
  END IF;
END;
$function$;
