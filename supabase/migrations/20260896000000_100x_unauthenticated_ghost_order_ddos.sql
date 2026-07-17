-- Migration 20260896000000_100x_unauthenticated_ghost_order_ddos.sql

-- Drop old overloads to prevent Legacy Endpoint Exploits
DROP FUNCTION IF EXISTS place_orders_transaction(jsonb, jsonb, uuid);
DROP FUNCTION IF EXISTS place_orders_transaction(jsonb, jsonb, uuid, uuid);
DROP FUNCTION IF EXISTS place_orders_transaction(jsonb, jsonb, uuid, uuid, text);
DROP FUNCTION IF EXISTS claim_order_as_rider(uuid, uuid);

CREATE OR REPLACE FUNCTION public.place_orders_transaction(p_orders jsonb, p_items jsonb, p_cart_group_id uuid, p_coupon_id uuid DEFAULT NULL::uuid, p_idempotency_key text DEFAULT NULL::text, p_order_id_to_cancel uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
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

  -- 100x Architecture Protection: Ghost Order Bypass Prevention
  -- Ensure that none of the target shops are deactivated/closed.
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_orders)
    LEFT JOIN shops s ON s.id = (value->>'shop_id')::uuid
    WHERE s.is_active = false
  ) THEN
    RAISE EXCEPTION 'One or more shops in this order are currently inactive or closed. Exploit blocked.';
  END IF;

  -- Load Dynamic Admin Rates (With 100x Architecture Sanity Bounds)
  BEGIN SELECT value::numeric INTO v_default_comm FROM platform_config WHERE key = 'default_commission_percent'; EXCEPTION WHEN OTHERS THEN v_default_comm := 10.0; END;
  v_default_comm := LEAST(GREATEST(COALESCE(v_default_comm, 10.0), 0.0), 100.0);
  
  BEGIN SELECT value::numeric INTO v_delivery_gst_rate FROM platform_config WHERE key = 'delivery_gst_rate'; EXCEPTION WHEN OTHERS THEN v_delivery_gst_rate := 0.18; END;
  v_delivery_gst_rate := LEAST(GREATEST(COALESCE(v_delivery_gst_rate, 0.18), 0.0), 1.0);
  
  BEGIN SELECT value::numeric INTO v_platform_gst_rate FROM platform_config WHERE key = 'platform_fee_gst_rate'; EXCEPTION WHEN OTHERS THEN v_platform_gst_rate := 0.18; END;
  v_platform_gst_rate := LEAST(GREATEST(COALESCE(v_platform_gst_rate, 0.18), 0.0), 1.0);
  
  BEGIN SELECT value::numeric INTO v_rider_commission_percent FROM platform_config WHERE key = 'rider_commission_percent'; EXCEPTION WHEN OTHERS THEN v_rider_commission_percent := 80.0; END;
  v_rider_commission_percent := LEAST(GREATEST(COALESCE(v_rider_commission_percent, 80.0), 0.0), 100.0);
  
  BEGIN SELECT value::numeric INTO v_global_delivery_rate_per_km FROM platform_config WHERE key = 'delivery_rate_per_km'; EXCEPTION WHEN OTHERS THEN v_global_delivery_rate_per_km := 20.0; END;
  v_global_delivery_rate_per_km := GREATEST(COALESCE(v_global_delivery_rate_per_km, 20.0), 0.0);

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

  -- 100x Architecture Protection: Coupon Mathematical Spoofing \u0026 State Abuse
  IF p_coupon_id IS NOT NULL THEN
    SELECT discount_type, discount_value, max_discount_cap, min_order_amount, valid_from, valid_until, is_active, usage_count, usage_limit
    INTO v_coupon_type, v_coupon_val, v_coupon_cap, v_coupon_min, v_coupon_valid_from, v_coupon_valid_until, v_coupon_is_active, v_coupon_usage_count, v_coupon_usage_limit
    FROM coupons WHERE id = p_coupon_id FOR UPDATE;

    IF v_coupon_type IS NULL THEN
      RAISE EXCEPTION 'Invalid coupon ID provided.';
    END IF;

    IF NOT v_coupon_is_active OR now() NOT BETWEEN v_coupon_valid_from AND v_coupon_valid_until THEN
      RAISE EXCEPTION 'Coupon is inactive or expired.';
    END IF;

    IF v_coupon_usage_count >= v_coupon_usage_limit THEN
      RAISE EXCEPTION 'Coupon usage limit reached.';
    END IF;

    IF v_sum_expected_total_amount >= COALESCE(v_coupon_min, 0) THEN
      IF v_coupon_type = 'percentage' THEN
         v_true_discount := LEAST(v_sum_expected_total_amount * (v_coupon_val / 100.0), v_coupon_cap);
      ELSE
         v_true_discount := LEAST(v_coupon_val, v_sum_expected_total_amount);
      END IF;
    ELSE
      v_true_discount := 0;
    END IF;
  ELSE
    v_true_discount := 0;
  END IF;

  FOR v_item IN SELECT y.quantity, p.weight_per_unit 
                FROM jsonb_to_recordset(p_items) AS y(product_id uuid, quantity int)
                JOIN products p ON p.id = y.product_id LOOP
    v_total_weight_kg := v_total_weight_kg + (COALESCE(v_item.weight_per_unit, 0.5) * v_item.quantity);
  END LOOP;

  IF v_total_weight_kg > 20.0 THEN
    RAISE EXCEPTION 'Order exceeds maximum allowed weight of 20kg. Estimated weight: % kg', v_total_weight_kg;
  END IF;

  SELECT COUNT(DISTINCT (value->>'shop_id')::uuid) INTO v_shop_count FROM jsonb_array_elements(p_orders);
  
  IF v_shop_count > 3 THEN
    RAISE EXCEPTION 'Maximum 3 shops allowed per order. Found: %', v_shop_count;
  END IF;

  FOR v_order_totals IN SELECT 
      (value->>'platform_fee')::numeric AS platform_fee,
      (value->>'small_cart_fee')::numeric AS small_cart_fee,
      (value->>'heavy_order_fee')::numeric AS heavy_order_fee,
      (value->>'multi_shop_surcharge')::numeric AS multi_shop_surcharge,
      (value->>'coupon_discount')::numeric AS coupon_discount,
      (value->>'delivery_charges')::numeric AS delivery_charges,
      (value->>'estimated_distance_km')::numeric AS estimated_distance_km
    FROM jsonb_array_elements(p_orders) 
  LOOP
    v_sum_client_platform_fee := v_sum_client_platform_fee + COALESCE(v_order_totals.platform_fee, 0);
    v_sum_client_small_cart_fee := v_sum_client_small_cart_fee + COALESCE(v_order_totals.small_cart_fee, 0);
    v_sum_client_heavy_order_fee := v_sum_client_heavy_order_fee + COALESCE(v_order_totals.heavy_order_fee, 0);
    v_sum_client_multi_shop_surcharge := v_sum_client_multi_shop_surcharge + COALESCE(v_order_totals.multi_shop_surcharge, 0);
    v_sum_client_coupon_discount := v_sum_client_coupon_discount + COALESCE(v_order_totals.coupon_discount, 0);
    v_sum_client_delivery_charges := v_sum_client_delivery_charges + COALESCE(v_order_totals.delivery_charges, 0);
    
    -- 100x Architecture Protection: Negative Math Exploit Prevention
    IF COALESCE(v_order_totals.platform_fee, 0) < 0.0 THEN RAISE EXCEPTION 'Negative platform fee is strictly prohibited.'; END IF;
    IF COALESCE(v_order_totals.small_cart_fee, 0) < 0.0 THEN RAISE EXCEPTION 'Negative small cart fee is strictly prohibited.'; END IF;
    IF COALESCE(v_order_totals.heavy_order_fee, 0) < 0.0 THEN RAISE EXCEPTION 'Negative heavy order fee is strictly prohibited.'; END IF;
    IF COALESCE(v_order_totals.multi_shop_surcharge, 0) < 0.0 THEN RAISE EXCEPTION 'Negative multi shop surcharge is strictly prohibited.'; END IF;
    IF COALESCE(v_order_totals.coupon_discount, 0) < 0.0 THEN RAISE EXCEPTION 'Negative coupon discount is strictly prohibited.'; END IF;
    
    IF COALESCE(v_order_totals.estimated_distance_km, 0) < 0.0 THEN
      RAISE EXCEPTION 'Distance cannot be negative. Exploit detected.';
    END IF;

    IF COALESCE(v_order_totals.estimated_distance_km, 0) > 100.0 THEN
      RAISE EXCEPTION 'Distance spoofing detected (Money Laundering Exploit). The maximum allowed delivery radius is 100km. Claimed: % km', v_order_totals.estimated_distance_km;
    END IF;

    -- 100x Architecture Protection: Enforce delivery charge floor to prevent Free Delivery hacks
    -- Allows 50% deviation margin from base formula to prevent breaking frontend surges/promos, while establishing hard minimum floor.
    IF COALESCE(v_order_totals.delivery_charges, 0) < GREATEST(10.0, COALESCE(v_order_totals.estimated_distance_km, 0) * (v_global_delivery_rate_per_km * 0.5)) THEN
      RAISE EXCEPTION 'Delivery charge floor breached. Possible exploit detected. Distance: % km, Charge: %', COALESCE(v_order_totals.estimated_distance_km, 0), COALESCE(v_order_totals.delivery_charges, 0);
    END IF;
  END LOOP;

  BEGIN SELECT value::numeric INTO v_global_platform_fee FROM platform_config WHERE key = 'platform_fee'; EXCEPTION WHEN OTHERS THEN v_global_platform_fee := 2.5; END;
  v_global_platform_fee := GREATEST(COALESCE(v_global_platform_fee, 2.5), 0.0);
  v_global_platform_fee := v_global_platform_fee * v_shop_count;

  IF ABS(v_sum_client_platform_fee - v_global_platform_fee) > 1.0 THEN
    RAISE EXCEPTION 'Platform fee spoofing detected. Expected: %, Got: %', v_global_platform_fee, v_sum_client_platform_fee;
  END IF;
  
  IF ABS(v_sum_client_coupon_discount - v_true_discount) > 1.0 THEN
    RAISE EXCEPTION 'Coupon discount spoofing detected. Expected: %, Got: %', v_true_discount, v_sum_client_coupon_discount;
  END IF;

  BEGIN SELECT value::numeric INTO v_global_small_cart_fee FROM platform_config WHERE key = 'small_cart_fee'; EXCEPTION WHEN OTHERS THEN v_global_small_cart_fee := 15.0; END;
  v_global_small_cart_fee := GREATEST(COALESCE(v_global_small_cart_fee, 15.0), 0.0);
  BEGIN SELECT value::numeric INTO v_global_small_cart_threshold FROM platform_config WHERE key = 'small_cart_threshold'; EXCEPTION WHEN OTHERS THEN v_global_small_cart_threshold := 99.0; END;
  v_global_small_cart_threshold := GREATEST(COALESCE(v_global_small_cart_threshold, 99.0), 0.0);

  IF v_sum_expected_total_amount < v_global_small_cart_threshold THEN
    IF ABS(v_sum_client_small_cart_fee - v_global_small_cart_fee) > 1.0 THEN
       RAISE EXCEPTION 'Small cart fee spoofing detected. Expected: %, Got: %', v_global_small_cart_fee, v_sum_client_small_cart_fee;
    END IF;
  ELSE
    IF v_sum_client_small_cart_fee > 0 THEN
       RAISE EXCEPTION 'Small cart fee applied incorrectly. Total amount % exceeds threshold %.', v_sum_expected_total_amount, v_global_small_cart_threshold;
    END IF;
  END IF;

  BEGIN SELECT value::numeric INTO v_global_heavy_order_fee FROM platform_config WHERE key = 'heavy_order_fee'; EXCEPTION WHEN OTHERS THEN v_global_heavy_order_fee := 25.0; END;
  v_global_heavy_order_fee := COALESCE(v_global_heavy_order_fee, 25.0);
  BEGIN SELECT value::numeric INTO v_global_heavy_order_threshold FROM platform_config WHERE key = 'heavy_order_threshold_kg'; EXCEPTION WHEN OTHERS THEN v_global_heavy_order_threshold := 10.0; END;
  v_global_heavy_order_threshold := COALESCE(v_global_heavy_order_threshold, 10.0);

  IF v_total_weight_kg > v_global_heavy_order_threshold THEN
    IF ABS(v_sum_client_heavy_order_fee - v_global_heavy_order_fee) > 1.0 THEN
       RAISE EXCEPTION 'Heavy order fee spoofing detected. Expected: %, Got: %', v_global_heavy_order_fee, v_sum_client_heavy_order_fee;
    END IF;
  ELSE
    IF v_sum_client_heavy_order_fee > 0 THEN
       RAISE EXCEPTION 'Heavy order fee applied incorrectly. Weight % is below threshold %.', v_total_weight_kg, v_global_heavy_order_threshold;
    END IF;
  END IF;

  BEGIN SELECT value::numeric INTO v_global_multi_shop_surcharge FROM platform_config WHERE key = 'multi_shop_surcharge'; EXCEPTION WHEN OTHERS THEN v_global_multi_shop_surcharge := 20.0; END;
  v_global_multi_shop_surcharge := COALESCE(v_global_multi_shop_surcharge, 20.0);

  IF v_shop_count > 1 THEN
    IF ABS(v_sum_client_multi_shop_surcharge - (v_global_multi_shop_surcharge * (v_shop_count - 1))) > 1.0 THEN
       RAISE EXCEPTION 'Multi shop surcharge spoofing detected. Expected: %, Got: %', (v_global_multi_shop_surcharge * (v_shop_count - 1)), v_sum_client_multi_shop_surcharge;
    END IF;
  ELSE
    IF v_sum_client_multi_shop_surcharge > 0 THEN
       RAISE EXCEPTION 'Multi shop surcharge applied incorrectly for single shop order.';
    END IF;
  END IF;

  FOR v_order IN SELECT * FROM jsonb_array_elements(p_orders) LOOP
    
    -- 100x Architecture Protection: String Payload Bloat bounds (Pixel Overloading)
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

    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) AS x(product_id uuid, variant_name text, price numeric, quantity int, shop_id uuid) WHERE shop_id = (v_order->>'shop_id')::uuid LOOP
      SELECT category INTO v_category FROM products WHERE id = v_item.product_id;
      
      BEGIN
        SELECT value::numeric INTO v_cat_comm FROM platform_config WHERE key = 'commission_percent_' || v_category;
      EXCEPTION WHEN OTHERS THEN v_cat_comm := v_default_comm; END;
      v_cat_comm := LEAST(GREATEST(COALESCE(v_cat_comm, v_default_comm), 0.0), 100.0);
      
      v_pure_commission := v_pure_commission + ((v_item.price * v_item.quantity * v_cat_comm) / 100.0);

      BEGIN
          SELECT gst_rate::numeric, is_deemed_supplier INTO v_gst_rate, v_is_deemed FROM tax_config WHERE category = v_category;
        EXCEPTION WHEN OTHERS THEN v_gst_rate := NULL; END;
        
        IF v_category IN ('Clothing', 'Footwear') THEN
          IF v_item.price > 2500 THEN
            v_gst_rate := 0.18;
          ELSE
            v_gst_rate := 0.05;
          END IF;
        END IF;

        IF v_gst_rate IS NULL THEN
          v_gst_rate := 0.18;
          v_is_deemed := false;
          IF v_category IN ('Restaurant', 'Fast Food', 'Bakery', 'Sweets \u0026 Mithai', 'Tea \u0026 Coffee', 'Ice Cream', 'Paan Shop') THEN
            v_gst_rate := 0.05;
            v_is_deemed := true;
          END IF;
        END IF;

        -- Admin Sanity Bound: Clamp GST rate to safe limits
        v_gst_rate := LEAST(GREATEST(v_gst_rate, 0.0), 1.0);
      
      v_line_gst := v_item.price * v_item.quantity * v_gst_rate;
      
      IF v_is_deemed THEN
        v_s9_5_gst := v_s9_5_gst + v_line_gst;
      ELSE
        v_non_food_gst := v_non_food_gst + v_line_gst;
      END IF;
      
      v_tcs_rate := CASE WHEN v_category IN ('Restaurant', 'Fast Food', 'Bakery', 'Sweets \u0026 Mithai', 'Tea \u0026 Coffee', 'Ice Cream', 'Paan Shop', 'Fruits \u0026 Vegs', 'Butcher', 'Fish \u0026 Seafood') THEN 0.0 ELSE 0.01 END;
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

    IF ABS((v_order->>'grand_total')::numeric - v_expected_grand_total) > 1.0 THEN
      RAISE EXCEPTION 'Grand total mismatch for order %. Expected: %, Got: %', v_order->>'id', v_expected_grand_total, v_order->>'grand_total';
    END IF;
    
    -- DYNAMIC GST
    v_server_gst_platform := COALESCE((v_order->>'platform_fee')::numeric, 0) - (COALESCE((v_order->>'platform_fee')::numeric, 0) / (1.0 + v_platform_gst_rate));
    
    v_server_gst_delivery := COALESCE((v_order->>'delivery_charges')::numeric, 0) - (COALESCE((v_order->>'delivery_charges')::numeric, 0) / (1.0 + v_delivery_gst_rate));

    v_gw_deduct := GREATEST(0, (v_expected_grand_total * 0.02) * (1.0 + v_platform_gst_rate));

    v_server_enything_commission := v_pure_commission + v_server_gst_platform;
    v_server_seller_payout := v_expected_total_amount + v_non_food_gst - v_server_enything_commission - v_tcs_amount - v_tds_amount - v_gw_deduct;
    
    -- DYNAMIC RIDER COMMISSION
    -- delivery_charges from frontend ALREADY includes heavy and multi_shop fees.
    v_server_rider_earnings := GREATEST(0, (COALESCE((v_order->>'delivery_charges')::numeric, 0) - v_server_gst_delivery - COALESCE((v_order->>'small_cart_fee')::numeric, 0)) * (v_rider_commission_percent / 100.0));

    IF auth.uid() IS NOT NULL AND auth.uid() != (v_order->>'customer_id')::uuid THEN
      RAISE EXCEPTION 'Unauthorized: customer_id mismatch';
    END IF;
    
    v_acceptance_deadline := CASE WHEN (v_order->>'payment_method') = 'cod' THEN (now() + interval '3 minutes') ELSE NULL END;

    v_secure_order := jsonb_build_object(
      'id', v_order->>'id',
      'customer_id', v_order->>'customer_id',
      'shop_id', v_order->>'shop_id',
      'payment_method', v_order->>'payment_method',
      'payment_status', v_order->>'payment_status',
      'status', v_order->>'status',
      'seller_accepted', false,
      'partner_accepted', false,
      'address', v_order->>'address',
      'address_label', v_order->>'address_label',
      'delivery_lat', v_order->>'delivery_lat',
      'delivery_lng', v_order->>'delivery_lng',
      'delivery_notes', v_order->>'delivery_notes',
      'estimated_distance_km', v_order->>'estimated_distance_km',
      'cancelled_reason', v_order->>'cancelled_reason',
      'customer_phone', v_order->>'customer_phone',
      'shop_phone', v_order->>'shop_phone',
      'shop_prep_time_snapshot', v_order->>'shop_prep_time_snapshot',
      'prescription_urls', v_order->'prescription_urls',
      'gst_rate_snapshot', v_gst_rate,
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
      customer_phone, shop_phone, shop_prep_time_snapshot, prescription_urls,
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
      NULL,
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
    SELECT total_quantity INTO v_total_qty FROM products WHERE id = v_item.product_id FOR UPDATE;
    IF v_total_qty IS NOT NULL THEN
      IF v_total_qty < v_item.total_qty_req THEN
        RAISE EXCEPTION 'Insufficient stock for product % (Requested: %, Available: %)', v_item.product_id, v_item.total_qty_req, v_total_qty;
      END IF;
      UPDATE products SET total_quantity = total_quantity - v_item.total_qty_req WHERE id = v_item.product_id;
    END IF;
  END LOOP;

  FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) AS x(
    id uuid,
    order_id uuid,
    product_id uuid,
    variant_name text,
    quantity int,
    special_instructions text
  ) LOOP
    IF length(v_item.special_instructions) > 500 THEN
      RAISE EXCEPTION 'Special instructions string too long (Max 500 chars)';
    END IF;
    IF length(v_item.variant_name) > 100 THEN
      RAISE EXCEPTION 'Variant name string too long (Max 100 chars)';
    END IF;
    
    IF v_item.order_id = ANY(v_inserted_ids) THEN
      IF v_item.variant_name IS NULL THEN
        SELECT price, name INTO v_db_price, v_db_product_name FROM products WHERE id = v_item.product_id;
      ELSE
        SELECT (elem->>'price')::numeric, p.name INTO v_db_price, v_db_product_name
        FROM products p, jsonb_array_elements(p.variants) elem
        WHERE p.id = v_item.product_id AND elem->>'name' = v_item.variant_name;
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
    END IF;
  END LOOP;
  
  IF p_coupon_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM orders 
      WHERE cart_group_id = v_cart_group_id 
        AND coupon_id = p_coupon_id
        AND status NOT IN ('cancelled', 'seller_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
    ) THEN
      UPDATE coupons SET usage_count = usage_count + 1 WHERE id = p_coupon_id;
    END IF;
  END IF;

  IF p_order_id_to_cancel IS NOT NULL THEN
    PERFORM reallocate_cancelled_delivery_fees(p_cart_group_id);
    PERFORM rebalance_active_delivery_fees(p_cart_group_id);
  END IF;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.client_confirm_payment(p_order_id uuid DEFAULT NULL::uuid, p_cart_group_id uuid DEFAULT NULL::uuid, p_razorpay_payment_id text DEFAULT NULL::text, p_razorpay_order_id text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_status text;
  v_payment_status text;
  v_existing_payment_id text;
  v_order_id uuid;
  v_rec record;
BEGIN
  -- 100x FIX: Unauthenticated Payment Spoofing Guard
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Unauthorized: Payment confirmation requires an active session.';
  END IF;
  -- 100x FIX: TOCTOU Double Spend Prevention via Transaction-Level Advisory Lock
  -- This forces all concurrent requests using the exact same payment ID to queue up here.
  IF p_razorpay_payment_id IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(hashtext('pay_' || p_razorpay_payment_id));
    
    IF EXISTS (
      SELECT 1 FROM orders 
      WHERE razorpay_payment_id = p_razorpay_payment_id 
      AND (
        (p_cart_group_id IS NOT NULL AND (cart_group_id IS NULL OR cart_group_id != p_cart_group_id))
        OR 
        (p_cart_group_id IS NULL AND id != p_order_id)
      )
    ) THEN
      RAISE EXCEPTION 'Double spend detected: Payment ID % is already used for another order or group.', p_razorpay_payment_id;
    END IF;
  END IF;

  IF p_cart_group_id IS NOT NULL THEN
    FOR v_rec IN SELECT id, status, payment_status, razorpay_payment_id FROM orders WHERE cart_group_id = p_cart_group_id ORDER BY id FOR UPDATE LOOP
      IF v_rec.status = 'awaiting_payment' THEN
        UPDATE orders
        SET 
          status = 'confirmed',
          payment_status = 'captured',
          razorpay_payment_id = p_razorpay_payment_id,
          razorpay_order_id = p_razorpay_order_id,
          updated_at = NOW()
        WHERE id = v_rec.id;
      ELSE
        -- If it's the exact same payment, just ignore (idempotent)
        IF v_rec.payment_status = 'captured' AND v_rec.razorpay_payment_id = p_razorpay_payment_id THEN
           CONTINUE;
        END IF;
        
        -- State changed during payment
        UPDATE orders
        SET 
          payment_status = 'captured',
          -- 100x STRESS TEST FIX (Phase 7): Prevent Late Webhook Free Food \u0026 Double-Refund Exploits
          refund_status = CASE 
            WHEN v_rec.status IN ('cancelled', 'seller_rejected', 'partner_rejected', 'timeout', 'verification_failed', 'shop_dispute_cancel') 
                 AND COALESCE(refund_status, 'none') NOT IN ('processing', 'completed') 
            THEN 'processing'
            ELSE refund_status
          END,
          razorpay_payment_id = p_razorpay_payment_id,
          razorpay_order_id = p_razorpay_order_id,
          updated_at = NOW()
        WHERE id = v_rec.id;
      END IF;
    END LOOP;
  ELSE
    SELECT status, payment_status, razorpay_payment_id INTO v_status, v_payment_status, v_existing_payment_id FROM orders WHERE id = p_order_id FOR UPDATE;
    IF FOUND THEN
      IF v_status = 'awaiting_payment' THEN
        UPDATE orders
        SET 
          status = 'confirmed',
          payment_status = 'captured',
          razorpay_payment_id = p_razorpay_payment_id,
          razorpay_order_id = p_razorpay_order_id,
          updated_at = NOW()
        WHERE id = p_order_id;
      ELSE
        -- If it's the exact same payment, just ignore (idempotent)
        IF v_payment_status = 'captured' AND v_existing_payment_id = p_razorpay_payment_id THEN
           RETURN;
        END IF;
        
        -- State changed during payment
        UPDATE orders
        SET 
          payment_status = 'captured',
          -- 100x STRESS TEST FIX (Phase 7): Prevent Late Webhook Free Food \u0026 Double-Refund Exploits
          refund_status = CASE 
            WHEN v_status IN ('cancelled', 'seller_rejected', 'partner_rejected', 'timeout', 'verification_failed', 'shop_dispute_cancel') 
                 AND COALESCE(refund_status, 'none') NOT IN ('processing', 'completed') 
            THEN 'processing'
            ELSE refund_status
          END,
          razorpay_payment_id = p_razorpay_payment_id,
          razorpay_order_id = p_razorpay_order_id,
          updated_at = NOW()
        WHERE id = p_order_id;
      END IF;
    END IF;
  END IF;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.claim_order_as_rider(p_order_id uuid, p_rider_id uuid, p_payment_deadline timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_updated int;
  v_seller_accepted boolean;
  v_status text;
BEGIN
  -- 100x FIX: Global Order Hijacking Guard
  IF auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM p_rider_id THEN
    RAISE EXCEPTION 'Unauthorized: You cannot claim orders on behalf of another rider.';
  END IF;
  -- Read current state
  SELECT seller_accepted, status
  INTO v_seller_accepted, v_status
  FROM orders
  WHERE id = p_order_id;

  -- 100x FIX: Allow claiming orphaned orders that have already passed payment (confirmed, preparing, etc)
  -- so that if a rider drops a paid order, a new rider can still pick it up!
  IF v_status NOT IN ('awaiting_acceptance', 'pending', 'confirmed', 'preparing', 'ready_for_pickup') THEN
    RETURN false;
  END IF;

  -- Atomic update: only succeeds if delivery_partner_id IS NULL (no other rider has it)
  UPDATE orders
  SET
    delivery_partner_id = p_rider_id,
    partner_accepted    = true,
    status = CASE
      WHEN v_status = 'awaiting_acceptance' AND v_seller_accepted THEN 'awaiting_payment'
      ELSE status -- Leave it as confirmed, preparing, etc if it was already past payment
    END,
    payment_deadline = CASE
      WHEN v_status = 'awaiting_acceptance' AND v_seller_accepted AND p_payment_deadline IS NOT NULL THEN p_payment_deadline
      ELSE payment_deadline
    END
  WHERE id = p_order_id
    AND delivery_partner_id IS NULL   -- Atomic lock: fails if another rider took it
    AND status = v_status;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated = 1;
END;
$function$
;


