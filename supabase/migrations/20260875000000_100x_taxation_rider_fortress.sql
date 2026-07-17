-- Migration 20260870000000_100x_cascading_fortress.sql
-- Fixes Phase 17: Cascading Logic Failures (Rider Pay, Coupon Locks, PK Spoofing)

DROP FUNCTION IF EXISTS place_orders_transaction(jsonb,jsonb,uuid,uuid,text,uuid);

CREATE OR REPLACE FUNCTION place_orders_transaction(
  p_orders JSONB,
  p_items JSONB,
  p_cart_group_id UUID,
  p_coupon_id UUID,
  p_idempotency_key TEXT,
  p_order_id_to_cancel UUID DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_order_record RECORD;
  v_order JSONB;
  v_item RECORD;
  v_order_totals RECORD;
  v_expected_total_amount NUMERIC := 0;
  v_sum_expected_total_amount NUMERIC := 0;
  v_sum_verified_shop_totals NUMERIC := 0;
  v_expected_grand_total NUMERIC;
  v_db_price NUMERIC;
  v_inserted_ids UUID[] := '{}';
  v_total_qty INT;
  v_cat_comm NUMERIC;
  v_default_comm NUMERIC := 10.0;
  v_category TEXT;
  v_gst_override NUMERIC;
  v_gst_rate NUMERIC;
  v_is_deemed BOOLEAN;
  v_line_gst NUMERIC;
  v_s9_5_gst NUMERIC := 0;
  v_non_food_gst NUMERIC := 0;
  v_tcs_rate NUMERIC;
  v_tcs_amount NUMERIC := 0;
  v_tds_amount NUMERIC := 0;
  v_pure_commission NUMERIC := 0;
  v_server_gst_platform NUMERIC := 0;
  v_server_gst_delivery NUMERIC := 0;
  v_server_enything_commission NUMERIC := 0;
  v_server_seller_payout NUMERIC := 0;
  v_server_rider_earnings NUMERIC := 0;
  v_gw_deduct NUMERIC := 0;
  v_secure_order JSONB;
  v_total_weight_kg NUMERIC := 0;
  
  v_coupon_record RECORD;
  
  v_global_platform_fee NUMERIC;
  v_sum_client_platform_fee NUMERIC := 0;
  v_global_small_cart_fee NUMERIC;
  v_sum_client_small_cart_fee NUMERIC := 0;
  v_global_small_cart_threshold NUMERIC;
  v_sum_client_heavy_order_fee NUMERIC := 0;
  v_sum_client_multi_shop_surcharge NUMERIC := 0;
  v_sum_client_coupon_discount NUMERIC := 0;
  v_sum_client_delivery_charges NUMERIC := 0;
  v_cart_group_id UUID := p_cart_group_id;
  
  v_payment_method TEXT;
  v_old_payment_status TEXT;
  v_refund_amount NUMERIC;
  v_acceptance_deadline TIMESTAMP WITH TIME ZONE;
BEGIN
  -- 100x STRESS TEST FIX: Pixel Overload Guard (Array Bombing)
  IF p_orders IS NULL OR jsonb_array_length(p_orders) = 0 THEN
    RAISE EXCEPTION 'Checkout requires at least one order.';
  END IF;
  IF jsonb_array_length(p_orders) > 10 THEN
    RAISE EXCEPTION 'Pixel Overload Guard: Maximum 10 shops allowed per checkout.';
  END IF;
  
  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Checkout requires at least one item.';
  END IF;
  IF jsonb_array_length(p_items) > 100 THEN
    RAISE EXCEPTION 'Pixel Overload Guard: Maximum 100 items allowed per checkout.';
  END IF;
  IF p_order_id_to_cancel IS NOT NULL THEN
    SELECT payment_method, payment_status INTO v_payment_method, v_old_payment_status 
    FROM orders 
    WHERE id = p_order_id_to_cancel 
      AND customer_id = auth.uid()
      AND status = 'seller_rejected';
      
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Replacement failed: Original order not found or not in rejected state.';
    END IF;
    
    UPDATE orders 
    SET status = 'cancelled', 
        cancellation_reason = 'Replaced by customer with alternative shop',
        refund_status = CASE WHEN v_old_payment_status = 'captured' THEN 'processing' ELSE refund_status END
    WHERE id = p_order_id_to_cancel;

    SELECT COALESCE(SUM(delivery_charges), 0) + COALESCE(SUM(multi_shop_surcharge), 0) + COALESCE(SUM(small_cart_fee), 0) + COALESCE(SUM(heavy_order_fee), 0)
    INTO v_refund_amount
    FROM orders WHERE id = p_order_id_to_cancel;
  END IF;

  BEGIN SELECT value::numeric INTO v_global_platform_fee FROM platform_config WHERE key = 'platform_fee'; EXCEPTION WHEN OTHERS THEN v_global_platform_fee := 5.0; END;
  v_global_platform_fee := COALESCE(v_global_platform_fee, 5.0);
  
  BEGIN SELECT value::numeric INTO v_default_comm FROM platform_config WHERE key = 'default_commission_percent'; EXCEPTION WHEN OTHERS THEN v_default_comm := 10.0; END;
  v_default_comm := COALESCE(v_default_comm, 10.0);

  FOR v_item IN SELECT y.product_id, y.quantity, p.price, y.variant_name, p.variants 
                FROM jsonb_to_recordset(p_items) AS y(product_id uuid, variant_name text, quantity int)
                JOIN products p ON p.id = y.product_id LOOP
    
    -- 100x STRESS TEST FIX (Phase 15): Negative Quantity Exploit Guard
    IF v_item.quantity IS NULL OR v_item.quantity <= 0 THEN
      RAISE EXCEPTION 'CRITICAL: Invalid quantity (%) detected for product %. Negative or zero quantities are strictly prohibited.', v_item.quantity, v_item.product_id;
    END IF;

    IF v_item.variant_name IS NOT NULL THEN
      SELECT (elem->>'price')::numeric INTO v_db_price
      FROM jsonb_array_elements(v_item.variants) elem
      WHERE elem->>'name' = v_item.variant_name;
      IF v_db_price IS NULL THEN RAISE EXCEPTION 'Variant % not found.', v_item.variant_name; END IF;
    ELSE
      v_db_price := v_item.price;
    END IF;

    v_sum_expected_total_amount := v_sum_expected_total_amount + (v_item.quantity * v_db_price);
  END LOOP;

  IF v_sum_expected_total_amount <= 0 THEN
    RAISE EXCEPTION 'Total order amount must be greater than zero. Phantom empty orders are strictly prohibited.';
  END IF;

  FOR v_item IN SELECT y.quantity, p.weight_per_unit 
                FROM jsonb_to_recordset(p_items) AS y(product_id uuid, quantity int)
                JOIN products p ON p.id = y.product_id LOOP
    v_total_weight_kg := v_total_weight_kg + (COALESCE(v_item.weight_per_unit, 0.5) * v_item.quantity);
  END LOOP;

  IF v_total_weight_kg > 20.0 THEN
    RAISE EXCEPTION 'AML Guard: Total order weight exceeds maximum physical limits (20.0 kg).';
  END IF;

  FOR v_order_totals IN SELECT * FROM jsonb_to_recordset(p_orders) AS x(
    id uuid,
    delivery_charges numeric,
    multi_shop_surcharge numeric,
    platform_fee numeric,
    small_cart_fee numeric,
    heavy_order_fee numeric,
    coupon_discount numeric,
    estimated_distance_km numeric
  ) LOOP
    v_sum_client_platform_fee := v_sum_client_platform_fee + COALESCE(v_order_totals.platform_fee, 0);
    v_sum_client_small_cart_fee := v_sum_client_small_cart_fee + COALESCE(v_order_totals.small_cart_fee, 0);
    v_sum_client_heavy_order_fee := v_sum_client_heavy_order_fee + COALESCE(v_order_totals.heavy_order_fee, 0);
    v_sum_client_multi_shop_surcharge := v_sum_client_multi_shop_surcharge + COALESCE(v_order_totals.multi_shop_surcharge, 0);
    v_sum_client_coupon_discount := v_sum_client_coupon_discount + COALESCE(v_order_totals.coupon_discount, 0);
    v_sum_client_delivery_charges := v_sum_client_delivery_charges + COALESCE(v_order_totals.delivery_charges, 0);
    
    IF COALESCE(v_order_totals.estimated_distance_km, 0) > 100.0 THEN
      RAISE EXCEPTION 'Distance spoofing detected (Money Laundering Exploit). The maximum allowed delivery radius is 100km. Claimed: % km', v_order_totals.estimated_distance_km;
    END IF;
    
    -- 100x STRESS TEST FIX: Reverse Deduction Exploit Guard
    IF COALESCE(v_order_totals.delivery_charges, 0) < 0 OR
       COALESCE(v_order_totals.multi_shop_surcharge, 0) < 0 OR
       COALESCE(v_order_totals.platform_fee, 0) < 0 OR
       COALESCE(v_order_totals.small_cart_fee, 0) < 0 OR
       COALESCE(v_order_totals.heavy_order_fee, 0) < 0 OR
       COALESCE(v_order_totals.coupon_discount, 0) < 0 THEN
      RAISE EXCEPTION 'Negative Fee Smuggling Guard: Fees and discounts cannot be negative.';
    END IF;

    -- 100x STRESS TEST FIX: Hyper-Inflation Delivery Spoofing Guard
    IF COALESCE(v_order_totals.delivery_charges, 0) > 2000.0 THEN
      RAISE EXCEPTION 'Delivery charge exceeds maximum allowed physical limit (Rs 2000).';
    END IF;
    IF COALESCE(v_order_totals.multi_shop_surcharge, 0) > 500.0 THEN
      RAISE EXCEPTION 'Multi-shop surcharge exceeds maximum allowed physical limit (Rs 500).';
    END IF;
  END LOOP;

  IF ABS(v_sum_client_platform_fee - v_global_platform_fee) > 1.0 THEN
    RAISE EXCEPTION 'Platform fee spoofing detected. Expected: %, Got: %', v_global_platform_fee, v_sum_client_platform_fee;
  END IF;

  BEGIN SELECT value::numeric INTO v_global_small_cart_fee FROM platform_config WHERE key = 'small_cart_fee'; EXCEPTION WHEN OTHERS THEN v_global_small_cart_fee := 15.0; END;
  v_global_small_cart_fee := COALESCE(v_global_small_cart_fee, 15.0);
  BEGIN SELECT value::numeric INTO v_global_small_cart_threshold FROM platform_config WHERE key = 'small_cart_threshold'; EXCEPTION WHEN OTHERS THEN v_global_small_cart_threshold := 99.0; END;
  v_global_small_cart_threshold := COALESCE(v_global_small_cart_threshold, 99.0);

  IF v_sum_expected_total_amount < v_global_small_cart_threshold THEN
    IF ABS(v_sum_client_small_cart_fee - v_global_small_cart_fee) > 1.0 THEN
      RAISE EXCEPTION 'Small cart fee spoofing detected. Expected: %, Got: %', v_global_small_cart_fee, v_sum_client_small_cart_fee;
    END IF;
  ELSE
    IF v_sum_client_small_cart_fee > 1.0 THEN
      RAISE EXCEPTION 'Small cart fee applied illegally for order above threshold.';
    END IF;
  END IF;

  IF p_coupon_id IS NOT NULL THEN
    IF v_sum_client_coupon_discount <= 0 THEN
      RAISE EXCEPTION 'Coupon ID provided but no discount claimed.';
    END IF;
    
    -- O1 FIX: Global Lockout for Atomic Swap Coupon Trapping
    -- Ensure coupon usage check is done properly here if not an atomic swap
    IF p_order_id_to_cancel IS NULL THEN
      IF EXISTS (
        SELECT 1 FROM orders 
        WHERE cart_group_id = v_cart_group_id 
          AND coupon_id = p_coupon_id
          AND status NOT IN ('cancelled', 'seller_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
      ) THEN
        RAISE EXCEPTION 'This coupon has already been used on this cart group.';
      END IF;
      
      -- 100x STRESS TEST FIX: Coupon Global State Validation (with FOR UPDATE row lock to prevent race conditions)
      SELECT * INTO v_coupon_record FROM coupons WHERE id = p_coupon_id FOR UPDATE;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'Coupon not found in database.';
      END IF;
      
      IF v_coupon_record.is_active = false THEN
        RAISE EXCEPTION 'This coupon is currently inactive.';
      END IF;
      
      IF v_coupon_record.valid_until IS NOT NULL AND v_coupon_record.valid_until < NOW() THEN
        RAISE EXCEPTION 'This coupon has expired.';
      END IF;
      
      IF v_coupon_record.usage_count >= v_coupon_record.usage_limit THEN
        RAISE EXCEPTION 'This coupon has reached its maximum usage limit.';
      END IF;
      
      IF v_sum_expected_total_amount < COALESCE(v_coupon_record.min_order_value, v_coupon_record.min_order_amount, 0) THEN
        RAISE EXCEPTION 'Order amount does not meet the minimum requirement for this coupon.';
      END IF;
      
      IF v_coupon_record.max_discount_cap IS NOT NULL AND v_sum_client_coupon_discount > v_coupon_record.max_discount_cap THEN
        RAISE EXCEPTION 'Claimed discount exceeds the coupons maximum cap.';
      END IF;
    END IF;
  ELSIF v_sum_client_coupon_discount > 0 THEN
    RAISE EXCEPTION 'Coupon discount applied without a valid coupon id.';
  END IF;

  v_acceptance_deadline := (NOW() AT TIME ZONE 'utc') + INTERVAL '3 minutes';
  
  FOR v_order_record IN SELECT * FROM jsonb_array_elements(p_orders) LOOP
    v_order := v_order_record.value;
    
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
      v_cat_comm := COALESCE(v_cat_comm, v_default_comm);
      
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
          IF v_category IN ('Restaurant', 'Fast Food', 'Bakery', 'Sweets & Mithai', 'Tea & Coffee', 'Ice Cream', 'Paan Shop') THEN
            v_is_deemed := true;
            v_gst_rate := 0.05;
          END IF;
        END IF;
      
      v_line_gst := v_item.price * v_item.quantity * v_gst_rate;
      IF v_is_deemed THEN
        v_s9_5_gst := v_s9_5_gst + v_line_gst;
      ELSE
        v_non_food_gst := v_non_food_gst + v_line_gst;
      END IF;
      
      v_tcs_rate := CASE WHEN v_category IN ('Restaurant', 'Fast Food', 'Bakery', 'Sweets & Mithai', 'Tea & Coffee', 'Ice Cream', 'Paan Shop', 'Fruits & Vegs', 'Butcher', 'Fish & Seafood') THEN 0.0 ELSE 0.01 END;
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
      + COALESCE((v_order->>'multi_shop_surcharge')::numeric, 0)
      + COALESCE((v_order->>'small_cart_fee')::numeric, 0)
      + COALESCE((v_order->>'heavy_order_fee')::numeric, 0)
      - COALESCE((v_order->>'coupon_discount')::numeric, 0));

    IF ABS(v_expected_grand_total - COALESCE((v_order->>'grand_total')::numeric, 0)) > 2.0 THEN
      RAISE EXCEPTION 'Grand total mismatch for order %. Expected: %, Got: %', v_order->>'id', v_expected_grand_total, v_order->>'grand_total';
    END IF;

    v_server_gst_platform := COALESCE((v_order->>'platform_fee')::numeric, 0) - (COALESCE((v_order->>'platform_fee')::numeric, 0) / 1.18);
    v_server_gst_delivery := COALESCE((v_order->>'delivery_charges')::numeric, 0) - (COALESCE((v_order->>'delivery_charges')::numeric, 0) / 1.18);

    v_server_enything_commission := v_pure_commission + v_server_gst_platform;
    v_gw_deduct := (v_expected_grand_total * 0.02) * 1.18;
    
    v_server_seller_payout := GREATEST(0, v_expected_total_amount 
                                    + v_non_food_gst 
                                    - v_pure_commission 
                                    - v_tcs_amount 
                                    - v_tds_amount 
                                    - v_gw_deduct);

    v_server_rider_earnings := GREATEST(0, (COALESCE((v_order->>'delivery_charges')::numeric, 0) - v_server_gst_delivery 
                                           - COALESCE((v_order->>'small_cart_fee')::numeric, 0)
                                           + COALESCE((v_order->>'multi_shop_surcharge')::numeric, 0)
                                           + COALESCE((v_order->>'heavy_order_fee')::numeric, 0)) * 0.80);

    v_secure_order := jsonb_build_object(
      'id', COALESCE(v_order->>'id', gen_random_uuid()::text),
      'customer_id', auth.uid(),
      'shop_id', v_order->>'shop_id',
      'payment_method', v_order->>'payment_method',
      'payment_status', CASE WHEN (v_order->>'payment_method') = 'cod' THEN 'pending' ELSE 'awaiting_payment' END,
      'status', CASE WHEN (v_order->>'payment_method') = 'cod' THEN 'pending' ELSE 'awaiting_payment' END,
      'seller_accepted', false,
      'partner_accepted', false,
      'address', v_order->>'address',
      'address_label', v_order->>'address_label',
      'delivery_lat', (v_order->>'delivery_lat')::double precision,
      'delivery_lng', (v_order->>'delivery_lng')::double precision,
      'delivery_notes', v_order->>'delivery_notes',
      'estimated_distance_km', v_order->>'estimated_distance_km',
      'cancelled_reason', v_order->>'cancellation_reason',
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
    IF v_item.order_id = ANY(v_inserted_ids) THEN
      IF v_item.variant_name IS NULL THEN
        SELECT price INTO v_db_price FROM products WHERE id = v_item.product_id;
      ELSE
        SELECT (elem->>'price')::numeric INTO v_db_price
        FROM products, jsonb_array_elements(variants) elem
        WHERE id = v_item.product_id AND elem->>'name' = v_item.variant_name;
      END IF;

      INSERT INTO order_items (
        id, order_id, product_id, variant_name, price, quantity, special_instructions
      ) VALUES (
        COALESCE(v_item.id, gen_random_uuid()),
        v_item.order_id,
        v_item.product_id,
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

  -- 100x ARCHITECTURE STRESS-TEST FIX: Atomic Swap Rebalance
  IF p_order_id_to_cancel IS NOT NULL THEN
    PERFORM reallocate_cancelled_delivery_fees(p_cart_group_id);
    PERFORM rebalance_active_delivery_fees(p_cart_group_id);
  END IF;
END;
$$;
-- =============================================================================
-- rebalance_active_delivery_fees
-- Phase 21: Correct inclusive GST extraction and Rider Earnings math
-- =============================================================================
CREATE OR REPLACE FUNCTION public.rebalance_active_delivery_fees(p_cart_group_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $$
DECLARE
  v_active_count INT;
  v_total_delivery NUMERIC;
  v_total_surcharge NUMERIC;
  v_total_small NUMERIC;
  v_total_heavy NUMERIC;
  
  v_split_delivery NUMERIC;
  v_split_surcharge NUMERIC;
  v_split_small NUMERIC;
  v_split_heavy NUMERIC;
  v_new_gst_delivery NUMERIC;
  
  rec RECORD;
BEGIN
  -- 1. Get active count
  SELECT COUNT(id) INTO v_active_count
  FROM orders
  WHERE cart_group_id = p_cart_group_id
    AND status IN ('awaiting_acceptance', 'awaiting_payment', 'pending_pickup', 'accepted', 'preparing', 'ready_for_pickup');
    
  IF v_active_count = 0 THEN RETURN; END IF;
  
  -- 2. Sum up all fees across ALL active orders
  SELECT 
    COALESCE(SUM(delivery_charges), 0),
    COALESCE(SUM(multi_shop_surcharge), 0),
    COALESCE(SUM(small_cart_fee), 0),
    COALESCE(SUM(heavy_order_fee), 0)
  INTO v_total_delivery, v_total_surcharge, v_total_small, v_total_heavy
  FROM orders
  WHERE cart_group_id = p_cart_group_id
    AND status IN ('awaiting_acceptance', 'awaiting_payment', 'pending_pickup', 'accepted', 'preparing', 'ready_for_pickup');
    
  v_split_delivery := v_total_delivery / v_active_count;
  v_split_surcharge := v_total_surcharge / v_active_count;
  v_split_small := v_total_small / v_active_count;
  v_split_heavy := v_total_heavy / v_active_count;
  
  -- 100x STRESS TEST FIX (Phase 21): GST is inclusive, not additive.
  v_new_gst_delivery := v_split_delivery - (v_split_delivery / 1.18);
  
  -- 3. Update all active orders with the equal split
  FOR rec IN 
    SELECT id, total_amount, gst_item_total, platform_fee, gst_platform, COALESCE(coupon_discount, 0) as coupon_discount, payment_status
    FROM orders
    WHERE cart_group_id = p_cart_group_id
      AND status IN ('awaiting_acceptance', 'awaiting_payment', 'pending_pickup', 'accepted', 'preparing', 'ready_for_pickup')
  LOOP
    UPDATE orders
    SET delivery_charges = v_split_delivery,
        multi_shop_surcharge = v_split_surcharge,
        small_cart_fee = v_split_small,
        heavy_order_fee = v_split_heavy,
        -- 100x STRESS TEST FIX (Phase 21): Fix rider earnings to include surcharges and exact GST logic
        rider_earnings = GREATEST(0, (v_split_delivery - v_new_gst_delivery - v_split_small + v_split_surcharge + v_split_heavy) * 0.80),
        gst_delivery = v_new_gst_delivery,
        grand_total = GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform + v_split_delivery + v_split_surcharge + v_split_small + v_split_heavy - rec.coupon_discount),
        grand_total_collected = CASE WHEN rec.payment_status = 'captured' THEN GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform + v_split_delivery + v_split_surcharge + v_split_small + v_split_heavy - rec.coupon_discount) ELSE 0 END
    WHERE id = rec.id;
  END LOOP;
END;
$$;

-- =============================================================================
-- reallocate_cancelled_delivery_fees
-- Phase 21: Correct inclusive GST extraction, Rider Earnings math, and Zero Active case
-- =============================================================================
CREATE OR REPLACE FUNCTION public.reallocate_cancelled_delivery_fees(p_cart_group_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $$
DECLARE
  v_active_count INT;
  v_missing_delivery NUMERIC;
  v_missing_surcharge NUMERIC;
  v_missing_small NUMERIC;
  v_missing_heavy NUMERIC;
  v_missing_coupon NUMERIC := 0;
  v_split_delivery NUMERIC;
  v_split_surcharge NUMERIC;
  v_split_small NUMERIC;
  v_split_heavy NUMERIC;
  v_split_coupon NUMERIC;
  v_net_delivery NUMERIC;
  v_new_gst_delivery NUMERIC;
  v_trapped_coupon NUMERIC;
  rec RECORD;
BEGIN
    -- 100x STRESS TEST FIX (Phase 8): Deterministic Bulk Locking (Deadlock & N+1 Prevention)
    PERFORM id FROM orders 
    WHERE cart_group_id = p_cart_group_id 
    ORDER BY id FOR UPDATE;

    SELECT COUNT(id) INTO v_active_count 
    FROM orders 
    WHERE cart_group_id = p_cart_group_id 
      AND status IN ('awaiting_acceptance', 'awaiting_payment', 'pending_pickup', 'accepted', 'preparing', 'ready_for_pickup');

    -- Aggregate missing fees
    SELECT 
        COALESCE(SUM(delivery_charges), 0),
        COALESCE(SUM(multi_shop_surcharge), 0),
        COALESCE(SUM(small_cart_fee), 0),
        COALESCE(SUM(heavy_order_fee), 0)
    INTO 
        v_missing_delivery, v_missing_surcharge, v_missing_small, v_missing_heavy
    FROM orders 
    WHERE cart_group_id = p_cart_group_id 
      AND status IN ('cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel')
      AND delivery_charges > 0
      AND COALESCE(rider_earnings, 0) = 0;

    -- Calculate TRAPPED COUPON
    FOR rec IN 
        SELECT id, total_amount, gst_item_total, platform_fee, gst_platform, coupon_discount
        FROM orders 
        WHERE cart_group_id = p_cart_group_id 
          AND status IN ('cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel') 
          AND delivery_charges > 0
          AND COALESCE(rider_earnings, 0) = 0
        ORDER BY id
    LOOP
        v_trapped_coupon := COALESCE(rec.coupon_discount, 0) - (rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform);
        IF v_trapped_coupon > 0 THEN
            v_missing_coupon := v_missing_coupon + v_trapped_coupon;
            
            UPDATE orders 
            SET coupon_discount = (rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform)
            WHERE id = rec.id;
        END IF;
    END LOOP;

    -- 100x STRESS TEST FIX (Phase 21): Even if no active orders remain, 
    -- we MUST zero out the delivery charges on the cancelled orders so they don't artificially inflate platform revenue metrics.
    IF v_missing_delivery > 0 THEN
        -- Zero out the cancelled ones FIRST
        FOR rec IN 
            SELECT id, total_amount, gst_item_total, platform_fee, gst_platform, coupon_discount, payment_status
            FROM orders 
            WHERE cart_group_id = p_cart_group_id 
              AND status IN ('cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel') 
              AND delivery_charges > 0
              AND COALESCE(rider_earnings, 0) = 0
            ORDER BY id
        LOOP
            UPDATE orders
            SET delivery_charges = 0,
                multi_shop_surcharge = 0,
                small_cart_fee = 0,
                heavy_order_fee = 0,
                gst_delivery = 0,
                grand_total = GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform - COALESCE(coupon_discount, 0)),
                grand_total_collected = CASE 
                    WHEN rec.payment_status = 'captured' THEN GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform - COALESCE(coupon_discount, 0)) 
                    ELSE 0 
                END
            WHERE id = rec.id;
        END LOOP;
    END IF;

    IF v_active_count = 0 OR v_missing_delivery = 0 THEN
        RETURN FALSE;
    END IF;

    v_split_delivery := v_missing_delivery / v_active_count;
    v_split_surcharge := v_missing_surcharge / v_active_count;
    v_split_small := v_missing_small / v_active_count;
    v_split_heavy := v_missing_heavy / v_active_count;
    v_split_coupon := v_missing_coupon / v_active_count;

    -- Add to active orders
    FOR rec IN 
        SELECT id, delivery_charges, multi_shop_surcharge, small_cart_fee, heavy_order_fee,
               total_amount, gst_item_total, platform_fee, gst_platform, payment_status,
               COALESCE(coupon_discount, 0) AS coupon_discount
        FROM orders 
        WHERE cart_group_id = p_cart_group_id 
          AND status IN ('awaiting_acceptance', 'awaiting_payment', 'pending_pickup', 'accepted', 'preparing', 'ready_for_pickup')
        ORDER BY id
    LOOP
        v_net_delivery := (rec.delivery_charges + v_split_delivery) 
                        + (rec.multi_shop_surcharge + v_split_surcharge)
                        + (rec.small_cart_fee + v_split_small)
                        + (rec.heavy_order_fee + v_split_heavy);
                        
        -- 100x STRESS TEST FIX (Phase 21): Mathematically pure GST extraction
        v_new_gst_delivery := (rec.delivery_charges + v_split_delivery) - ((rec.delivery_charges + v_split_delivery) / 1.18);
        
        UPDATE orders
        SET delivery_charges = rec.delivery_charges + v_split_delivery,
            -- 100x STRESS TEST FIX (Phase 21): Add surcharges to Rider Earnings
            rider_earnings = GREATEST(0, ((rec.delivery_charges + v_split_delivery) - v_new_gst_delivery - (rec.small_cart_fee + v_split_small) + (rec.multi_shop_surcharge + v_split_surcharge) + (rec.heavy_order_fee + v_split_heavy)) * 0.80),
            multi_shop_surcharge = rec.multi_shop_surcharge + v_split_surcharge,
            small_cart_fee = rec.small_cart_fee + v_split_small,
            heavy_order_fee = rec.heavy_order_fee + v_split_heavy,
            coupon_discount = rec.coupon_discount + v_split_coupon,
            gst_delivery = v_new_gst_delivery,
            grand_total = GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform + v_net_delivery - (rec.coupon_discount + v_split_coupon)),
            grand_total_collected = CASE 
                WHEN rec.payment_status = 'captured' THEN GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform + v_net_delivery - (rec.coupon_discount + v_split_coupon)) 
                ELSE 0 
            END
        WHERE id = rec.id;
    END LOOP;

    RETURN TRUE;
END;
$$;

-- =============================================================================
-- cancel_order
-- Phase 21: Added explicit trigger to reallocate fees for customer cancellations
-- =============================================================================
CREATE OR REPLACE FUNCTION public.cancel_order(p_order_id uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
  v_customer_id uuid;
  v_cart_group_id uuid;
  v_rec record;
  v_is_customer boolean;
BEGIN
  -- First find group ID without locking to avoid partial lock deadlocks
  SELECT customer_id, cart_group_id INTO v_customer_id, v_cart_group_id
  FROM orders WHERE id = p_order_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  v_is_customer := (auth.uid() = v_customer_id);

  -- 100x FIX: Prevent Global DoS Cancellation Exploit
  IF NOT v_is_customer AND NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: Only the customer or an admin can cancel this order.';
  END IF;

  IF v_cart_group_id IS NOT NULL THEN
    -- Lock all orders in group consistently ordered by ID
    FOR v_rec IN SELECT id, status, payment_status, refund_status FROM orders WHERE cart_group_id = v_cart_group_id ORDER BY id FOR UPDATE LOOP
      -- 100x FIX: Allow terminal states to exist in the cart group without blocking cancellation
      IF v_is_customer AND v_rec.status NOT IN (
        'awaiting_acceptance', 'awaiting_payment', 'pending',
        'cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel', 'rider_rejected'
      ) THEN
        RAISE EXCEPTION 'Order cannot be cancelled at this stage by customer';
      END IF;
      
      IF v_rec.status IN ('awaiting_acceptance', 'awaiting_payment', 'pending', 'seller_rejected', 'rider_rejected') THEN
        UPDATE orders
        SET 
          status = 'cancelled',
          cancelled_reason = p_reason,
          -- 100x STRESS TEST FIX (Phase 11): Prevent Customer-Triggered Double Refunds
          refund_status = CASE 
                            WHEN v_rec.payment_status = 'captured' AND COALESCE(v_rec.refund_status, 'none') NOT IN ('processing', 'completed') THEN 'processing' 
                            ELSE v_rec.refund_status 
                          END,
          updated_at = NOW()
        WHERE id = v_rec.id;
      END IF;
    END LOOP;
    
    -- 100x STRESS TEST FIX (Phase 21): Trigger Reallocation for Customer Cancellations!
    PERFORM reallocate_cancelled_delivery_fees(v_cart_group_id);
    
  ELSE
    -- Single order lock
    FOR v_rec IN SELECT id, status, payment_status, refund_status FROM orders WHERE id = p_order_id FOR UPDATE LOOP
      IF v_is_customer AND v_rec.status NOT IN (
        'awaiting_acceptance', 'awaiting_payment', 'pending',
        'cancelled', 'seller_rejected', 'timeout', 'payment_failed', 'shop_dispute_cancel', 'rider_rejected'
      ) THEN
        RAISE EXCEPTION 'Order cannot be cancelled at this stage by customer';
      END IF;

      IF v_rec.status IN ('awaiting_acceptance', 'awaiting_payment', 'pending', 'seller_rejected', 'rider_rejected') THEN
        UPDATE orders
        SET 
          status = 'cancelled',
          cancelled_reason = p_reason,
          -- 100x STRESS TEST FIX (Phase 11): Prevent Customer-Triggered Double Refunds
          refund_status = CASE 
                            WHEN v_rec.payment_status = 'captured' AND COALESCE(v_rec.refund_status, 'none') NOT IN ('processing', 'completed') THEN 'processing' 
                            ELSE v_rec.refund_status 
                          END,
          updated_at = NOW()
        WHERE id = v_rec.id;
      END IF;
    END LOOP;
  END IF;
END;
$$;
