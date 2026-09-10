-- =============================================================================
-- Migration: 20290000000118_100x_leg_specific_distance_surcharge_engine.sql
-- =============================================================================
-- Description:
--   1. Replaces max-distance cart delivery with sequential chain distance engine:
--      - Base Delivery: Distance from Shop 1 (first added) to Customer
--        v_calculated_delivery_base := GREATEST(v_global_delivery_base, GREATEST(1, CEIL(v_first_shop_dist_km)) * v_delivery_rate_per_km);
--      - Multi-Shop Surcharge: Distance-based sequential chain across shops:
--        Leg 1-2: GREATEST(1, CEIL(dist(Shop 1, Shop 2))) * rate_per_km
--        Leg 2-3: GREATEST(1, CEIL(dist(Shop 2, Shop 3))) * rate_per_km
--   2. Enforces Leg-Specific Order Row Attribution in DB:
--      - Shop 1 row holds Base Delivery (+ Delivery GST) and full Handling Fee (+₹20)
--      - Shop 2 row holds Leg 1-2 Surcharge (+ Delivery GST) and platform_fee = 0
--      - Shop 3 row holds Leg 2-3 Surcharge (+ Delivery GST) and platform_fee = 0
--   3. Fortifies Partial Rejection Active Chain Recalculation:
--      - If Shop 2 cancels: Leg 1-2 surcharge is cleanly refunded to customer.
--      - If Shop 1 cancels: Shop 2 is promoted to Base Shop (distance to customer),
--        Handling Fee transfers to Shop 2 (only refunded if ALL cancel), and excess is refunded.
--      - If ALL shops cancel (v_active_count = 0): 100% full refund and rider unassigned.
--   4. Strictly ADDITIVE ONLY, preserving soft deletes (is_deleted = false),
--      TCS/TDS deductions, 18% gateway deduction GST, and full backwards-compatibility.
-- =============================================================================

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
  v_db_stock int;
  v_order_seq int := 0;
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
  v_expected_surcharge numeric := 0;
  
  v_global_delivery_base numeric := 20.0;
  v_delivery_rate_per_km numeric := 20.0;
  v_calculated_delivery_base numeric := 20.0;
  v_first_shop_dist_km double precision := 0.0;
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

  v_shop_lat numeric;
  v_shop_lng numeric;
  v_dist_km double precision;
  v_max_radius_km double precision := 15.0;
  v_unit_weight numeric;
  v_unit_type text;
  v_item_category text;
  v_clean_unit text;
  v_resolved_unit_weight_kg numeric;
  v_existing_rider_id uuid;
  v_existing_rider_phone text;
  v_existing_partner_accepted boolean;

  -- Coordinates array for sequential chain
  v_shop_lats double precision[] := '{}';
  v_shop_lngs double precision[] := '{}';
  v_inter_dist double precision;
  v_leg_surcharge numeric;
  i int;
BEGIN
  IF jsonb_array_length(p_orders) = 0 THEN
    RAISE EXCEPTION 'Transaction must contain at least one order.';
  END IF;

  -- 100x IDEMPOTENCY SAFETY GUARD
  IF p_idempotency_key IS NOT NULL AND trim(p_idempotency_key) != '' THEN
    IF EXISTS (SELECT 1 FROM orders WHERE idempotency_key = p_idempotency_key) THEN
      RETURN (
        SELECT jsonb_agg(to_jsonb(o))
        FROM orders o
        WHERE o.idempotency_key = p_idempotency_key
      );
    END IF;
  END IF;

  -- REPLACEMENT ORDER & PREVIOUS RIDER INHERITANCE
  IF p_cart_group_id IS NOT NULL THEN
    SELECT EXISTS (
      SELECT 1 FROM orders
      WHERE cart_group_id = p_cart_group_id
        AND status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected')
    ) INTO v_is_replacement;

    SELECT delivery_partner_id, rider_phone, partner_accepted
    INTO v_existing_rider_id, v_existing_rider_phone, v_existing_partner_accepted
    FROM orders
    WHERE cart_group_id = p_cart_group_id
      AND delivery_partner_id IS NOT NULL
      AND status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected')
    LIMIT 1;
  END IF;

  -- Dynamic Platform Configurations
  BEGIN SELECT (value#>>'{}')::numeric INTO v_default_comm FROM platform_config WHERE key = 'default_commission_percent'; EXCEPTION WHEN OTHERS THEN v_default_comm := NULL; END;
  IF v_default_comm IS NULL THEN
    BEGIN SELECT (value#>>'{}')::numeric INTO v_default_comm FROM platform_config WHERE key = 'commission_percent'; EXCEPTION WHEN OTHERS THEN v_default_comm := 5.0; END;
  END IF;
  v_default_comm := LEAST(GREATEST(COALESCE(v_default_comm, 5.0), 0.0), 100.0);

  BEGIN SELECT (value#>>'{}')::numeric INTO v_platform_gst_rate FROM platform_config WHERE key = 'platform_fee_gst_rate'; EXCEPTION WHEN OTHERS THEN v_platform_gst_rate := 0.18; END;
  v_platform_gst_rate := LEAST(GREATEST(COALESCE(v_platform_gst_rate, 0.18), 0.0), 1.0);

  BEGIN SELECT (value#>>'{}')::numeric INTO v_delivery_gst_rate FROM platform_config WHERE key = 'delivery_gst_rate'; EXCEPTION WHEN OTHERS THEN v_delivery_gst_rate := 0.18; END;
  v_delivery_gst_rate := LEAST(GREATEST(COALESCE(v_delivery_gst_rate, 0.18), 0.0), 1.0);

  BEGIN SELECT (value#>>'{}')::numeric INTO v_rider_commission_percent FROM platform_config WHERE key = 'rider_commission_percent'; EXCEPTION WHEN OTHERS THEN v_rider_commission_percent := 80.0; END;
  v_rider_commission_percent := LEAST(GREATEST(COALESCE(v_rider_commission_percent, 80.0), 0.0), 100.0);

  BEGIN SELECT (value#>>'{}')::double precision INTO v_max_radius_km FROM platform_config WHERE key = 'max_delivery_radius_km'; EXCEPTION WHEN OTHERS THEN v_max_radius_km := 15.0; END;
  v_max_radius_km := GREATEST(COALESCE(v_max_radius_km, 15.0), 1.0);

  BEGIN SELECT (value#>>'{}')::numeric INTO v_global_delivery_base FROM platform_config WHERE key = 'delivery_base_fee'; EXCEPTION WHEN OTHERS THEN v_global_delivery_base := 20.0; END;
  v_global_delivery_base := GREATEST(COALESCE(v_global_delivery_base, 20.0), 0.0);

  BEGIN SELECT (value#>>'{}')::numeric INTO v_delivery_rate_per_km FROM platform_config WHERE key = 'delivery_rate_per_km'; EXCEPTION WHEN OTHERS THEN v_delivery_rate_per_km := 20.0; END;
  v_delivery_rate_per_km := GREATEST(COALESCE(v_delivery_rate_per_km, 20.0), 0.0);

  BEGIN SELECT (value#>>'{}')::numeric INTO v_global_platform_fee FROM platform_config WHERE key = 'platform_fee'; EXCEPTION WHEN OTHERS THEN v_global_platform_fee := 20.0; END;
  v_global_platform_fee := GREATEST(COALESCE(v_global_platform_fee, 20.0), 0.0);

  IF jsonb_array_length(p_orders) > 50 THEN
    RAISE EXCEPTION 'Bulk payload attack: Exceeded maximum 50 sub-orders per cart transaction.';
  END IF;

  IF jsonb_array_length(p_items) > 500 THEN
    RAISE EXCEPTION 'Bulk payload attack: Exceeded maximum 500 items per cart transaction.';
  END IF;

  -- 1. Geospatial & Sequential Chain Shop Processing
  FOR v_order IN SELECT * FROM jsonb_array_elements(p_orders) LOOP
    v_shop_count := v_shop_count + 1;
    v_sum_client_multi_shop_surcharge := v_sum_client_multi_shop_surcharge + COALESCE((v_order->>'multi_shop_surcharge')::numeric, 0);
    v_sum_client_heavy_order_fee := v_sum_client_heavy_order_fee + COALESCE((v_order->>'heavy_order_fee')::numeric, 0);
    v_sum_client_small_cart_fee := v_sum_client_small_cart_fee + COALESCE((v_order->>'small_cart_fee')::numeric, 0);
    v_sum_client_platform_fee := v_sum_client_platform_fee + COALESCE((v_order->>'platform_fee')::numeric, 0);
    v_sum_client_delivery_charges := v_sum_client_delivery_charges + COALESCE((v_order->>'delivery_charges')::numeric, 0);
    
    v_dist_km := COALESCE((v_order->>'estimated_distance_km')::double precision, 0.0);

    SELECT ST_Y(location::geometry), ST_X(location::geometry) 
    INTO v_shop_lat, v_shop_lng 
    FROM shops 
    WHERE id = (v_order->>'shop_id')::uuid;

    IF v_shop_lat IS NOT NULL AND v_shop_lng IS NOT NULL THEN
      v_shop_lats := array_append(v_shop_lats, v_shop_lat::double precision);
      v_shop_lngs := array_append(v_shop_lngs, v_shop_lng::double precision);

      IF (v_order->>'delivery_lat') IS NOT NULL AND (v_order->>'delivery_lng') IS NOT NULL THEN
        DECLARE
          v_server_calc_dist double precision;
          v_client_dist double precision := COALESCE((v_order->>'estimated_distance_km')::double precision, 0.0);
        BEGIN
          v_server_calc_dist := 6371.0 * acos(
            LEAST(1.0, GREATEST(-1.0, 
              cos(radians(v_shop_lat)) * cos(radians((v_order->>'delivery_lat')::double precision)) *
              cos(radians((v_order->>'delivery_lng')::double precision) - radians(v_shop_lng)) +
              sin(radians(v_shop_lat)) * sin(radians((v_order->>'delivery_lat')::double precision))
            ))
          );
          IF v_server_calc_dist > (v_max_radius_km + 0.5) THEN
            RAISE EXCEPTION 'Geospatial validation failed: Shop % is % km away, exceeding max delivery radius of % km.', v_order->>'shop_id', round(v_server_calc_dist::numeric, 2), v_max_radius_km;
          END IF;

          IF v_client_dist > 0 AND ABS(v_server_calc_dist - v_client_dist) <= 0.3 THEN
            v_dist_km := v_client_dist;
          ELSE
            v_dist_km := v_server_calc_dist;
          END IF;
        END;
      END IF;
    END IF;

    -- Base delivery fee distance is strictly anchored to Shop 1 (first shop added to cart)
    IF v_shop_count = 1 THEN
      v_first_shop_dist_km := COALESCE(v_dist_km, 0.0);
    END IF;
  END LOOP;

  -- Calculate Distance-Based Multi-Shop Surcharges (Sequential Chain: Shop 1->2, Shop 2->3)
  IF v_shop_count > 1 AND NOT v_is_replacement THEN
    FOR i IN 1..(v_shop_count - 1) LOOP
      IF array_length(v_shop_lats, 1) >= (i + 1) THEN
        v_inter_dist := 6371.0 * acos(
          LEAST(1.0, GREATEST(-1.0, 
            cos(radians(v_shop_lats[i])) * cos(radians(v_shop_lats[i+1])) *
            cos(radians(v_shop_lngs[i+1]) - radians(v_shop_lngs[i])) +
            sin(radians(v_shop_lats[i])) * sin(radians(v_shop_lats[i+1]))
          ))
        );
        v_leg_surcharge := GREATEST(1, CEIL(v_inter_dist)) * v_delivery_rate_per_km;
        v_expected_surcharge := v_expected_surcharge + v_leg_surcharge;
      END IF;
    END LOOP;
  ELSIF v_is_replacement THEN
    v_expected_surcharge := v_sum_client_multi_shop_surcharge;
  END IF;

  -- 2. Items & Weight Validation
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

      v_total_weight_kg := v_total_weight_kg + (v_item.quantity * v_resolved_unit_weight_kg);
    ELSE
      v_total_weight_kg := v_total_weight_kg + (v_item.quantity * COALESCE(v_item.weight_kg, 0.5));
    END IF;
  END LOOP;

  -- 3. Small Cart & Heavy Order Fees
  BEGIN SELECT (value#>>'{}')::numeric INTO v_global_small_cart_threshold FROM platform_config WHERE key = 'small_cart_threshold'; EXCEPTION WHEN OTHERS THEN v_global_small_cart_threshold := 99.0; END;
  BEGIN SELECT (value#>>'{}')::numeric INTO v_global_small_cart_fee FROM platform_config WHERE key = 'small_cart_fee'; EXCEPTION WHEN OTHERS THEN v_global_small_cart_fee := 15.0; END;
  v_global_small_cart_threshold := COALESCE(v_global_small_cart_threshold, 99.0);
  v_global_small_cart_fee := COALESCE(v_global_small_cart_fee, 15.0);

  IF v_sum_expected_total_amount < v_global_small_cart_threshold THEN
    IF NOT v_is_replacement AND ABS(v_sum_client_small_cart_fee - v_global_small_cart_fee) > 1.0 THEN
      RAISE EXCEPTION 'Small cart fee spoofing detected. Expected: %, Got: %', v_global_small_cart_fee, v_sum_client_small_cart_fee;
    END IF;
  ELSE
    IF v_sum_client_small_cart_fee > 0.01 THEN
      RAISE EXCEPTION 'Small cart fee applied incorrectly. Cart subtotal % meets threshold %.', v_sum_expected_total_amount, v_global_small_cart_threshold;
    END IF;
  END IF;

  BEGIN SELECT (value#>>'{}')::numeric INTO v_global_heavy_order_fee FROM platform_config WHERE key = 'heavy_order_fee'; EXCEPTION WHEN OTHERS THEN v_global_heavy_order_fee := NULL; END;
  IF v_global_heavy_order_fee IS NULL THEN
    BEGIN SELECT (value#>>'{}')::numeric INTO v_global_heavy_order_fee FROM platform_config WHERE key = 'heavy_order_fee_per_kg'; EXCEPTION WHEN OTHERS THEN v_global_heavy_order_fee := 20.0; END;
  END IF;
  v_global_heavy_order_fee := COALESCE(v_global_heavy_order_fee, 20.0);

  BEGIN SELECT (value#>>'{}')::numeric INTO v_global_heavy_order_threshold FROM platform_config WHERE key = 'heavy_order_threshold_kg'; EXCEPTION WHEN OTHERS THEN v_global_heavy_order_threshold := 10.0; END;
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

  -- 4. Multi-Shop Surcharge Validation
  IF v_shop_count > 1 AND NOT v_is_replacement THEN
    IF ABS(v_sum_client_multi_shop_surcharge - v_expected_surcharge) > 2.0 THEN
       IF ABS(v_sum_client_multi_shop_surcharge - (20.0 * (v_shop_count - 1))) > 2.0 THEN
          RAISE EXCEPTION 'Multi shop surcharge mismatch. Expected: %, Got: %', v_expected_surcharge, v_sum_client_multi_shop_surcharge;
       END IF;
    END IF;
  END IF;

  -- 5. Handling / Platform Fee (Flat ₹20 per cart, ₹0 on replacement)
  IF v_is_replacement THEN
    v_expected_platform_fee := 0.0;
  ELSE
    v_expected_platform_fee := v_global_platform_fee;
  END IF;

  IF ABS(v_sum_client_platform_fee - v_expected_platform_fee) > 1.0 THEN
     RAISE EXCEPTION 'Handling fee spoofing detected. Expected: %, Got: %', v_expected_platform_fee, v_sum_client_platform_fee;
  END IF;

  -- 6. Delivery Fee Validation (Base from Shop 1 + Surcharges)
  IF v_is_replacement THEN
    v_expected_delivery_fee := (v_sum_client_multi_shop_surcharge + v_sum_client_heavy_order_fee + v_sum_client_small_cart_fee) * (1.0 + v_delivery_gst_rate);
  ELSE
    v_calculated_delivery_base := GREATEST(
      v_global_delivery_base, 
      GREATEST(1, CEIL(v_first_shop_dist_km)) * v_delivery_rate_per_km
    );
    v_expected_delivery_fee := (v_calculated_delivery_base + v_expected_surcharge + v_expected_heavy_order_fee + v_sum_client_small_cart_fee) * (1.0 + v_delivery_gst_rate);
  END IF;

  IF ABS(v_sum_client_delivery_charges - v_expected_delivery_fee) > 2.5 THEN
     RAISE EXCEPTION 'Delivery charges spoofing detected. Expected: %, Got: %', v_expected_delivery_fee, v_sum_client_delivery_charges;
  END IF;

  -- 7. Coupon Discount Validation
  IF p_coupon_id IS NOT NULL THEN
    SELECT * INTO v_coupon_record FROM coupons WHERE id = p_coupon_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Invalid coupon.';
    END IF;
    IF NOT v_coupon_record.is_active THEN
      RAISE EXCEPTION 'Coupon is inactive.';
    END IF;
    IF v_coupon_record.valid_until < NOW() THEN
      RAISE EXCEPTION 'Coupon has expired.';
    END IF;
    IF v_coupon_record.min_order_amount IS NOT NULL AND v_sum_expected_total_amount < v_coupon_record.min_order_amount THEN
      RAISE EXCEPTION 'Order amount % does not meet minimum % for coupon.', v_sum_expected_total_amount, v_coupon_record.min_order_amount;
    END IF;
    
    v_customer_id := (p_orders->0->>'customer_id')::uuid;
    SELECT COUNT(*) INTO v_user_usage_count FROM user_coupon_usage WHERE user_id = v_customer_id AND coupon_id = p_coupon_id;
    IF v_coupon_record.usage_limit_per_user IS NOT NULL AND v_user_usage_count >= v_coupon_record.usage_limit_per_user THEN
      RAISE EXCEPTION 'Coupon usage limit per user reached.';
    END IF;
    
    SELECT COUNT(*) INTO v_total_usage_count FROM user_coupon_usage WHERE coupon_id = p_coupon_id;
    IF v_coupon_record.total_usage_limit IS NOT NULL AND v_total_usage_count >= v_coupon_record.total_usage_limit THEN
      RAISE EXCEPTION 'Coupon total usage limit reached.';
    END IF;
    
    IF v_coupon_record.discount_type = 'percentage' THEN
      v_calculated_discount := (v_sum_expected_total_amount * (v_coupon_record.discount_value / 100.0));
      IF v_coupon_record.max_discount_amount IS NOT NULL THEN
        v_calculated_discount := LEAST(v_calculated_discount, v_coupon_record.max_discount_amount);
      END IF;
    ELSE
      v_calculated_discount := v_coupon_record.discount_value;
    END IF;
    v_expected_discount := v_calculated_discount;
  END IF;

  FOR v_order IN SELECT * FROM jsonb_array_elements(p_orders) LOOP
    v_coupon_discount_sum := v_coupon_discount_sum + COALESCE((v_order->>'coupon_discount')::numeric, 0);
  END LOOP;

  IF p_coupon_id IS NOT NULL THEN
    IF ABS(v_coupon_discount_sum - v_expected_discount) > 1.0 THEN
      RAISE EXCEPTION 'Coupon discount spoofing detected: Claimed %, Expected %', v_coupon_discount_sum, v_expected_discount;
    END IF;
  ELSE
    IF v_coupon_discount_sum > 0 THEN
      RAISE EXCEPTION 'Unauthorized coupon discount without coupon_id.';
    END IF;
  END IF;

  -- 8. Sub-Orders Secure Processing & Database Insertion
  v_order_seq := 0;
  FOR v_order IN SELECT * FROM jsonb_array_elements(p_orders) LOOP
    v_order_seq := v_order_seq + 1;
    v_expected_total_amount := 0;
    v_s9_5_gst := 0;
    v_non_food_gst := 0;
    v_tcs_amount := 0;
    v_tds_amount := 0;
    v_pure_commission := 0;

    SELECT category INTO v_category FROM shops WHERE id = (v_order->>'shop_id')::uuid;

    v_cat_comm := NULL;
    IF v_category IS NOT NULL THEN
      BEGIN
        SELECT (value#>>'{}')::numeric INTO v_cat_comm
        FROM platform_config WHERE key = 'commission_percent_' || v_category;
      EXCEPTION WHEN OTHERS THEN v_cat_comm := NULL;
      END;
    END IF;
    IF v_cat_comm IS NOT NULL THEN
      v_cat_comm := LEAST(GREATEST(v_cat_comm, 0.0), 100.0);
    ELSE
      v_cat_comm := v_default_comm;
    END IF;

    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) AS x(
      product_id uuid, 
      variant_name text, 
      price numeric, 
      quantity int, 
      order_id uuid
    ) LOOP
      IF v_item.order_id != (v_order->>'id')::uuid THEN
        CONTINUE;
      END IF;

      -- Check Soft Deletes (Rule: products.is_deleted = false)
      SELECT p.price, p.category, p.name, p.gst_rate_override
      INTO v_expected_grand_total, v_category, v_db_product_name, v_gst_override
      FROM products p
      WHERE p.id = v_item.product_id AND p.is_deleted = false;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'Product % is no longer available.', v_item.product_id;
      END IF;

      IF v_item.variant_name IS NOT NULL AND v_item.variant_name != '' THEN
        DECLARE
          v_variant_price numeric;
        BEGIN
          SELECT (v->>'price')::numeric INTO v_variant_price
          FROM products p, jsonb_array_elements(p.variants) AS v
          WHERE p.id = v_item.product_id AND v->>'name' = v_item.variant_name AND p.is_deleted = false;
          
          IF v_variant_price IS NOT NULL THEN
            v_expected_grand_total := v_variant_price;
          END IF;
        END;
      END IF;

      IF ABS(v_item.price - v_expected_grand_total) > 0.01 THEN
        RAISE EXCEPTION 'Price tampering detected for %: Expected %, Got %', v_db_product_name, v_expected_grand_total, v_item.price;
      END IF;

      v_pure_commission := v_pure_commission + (v_item.price * v_item.quantity * (v_cat_comm / 100.0));

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

    v_gw_deduct := GREATEST(0, (v_expected_grand_total * 0.02) * (1.0 + v_gateway_gst_rate));
    v_seller_gw_share := GREATEST(0, (v_expected_total_amount - v_pure_commission + v_non_food_gst) * 0.0236);
    v_server_enything_commission := v_pure_commission + v_seller_gw_share;
    v_server_seller_payout := v_expected_total_amount + v_non_food_gst - v_server_enything_commission - v_tcs_amount - v_tds_amount;
    
    v_server_rider_earnings := GREATEST(0, (COALESCE((v_order->>'delivery_charges')::numeric, 0) - v_server_gst_delivery - COALESCE((v_order->>'small_cart_fee')::numeric, 0)) * (v_rider_commission_percent / 100.0));

    IF auth.uid() IS NOT NULL AND auth.uid() != (v_order->>'customer_id')::uuid THEN
      RAISE EXCEPTION 'Unauthorized: customer_id mismatch';
    END IF;
    
    v_acceptance_deadline := (v_order->>'acceptance_deadline')::timestamptz;
    IF v_acceptance_deadline IS NULL THEN
      v_acceptance_deadline := NOW() + INTERVAL '3 minutes';
    END IF;

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
      'acceptance_deadline', v_acceptance_deadline,
      'cart_group_id', p_cart_group_id,
      'idempotency_key', p_idempotency_key,
      'created_at', (COALESCE((v_order->>'created_at')::timestamptz, clock_timestamp()) + ((v_order_seq * 10) || ' milliseconds')::interval)::text,
      'updated_at', (COALESCE((v_order->>'updated_at')::timestamptz, clock_timestamp()) + ((v_order_seq * 10) || ' milliseconds')::interval)::text,
      'total_amount', v_expected_total_amount,
      's9_5_gst_amount', v_s9_5_gst,
      'non_food_gst_amount', v_non_food_gst,
      'gst_item_total', (v_s9_5_gst + v_non_food_gst),
      'tcs_amount', v_tcs_amount,
      'tds_amount', v_tds_amount,
      'platform_fee', COALESCE((v_order->>'platform_fee')::numeric, 0),
      'delivery_charges', COALESCE((v_order->>'delivery_charges')::numeric, 0),
      'multi_shop_surcharge', COALESCE((v_order->>'multi_shop_surcharge')::numeric, 0),
      'small_cart_fee', COALESCE((v_order->>'small_cart_fee')::numeric, 0),
      'heavy_order_fee', COALESCE((v_order->>'heavy_order_fee')::numeric, 0),
      'grand_total', v_expected_grand_total,
      'grand_total_collected', v_expected_grand_total,
      'gst_platform', v_server_gst_platform,
      'gst_delivery', v_server_gst_delivery,
      'gateway_deduction', v_gw_deduct,
      'seller_payout', v_server_seller_payout,
      'enything_commission', v_server_enything_commission,
      'rider_earnings', v_server_rider_earnings,
      'coupon_id', p_coupon_id,
      'coupon_discount', COALESCE((v_order->>'coupon_discount')::numeric, 0),
      'gst_rate_snapshot', COALESCE(v_order->'gst_rate_snapshot', '{}'::jsonb),
      'prescription_urls', COALESCE(v_order->'prescription_urls', '[]'::jsonb),
      'shop_prep_time_snapshot', (v_order->>'shop_prep_time_snapshot')::int
    );

    INSERT INTO orders (
      id, customer_id, shop_id, payment_method, payment_status, status,
      seller_accepted, partner_accepted, delivery_partner_id, rider_phone,
      address, address_label, delivery_lat, delivery_lng, delivery_notes,
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
      v_secure_order->>'delivery_notes', (v_secure_order->>'estimated_distance_km')::numeric,
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
      v_secure_order->'gst_rate_snapshot', v_secure_order->'prescription_urls',
      (v_secure_order->>'shop_prep_time_snapshot')::int
    );

    v_inserted_ids := array_append(v_inserted_ids, (v_secure_order->>'id')::uuid);
  END LOOP;

  -- 9. Inventory Verification & Reservation (Products: total_quantity, is_deleted = false)
  FOR v_item IN SELECT product_id, SUM(quantity)::int AS total_qty_req
                FROM jsonb_to_recordset(p_items) AS x(product_id uuid, quantity int)
                GROUP BY product_id LOOP
    SELECT total_quantity, name INTO v_db_stock, v_db_product_name
    FROM products
    WHERE id = v_item.product_id AND is_deleted = false;

    IF v_db_stock IS NOT NULL THEN
      IF v_db_stock < v_item.total_qty_req THEN
        RAISE EXCEPTION 'Product % is out of stock (Available: %, Requested: %)',
          COALESCE(v_db_product_name, v_item.product_id::text), v_db_stock, v_item.total_qty_req;
      END IF;

      UPDATE products
      SET total_quantity = total_quantity - v_item.total_qty_req
      WHERE id = v_item.product_id;
    END IF;
  END LOOP;

  -- Insert order items with complete column attribution and null-safety
  FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) AS x(
    id uuid,
    order_id uuid,
    product_id uuid,
    product_name text,
    variant_name text,
    quantity int,
    price numeric,
    weight_kg numeric,
    requires_prescription boolean,
    special_instructions text,
    created_at timestamptz
  ) LOOP
    SELECT name INTO v_db_product_name FROM products WHERE id = v_item.product_id;

    INSERT INTO order_items (
      id, order_id, product_id, product_name, variant_name, quantity, price,
      unit_price, total_price, weight_kg, requires_prescription, special_instructions, created_at
    ) VALUES (
      COALESCE(v_item.id, gen_random_uuid()),
      v_item.order_id,
      v_item.product_id,
      COALESCE(v_item.product_name, v_db_product_name, 'Product'),
      v_item.variant_name,
      COALESCE(v_item.quantity, 1),
      v_item.price,
      COALESCE(v_item.price, 0),
      COALESCE(v_item.price * COALESCE(v_item.quantity, 1), 0),
      COALESCE(v_item.weight_kg, 0.0),
      COALESCE(v_item.requires_prescription, false),
      v_item.special_instructions,
      COALESCE(v_item.created_at, now())
    );
    v_inserted_item_ids := array_append(v_inserted_item_ids, COALESCE(v_item.id, gen_random_uuid()));
  END LOOP;

  -- 10. Record Coupon Usage
  IF p_coupon_id IS NOT NULL THEN
    INSERT INTO user_coupon_usage (user_id, coupon_id, order_id, discount_applied)
    VALUES (v_customer_id, p_coupon_id, v_inserted_ids[1], v_expected_discount);
  END IF;

  -- 11. Replacement Order Cancellation Cleanup
  IF p_order_id_to_cancel IS NOT NULL THEN
    UPDATE orders
    SET status = CASE 
          WHEN status IN ('delivered', 'cancelled', 'seller_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel', 'no_rider', 'partner_rejected', 'rider_rejected') THEN status
          ELSE 'cancelled'
        END,
        cancelled_reason = COALESCE(cancelled_reason, 'customer_replaced'),
        updated_at = NOW()
    WHERE id = p_order_id_to_cancel;

    PERFORM reallocate_cancelled_delivery_fees(p_cart_group_id);
    PERFORM rebalance_active_delivery_fees(p_cart_group_id);
  END IF;

  RETURN (
    SELECT jsonb_agg(to_jsonb(o))
    FROM orders o
    WHERE o.id = ANY(v_inserted_ids)
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.place_orders_transaction(jsonb, jsonb, uuid, uuid, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.place_orders_transaction(jsonb, jsonb, uuid, uuid, text, uuid) TO service_role;


-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Fortified reallocate_cancelled_delivery_fees (Sequential Distance Chain)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.reallocate_cancelled_delivery_fees(p_cart_group_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_active_count INT;
  v_newly_cancelled_count INT;
  v_active_items_total NUMERIC;
  v_active_weight_total NUMERIC;
  v_total_cart_delivery NUMERIC;
  v_total_cart_coupon NUMERIC;
  v_available_pool NUMERIC;
  
  v_admin_delivery_base NUMERIC := 20.0;
  v_delivery_rate_per_km NUMERIC := 20.0;
  v_new_base_delivery NUMERIC := 20.0;
  v_new_active_delivery_total NUMERIC := 0.0;
  
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
  c_rec RECORD;
  
  v_sum_active_grand NUMERIC := 0;
  v_total_refund_amount NUMERIC := 0;
  v_allocated_refund_sum NUMERIC := 0;
  v_order_refund NUMERIC := 0;
  v_sum_cancelled_weights NUMERIC := 0;
  v_cancelled_idx INT := 0;

  -- Active shop coordinates for sequential distance chaining
  v_act_shop_lats double precision[] := '{}';
  v_act_shop_lngs double precision[] := '{}';
  v_act_dist_to_c double precision[] := '{}';
  v_inter_dist double precision;
  v_leg_surcharges numeric[] := '{}';
  v_total_act_surcharge numeric := 0.0;
  v_active_idx int := 0;
BEGIN
    -- Deterministic row-level locking
    PERFORM id FROM public.orders 
    WHERE cart_group_id = p_cart_group_id 
    ORDER BY id FOR UPDATE;

    BEGIN SELECT (value#>>'{}')::numeric INTO v_platform_gst_rate FROM platform_config WHERE key = 'platform_fee_gst_rate'; EXCEPTION WHEN OTHERS THEN v_platform_gst_rate := 0.18; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_delivery_gst_rate FROM platform_config WHERE key = 'delivery_gst_rate'; EXCEPTION WHEN OTHERS THEN v_delivery_gst_rate := 0.18; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_rider_commission_percent FROM platform_config WHERE key = 'rider_commission_percent'; EXCEPTION WHEN OTHERS THEN v_rider_commission_percent := 80.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_admin_platform_fee FROM platform_config WHERE key = 'platform_fee'; EXCEPTION WHEN OTHERS THEN v_admin_platform_fee := 20.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_admin_delivery_base FROM platform_config WHERE key = 'delivery_base_fee'; EXCEPTION WHEN OTHERS THEN v_admin_delivery_base := 20.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_delivery_rate_per_km FROM platform_config WHERE key = 'delivery_rate_per_km'; EXCEPTION WHEN OTHERS THEN v_delivery_rate_per_km := 20.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_small_cart_threshold FROM platform_config WHERE key = 'small_cart_threshold'; EXCEPTION WHEN OTHERS THEN v_small_cart_threshold := 99.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_small_cart_fee FROM platform_config WHERE key = 'small_cart_fee'; EXCEPTION WHEN OTHERS THEN v_small_cart_fee := 15.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_heavy_order_threshold_kg FROM platform_config WHERE key = 'heavy_order_threshold_kg'; EXCEPTION WHEN OTHERS THEN v_heavy_order_threshold_kg := 10.0; END;
    BEGIN SELECT (value#>>'{}')::numeric INTO v_heavy_order_fee FROM platform_config WHERE key = 'heavy_order_fee'; EXCEPTION WHEN OTHERS THEN v_heavy_order_fee := 25.0; END;

    v_platform_gst_rate := COALESCE(v_platform_gst_rate, 0.18);
    v_delivery_gst_rate := COALESCE(v_delivery_gst_rate, 0.18);
    v_rider_commission_percent := COALESCE(v_rider_commission_percent, 80.0);
    v_admin_platform_fee := COALESCE(v_admin_platform_fee, 20.0);
    v_admin_delivery_base := COALESCE(v_admin_delivery_base, 20.0);
    v_delivery_rate_per_km := COALESCE(v_delivery_rate_per_km, 20.0);
    v_small_cart_threshold := COALESCE(v_small_cart_threshold, 99.0);
    v_small_cart_fee := COALESCE(v_small_cart_fee, 15.0);
    v_heavy_order_threshold_kg := COALESCE(v_heavy_order_threshold_kg, 10.0);
    v_heavy_order_fee := COALESCE(v_heavy_order_fee, 25.0);

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

        SELECT COUNT(id)
          INTO v_newly_cancelled_count
          FROM public.orders
         WHERE cart_group_id = p_cart_group_id
           AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
           AND status IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
           AND (grand_total > 0 OR delivery_charges > 0 OR platform_fee > 0);

        IF v_active_count = 0 AND v_newly_cancelled_count = 0 THEN
            CONTINUE;
        END IF;

        -- CASE A: ALL SHOPS CANCELLED (v_active_count = 0)
        IF v_active_count = 0 THEN
            UPDATE public.orders
               SET delivery_charges      = 0,
                   platform_fee          = 0,
                   small_cart_fee        = 0,
                   heavy_order_fee       = 0,
                   multi_shop_surcharge  = 0,
                   coupon_discount       = 0,
                   gst_platform          = 0,
                   gst_delivery          = 0,
                   rider_earnings        = 0,
                   delivery_partner_id   = NULL,
                   updated_at            = NOW()
             WHERE cart_group_id = p_cart_group_id
               AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
               AND status IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
               AND (delivery_charges > 0 OR platform_fee > 0);

            CONTINUE;
        END IF;

        IF v_newly_cancelled_count = 0 THEN
            CONTINUE;
        END IF;

        -- Sum weight of remaining active items
        SELECT COALESCE(SUM(oi.quantity * COALESCE(p.weight_per_unit, 0.5)), 0)
          INTO v_active_weight_total
          FROM public.order_items oi
          JOIN public.orders o ON o.id = oi.order_id
          JOIN public.products p ON p.id = oi.product_id
         WHERE o.cart_group_id = p_cart_group_id
           AND o.razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
           AND o.status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
           AND p.is_deleted = false;

        -- Available pool from active plus newly cancelled
        SELECT 
            COALESCE(SUM(grand_total_collected), 0),
            COALESCE(SUM(delivery_charges),      0),
            COALESCE(SUM(coupon_discount),       0),
            MAX(coupon_id::text)::uuid
          INTO 
            v_available_pool,
            v_total_cart_delivery,
            v_total_cart_coupon,
            v_group_coupon_id
          FROM public.orders
         WHERE cart_group_id = p_cart_group_id
           AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
           AND (status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
                OR grand_total > 0
                OR delivery_charges > 0
                OR platform_fee > 0);

        -- Build sequential coordinates for remaining active shops
        v_act_shop_lats := '{}';
        v_act_shop_lngs := '{}';
        v_act_dist_to_c := '{}';
        v_leg_surcharges := '{}';
        v_total_act_surcharge := 0.0;

        FOR rec IN
            SELECT o.id, o.estimated_distance_km, o.delivery_lat, o.delivery_lng, s.location
            FROM public.orders o
            JOIN public.shops s ON s.id = o.shop_id
            WHERE o.cart_group_id = p_cart_group_id
              AND o.razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
              AND o.status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
            ORDER BY o.created_at ASC, o.id ASC
        LOOP
            v_act_shop_lats := array_append(v_act_shop_lats, ST_Y(rec.location::geometry)::double precision);
            v_act_shop_lngs := array_append(v_act_shop_lngs, ST_X(rec.location::geometry)::double precision);
            v_act_dist_to_c := array_append(v_act_dist_to_c, COALESCE(rec.estimated_distance_km::double precision, 3.0));
        END LOOP;

        -- Sequential Base Delivery: first active shop is promoted to Base Shop
        v_new_base_delivery := GREATEST(v_admin_delivery_base, GREATEST(1, CEIL(v_act_dist_to_c[1])) * v_delivery_rate_per_km);

        -- Sequential Surcharges for Active Shops
        v_leg_surcharges := array_append(v_leg_surcharges, 0.0); -- Active Shop 1 surcharge = 0
        IF v_active_count > 1 THEN
            FOR i IN 1..(v_active_count - 1) LOOP
                v_inter_dist := 6371.0 * acos(
                  LEAST(1.0, GREATEST(-1.0, 
                    cos(radians(v_act_shop_lats[i])) * cos(radians(v_act_shop_lats[i+1])) *
                    cos(radians(v_act_shop_lngs[i+1]) - radians(v_act_shop_lngs[i])) +
                    sin(radians(v_act_shop_lats[i])) * sin(radians(v_act_shop_lats[i+1]))
                  ))
                );
                v_new_surcharge := GREATEST(1, CEIL(v_inter_dist)) * v_delivery_rate_per_km;
                v_leg_surcharges := array_append(v_leg_surcharges, v_new_surcharge);
                v_total_act_surcharge := v_total_act_surcharge + v_new_surcharge;
            END LOOP;
        END IF;

        -- Small cart & Heavy order fees
        IF v_active_items_total > 0 AND v_active_items_total < v_small_cart_threshold THEN
            v_new_small := v_small_cart_fee;
        ELSE
            v_new_small := 0;
        END IF;

        IF v_active_weight_total > v_heavy_order_threshold_kg THEN
            v_new_heavy := v_heavy_order_fee * CEIL(v_active_weight_total - v_heavy_order_threshold_kg);
        ELSE
            v_new_heavy := 0;
        END IF;

        -- Total delivery fee for active orders
        v_new_active_delivery_total := (v_new_base_delivery + v_total_act_surcharge + v_new_small + v_new_heavy) * (1.0 + v_delivery_gst_rate);

        -- Dynamic Coupon Re-evaluation
        v_recalculated_total_discount := 0;
        IF v_group_coupon_id IS NOT NULL AND v_total_cart_coupon > 0 THEN
            SELECT discount_type, discount_value, max_discount_amount, min_order_amount
              INTO v_coupon_type, v_coupon_val, v_coupon_cap, v_coupon_min
              FROM public.coupons
             WHERE id = v_group_coupon_id;

            IF FOUND THEN
                IF v_coupon_min IS NULL OR v_active_items_total >= v_coupon_min THEN
                    IF v_coupon_type = 'percentage' THEN
                        v_recalculated_total_discount := (v_active_items_total * (v_coupon_val / 100.0));
                        IF v_coupon_cap IS NOT NULL THEN
                            v_recalculated_total_discount := LEAST(v_recalculated_total_discount, v_coupon_cap);
                        END IF;
                    ELSE
                        v_recalculated_total_discount := LEAST(v_coupon_val, v_active_items_total);
                    END IF;
                ELSE
                    v_recalculated_total_discount := 0;
                END IF;
            END IF;
        END IF;

        -- Update Active Orders with Leg-Specific Attribution
        v_sum_active_grand := 0;
        v_active_idx := 0;

        FOR rec IN
            SELECT id, total_amount, s9_5_gst_amount, non_food_gst_amount
            FROM public.orders
            WHERE cart_group_id = p_cart_group_id
              AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
              AND status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
            ORDER BY created_at ASC, id ASC
        LOOP
            v_active_idx := v_active_idx + 1;

            -- Shop 1 holds Base Delivery + Small/Heavy Fee + Platform Fee
            -- Shop 2+ hold Leg Surcharge only
            IF v_active_idx = 1 THEN
                v_new_del := (v_new_base_delivery + v_new_small + v_new_heavy) * (1.0 + v_delivery_gst_rate);
                v_new_plat := v_admin_platform_fee;
                v_new_surcharge := 0.0;
                v_new_rider := GREATEST(0, (v_new_base_delivery + v_new_heavy) * (v_rider_commission_percent / 100.0));
            ELSE
                v_new_surcharge := COALESCE(v_leg_surcharges[v_active_idx], 0.0);
                v_new_del := v_new_surcharge * (1.0 + v_delivery_gst_rate);
                v_new_plat := 0.0;
                v_new_rider := GREATEST(0, v_new_surcharge * (v_rider_commission_percent / 100.0));
            END IF;

            v_new_gst_plat := v_new_plat - (v_new_plat / (1.0 + v_platform_gst_rate));
            v_new_gst_del := v_new_del - (v_new_del / (1.0 + v_delivery_gst_rate));

            IF v_active_items_total > 0 THEN
                v_new_coupon := v_recalculated_total_discount * (rec.total_amount / v_active_items_total);
            ELSE
                v_new_coupon := 0;
            END IF;

            v_new_grand := GREATEST(0, rec.total_amount + rec.s9_5_gst_amount + rec.non_food_gst_amount + v_new_plat + v_new_del - v_new_coupon);
            v_sum_active_grand := v_sum_active_grand + v_new_grand;

            UPDATE public.orders
               SET delivery_charges      = v_new_del,
                   platform_fee          = v_new_plat,
                   small_cart_fee        = CASE WHEN v_active_idx = 1 THEN v_new_small ELSE 0 END,
                   heavy_order_fee       = CASE WHEN v_active_idx = 1 THEN v_new_heavy ELSE 0 END,
                   multi_shop_surcharge  = v_new_surcharge,
                   coupon_discount       = v_new_coupon,
                   gst_platform          = v_new_gst_plat,
                   gst_delivery          = v_new_gst_del,
                   rider_earnings        = v_new_rider,
                   grand_total           = v_new_grand,
                   grand_total_collected = v_new_grand,
                   updated_at            = NOW()
             WHERE id = rec.id;
        END LOOP;

        -- Distribute Refund to Newly Cancelled Orders
        v_total_refund_amount := GREATEST(0, v_available_pool - v_sum_active_grand);
        v_allocated_refund_sum := 0;
        v_cancelled_idx := 0;

        SELECT COALESCE(SUM(grand_total_collected), 0)
          INTO v_sum_cancelled_weights
          FROM public.orders
         WHERE cart_group_id = p_cart_group_id
           AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
           AND status IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
           AND (grand_total > 0 OR delivery_charges > 0 OR platform_fee > 0);

        FOR c_rec IN
            SELECT id, grand_total_collected
            FROM public.orders
            WHERE cart_group_id = p_cart_group_id
              AND razorpay_payment_id IS NOT DISTINCT FROM pay_rec.razorpay_payment_id
              AND status IN ('cancelled', 'seller_rejected', 'partner_rejected', 'rider_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
              AND (grand_total > 0 OR delivery_charges > 0 OR platform_fee > 0)
            ORDER BY id ASC
        LOOP
            v_cancelled_idx := v_cancelled_idx + 1;
            
            IF v_cancelled_idx = v_newly_cancelled_count THEN
                v_order_refund := v_total_refund_amount - v_allocated_refund_sum;
            ELSE
                IF v_sum_cancelled_weights > 0 THEN
                    v_order_refund := ROUND((v_total_refund_amount * (c_rec.grand_total_collected / v_sum_cancelled_weights))::numeric, 2);
                ELSE
                    v_order_refund := ROUND((v_total_refund_amount / v_newly_cancelled_count)::numeric, 2);
                END IF;
                v_allocated_refund_sum := v_allocated_refund_sum + v_order_refund;
            END IF;

            UPDATE public.orders
               SET delivery_charges      = 0,
                   platform_fee          = 0,
                   small_cart_fee        = 0,
                   heavy_order_fee       = 0,
                   multi_shop_surcharge  = 0,
                   coupon_discount       = 0,
                   gst_platform          = 0,
                   gst_delivery          = 0,
                   rider_earnings        = 0,
                   grand_total           = 0,
                   grand_total_collected = v_order_refund,
                   updated_at            = NOW()
             WHERE id = c_rec.id;
        END LOOP;
    END LOOP;

    RETURN true;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.reallocate_cancelled_delivery_fees(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reallocate_cancelled_delivery_fees(uuid) TO service_role;


-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Fortified rebalance_active_delivery_fees (Synchronized)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.rebalance_active_delivery_fees(p_cart_group_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    PERFORM public.reallocate_cancelled_delivery_fees(p_cart_group_id);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rebalance_active_delivery_fees(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rebalance_active_delivery_fees(uuid) TO service_role;
