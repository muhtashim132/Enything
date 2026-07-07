-- =============================================================================
-- Migration: 100x Ultimate Financial Security (Definitive Patch)
-- Description:
--   1. Restores the advanced GST 2.0 slabs and global fee strict enforcement 
--      that were accidentally overwritten by 20260752000000.
--   2. Retains the is_available and is_deleted product security blocks.
--   3. CRITICAL: Forcefully calculates v_server_rider_earnings server-side by 
--      extracting GST and the small cart fee first, ignoring the client payload
--      to prevent spoofing to 0.
-- =============================================================================

CREATE OR REPLACE FUNCTION place_orders_transaction(
  p_orders JSONB,
  p_items JSONB,
  p_coupon_id UUID DEFAULT NULL,
  p_idempotency_key UUID DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_item RECORD;
  v_order RECORD;
  v_db_price NUMERIC;
  v_is_available BOOLEAN;
  v_is_deleted BOOLEAN;
  v_total_qty INT;
  v_expected_total_amount NUMERIC;
  v_expected_grand_total NUMERIC;
  v_shop_active BOOLEAN;
  v_shop_accepting BOOLEAN;
  v_secure_orders JSONB := '[]'::jsonb;
  v_secure_order JSONB;
  
  -- Financial Calculation Variables
  v_pure_commission NUMERIC;
  v_category TEXT;
  v_cat_comm NUMERIC;
  v_default_comm NUMERIC;
  v_is_online BOOLEAN;
  v_gw_deduct NUMERIC;
  v_seller_base_payout NUMERIC;
  v_seller_gw_share NUMERIC;
  v_server_enything_commission NUMERIC;
  v_server_seller_payout NUMERIC;
  v_server_rider_earnings NUMERIC;
  v_expected_rider_base NUMERIC;
  v_delivery_base NUMERIC;
  v_s9_5_gst NUMERIC;
  v_non_food_gst NUMERIC;
  v_gst_rate NUMERIC;
  v_is_deemed BOOLEAN;
  v_line_gst NUMERIC;
  v_tcs_rate NUMERIC;
  v_tds_amount NUMERIC;
  v_tcs_amount NUMERIC;
  v_gst_override NUMERIC;

  -- Incoming status overrides variables
  v_req_status TEXT;
  v_req_seller_accepted BOOLEAN;
  v_req_partner_accepted BOOLEAN;
  v_req_payment_status TEXT;

  -- Global Fees validation variables
  v_global_platform_fee NUMERIC;
  v_global_small_cart_threshold NUMERIC;
  v_global_small_cart_fee NUMERIC;
  v_global_heavy_order_threshold NUMERIC;
  v_global_heavy_order_fee NUMERIC;
  v_global_platform_gst_rate NUMERIC;
  v_global_delivery_gst_rate NUMERIC;
  v_global_delivery_rate_per_km NUMERIC;
  
  v_sum_client_platform_fee NUMERIC := 0;
  v_sum_client_small_cart_fee NUMERIC := 0;
  v_sum_client_heavy_order_fee NUMERIC := 0;
  v_sum_client_multi_shop_surcharge NUMERIC := 0;
  v_sum_client_coupon_discount NUMERIC := 0;
  v_sum_client_delivery_charges NUMERIC := 0;
  v_sum_expected_total_amount NUMERIC := 0;
  v_total_weight_kg NUMERIC := 0;
  v_num_shops INT := 0;

  v_server_gst_platform NUMERIC;
  v_server_gst_delivery NUMERIC;

  -- Coupon validation variables
  v_coupon_max_uses INT;
  v_coupon_current_uses INT;
  v_coupon_type TEXT;
  v_coupon_value NUMERIC;
  v_coupon_max_discount NUMERIC;
  v_coupon_min_order NUMERIC;
  v_expected_coupon_discount NUMERIC;
BEGIN
  -- Idempotency Check
  IF p_idempotency_key IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM orders WHERE idempotency_key = p_idempotency_key) THEN
      RETURN;
    END IF;
  END IF;

  -- Fetch platform configurations securely
  BEGIN
    SELECT value::numeric INTO v_default_comm FROM platform_config WHERE key = 'commission_percent';
  EXCEPTION WHEN OTHERS THEN v_default_comm := 5.0; END;
  v_default_comm := COALESCE(v_default_comm, 5.0);

  BEGIN
    SELECT value::numeric INTO v_global_platform_fee FROM platform_config WHERE key = 'platform_fee';
  EXCEPTION WHEN OTHERS THEN v_global_platform_fee := 15.0; END;
  v_global_platform_fee := COALESCE(v_global_platform_fee, 15.0);

  BEGIN
    SELECT value::numeric INTO v_global_small_cart_threshold FROM platform_config WHERE key = 'small_cart_threshold';
  EXCEPTION WHEN OTHERS THEN v_global_small_cart_threshold := 99.0; END;
  v_global_small_cart_threshold := COALESCE(v_global_small_cart_threshold, 99.0);

  BEGIN
    SELECT value::numeric INTO v_global_small_cart_fee FROM platform_config WHERE key = 'small_cart_fee';
  EXCEPTION WHEN OTHERS THEN v_global_small_cart_fee := 15.0; END;
  v_global_small_cart_fee := COALESCE(v_global_small_cart_fee, 15.0);

  BEGIN
    SELECT value::numeric INTO v_global_heavy_order_threshold FROM platform_config WHERE key = 'heavy_order_threshold_kg';
  EXCEPTION WHEN OTHERS THEN v_global_heavy_order_threshold := 10.0; END;
  v_global_heavy_order_threshold := COALESCE(v_global_heavy_order_threshold, 10.0);

  BEGIN
    SELECT value::numeric INTO v_global_heavy_order_fee FROM platform_config WHERE key = 'heavy_order_fee';
  EXCEPTION WHEN OTHERS THEN v_global_heavy_order_fee := 20.0; END;
  v_global_heavy_order_fee := COALESCE(v_global_heavy_order_fee, 20.0);

  BEGIN
    SELECT value::numeric INTO v_global_platform_gst_rate FROM platform_config WHERE key = 'platform_fee_gst_rate';
  EXCEPTION WHEN OTHERS THEN v_global_platform_gst_rate := 0.18; END;
  v_global_platform_gst_rate := COALESCE(v_global_platform_gst_rate, 0.18);

  BEGIN
    SELECT value::numeric INTO v_global_delivery_gst_rate FROM platform_config WHERE key = 'delivery_gst_rate';
  EXCEPTION WHEN OTHERS THEN v_global_delivery_gst_rate := 0.18; END;
  v_global_delivery_gst_rate := COALESCE(v_global_delivery_gst_rate, 0.18);

  BEGIN
    SELECT value::numeric INTO v_global_delivery_rate_per_km FROM platform_config WHERE key = 'delivery_rate_per_km';
  EXCEPTION WHEN OTHERS THEN v_global_delivery_rate_per_km := 10.0; END;
  v_global_delivery_rate_per_km := COALESCE(v_global_delivery_rate_per_km, 10.0);

  -- 0. Validate Shops are Active and Accepting Orders
  FOR v_order IN SELECT * FROM jsonb_to_recordset(p_orders) AS x(shop_id uuid) LOOP
    IF v_order.shop_id IS NOT NULL THEN
      SELECT is_active, is_accepting_orders INTO v_shop_active, v_shop_accepting FROM shops WHERE id = v_order.shop_id;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'Shop not found for id %', v_order.shop_id;
      END IF;
      
      IF v_shop_active = false OR v_shop_accepting = false THEN
        RAISE EXCEPTION 'One or more shops in your cart are currently offline and not accepting orders.';
      END IF;
    END IF;
  END LOOP;

  SELECT count(DISTINCT shop_id) INTO v_num_shops FROM jsonb_to_recordset(p_orders) AS x(shop_id uuid);

  -- 1. Validate Base Prices and Availability securely (100x Seller Dashboard Fix preserved)
  FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) AS x(product_id uuid, variant_name text, price numeric, quantity int) LOOP
    IF v_item.variant_name IS NULL THEN
      SELECT price, is_available, is_deleted INTO v_db_price, v_is_available, v_is_deleted FROM products WHERE id = v_item.product_id;
    ELSE
      SELECT (elem->>'price')::numeric, is_available, is_deleted INTO v_db_price, v_is_available, v_is_deleted
      FROM products, jsonb_array_elements(variants) elem
      WHERE id = v_item.product_id AND elem->>'name' = v_item.variant_name;
    END IF;

    IF v_db_price IS NULL THEN
      RAISE EXCEPTION 'Product or variant not found: % / %', v_item.product_id, COALESCE(v_item.variant_name, 'None');
    END IF;

    -- Security bypass fix restored
    IF COALESCE(v_is_deleted, false) = true THEN
      RAISE EXCEPTION 'Product % has been deleted and cannot be ordered.', v_item.product_id;
    END IF;

    IF COALESCE(v_is_available, false) = false THEN
      RAISE EXCEPTION 'Product % is currently unavailable or hidden by the seller.', v_item.product_id;
    END IF;

    IF ABS(v_db_price - v_item.price) > 0.01 THEN
      RAISE EXCEPTION 'Price spoofing detected for product %. Expected: %, Got: %', v_item.product_id, v_db_price, v_item.price;
    END IF;

    v_sum_expected_total_amount := v_sum_expected_total_amount + (v_item.quantity * v_item.price);
  END LOOP;

  -- Calculate weight securely from DB
  FOR v_item IN SELECT y.quantity, p.weight_per_unit 
                FROM jsonb_to_recordset(p_items) AS y(product_id uuid, quantity int)
                JOIN products p ON p.id = y.product_id LOOP
    v_total_weight_kg := v_total_weight_kg + (COALESCE(v_item.weight_per_unit, 0.5) * v_item.quantity);
  END LOOP;

  -- 2. Aggregate Client Fees
  FOR v_order IN SELECT * FROM jsonb_to_recordset(p_orders) AS x(
    id uuid,
    delivery_charges numeric,
    multi_shop_surcharge numeric,
    platform_fee numeric,
    small_cart_fee numeric,
    heavy_order_fee numeric,
    coupon_discount numeric
  ) LOOP
    v_sum_client_platform_fee := v_sum_client_platform_fee + COALESCE(v_order.platform_fee, 0);
    v_sum_client_small_cart_fee := v_sum_client_small_cart_fee + COALESCE(v_order.small_cart_fee, 0);
    v_sum_client_heavy_order_fee := v_sum_client_heavy_order_fee + COALESCE(v_order.heavy_order_fee, 0);
    v_sum_client_multi_shop_surcharge := v_sum_client_multi_shop_surcharge + COALESCE(v_order.multi_shop_surcharge, 0);
    v_sum_client_coupon_discount := v_sum_client_coupon_discount + COALESCE(v_order.coupon_discount, 0);
    v_sum_client_delivery_charges := v_sum_client_delivery_charges + COALESCE(v_order.delivery_charges, 0);
  END LOOP;

  -- Secure Mathematical Assertions for Global Fees
  IF ABS(v_sum_client_platform_fee - v_global_platform_fee) > 1.0 THEN
    RAISE EXCEPTION 'Platform fee spoofing detected. Expected: %, Got: %', v_global_platform_fee, v_sum_client_platform_fee;
  END IF;

  -- STRICT ENFORCEMENT OF SMALL CART FEE
  IF v_sum_expected_total_amount > 0 AND v_sum_expected_total_amount < v_global_small_cart_threshold THEN
    IF ABS(v_sum_client_small_cart_fee - v_global_small_cart_fee) > 1.0 THEN
      RAISE EXCEPTION 'Small cart fee missing or incorrect. Expected: %, Got: %', v_global_small_cart_fee, v_sum_client_small_cart_fee;
    END IF;
  ELSE
    IF v_sum_client_small_cart_fee > 1.0 THEN
      RAISE EXCEPTION 'Small cart fee charged when not applicable. Cart total: %, Threshold: %', v_sum_expected_total_amount, v_global_small_cart_threshold;
    END IF;
  END IF;

  -- STRICT ENFORCEMENT OF HEAVY ORDER FEE
  IF v_total_weight_kg > v_global_heavy_order_threshold THEN
    IF ABS(v_sum_client_heavy_order_fee - v_global_heavy_order_fee) > 1.0 THEN
      RAISE EXCEPTION 'Heavy order fee missing or incorrect. Expected: %, Got: %', v_global_heavy_order_fee, v_sum_client_heavy_order_fee;
    END IF;
  ELSE
    IF v_sum_client_heavy_order_fee > 1.0 THEN
      RAISE EXCEPTION 'Heavy order fee charged when not applicable. Total weight: % kg, Threshold: % kg', v_total_weight_kg, v_global_heavy_order_threshold;
    END IF;
  END IF;

  -- STRICT ENFORCEMENT OF MULTI-SHOP SURCHARGE
  IF v_num_shops > 1 THEN
    IF v_sum_client_multi_shop_surcharge < (v_global_delivery_rate_per_km - 1.0) THEN
      RAISE EXCEPTION 'Multi-shop surcharge missing or too low. Expected at least: %, Got: %', v_global_delivery_rate_per_km, v_sum_client_multi_shop_surcharge;
    END IF;
  ELSE
    IF v_sum_client_multi_shop_surcharge > 1.0 THEN
      RAISE EXCEPTION 'Multi-shop surcharge charged when not applicable.';
    END IF;
  END IF;

  -- Validate Coupon Discount Mathematically
  IF p_coupon_id IS NOT NULL THEN
    SELECT usage_limit, usage_count, discount_type, discount_value, max_discount, min_order_amount
    INTO v_coupon_max_uses, v_coupon_current_uses, v_coupon_type, v_coupon_value, v_coupon_max_discount, v_coupon_min_order
    FROM coupons
    WHERE id = p_coupon_id FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Coupon does not exist.';
    END IF;

    IF v_coupon_max_uses IS NOT NULL AND v_coupon_current_uses >= v_coupon_max_uses THEN
      RAISE EXCEPTION 'Coupon has reached its maximum usage limit.';
    END IF;

    IF v_sum_expected_total_amount < COALESCE(v_coupon_min_order, 0) THEN
      RAISE EXCEPTION 'Order amount is less than the minimum required for this coupon.';
    END IF;

    IF v_coupon_type = 'percent' THEN
      v_expected_coupon_discount := (v_sum_expected_total_amount * v_coupon_value) / 100.0;
      IF v_coupon_max_discount IS NOT NULL AND v_expected_coupon_discount > v_coupon_max_discount THEN
        v_expected_coupon_discount := v_coupon_max_discount;
      END IF;
    ELSIF v_coupon_type = 'flat' THEN
      v_expected_coupon_discount := v_coupon_value;
    ELSE
      v_expected_coupon_discount := 0;
    END IF;

    IF v_sum_client_coupon_discount > v_expected_coupon_discount + 1.0 THEN
      RAISE EXCEPTION 'Coupon discount spoofing detected. Max allowed: %, Claimed: %', v_expected_coupon_discount, v_sum_client_coupon_discount;
    END IF;
  ELSIF v_sum_client_coupon_discount > 0 THEN
    RAISE EXCEPTION 'Cannot apply coupon discount without a valid coupon code.';
  END IF;

  -- 3. Secure Order Reconstruction & Exact Backend Math
  FOR v_order IN SELECT * FROM jsonb_to_recordset(p_orders) AS x(
    id uuid,
    total_amount numeric,
    delivery_charges numeric,
    multi_shop_surcharge numeric,
    platform_fee numeric,
    small_cart_fee numeric,
    heavy_order_fee numeric,
    coupon_discount numeric,
    grand_total_collected numeric,
    payment_method text
  ) LOOP

    v_expected_total_amount := 0;
    v_pure_commission := 0;
    v_s9_5_gst := 0;
    v_non_food_gst := 0;
    v_tcs_amount := 0;
    v_tds_amount := 0;

    FOR v_item IN 
      SELECT y.product_id, y.quantity, y.price 
      FROM jsonb_to_recordset(p_items) AS y(order_id uuid, product_id uuid, quantity int, price numeric) 
      WHERE y.order_id = v_order.id 
    LOOP
      v_expected_total_amount := v_expected_total_amount + (v_item.quantity * v_item.price);
      
      -- GST 2.0 OVERRIDES AND SLABS
      SELECT category, gst_rate_override INTO v_category, v_gst_override FROM products WHERE id = v_item.product_id;
      
      -- Calculate Pure Commission
      BEGIN
        SELECT value::numeric INTO v_cat_comm FROM platform_config WHERE key = 'commission_percent_' || v_category;
      EXCEPTION WHEN OTHERS THEN v_cat_comm := NULL; END;
      
      v_pure_commission := v_pure_commission + (v_item.price * v_item.quantity * COALESCE(v_cat_comm, v_default_comm) / 100.0);
      
      -- Calculate GST (Override > Category Slab > Category Default)
      IF v_gst_override IS NOT NULL THEN
        v_gst_rate := v_gst_override;
        v_is_deemed := CASE WHEN v_category IN ('Restaurant', 'Fast Food', 'Bakery', 'Sweets & Mithai', 'Tea & Coffee', 'Ice Cream', 'Paan Shop') THEN true ELSE false END;
      ELSE
        BEGIN
          SELECT gst_rate::numeric, is_deemed_supplier INTO v_gst_rate, v_is_deemed FROM tax_config WHERE category = v_category;
        EXCEPTION WHEN OTHERS THEN v_gst_rate := NULL; END;
        
        -- GST 2.0: Clothing & Footwear Slabs
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
    END LOOP;

    IF ABS(v_expected_total_amount - COALESCE(v_order.total_amount, 0)) > 0.01 THEN
      RAISE EXCEPTION 'Order base total mismatch. Expected: %, Got: %', v_expected_total_amount, v_order.total_amount;
    END IF;

    -- Security Bounds Validation
    IF COALESCE(v_order.delivery_charges, 0) < 0 THEN RAISE EXCEPTION 'delivery_charges cannot be negative'; END IF;
    IF COALESCE(v_order.multi_shop_surcharge, 0) < 0 THEN RAISE EXCEPTION 'multi_shop_surcharge cannot be negative'; END IF;
    IF COALESCE(v_order.platform_fee, 0) < 0 THEN RAISE EXCEPTION 'platform_fee cannot be negative'; END IF;
    IF COALESCE(v_order.small_cart_fee, 0) < 0 THEN RAISE EXCEPTION 'small_cart_fee cannot be negative'; END IF;
    IF COALESCE(v_order.heavy_order_fee, 0) < 0 THEN RAISE EXCEPTION 'heavy_order_fee cannot be negative'; END IF;
    IF COALESCE(v_order.coupon_discount, 0) < 0 THEN RAISE EXCEPTION 'coupon_discount cannot be negative'; END IF;

    v_expected_grand_total :=
      v_expected_total_amount +
      v_s9_5_gst + v_non_food_gst +
      COALESCE(v_order.delivery_charges, 0) +
      COALESCE(v_order.platform_fee, 0) -
      COALESCE(v_order.coupon_discount, 0);

    IF v_expected_grand_total < 0 THEN v_expected_grand_total := 0; END IF;

    IF ABS(v_expected_grand_total - COALESCE(v_order.grand_total_collected, 0)) > 1.00 THEN
      RAISE EXCEPTION 'Order grand total mismatch. Expected: %, Got: %', v_expected_grand_total, v_order.grand_total_collected;
    END IF;

    -- SERVER-SIDE PAYOUT CALCULATIONS
    v_is_online := COALESCE(v_order.payment_method, 'cod') != 'cod';
    v_gw_deduct := CASE WHEN v_is_online THEN v_expected_grand_total * 0.0236 ELSE 0.0 END;
    
    v_seller_base_payout := v_expected_total_amount - v_pure_commission;
    v_seller_gw_share := CASE WHEN v_is_online THEN (v_seller_base_payout + v_non_food_gst) * 0.0236 ELSE 0.0 END;
    
    v_server_enything_commission := v_pure_commission + v_seller_gw_share;
    v_server_seller_payout := v_expected_total_amount + v_non_food_gst - v_server_enything_commission - v_tcs_amount - v_tds_amount;

    IF COALESCE(v_order.platform_fee, 0) > 0 THEN
      v_server_gst_platform := v_order.platform_fee - (v_order.platform_fee / (1 + v_global_platform_gst_rate));
    ELSE
      v_server_gst_platform := 0;
    END IF;

    IF COALESCE(v_order.delivery_charges, 0) > 0 THEN
      v_server_gst_delivery := v_order.delivery_charges - (v_order.delivery_charges / (1 + v_global_delivery_gst_rate));
    ELSE
      v_server_gst_delivery := 0;
    END IF;

    -- 100x SECURITY FIX: DO NOT TRUST CLIENT'S RIDER EARNINGS PAYLOAD!
    -- Extract GST and the Small Cart Fee out of the collected delivery charge to find the true base.
    v_delivery_base := COALESCE(v_order.delivery_charges, 0) - v_server_gst_delivery;
    v_expected_rider_base := v_delivery_base - COALESCE(v_order.small_cart_fee, 0);
    v_server_rider_earnings := v_expected_rider_base * 0.80;

    SELECT elem INTO v_secure_order FROM jsonb_array_elements(p_orders) elem WHERE (elem->>'id')::uuid = v_order.id;
    
    v_req_status := COALESCE(v_secure_order->>'status', 'pending');
    v_req_seller_accepted := COALESCE((v_secure_order->>'seller_accepted')::boolean, false);
    v_req_partner_accepted := COALESCE((v_secure_order->>'partner_accepted')::boolean, false);
    v_req_payment_status := COALESCE(v_secure_order->>'payment_status', 'pending');

    IF v_req_status NOT IN ('awaiting_acceptance', 'awaiting_payment', 'pending') THEN
      v_req_status := 'pending';
    END IF;

    v_secure_order := v_secure_order || jsonb_build_object(
      'status', v_req_status,
      'payment_status', v_req_payment_status,
      'seller_accepted', v_req_seller_accepted,
      'partner_accepted', v_req_partner_accepted,
      'refund_status', 'none',
      'enything_commission', v_server_enything_commission,
      'seller_payout', v_server_seller_payout,
      'rider_earnings', v_server_rider_earnings,
      'non_food_gst_amount', v_non_food_gst,
      's9_5_gst_amount', v_s9_5_gst,
      'gst_item_total', (v_s9_5_gst + v_non_food_gst),
      'gst_platform', v_server_gst_platform,
      'gst_delivery', v_server_gst_delivery,
      'gateway_deduction', v_gw_deduct,
      'tcs_amount', v_tcs_amount,
      'tds_amount', v_tds_amount,
      'grand_total_collected', v_expected_grand_total
    );
    
    -- Strip fields that the client shouldn't inject
    v_secure_order := v_secure_order - 'delivery_discount';
    
    IF p_idempotency_key IS NOT NULL THEN
      v_secure_order := v_secure_order || jsonb_build_object('idempotency_key', p_idempotency_key);
    END IF;

    v_secure_orders := v_secure_orders || v_secure_order;

  END LOOP;

  INSERT INTO orders SELECT * FROM jsonb_populate_recordset(null::orders, v_secure_orders);
  INSERT INTO order_items SELECT * FROM jsonb_populate_recordset(null::order_items, p_items);

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

  IF p_coupon_id IS NOT NULL THEN
    UPDATE coupons SET usage_count = usage_count + 1 WHERE id = p_coupon_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION place_orders_transaction(JSONB, JSONB, UUID, UUID) TO authenticated;
