-- =============================================================================
-- Migration: 20290000000092_100x_calculation_unification_and_edgecase_fortress.sql
-- =============================================================================
-- FIXES (ADDITIVE ONLY — no logic changes):
--
--   1. place_orders_transaction(): Commission key lookup reads ONLY
--      'commission_percent', but Admin Panel writes 'default_commission_percent'.
--      Fix: Read 'default_commission_percent' first, fall back to 'commission_percent'.
--      (Preserves all migration 91 features: ST_Y/ST_X PostGIS location resolution,
--       WeightEngine alignment, gateway deduction fixed 18% GST).
--
--   2. reallocate_cancelled_delivery_fees(): grand_total_collected formula
--      double-counts small_cart_fee, heavy_order_fee, and multi_shop_surcharge
--      because v_new_del (= delivery_charges) already bundles them with GST.
--      Fix: Remove the separate + v_new_small + v_new_heavy + v_new_surcharge.
--
--   3. rebalance_active_delivery_fees(): Same double-counting bug as #2.
--      Fix: Remove the separate + v_split_small + v_split_heavy + v_split_surcharge.
-- =============================================================================


-- ─────────────────────────────────────────────────────────────────────────────
-- FIX 1: place_orders_transaction — commission key aliasing
-- ─────────────────────────────────────────────────────────────────────────────

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
AS $function$
DECLARE
  v_order jsonb;
  v_item record;
  v_expected_total_amount numeric;
  v_expected_grand_total numeric;
  v_s9_5_gst numeric;
  v_non_food_gst numeric;
  v_tcs_amount numeric;
  v_tds_amount numeric;
  v_pure_commission numeric;
  v_default_comm numeric := 5.0;
  v_cat_comm numeric;
  v_category text;
  v_db_product_name text;
  v_gst_rate numeric;
  v_gst_override numeric;
  v_is_deemed boolean;
  v_tcs_rate numeric;
  v_line_gst numeric;
  v_slab_threshold numeric;
  v_slab_high_rate numeric;
  
  v_platform_gst_rate numeric := 0.18;
  v_delivery_gst_rate numeric := 0.18;
  v_rider_commission_percent numeric := 80.0;
  
  -- Fixed gateway GST rate (Razorpay's fee GST is always 18%, independent of platform_fee_gst_rate)
  v_gateway_gst_rate CONSTANT numeric := 0.18;
  
  v_server_gst_platform numeric;
  v_server_gst_delivery numeric;
  v_server_enything_commission numeric;
  v_server_seller_payout numeric;
  v_seller_gw_share numeric;
  v_server_rider_earnings numeric;
  v_gw_deduct numeric;
  
  v_inserted_ids uuid[] := '{}';
  v_inserted_item_ids uuid[] := '{}';
  v_secure_order jsonb;
  v_inventory_record record;
  v_acceptance_deadline timestamptz;
  
  v_coupon_record record;
  v_user_usage_count int;
  v_total_usage_count int;
  v_customer_id uuid;
  v_expected_discount numeric := 0;
  v_coupon_discount_sum numeric := 0;
  v_calculated_discount numeric := 0;
  v_client_claimed_discount numeric := 0;
  v_sum_expected_total_amount numeric := 0;
  v_sum_verified_shop_totals numeric := 0;

  v_shop_count int := 0;
  v_sum_client_multi_shop_surcharge numeric := 0;
  v_global_multi_shop_surcharge numeric := 20.0;
  
  v_global_delivery_base numeric := 20.0;
  v_sum_client_delivery_charges numeric := 0;
  v_expected_delivery_fee numeric := 0;

  v_total_weight_kg numeric := 0;
  v_sum_client_heavy_order_fee numeric := 0;
  v_global_heavy_order_fee numeric := 25.0;
  v_global_heavy_order_threshold numeric := 10.0;
  v_expected_heavy_order_fee numeric := 0.0;

  v_sum_client_small_cart_fee numeric := 0;
  v_global_small_cart_fee numeric := 15.0;
  v_global_small_cart_threshold numeric := 99.0;

  v_sum_client_platform_fee numeric := 0;
  v_global_platform_fee numeric := 20.0;
  v_expected_platform_fee numeric := 20.0;
  v_is_replacement boolean := false;

  v_existing_rider_id uuid := NULL;
  v_existing_partner_accepted boolean := false;
  v_existing_rider_phone text := NULL;
  
  v_shop_lat double precision;
  v_shop_lng double precision;
  v_dist_km double precision;
  v_max_radius_km double precision := 15.0;
  
  v_unit_weight numeric;
  v_unit_type text;
  v_clean_unit text;
  v_resolved_unit_weight_kg numeric;
  v_item_category text;
BEGIN
  IF p_idempotency_key IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(hashtext(p_idempotency_key));
    IF EXISTS (SELECT 1 FROM orders WHERE idempotency_key = p_idempotency_key::uuid) THEN
      RETURN jsonb_build_object(
        'success', true,
        'message', 'Order already placed (idempotent)',
        'order_ids', (SELECT jsonb_agg(id) FROM orders WHERE idempotency_key = p_idempotency_key::uuid)
      );
    END IF;
  END IF;

  v_customer_id := (p_orders->0->>'customer_id')::uuid;

  -- Detect if this is an additive / replacement order on an existing cart group
  IF p_order_id_to_cancel IS NOT NULL THEN
    v_is_replacement := true;
    
    -- Cancel non-terminal order
    UPDATE orders 
    SET status = 'cancelled', 
        cancelled_reason = 'Replaced by split cart checkout',
        updated_at = NOW()
    WHERE id = p_order_id_to_cancel 
      AND status IN ('pending', 'awaiting_payment', 'awaiting_acceptance');

    -- For already terminal orders (seller_rejected / partner_rejected), DO NOT touch status
    UPDATE orders 
    SET cancelled_reason = 'Replaced by split cart checkout',
        refund_status = CASE
                          WHEN payment_status = 'captured' AND COALESCE(refund_status, 'none') NOT IN ('processing', 'completed')
                          THEN 'processing'
                          ELSE refund_status
                        END,
        updated_at = NOW()
    WHERE id = p_order_id_to_cancel 
      AND status IN ('seller_rejected', 'partner_rejected');
  ELSIF p_cart_group_id IS NOT NULL THEN
    SELECT EXISTS (
      SELECT 1 FROM orders
      WHERE cart_group_id = p_cart_group_id
        AND customer_id = v_customer_id
        AND status IN (
          'awaiting_acceptance', 'awaiting_payment', 'pending_pickup',
          'accepted', 'preparing', 'ready_for_pickup',
          'picked_up', 'out_for_delivery', 'delivered', 'seller_rejected'
        )
    ) INTO v_is_replacement;
  END IF;

  -- Inherit assigned rider from existing active orders in this cart group
  IF p_cart_group_id IS NOT NULL THEN
    SELECT delivery_partner_id, partner_accepted, rider_phone
    INTO v_existing_rider_id, v_existing_partner_accepted, v_existing_rider_phone
    FROM orders
    WHERE cart_group_id = p_cart_group_id
      AND delivery_partner_id IS NOT NULL
      AND status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected')
    LIMIT 1;
  END IF;

  -- ═══════════════════════════════════════════════════════════════════════════
  -- FIX 1: Commission key aliasing.
  -- Admin Panel writes 'default_commission_percent' (see CommissionFeesPage).
  -- Read 'default_commission_percent' first, then fall back to 'commission_percent'.
  -- ═══════════════════════════════════════════════════════════════════════════
  BEGIN SELECT (value#>>'{}'  )::numeric INTO v_default_comm FROM platform_config WHERE key = 'default_commission_percent'; EXCEPTION WHEN OTHERS THEN v_default_comm := NULL; END;
  IF v_default_comm IS NULL THEN
    BEGIN SELECT (value#>>'{}'  )::numeric INTO v_default_comm FROM platform_config WHERE key = 'commission_percent'; EXCEPTION WHEN OTHERS THEN v_default_comm := 5.0; END;
  END IF;
  v_default_comm := LEAST(GREATEST(COALESCE(v_default_comm, 5.0), 0.0), 100.0);

  BEGIN SELECT (value#>>'{}'  )::numeric INTO v_platform_gst_rate FROM platform_config WHERE key = 'platform_fee_gst_rate'; EXCEPTION WHEN OTHERS THEN v_platform_gst_rate := 0.18; END;
  v_platform_gst_rate := LEAST(GREATEST(COALESCE(v_platform_gst_rate, 0.18), 0.0), 1.0);

  BEGIN SELECT (value#>>'{}'  )::numeric INTO v_delivery_gst_rate FROM platform_config WHERE key = 'delivery_gst_rate'; EXCEPTION WHEN OTHERS THEN v_delivery_gst_rate := 0.18; END;
  v_delivery_gst_rate := LEAST(GREATEST(COALESCE(v_delivery_gst_rate, 0.18), 0.0), 1.0);

  BEGIN SELECT (value#>>'{}'  )::numeric INTO v_rider_commission_percent FROM platform_config WHERE key = 'rider_commission_percent'; EXCEPTION WHEN OTHERS THEN v_rider_commission_percent := 80.0; END;
  v_rider_commission_percent := LEAST(GREATEST(COALESCE(v_rider_commission_percent, 80.0), 0.0), 100.0);

  BEGIN SELECT (value#>>'{}'  )::double precision INTO v_max_radius_km FROM platform_config WHERE key = 'max_delivery_radius_km'; EXCEPTION WHEN OTHERS THEN v_max_radius_km := 15.0; END;
  v_max_radius_km := GREATEST(COALESCE(v_max_radius_km, 15.0), 1.0);

  BEGIN SELECT (value#>>'{}'  )::numeric INTO v_global_delivery_base FROM platform_config WHERE key = 'delivery_base_fee'; EXCEPTION WHEN OTHERS THEN v_global_delivery_base := 20.0; END;
  v_global_delivery_base := GREATEST(COALESCE(v_global_delivery_base, 20.0), 0.0);

  BEGIN SELECT (value#>>'{}'  )::numeric INTO v_global_multi_shop_surcharge FROM platform_config WHERE key = 'multi_shop_surcharge'; EXCEPTION WHEN OTHERS THEN v_global_multi_shop_surcharge := 20.0; END;
  v_global_multi_shop_surcharge := GREATEST(COALESCE(v_global_multi_shop_surcharge, 20.0), 0.0);

  BEGIN SELECT (value#>>'{}'  )::numeric INTO v_global_platform_fee FROM platform_config WHERE key = 'platform_fee'; EXCEPTION WHEN OTHERS THEN v_global_platform_fee := 20.0; END;
  v_global_platform_fee := GREATEST(COALESCE(v_global_platform_fee, 20.0), 0.0);

  IF jsonb_array_length(p_orders) > 50 THEN
    RAISE EXCEPTION 'Bulk payload attack: Exceeded maximum 50 sub-orders per cart transaction.';
  END IF;

  IF jsonb_array_length(p_items) > 500 THEN
    RAISE EXCEPTION 'Bulk payload attack: Exceeded maximum 500 items per cart transaction.';
  END IF;

  FOR v_order IN SELECT * FROM jsonb_array_elements(p_orders) LOOP
    v_shop_count := v_shop_count + 1;
    v_sum_client_multi_shop_surcharge := v_sum_client_multi_shop_surcharge + COALESCE((v_order->>'multi_shop_surcharge')::numeric, 0);
    v_sum_client_heavy_order_fee := v_sum_client_heavy_order_fee + COALESCE((v_order->>'heavy_order_fee')::numeric, 0);
    v_sum_client_small_cart_fee := v_sum_client_small_cart_fee + COALESCE((v_order->>'small_cart_fee')::numeric, 0);
    v_sum_client_platform_fee := v_sum_client_platform_fee + COALESCE((v_order->>'platform_fee')::numeric, 0);
    v_sum_client_delivery_charges := v_sum_client_delivery_charges + COALESCE((v_order->>'delivery_charges')::numeric, 0);
    
    SELECT ST_Y(location::geometry), ST_X(location::geometry) INTO v_shop_lat, v_shop_lng FROM shops WHERE id = (v_order->>'shop_id')::uuid;
    IF v_shop_lat IS NOT NULL AND v_shop_lng IS NOT NULL 
       AND (v_order->>'delivery_lat') IS NOT NULL AND (v_order->>'delivery_lng') IS NOT NULL THEN
       v_dist_km := 6371.0 * acos(
         LEAST(1.0, GREATEST(-1.0, 
           cos(radians(v_shop_lat)) * cos(radians((v_order->>'delivery_lat')::double precision)) *
           cos(radians((v_order->>'delivery_lng')::double precision) - radians(v_shop_lng)) +
           sin(radians(v_shop_lat)) * sin(radians((v_order->>'delivery_lat')::double precision))
         ))
       );
       IF v_dist_km > (v_max_radius_km + 0.5) THEN
          RAISE EXCEPTION 'Geospatial validation failed: Shop % is % km away, exceeding max delivery radius of % km.', v_order->>'shop_id', round(v_dist_km::numeric, 2), v_max_radius_km;
       END IF;
    END IF;
  END LOOP;

  FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) AS x(
    product_id uuid, 
    variant_name text, 
    price numeric, 
    quantity int, 
    order_id uuid,
    weight_kg numeric
  ) LOOP
    IF v_item.price < 0 OR v_item.quantity <= 0 THEN
      RAISE EXCEPTION 'Negative financial smuggling detected: Invalid price (%) or quantity (%).', v_item.price, v_item.quantity;
    END IF;
    v_sum_expected_total_amount := v_sum_expected_total_amount + (v_item.quantity * v_item.price);
    
    -- 100x Universal Weight Resolution matching WeightEngine
    SELECT weight_per_unit, unit_type, category 
    INTO v_unit_weight, v_unit_type, v_item_category 
    FROM products 
    WHERE id = v_item.product_id;

    IF v_unit_weight IS NOT NULL AND v_unit_weight > 0 THEN
      v_clean_unit := lower(trim(COALESCE(v_unit_type, 'kg')));
      IF v_clean_unit IN ('g', 'gm', 'gms', 'gram', 'grams', 'ml', 'milliliter', 'milliliters', 'millilitre', 'millilitres') THEN
        v_resolved_unit_weight_kg := v_unit_weight / 1000.0;
      ELSIF v_clean_unit IN ('mg', 'milligram', 'milligrams') THEN
        v_resolved_unit_weight_kg := v_unit_weight / 1000000.0;
      ELSIF v_clean_unit IN ('kg', 'kilogram', 'kilograms', 'l', 'liter', 'liters', 'ltr', 'litre', 'litres') THEN
        v_resolved_unit_weight_kg := v_unit_weight;
      ELSIF v_clean_unit IN ('pieces', 'piece', 'pcs', 'pc') THEN
        IF v_unit_weight > 25.0 THEN
          v_resolved_unit_weight_kg := v_unit_weight / 1000.0;
        ELSE
          v_resolved_unit_weight_kg := v_unit_weight;
        END IF;
      ELSE
        IF v_unit_weight > 20.0 THEN
          v_resolved_unit_weight_kg := v_unit_weight / 1000.0;
        ELSE
          v_resolved_unit_weight_kg := v_unit_weight;
        END IF;
      END IF;

      IF v_item_category IN ('Clothing', 'Footwear', 'Pharmacy', 'Medical Store', 'Restaurant', 'Bakery', 'Fast Food', 'Beverages') AND v_resolved_unit_weight_kg > 20.0 THEN
        v_resolved_unit_weight_kg := v_resolved_unit_weight_kg / 1000.0;
      END IF;

      v_total_weight_kg := v_total_weight_kg + (v_resolved_unit_weight_kg * v_item.quantity);
    ELSIF v_item.weight_kg IS NOT NULL AND v_item.weight_kg > 0 THEN
      v_total_weight_kg := v_total_weight_kg + v_item.weight_kg;
    ELSE
      v_total_weight_kg := v_total_weight_kg + (0.5 * v_item.quantity);
    END IF;
  END LOOP;

  -- 1. Validate Small Cart Fee
  BEGIN SELECT (value#>>'{}'  )::numeric INTO v_global_small_cart_threshold FROM platform_config WHERE key = 'small_cart_threshold'; EXCEPTION WHEN OTHERS THEN v_global_small_cart_threshold := 99.0; END;
  v_global_small_cart_threshold := COALESCE(v_global_small_cart_threshold, 99.0);

  BEGIN SELECT (value#>>'{}'  )::numeric INTO v_global_small_cart_fee FROM platform_config WHERE key = 'small_cart_fee'; EXCEPTION WHEN OTHERS THEN v_global_small_cart_fee := 15.0; END;
  v_global_small_cart_fee := COALESCE(v_global_small_cart_fee, 15.0);

  IF v_sum_expected_total_amount > 0 AND v_sum_expected_total_amount < v_global_small_cart_threshold THEN
    IF NOT v_is_replacement AND ABS(v_sum_client_small_cart_fee - v_global_small_cart_fee) > 1.0 THEN
       RAISE EXCEPTION 'Small cart fee spoofing detected. Expected: %, Got: %', v_global_small_cart_fee, v_sum_client_small_cart_fee;
    END IF;
  ELSE
    IF v_sum_client_small_cart_fee > 0.01 THEN
       RAISE EXCEPTION 'Small cart fee applied incorrectly when cart total % is above threshold %.', v_sum_expected_total_amount, v_global_small_cart_threshold;
    END IF;
  END IF;

  -- 2. Validate Heavy Order Fee
  BEGIN SELECT (value#>>'{}'  )::numeric INTO v_global_heavy_order_fee FROM platform_config WHERE key = 'heavy_order_fee'; EXCEPTION WHEN OTHERS THEN v_global_heavy_order_fee := NULL; END;
  IF v_global_heavy_order_fee IS NULL THEN
    BEGIN SELECT (value#>>'{}'  )::numeric INTO v_global_heavy_order_fee FROM platform_config WHERE key = 'heavy_order_fee_per_kg'; EXCEPTION WHEN OTHERS THEN v_global_heavy_order_fee := 20.0; END;
  END IF;
  v_global_heavy_order_fee := COALESCE(v_global_heavy_order_fee, 20.0);

  BEGIN SELECT (value#>>'{}'  )::numeric INTO v_global_heavy_order_threshold FROM platform_config WHERE key = 'heavy_order_threshold_kg'; EXCEPTION WHEN OTHERS THEN v_global_heavy_order_threshold := 10.0; END;
  v_global_heavy_order_threshold := COALESCE(v_global_heavy_order_threshold, 10.0);

  IF v_total_weight_kg > v_global_heavy_order_threshold THEN
    v_expected_heavy_order_fee := v_global_heavy_order_fee * CEIL(v_total_weight_kg - v_global_heavy_order_threshold);
    IF NOT v_is_replacement AND ABS(v_sum_client_heavy_order_fee - v_expected_heavy_order_fee) > 1.5 THEN
       IF ABS(v_sum_client_heavy_order_fee - v_global_heavy_order_fee) > 1.5 THEN
          RAISE EXCEPTION 'Heavy order fee spoofing detected. Expected: %, Got: %', v_expected_heavy_order_fee, v_sum_client_heavy_order_fee;
       END IF;
    END IF;
  ELSE
    IF v_sum_client_heavy_order_fee > 0.01 THEN
       RAISE EXCEPTION 'Heavy order fee applied incorrectly. Weight % is below threshold %.', v_total_weight_kg, v_global_heavy_order_threshold;
    END IF;
  END IF;

  -- 3. Validate Multi-Shop Surcharge
  IF v_shop_count > 1 AND NOT v_is_replacement THEN
    IF ABS(v_sum_client_multi_shop_surcharge - (v_global_multi_shop_surcharge * (v_shop_count - 1))) > 1.0 THEN
       RAISE EXCEPTION 'Multi shop surcharge spoofing detected. Expected: %, Got: %', (v_global_multi_shop_surcharge * (v_shop_count - 1)), v_sum_client_multi_shop_surcharge;
    END IF;
  END IF;

  -- 4. Validate Flat Handling / Platform Fee (Flat per cart)
  IF v_is_replacement THEN
    v_expected_platform_fee := 0.0;
  ELSE
    v_expected_platform_fee := v_global_platform_fee;
  END IF;

  IF ABS(v_sum_client_platform_fee - v_expected_platform_fee) > 1.0 THEN
     RAISE EXCEPTION 'Handling fee spoofing detected. Expected: %, Got: %', v_expected_platform_fee, v_sum_client_platform_fee;
  END IF;

  -- 5. Validate Delivery Fee
  IF v_is_replacement THEN
    v_expected_delivery_fee := (v_sum_client_multi_shop_surcharge + v_sum_client_heavy_order_fee + v_sum_client_small_cart_fee) * (1.0 + v_delivery_gst_rate);
  ELSE
    v_expected_delivery_fee := (v_global_delivery_base + v_sum_client_multi_shop_surcharge + v_sum_client_heavy_order_fee + v_sum_client_small_cart_fee) * (1.0 + v_delivery_gst_rate);
  END IF;

  IF ABS(v_sum_client_delivery_charges - v_expected_delivery_fee) > 1.5 THEN
     RAISE EXCEPTION 'Delivery fee spoofing detected. Expected: %, Got: %', v_expected_delivery_fee, v_sum_client_delivery_charges;
  END IF;

  FOR v_order IN SELECT * FROM jsonb_array_elements(p_orders) LOOP
    IF length(v_order->>'address') > 1000 THEN RAISE EXCEPTION 'Address string too long (Max 1000 chars)'; END IF;
    IF length(v_order->>'address_label') > 100 THEN RAISE EXCEPTION 'Address label string too long (Max 100 chars)'; END IF;
    IF length(v_order->>'delivery_notes') > 500 THEN RAISE EXCEPTION 'Delivery notes string too long (Max 500 chars)'; END IF;
    IF length(v_order->>'cancelled_reason') > 500 THEN RAISE EXCEPTION 'Cancelled reason string too long (Max 500 chars)'; END IF;
    IF length(v_order->>'customer_phone') > 20 THEN RAISE EXCEPTION 'Customer phone string too long (Max 20 chars)'; END IF;
    IF length(v_order->>'shop_phone') > 20 THEN RAISE EXCEPTION 'Shop phone string too long (Max 20 chars)'; END IF;
    IF length(v_order->>'razorpay_payment_id') > 255 THEN RAISE EXCEPTION 'Payment ID string too long (Max 255 chars)'; END IF;
    IF length(v_order->>'razorpay_order_id') > 255 THEN RAISE EXCEPTION 'Order ID string too long (Max 255 chars)'; END IF;
    
    v_expected_total_amount := 0;
    v_s9_5_gst := 0;
    v_non_food_gst := 0;
    v_tcs_amount := 0;
    v_tds_amount := 0;
    v_pure_commission := 0;

    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) AS x(product_id uuid, variant_name text, price numeric, quantity int, order_id uuid) WHERE order_id = (v_order->>'id')::uuid LOOP
      SELECT category, gst_rate_override INTO v_category, v_gst_override FROM products WHERE id = v_item.product_id;
      
      BEGIN
        SELECT (value#>>'{}'  )::numeric INTO v_cat_comm FROM platform_config WHERE key = 'commission_percent_' || v_category;
      EXCEPTION WHEN OTHERS THEN v_cat_comm := v_default_comm; END;
      v_cat_comm := LEAST(GREATEST(COALESCE(v_cat_comm, v_default_comm), 0.0), 100.0);
      
      v_pure_commission := v_pure_commission + ((v_item.price * v_item.quantity * v_cat_comm) / 100.0);

      BEGIN
        SELECT gst_rate::numeric, is_deemed_supplier, slab_threshold, slab_high_rate
        INTO v_gst_rate, v_is_deemed, v_slab_threshold, v_slab_high_rate
        FROM tax_config WHERE category = v_category;
      EXCEPTION WHEN OTHERS THEN v_gst_rate := NULL; END;
        
      IF v_category IN ('Clothing', 'Footwear') THEN
        v_slab_threshold := COALESCE(v_slab_threshold, 2500.0);
        v_slab_high_rate := COALESCE(v_slab_high_rate, 0.18);
        IF v_item.price > v_slab_threshold THEN
          v_gst_rate := v_slab_high_rate;
        ELSE
          v_gst_rate := COALESCE(v_gst_rate, 0.05);
        END IF;
      END IF;

      IF v_gst_rate IS NULL THEN
        v_gst_rate := 0.18;
        v_is_deemed := false;
        IF v_category IN ('Restaurant', 'Fast Food', 'Bakery', 'Sweets & Mithai', 'Tea & Coffee', 'Ice Cream', 'Paan Shop') THEN
          v_gst_rate := 0.05;
          v_is_deemed := true;
        END IF;
      END IF;

      IF v_gst_override IS NOT NULL THEN
        v_gst_rate := v_gst_override;
      END IF;

      v_gst_rate := LEAST(GREATEST(v_gst_rate, 0.0), 1.0);
      
      v_line_gst := v_item.price * v_item.quantity * v_gst_rate;
      
      IF v_is_deemed THEN
        v_s9_5_gst := v_s9_5_gst + v_line_gst;
      ELSE
        v_non_food_gst := v_non_food_gst + v_line_gst;
      END IF;
      
      -- GST TCS (§52 CGST Act: 0.5% on non-food taxable goods, 0% on §9(5) and fresh produce)
      v_tcs_rate := CASE WHEN v_category IN ('Restaurant', 'Fast Food', 'Bakery', 'Sweets & Mithai', 'Tea & Coffee', 'Ice Cream', 'Paan Shop', 'Fruits & Vegs', 'Butcher', 'Fish & Seafood') THEN 0.0 ELSE 0.005 END;
      v_tcs_amount := v_tcs_amount + (v_item.price * v_item.quantity * v_tcs_rate);
      v_tds_amount := v_tds_amount + (v_item.price * v_item.quantity * 0.001);

      v_expected_total_amount := v_expected_total_amount + (v_item.quantity * v_item.price);
    END LOOP;
    
    IF v_expected_total_amount <= 0 THEN
      RAISE EXCEPTION 'Shop order % must contain at least one valid item.', v_order->>'id';
    END IF;

    v_expected_grand_total := GREATEST(0, v_expected_total_amount 
      + v_s9_5_gst + v_non_food_gst 
      + COALESCE((v_order->>'platform_fee')::numeric, 0) 
      + COALESCE((v_order->>'delivery_charges')::numeric, 0)
      - COALESCE((v_order->>'coupon_discount')::numeric, 0));

    IF ABS((v_order->>'total_amount')::numeric - v_expected_total_amount) > 1.0 THEN
      RAISE EXCEPTION 'Total amount mismatch for order %. Expected: %, Got: %', v_order->>'id', v_expected_total_amount, v_order->>'total_amount';
    END IF;

    IF ABS((v_order->>'s9_5_gst_amount')::numeric - v_s9_5_gst) > 1.0 THEN
      RAISE EXCEPTION 'S9.5 GST mismatch for order %. Expected: %, Got: %', v_order->>'id', v_s9_5_gst, v_order->>'s9_5_gst_amount';
    END IF;
    
    IF ABS((v_order->>'non_food_gst_amount')::numeric - v_non_food_gst) > 1.0 THEN
      RAISE EXCEPTION 'Non-food GST mismatch for order %. Expected: %, Got: %', v_order->>'id', v_non_food_gst, v_order->>'non_food_gst_amount';
    END IF;

    IF (v_order->>'grand_total_collected') IS NOT NULL AND ABS((v_order->>'grand_total_collected')::numeric - v_expected_grand_total) > 1.0 THEN
      RAISE EXCEPTION 'Grand total mismatch for order %. Expected: %, Got: %', v_order->>'id', v_expected_grand_total, v_order->>'grand_total_collected';
    ELSIF (v_order->>'grand_total') IS NOT NULL AND ABS((v_order->>'grand_total')::numeric - v_expected_grand_total) > 1.0 THEN
      RAISE EXCEPTION 'Grand total mismatch for order %. Expected: %, Got: %', v_order->>'id', v_expected_grand_total, v_order->>'grand_total';
    END IF;
    
    v_server_gst_platform := COALESCE((v_order->>'platform_fee')::numeric, 0) - (COALESCE((v_order->>'platform_fee')::numeric, 0) / (1.0 + v_platform_gst_rate));
    
    v_server_gst_delivery := COALESCE((v_order->>'delivery_charges')::numeric, 0) - (COALESCE((v_order->>'delivery_charges')::numeric, 0) / (1.0 + v_delivery_gst_rate));

    -- Gateway deduction fixed 18% GST (Razorpay rate = 2.36%)
    v_gw_deduct := GREATEST(0, (v_expected_grand_total * 0.02) * (1.0 + v_gateway_gst_rate));

    -- 100x Business Model Alignment: Seller absorbs gateway fee (2.36%) only on their payout portion
    v_seller_gw_share := GREATEST(0, (v_expected_total_amount - v_pure_commission + v_non_food_gst) * 0.0236);
    v_server_enything_commission := v_pure_commission + v_seller_gw_share;
    v_server_seller_payout := v_expected_total_amount + v_non_food_gst - v_server_enything_commission - v_tcs_amount - v_tds_amount;
    
    v_server_rider_earnings := GREATEST(0, (COALESCE((v_order->>'delivery_charges')::numeric, 0) - v_server_gst_delivery - COALESCE((v_order->>'small_cart_fee')::numeric, 0)) * (v_rider_commission_percent / 100.0));

    IF auth.uid() IS NOT NULL AND auth.uid() != (v_order->>'customer_id')::uuid THEN
      RAISE EXCEPTION 'Unauthorized: customer_id mismatch';
    END IF;
    
    v_acceptance_deadline := (v_order->>'acceptance_deadline')::timestamptz;

    v_secure_order := jsonb_build_object(
      'id', v_order->>'id',
      'customer_id', v_order->>'customer_id',
      'shop_id', v_order->>'shop_id',
      'payment_method', v_order->>'payment_method',
      'payment_status', v_order->>'payment_status',
      'status', v_order->>'status',
      'seller_accepted', false,
      'partner_accepted', COALESCE(v_existing_partner_accepted, false),
      'delivery_partner_id', v_existing_rider_id,
      'rider_phone', COALESCE(v_existing_rider_phone, v_order->>'rider_phone'),
      'address', v_order->>'address',
      'address_label', v_order->>'address_label',
      'delivery_lat', v_order->>'delivery_lat',
      'delivery_lng', v_order->>'delivery_lng',
      'delivery_notes', v_order->>'delivery_notes',
      'estimated_distance_km', v_order->>'estimated_distance_km',
      'cancelled_reason', v_order->>'cancelled_reason',
      'customer_phone', v_order->>'customer_phone',
      'shop_phone', v_order->>'shop_phone',
      'rider_phone', v_order->>'rider_phone',
      'shop_prep_time_snapshot', v_order->>'shop_prep_time_snapshot',
      'prescription_urls', v_order->'prescription_urls',
      'gst_rate_snapshot', COALESCE(v_order->'gst_rate_snapshot', jsonb_build_object('rate', v_gst_rate)),
      'razorpay_payment_id', v_order->>'razorpay_payment_id',
      'razorpay_order_id', v_order->>'razorpay_order_id',
      'total_amount', v_expected_total_amount,
      'gst_item_total', v_s9_5_gst + v_non_food_gst,
      'platform_fee', COALESCE((v_order->>'platform_fee')::numeric, 0),
      'delivery_charges', COALESCE((v_order->>'delivery_charges')::numeric, 0),
      'multi_shop_surcharge', COALESCE((v_order->>'multi_shop_surcharge')::numeric, 0),
      'small_cart_fee', COALESCE((v_order->>'small_cart_fee')::numeric, 0),
      'heavy_order_fee', COALESCE((v_order->>'heavy_order_fee')::numeric, 0),
      'coupon_discount', COALESCE((v_order->>'coupon_discount')::numeric, 0),
      'grand_total_collected', v_expected_grand_total,
      's9_5_gst_amount', v_s9_5_gst,
      'non_food_gst_amount', v_non_food_gst,
      'gst_platform', v_server_gst_platform,
      'gst_delivery', v_server_gst_delivery,
      'tcs_amount', v_tcs_amount,
      'tds_amount', v_tds_amount,
      'gateway_deduction', v_gw_deduct,
      'seller_payout', v_server_seller_payout,
      'enything_commission', v_server_enything_commission,
      'rider_earnings', v_server_rider_earnings,
      'coupon_id', p_coupon_id
    );

    INSERT INTO orders (
      id, customer_id, shop_id, delivery_partner_id, cart_group_id,
      payment_method, payment_status, status,
      seller_accepted, partner_accepted, address, address_label,
      delivery_lat, delivery_lng, delivery_notes,
      estimated_distance_km, cancelled_reason,
      customer_phone, shop_phone, rider_phone, shop_prep_time_snapshot, prescription_urls,
      gst_rate_snapshot, razorpay_payment_id, razorpay_order_id,
      total_amount, s9_5_gst_amount, non_food_gst_amount, gst_item_total,
      platform_fee, gst_platform,
      delivery_charges, multi_shop_surcharge, small_cart_fee, heavy_order_fee, gst_delivery,
      coupon_discount, grand_total_collected,
      tcs_amount, tds_amount,
      gateway_deduction, seller_payout, enything_commission, rider_earnings,
      idempotency_key, coupon_id, acceptance_deadline
    )
    SELECT
      (v_secure_order->>'id')::uuid,
      (v_secure_order->>'customer_id')::uuid,
      (v_secure_order->>'shop_id')::uuid,
      (v_secure_order->>'delivery_partner_id')::uuid,
      p_cart_group_id,
      v_secure_order->>'payment_method',
      v_secure_order->>'payment_status',
      v_secure_order->>'status',
      (v_secure_order->>'seller_accepted')::boolean,
      (v_secure_order->>'partner_accepted')::boolean,
      v_secure_order->>'address',
      v_secure_order->>'address_label',
      (v_secure_order->>'delivery_lat')::double precision,
      (v_secure_order->>'delivery_lng')::double precision,
      v_secure_order->>'delivery_notes',
      (v_secure_order->>'estimated_distance_km')::numeric,
      v_secure_order->>'cancelled_reason',
      v_secure_order->>'customer_phone',
      v_secure_order->>'shop_phone',
      v_secure_order->>'rider_phone',
      (v_secure_order->>'shop_prep_time_snapshot')::int,
      v_secure_order->'prescription_urls',
      v_secure_order->'gst_rate_snapshot', v_secure_order->>'razorpay_payment_id', v_secure_order->>'razorpay_order_id',
      (v_secure_order->>'total_amount')::numeric,
      (v_secure_order->>'s9_5_gst_amount')::numeric,
      (v_secure_order->>'non_food_gst_amount')::numeric,
      (v_secure_order->>'gst_item_total')::numeric,
      (v_secure_order->>'platform_fee')::numeric,
      (v_secure_order->>'gst_platform')::numeric,
      (v_secure_order->>'delivery_charges')::numeric,
      (v_secure_order->>'multi_shop_surcharge')::numeric,
      (v_secure_order->>'small_cart_fee')::numeric,
      (v_secure_order->>'heavy_order_fee')::numeric,
      (v_secure_order->>'gst_delivery')::numeric,
      (v_secure_order->>'coupon_discount')::numeric,
      (v_secure_order->>'grand_total_collected')::numeric,
      (v_secure_order->>'tcs_amount')::numeric,
      (v_secure_order->>'tds_amount')::numeric,
      (v_secure_order->>'gateway_deduction')::numeric, (v_secure_order->>'seller_payout')::numeric, (v_secure_order->>'enything_commission')::numeric, (v_secure_order->>'rider_earnings')::numeric,
      p_idempotency_key::uuid,
      p_coupon_id,
      v_acceptance_deadline
    ;

    v_inserted_ids := array_append(v_inserted_ids, (v_order->>'id')::uuid);
    v_sum_verified_shop_totals := v_sum_verified_shop_totals + v_expected_total_amount;
  END LOOP;
  
  IF v_sum_verified_shop_totals != v_sum_expected_total_amount THEN
    RAISE EXCEPTION 'Phantom item smuggling detected: Some items bypassed shop validation loops.';
  END IF;
  
  FOR v_item IN
    SELECT product_id, SUM(quantity) as total_qty_req
    FROM jsonb_to_recordset(p_items) AS x(product_id uuid, quantity int)
    GROUP BY product_id
    ORDER BY product_id
  LOOP
    SELECT total_quantity, is_available, is_deleted, name INTO v_inventory_record
    FROM products
    WHERE id = v_item.product_id
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Product % does not exist.', v_item.product_id;
    END IF;

    -- Additive Soft Delete Guard: Reject checkout if product was soft deleted
    IF v_inventory_record.is_deleted THEN
      RAISE EXCEPTION 'Product % is no longer available.', v_inventory_record.name;
    END IF;

    IF NOT v_inventory_record.is_available THEN
      RAISE EXCEPTION 'Product % is currently unavailable.', v_inventory_record.name;
    END IF;

    IF v_inventory_record.total_quantity IS NOT NULL THEN
      IF v_inventory_record.total_quantity < v_item.total_qty_req THEN
        RAISE EXCEPTION 'Insufficient stock for product %. Requested: %, Available: %',
          v_inventory_record.name, v_item.total_qty_req, v_inventory_record.total_quantity;
      END IF;

      UPDATE products
      SET total_quantity = total_quantity - v_item.total_qty_req
      WHERE id = v_item.product_id;
    END IF;
  END LOOP;

  FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) AS x(id uuid, order_id uuid, product_id uuid, variant_name text, price numeric, quantity int, special_instructions text) LOOP
    SELECT name INTO v_db_product_name FROM products WHERE id = v_item.product_id;

    INSERT INTO order_items (
      id, order_id, product_id, product_name, variant_name, price, quantity, special_instructions
    ) VALUES (
      COALESCE(v_item.id, gen_random_uuid()),
      v_item.order_id,
      v_item.product_id,
      COALESCE(v_db_product_name, 'Product'),
      v_item.variant_name,
      v_item.price,
      v_item.quantity,
      v_item.special_instructions
    );
    v_inserted_item_ids := array_append(v_inserted_item_ids, COALESCE(v_item.id, gen_random_uuid()));
  END LOOP;

  IF p_coupon_id IS NOT NULL THEN
    UPDATE coupons
    SET usage_count = COALESCE(usage_count, 0) + 1
    WHERE id = p_coupon_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'order_ids', to_jsonb(v_inserted_ids),
    'cart_group_id', p_cart_group_id
  );
END;
$function$;


-- ─────────────────────────────────────────────────────────────────────────────
-- FIX 2: reallocate_cancelled_delivery_fees — grand_total_collected double-count
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.reallocate_cancelled_delivery_fees(p_cart_group_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_active_count INT;
  v_active_items_total NUMERIC;
  v_active_weight_total NUMERIC;
  v_total_cart_delivery NUMERIC;
  v_total_cart_coupon NUMERIC;
  v_original_surcharge NUMERIC;
  v_admin_surcharge_rate NUMERIC;
  v_allowed_surcharge NUMERIC;
  v_cancelled_surcharge NUMERIC;
  v_available_pool NUMERIC;
  
  v_prop NUMERIC;
  v_new_del NUMERIC;
  v_new_plat NUMERIC;
  v_new_small NUMERIC;
  v_new_heavy NUMERIC;
  v_new_surcharge NUMERIC;
  v_new_coupon NUMERIC;
  v_new_gst_plat NUMERIC;
  v_new_gst_del NUMERIC;
  v_new_rider NUMERIC;
  v_new_grand NUMERIC;
  
  v_platform_gst_rate NUMERIC;
  v_delivery_gst_rate NUMERIC;
  v_rider_commission_percent NUMERIC;
  v_admin_platform_fee NUMERIC;
  v_small_cart_threshold NUMERIC;
  v_small_cart_fee NUMERIC;
  v_heavy_order_threshold_kg NUMERIC;
  v_heavy_order_fee NUMERIC;
  
  -- Coupon re-evaluation variables
  v_group_coupon_id UUID;
  v_coupon_type TEXT;
  v_coupon_val NUMERIC;
  v_coupon_cap NUMERIC;
  v_coupon_min NUMERIC;
  v_recalculated_total_discount NUMERIC := 0;
  
  rec RECORD;
  pay_rec RECORD;
  
  v_sum_active_grand NUMERIC := 0;
  v_refund_amount NUMERIC := 0;
  v_first_cancelled_id UUID;
BEGIN
    -- JSONB-safe config reads
    BEGIN SELECT (value#>>'{}')::numeric INTO v_platform_gst_rate FROM platform_config WHERE key = 'platform_fee_gst_rate'; EXCEPTION WHEN OTHERS THEN v_platform_gst_rate := 0.18; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_delivery_gst_rate FROM platform_config WHERE key = 'delivery_gst_rate'; EXCEPTION WHEN OTHERS THEN v_delivery_gst_rate := 0.18; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_rider_commission_percent FROM platform_config WHERE key = 'rider_commission_percent'; EXCEPTION WHEN OTHERS THEN v_rider_commission_percent := 80.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_admin_surcharge_rate FROM platform_config WHERE key = 'multi_shop_surcharge'; EXCEPTION WHEN OTHERS THEN v_admin_surcharge_rate := 20.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_admin_platform_fee FROM platform_config WHERE key = 'platform_fee'; EXCEPTION WHEN OTHERS THEN v_admin_platform_fee := 20.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_small_cart_threshold FROM platform_config WHERE key = 'small_cart_threshold'; EXCEPTION WHEN OTHERS THEN v_small_cart_threshold := 99.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_small_cart_fee FROM platform_config WHERE key = 'small_cart_fee'; EXCEPTION WHEN OTHERS THEN v_small_cart_fee := 15.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_heavy_order_threshold_kg FROM platform_config WHERE key = 'heavy_order_threshold_kg'; EXCEPTION WHEN OTHERS THEN v_heavy_order_threshold_kg := 10.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_heavy_order_fee FROM platform_config WHERE key = 'heavy_order_fee'; EXCEPTION WHEN OTHERS THEN v_heavy_order_fee := 25.0; END;

    v_platform_gst_rate := COALESCE(v_platform_gst_rate, 0.18);
    v_delivery_gst_rate := COALESCE(v_delivery_gst_rate, 0.18);
    v_rider_commission_percent := COALESCE(v_rider_commission_percent, 80.0);
    v_admin_surcharge_rate := COALESCE(v_admin_surcharge_rate, 20.0);
    v_admin_platform_fee := COALESCE(v_admin_platform_fee, 20.0);
    v_small_cart_threshold := COALESCE(v_small_cart_threshold, 99.0);
    v_small_cart_fee := COALESCE(v_small_cart_fee, 15.0);
    v_heavy_order_threshold_kg := COALESCE(v_heavy_order_threshold_kg, 10.0);
    v_heavy_order_fee := COALESCE(v_heavy_order_fee, 25.0);

    -- Iterate per unique payment in the cart group that has cancellations/rejections
    FOR pay_rec IN
        SELECT DISTINCT razorpay_payment_id
        FROM public.orders
        WHERE cart_group_id = p_cart_group_id
          AND status IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
    LOOP
        SELECT COUNT(id), COALESCE(SUM(total_amount), 0)
          INTO v_active_count, v_active_items_total
          FROM public.orders
         WHERE cart_group_id = p_cart_group_id
           AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
           AND status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel');

        IF v_active_count = 0 THEN
            CONTINUE; 
        END IF;

        -- Sum weight of remaining active items (Rule: Soft deletes is_deleted = false)
        SELECT COALESCE(SUM(oi.quantity * COALESCE(p.weight_per_unit, 0.5)), 0)
          INTO v_active_weight_total
          FROM public.order_items oi
          JOIN public.orders o ON o.id = oi.order_id
          JOIN public.products p ON p.id = oi.product_id
         WHERE o.cart_group_id = p_cart_group_id
           AND o.razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
           AND o.status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
           AND p.is_deleted = false;

        SELECT 
            COALESCE(SUM(grand_total_collected), 0),
            COALESCE(SUM(delivery_charges),      0),
            COALESCE(SUM(multi_shop_surcharge),  0),
            COALESCE(SUM(coupon_discount),       0),
            MAX(coupon_id::text)::uuid
          INTO 
            v_available_pool,
            v_total_cart_delivery,
            v_original_surcharge,
            v_total_cart_coupon,
            v_group_coupon_id
          FROM public.orders
         WHERE cart_group_id = p_cart_group_id
           AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
           AND (status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
                OR delivery_charges > 0);

        -- MULTI-SHOP SURCHARGE RECALCULATION:
        IF v_active_count > 1 THEN
            v_allowed_surcharge := v_admin_surcharge_rate * (v_active_count - 1);
        ELSE
            v_allowed_surcharge := 0;
        END IF;

        v_allowed_surcharge := LEAST(v_allowed_surcharge, v_original_surcharge);
        v_cancelled_surcharge := GREATEST(0, v_original_surcharge - v_allowed_surcharge);
        
        v_total_cart_delivery := GREATEST(0, v_total_cart_delivery - (v_cancelled_surcharge * (1.0 + v_delivery_gst_rate)));

        -- SMALL CART FEE DYNAMIC RE-EVALUATION:
        IF v_active_items_total > 0 AND v_active_items_total < v_small_cart_threshold THEN
            v_new_small := v_small_cart_fee / v_active_count;
        ELSE
            v_new_small := 0;
        END IF;

        -- HEAVY ORDER FEE DYNAMIC RE-EVALUATION:
        IF v_active_weight_total > v_heavy_order_threshold_kg THEN
            v_new_heavy := v_heavy_order_fee / v_active_count;
        ELSE
            v_new_heavy := 0;
        END IF;

        -- HANDLING FEE (PLATFORM FEE):
        -- Split equally across active shops
        v_new_plat := v_admin_platform_fee / v_active_count;

        -- DYNAMIC COUPON RE-EVALUATION:
        IF v_group_coupon_id IS NOT NULL AND v_active_items_total > 0 THEN
            SELECT type, value, max_discount, min_order_value
            INTO v_coupon_type, v_coupon_val, v_coupon_cap, v_coupon_min
            FROM public.coupons
            WHERE id = v_group_coupon_id;

            IF FOUND THEN
                IF v_active_items_total >= COALESCE(v_coupon_min, 0) THEN
                    IF v_coupon_type = 'percentage' THEN
                        v_recalculated_total_discount := v_active_items_total * (v_coupon_val / 100.0);
                        IF v_coupon_cap IS NOT NULL THEN
                            v_recalculated_total_discount := LEAST(v_recalculated_total_discount, v_coupon_cap);
                        END IF;
                    ELSIF v_coupon_type = 'flat' THEN
                        v_recalculated_total_discount := LEAST(v_coupon_val, v_active_items_total);
                    ELSE
                        v_recalculated_total_discount := v_total_cart_coupon;
                    END IF;
                ELSE
                    v_recalculated_total_discount := 0;
                END IF;
            ELSE
                v_recalculated_total_discount := v_total_cart_coupon;
            END IF;
        ELSE
            v_recalculated_total_discount := v_total_cart_coupon;
        END IF;

        FOR rec IN
            SELECT id, total_amount, gst_item_total
              FROM public.orders
             WHERE cart_group_id = p_cart_group_id
               AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
               AND status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
        LOOP
            IF v_active_items_total > 0 THEN
                v_prop := rec.total_amount / v_active_items_total;
            ELSE
                v_prop := 1.0 / v_active_count;
            END IF;

            v_new_del       := v_total_cart_delivery * v_prop;
            v_new_surcharge := v_allowed_surcharge   * v_prop;
            v_new_coupon    := v_recalculated_total_discount * v_prop;

            v_new_gst_plat := v_new_plat - (v_new_plat / (1.0 + v_platform_gst_rate));
            v_new_gst_del  := v_new_del  - (v_new_del  / (1.0 + v_delivery_gst_rate));

            v_new_rider := GREATEST(0,
                (v_new_del - v_new_gst_del - v_new_small)
                * (v_rider_commission_percent / 100.0)
            );
            
            -- FIX 2: grand_total_collected formula (no double addition of surcharges)
            v_new_grand := GREATEST(0,
                rec.total_amount
                + rec.gst_item_total
                + v_new_plat
                + v_new_del
                - COALESCE(v_new_coupon, 0)
            );

            UPDATE public.orders
               SET delivery_charges      = v_new_del,
                   platform_fee          = v_new_plat,
                   small_cart_fee        = v_new_small,
                   heavy_order_fee       = v_new_heavy,
                   multi_shop_surcharge  = v_new_surcharge,
                   coupon_discount       = v_new_coupon,
                   gst_platform          = v_new_gst_plat,
                   gst_delivery          = v_new_gst_del,
                   rider_earnings        = v_new_rider,
                   grand_total_collected = v_new_grand,
                   updated_at            = NOW()
             WHERE id = rec.id;
        END LOOP;

        SELECT COALESCE(SUM(grand_total_collected), 0)
          INTO v_sum_active_grand
          FROM public.orders
         WHERE cart_group_id = p_cart_group_id
           AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
           AND status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel');

        v_refund_amount := GREATEST(0, v_available_pool - v_sum_active_grand);

        SELECT id INTO v_first_cancelled_id
          FROM public.orders
         WHERE cart_group_id = p_cart_group_id
           AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
           AND status IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
         ORDER BY created_at ASC
         LIMIT 1;

        UPDATE public.orders
           SET grand_total_collected = CASE WHEN id = v_first_cancelled_id THEN v_refund_amount ELSE 0 END,
               delivery_charges      = 0,
               platform_fee          = 0,
               small_cart_fee        = 0,
               heavy_order_fee       = 0,
               multi_shop_surcharge  = 0,
               coupon_discount       = 0,
               gst_platform          = 0,
               gst_delivery          = 0,
               rider_earnings        = 0,
               updated_at            = NOW()
         WHERE cart_group_id = p_cart_group_id
           AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
           AND status IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel');

    END LOOP;

    RETURN TRUE;
END;
$function$;


-- ─────────────────────────────────────────────────────────────────────────────
-- FIX 3: rebalance_active_delivery_fees — grand_total_collected double-count
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.rebalance_active_delivery_fees(p_cart_group_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_active_count INT;
  v_active_items_total NUMERIC;
  v_active_weight_total NUMERIC;
  v_total_delivery NUMERIC;
  v_total_surcharge NUMERIC;
  v_split_delivery NUMERIC;
  v_split_surcharge NUMERIC;
  v_split_small NUMERIC;
  v_split_heavy NUMERIC;
  v_split_plat NUMERIC;
  v_net_delivery NUMERIC;
  v_new_gst_delivery NUMERIC;
  v_new_plat NUMERIC;
  v_new_gst_plat NUMERIC;
  rec RECORD;
  pay_rec RECORD;
  
  v_delivery_gst_rate numeric;
  v_platform_gst_rate numeric;
  v_rider_commission_percent numeric;
  v_admin_platform_fee numeric;
  v_admin_surcharge_rate numeric;
  v_small_cart_threshold numeric;
  v_small_cart_fee numeric;
  v_heavy_order_threshold_kg numeric;
  v_heavy_order_fee numeric;
BEGIN
    BEGIN SELECT (value#>>'{}')::numeric INTO v_platform_gst_rate FROM platform_config WHERE key = 'platform_fee_gst_rate'; EXCEPTION WHEN OTHERS THEN v_platform_gst_rate := 0.18; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_delivery_gst_rate FROM platform_config WHERE key = 'delivery_gst_rate'; EXCEPTION WHEN OTHERS THEN v_delivery_gst_rate := 0.18; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_rider_commission_percent FROM platform_config WHERE key = 'rider_commission_percent'; EXCEPTION WHEN OTHERS THEN v_rider_commission_percent := 80.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_admin_surcharge_rate FROM platform_config WHERE key = 'multi_shop_surcharge'; EXCEPTION WHEN OTHERS THEN v_admin_surcharge_rate := 20.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_admin_platform_fee FROM platform_config WHERE key = 'platform_fee'; EXCEPTION WHEN OTHERS THEN v_admin_platform_fee := 20.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_small_cart_threshold FROM platform_config WHERE key = 'small_cart_threshold'; EXCEPTION WHEN OTHERS THEN v_small_cart_threshold := 99.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_small_cart_fee FROM platform_config WHERE key = 'small_cart_fee'; EXCEPTION WHEN OTHERS THEN v_small_cart_fee := 15.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_heavy_order_threshold_kg FROM platform_config WHERE key = 'heavy_order_threshold_kg'; EXCEPTION WHEN OTHERS THEN v_heavy_order_threshold_kg := 10.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_heavy_order_fee FROM platform_config WHERE key = 'heavy_order_fee'; EXCEPTION WHEN OTHERS THEN v_heavy_order_fee := 25.0; END;

    v_platform_gst_rate := COALESCE(v_platform_gst_rate, 0.18);
    v_delivery_gst_rate := COALESCE(v_delivery_gst_rate, 0.18);
    v_rider_commission_percent := COALESCE(v_rider_commission_percent, 80.0);
    v_admin_surcharge_rate := COALESCE(v_admin_surcharge_rate, 20.0);
    v_admin_platform_fee := COALESCE(v_admin_platform_fee, 20.0);
    v_small_cart_threshold := COALESCE(v_small_cart_threshold, 99.0);
    v_small_cart_fee := COALESCE(v_small_cart_fee, 15.0);
    v_heavy_order_threshold_kg := COALESCE(v_heavy_order_threshold_kg, 10.0);
    v_heavy_order_fee := COALESCE(v_heavy_order_fee, 25.0);

    -- Lock rows to prevent concurrency race
    PERFORM id FROM public.orders 
    WHERE cart_group_id = p_cart_group_id 
    ORDER BY id FOR UPDATE;

    FOR pay_rec IN
        SELECT DISTINCT razorpay_payment_id
        FROM public.orders
        WHERE cart_group_id = p_cart_group_id
          AND status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
    LOOP
        SELECT COUNT(id), COALESCE(SUM(total_amount), 0)
          INTO v_active_count, v_active_items_total
          FROM public.orders 
         WHERE cart_group_id = p_cart_group_id 
           AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
           AND status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel');

        IF v_active_count = 0 THEN
            CONTINUE;
        END IF;

        -- Active weight total (Rule: Soft deletes is_deleted = false)
        SELECT COALESCE(SUM(oi.quantity * COALESCE(p.weight_per_unit, 0.5)), 0)
          INTO v_active_weight_total
          FROM public.order_items oi
          JOIN public.orders o ON o.id = oi.order_id
          JOIN public.products p ON p.id = oi.product_id
         WHERE o.cart_group_id = p_cart_group_id
           AND o.razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
           AND o.status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
           AND p.is_deleted = false;

        SELECT 
            COALESCE(SUM(delivery_charges),     0),
            COALESCE(SUM(multi_shop_surcharge), 0)
          INTO 
            v_total_delivery, v_total_surcharge
          FROM public.orders 
         WHERE cart_group_id = p_cart_group_id 
           AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
           AND status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel');

        v_split_delivery := v_total_delivery / v_active_count;

        IF v_active_count > 1 THEN
            v_split_surcharge := (v_admin_surcharge_rate * (v_active_count - 1)) / v_active_count;
        ELSE
            v_split_surcharge := 0;
        END IF;

        IF v_active_items_total > 0 AND v_active_items_total < v_small_cart_threshold THEN
            v_split_small := v_small_cart_fee / v_active_count;
        ELSE
            v_split_small := 0;
        END IF;

        IF v_active_weight_total > v_heavy_order_threshold_kg THEN
            v_split_heavy := v_heavy_order_fee / v_active_count;
        ELSE
            v_split_heavy := 0;
        END IF;

        v_split_plat := v_admin_platform_fee / v_active_count;

        FOR rec IN 
            SELECT id, total_amount, gst_item_total,
                   COALESCE(coupon_discount, 0) AS coupon_discount
              FROM public.orders 
             WHERE cart_group_id = p_cart_group_id 
               AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
               AND status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
             ORDER BY id
        LOOP
            v_net_delivery := v_split_delivery;
            v_new_gst_delivery := v_split_delivery - (v_split_delivery / (1.0 + v_delivery_gst_rate));
            v_new_plat := v_split_plat;
            v_new_gst_plat := v_new_plat - (v_new_plat / (1.0 + v_platform_gst_rate));
            
            UPDATE public.orders
               SET delivery_charges      = v_split_delivery,
                   rider_earnings        = GREATEST(0,
                       (v_split_delivery - v_new_gst_delivery - v_split_small)
                       * (v_rider_commission_percent / 100.0)
                   ),
                   multi_shop_surcharge  = v_split_surcharge,
                   small_cart_fee        = v_split_small,
                   heavy_order_fee       = v_split_heavy,
                   platform_fee          = v_new_plat,
                   gst_platform          = v_new_gst_plat,
                   gst_delivery          = v_new_gst_delivery,
                   -- FIX 3: grand_total_collected formula (no double addition of surcharges)
                   grand_total_collected = GREATEST(0,
                       rec.total_amount
                       + rec.gst_item_total
                       + v_new_plat
                       + v_net_delivery
                       - rec.coupon_discount
                   ),
                   updated_at            = NOW()
             WHERE id = rec.id;
        END LOOP;
    END LOOP;
END;
$function$;
