-- =============================================================================
-- Migration: 100x Final Revenue & Trigger Crash Fix
-- Description:
--   1. Fixes the "Cascading Trigger Crash" by removing legacy references to 
--      the dropped `delivery_discount` column in `reallocate_cancelled_delivery_fees`.
--      This un-bricks the entire cancellation pipeline.
--   2. Fixes the "Systemic Revenue Bleed" by restoring missing fee components
--      (multi_shop_surcharge, small_cart_fee, heavy_order_fee) to the
--      `v_expected_grand_total` validation math in `place_orders_transaction`.
-- =============================================================================

-- 1. Un-brick the Cancellation Pipeline (Fix Trigger Crash)
CREATE OR REPLACE FUNCTION reallocate_cancelled_delivery_fees()
RETURNS TRIGGER AS $$
DECLARE
  v_active_order_id UUID;
  v_active_count INT;
  v_missing_delivery NUMERIC;
  v_missing_rider NUMERIC;
  v_missing_surcharge NUMERIC;
  v_missing_small NUMERIC;
  v_missing_heavy NUMERIC;
  v_split_delivery NUMERIC;
  v_split_rider NUMERIC;
  v_split_surcharge NUMERIC;
  v_split_small NUMERIC;
  v_split_heavy NUMERIC;
  v_net_delivery NUMERIC;
  v_new_gst_delivery NUMERIC;
  p_cart_group_id UUID;
  rec RECORD;
BEGIN
    p_cart_group_id := NEW.cart_group_id;

    -- Count active orders that can absorb the delivery fee
    SELECT COUNT(id) INTO v_active_count 
    FROM orders 
    WHERE cart_group_id = p_cart_group_id 
      AND status IN ('awaiting_acceptance', 'awaiting_payment', 'pending_pickup', 'accepted');

    IF v_active_count = 0 THEN
        RETURN FALSE;
    END IF;

    -- Aggregate missing fees from rejected/cancelled orders
    -- 100x FIX 1: Removed delivery_discount which was securely dropped in Phase 8
    SELECT 
        COALESCE(SUM(delivery_charges), 0),
        COALESCE(SUM(rider_earnings), 0),
        COALESCE(SUM(multi_shop_surcharge), 0),
        COALESCE(SUM(small_cart_fee), 0),
        COALESCE(SUM(heavy_order_fee), 0)
    INTO 
        v_missing_delivery, v_missing_rider, v_missing_surcharge, v_missing_small, v_missing_heavy
    FROM orders
    WHERE cart_group_id = p_cart_group_id 
      AND status IN ('cancelled', 'seller_rejected')
      AND delivery_charges > 0;

    IF v_missing_delivery = 0 THEN
        RETURN FALSE;
    END IF;

    -- Split among active orders
    v_split_delivery := v_missing_delivery / v_active_count;
    v_split_rider := v_missing_rider / v_active_count;
    v_split_surcharge := v_missing_surcharge / v_active_count;
    v_split_small := v_missing_small / v_active_count;
    v_split_heavy := v_missing_heavy / v_active_count;

    -- Zero out the cancelled ones, while PRESERVING the customer's right to a refund
    FOR rec IN 
        SELECT id, total_amount, gst_item_total, platform_fee, gst_platform, coupon_discount, payment_status
        FROM orders 
        WHERE cart_group_id = p_cart_group_id 
          AND status IN ('cancelled', 'seller_rejected') 
          AND delivery_charges > 0
    LOOP
        UPDATE orders
        SET delivery_charges = 0,
            rider_earnings = 0,
            multi_shop_surcharge = 0,
            small_cart_fee = 0,
            heavy_order_fee = 0,
            gst_delivery = 0,
            grand_total = GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform - COALESCE(rec.coupon_discount, 0)),
            grand_total_collected = CASE 
                WHEN rec.payment_status = 'captured' THEN GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform - COALESCE(rec.coupon_discount, 0)) 
                ELSE 0 
            END
        WHERE id = rec.id;
    END LOOP;

    -- Add to active orders (Prevent Rider Underpayment Blackhole)
    FOR rec IN 
        SELECT id, delivery_charges, rider_earnings, multi_shop_surcharge, small_cart_fee, heavy_order_fee,
               total_amount, gst_item_total, platform_fee, gst_platform, payment_status,
               COALESCE(coupon_discount, 0) AS coupon_discount
        FROM orders 
        WHERE cart_group_id = p_cart_group_id 
          AND status IN ('awaiting_acceptance', 'awaiting_payment', 'pending_pickup', 'accepted')
    LOOP
        v_net_delivery := (rec.delivery_charges + v_split_delivery) 
                        + (rec.multi_shop_surcharge + v_split_surcharge)
                        + (rec.small_cart_fee + v_split_small)
                        + (rec.heavy_order_fee + v_split_heavy);
                        
        -- Extract 18% embedded GST: net - (net / 1.18)
        v_new_gst_delivery := v_net_delivery - (v_net_delivery / 1.18);
        
        UPDATE orders
        SET delivery_charges = rec.delivery_charges + v_split_delivery,
            rider_earnings = rec.rider_earnings + v_split_rider,
            multi_shop_surcharge = rec.multi_shop_surcharge + v_split_surcharge,
            small_cart_fee = rec.small_cart_fee + v_split_small,
            heavy_order_fee = rec.heavy_order_fee + v_split_heavy,
            gst_delivery = v_new_gst_delivery,
            grand_total = GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform + v_net_delivery - rec.coupon_discount),
            grand_total_collected = CASE 
                WHEN rec.payment_status = 'captured' THEN GREATEST(0, rec.total_amount + rec.gst_item_total + rec.platform_fee + rec.gst_platform + v_net_delivery - rec.coupon_discount) 
                ELSE 0 
            END
        WHERE id = rec.id;
    END LOOP;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 2. Plug the Systemic Revenue Bleed in Checkout Validation
CREATE OR REPLACE FUNCTION place_orders_transaction(
  p_orders JSONB,
  p_items JSONB,
  p_cart_group_id UUID,
  p_coupon_id UUID DEFAULT NULL,
  p_idempotency_key TEXT DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order JSONB;
  v_item RECORD;
  v_order_record RECORD;
  v_sum_expected_total_amount NUMERIC := 0;
  v_sum_client_platform_fee NUMERIC := 0;
  v_sum_client_small_cart_fee NUMERIC := 0;
  v_sum_client_heavy_order_fee NUMERIC := 0;
  v_sum_client_multi_shop_surcharge NUMERIC := 0;
  v_sum_client_coupon_discount NUMERIC := 0;
  v_sum_client_delivery_charges NUMERIC := 0;
  v_expected_coupon_discount NUMERIC := 0;
  v_global_platform_fee NUMERIC;
  v_global_small_cart_fee NUMERIC;
  v_global_small_cart_threshold NUMERIC;
  v_global_heavy_order_fee NUMERIC;
  v_global_heavy_order_threshold NUMERIC;
  v_num_shops INT;
  v_total_weight_kg NUMERIC := 0;
  v_cart_distance_km NUMERIC := 0;
  v_delivery_base_fee NUMERIC;
  v_delivery_rate_per_km NUMERIC;
  v_delivery_max_distance NUMERIC;
  v_expected_delivery_fee NUMERIC := 0;
  v_cross_shop_total_amount NUMERIC := 0;

  v_shop_delivery_fee NUMERIC;
  v_shop_coupon_discount NUMERIC;

  v_expected_total_amount NUMERIC;
  v_s9_5_gst NUMERIC;
  v_non_food_gst NUMERIC;
  v_tcs_amount NUMERIC;
  v_tds_amount NUMERIC;
  v_expected_grand_total NUMERIC;
  
  v_shop_id UUID;
  v_seller_id UUID;
  v_is_deleted BOOLEAN;
  v_is_available BOOLEAN;
  v_db_price NUMERIC;
  v_category TEXT;
  v_cat_comm NUMERIC;
  v_default_comm NUMERIC := 10.0;
  v_pure_commission NUMERIC;
  v_gst_rate NUMERIC;
  v_is_deemed BOOLEAN;
  v_line_gst NUMERIC;
  v_tcs_rate NUMERIC;

  v_is_online BOOLEAN;
  v_gw_deduct NUMERIC;
  v_seller_base_payout NUMERIC;
  v_seller_gw_share NUMERIC;
  v_server_enything_commission NUMERIC;
  v_server_seller_payout NUMERIC;
  
  v_server_gst_platform NUMERIC;
  v_server_gst_delivery NUMERIC;
  v_global_platform_gst_rate NUMERIC := 0.18;
  v_global_delivery_gst_rate NUMERIC := 0.18;

  v_delivery_base NUMERIC;
  v_expected_rider_base NUMERIC;
  v_server_rider_earnings NUMERIC;

  v_inserted_ids UUID[] := '{}';
  v_secure_order JSONB;
  
  v_req_status TEXT;
  v_req_seller_accepted BOOLEAN;
  v_req_partner_accepted BOOLEAN;
  v_req_payment_status TEXT;

  v_coupon_max_uses INT;
  v_coupon_current_uses INT;
  v_coupon_type TEXT;
  v_coupon_value NUMERIC;
  v_coupon_max_discount NUMERIC;
  v_coupon_min_order NUMERIC;
  v_total_coupon_applied NUMERIC := 0;
  v_coupon_valid_from TIMESTAMPTZ;
  v_coupon_valid_until TIMESTAMPTZ;

  v_gst_override NUMERIC;
  v_shop_active BOOLEAN;
  v_shop_accepting BOOLEAN;
  v_cart_group_id UUID;
BEGIN
  IF jsonb_array_length(p_orders) = 0 THEN
    RAISE EXCEPTION 'No orders provided';
  END IF;

  v_cart_group_id := p_cart_group_id;
  IF v_cart_group_id IS NULL THEN
    RAISE EXCEPTION 'cart_group_id is required for multi-shop orders.';
  END IF;

  IF p_coupon_id IS NOT NULL THEN
    SELECT usage_limit, usage_count, discount_type, discount_value, max_discount, min_order_amount, valid_from, valid_until
    INTO v_coupon_max_uses, v_coupon_current_uses, v_coupon_type, v_coupon_value, v_coupon_max_discount, v_coupon_min_order, v_coupon_valid_from, v_coupon_valid_until
    FROM coupons
    WHERE id = p_coupon_id FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Coupon not found.';
    END IF;

    IF v_coupon_valid_from > NOW() THEN
      RAISE EXCEPTION 'Coupon is not active yet.';
    END IF;
    IF v_coupon_valid_until IS NOT NULL AND v_coupon_valid_until < NOW() THEN
      RAISE EXCEPTION 'Coupon has expired.';
    END IF;

    IF v_coupon_max_uses IS NOT NULL AND v_coupon_current_uses >= v_coupon_max_uses THEN
      RAISE EXCEPTION 'Coupon usage limit reached.';
    END IF;
  END IF;

  FOR v_order IN SELECT * FROM jsonb_array_elements(p_orders) LOOP
    IF v_order->>'shop_id' IS NOT NULL THEN
      SELECT is_active, accepting_orders, gst_override INTO v_shop_active, v_shop_accepting, v_gst_override 
      FROM shops WHERE id = (v_order->>'shop_id')::uuid;
      
      IF NOT FOUND THEN
        RAISE EXCEPTION 'Shop not found for id %', v_order->>'shop_id';
      END IF;
      
      IF v_shop_active = false OR COALESCE(v_shop_accepting, false) = false THEN
        RAISE EXCEPTION 'One or more shops in your cart are currently offline and not accepting orders.';
      END IF;
    END IF;
  END LOOP;

  SELECT count(DISTINCT shop_id) INTO v_num_shops FROM jsonb_to_recordset(p_orders) AS x(shop_id uuid);

  BEGIN
    SELECT (value::numeric * v_num_shops) INTO v_global_platform_fee FROM platform_config WHERE key = 'platform_fee';
  EXCEPTION WHEN OTHERS THEN v_global_platform_fee := (5.0 * v_num_shops); END;
  v_global_platform_fee := COALESCE(v_global_platform_fee, (5.0 * v_num_shops));

  -- 1. Validate Base Prices and Availability securely
  FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) AS x(product_id uuid, variant_name text, price numeric, quantity int) LOOP
    IF v_item.quantity <= 0 THEN
      RAISE EXCEPTION 'Invalid negative or zero quantity % for product %', v_item.quantity, v_item.product_id;
    END IF;

    IF v_item.variant_name IS NULL THEN
      SELECT price, is_available, is_deleted INTO v_db_price, v_is_available, v_is_deleted FROM products WHERE id = v_item.product_id;
    ELSE
      SELECT (elem->>'price')::numeric, is_available, is_deleted INTO v_db_price, v_is_available, v_is_deleted
      FROM products, jsonb_array_elements(variants) elem
      WHERE id = v_item.product_id AND elem->>'name' = v_item.variant_name;
    END IF;

    IF v_is_deleted THEN
      RAISE EXCEPTION 'Product % has been deleted.', v_item.product_id;
    END IF;

    IF COALESCE(v_is_available, false) = false THEN
      RAISE EXCEPTION 'Product % is currently unavailable or hidden by the seller.', v_item.product_id;
    END IF;

    IF ABS(v_db_price - v_item.price) > 0.01 THEN
      RAISE EXCEPTION 'Price spoofing detected for product %. Expected: %, Got: %', v_item.product_id, v_db_price, v_item.price;
    END IF;

    v_sum_expected_total_amount := v_sum_expected_total_amount + (v_item.quantity * v_item.price);
  END LOOP;

  IF v_sum_expected_total_amount <= 0 THEN
    RAISE EXCEPTION 'Total order amount must be greater than zero. Phantom empty orders are strictly prohibited.';
  END IF;

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
    coupon_discount numeric,
    estimated_distance_km numeric
  ) LOOP
    v_sum_client_platform_fee := v_sum_client_platform_fee + COALESCE(v_order.platform_fee, 0);
    v_sum_client_small_cart_fee := v_sum_client_small_cart_fee + COALESCE(v_order.small_cart_fee, 0);
    v_sum_client_heavy_order_fee := v_sum_client_heavy_order_fee + COALESCE(v_order.heavy_order_fee, 0);
    v_sum_client_multi_shop_surcharge := v_sum_client_multi_shop_surcharge + COALESCE(v_order.multi_shop_surcharge, 0);
    v_sum_client_coupon_discount := v_sum_client_coupon_discount + COALESCE(v_order.coupon_discount, 0);
    v_sum_client_delivery_charges := v_sum_client_delivery_charges + COALESCE(v_order.delivery_charges, 0);
    
    IF COALESCE(v_order.estimated_distance_km, 0) > 100.0 THEN
      RAISE EXCEPTION 'Distance spoofing detected (Money Laundering Exploit). The maximum allowed delivery radius is 100km. Claimed: % km', v_order.estimated_distance_km;
    END IF;
  END LOOP;

  IF ABS(v_sum_client_platform_fee - v_global_platform_fee) > 1.0 THEN
    RAISE EXCEPTION 'Platform fee spoofing detected. Expected: %, Got: %', v_global_platform_fee, v_sum_client_platform_fee;
  END IF;

  BEGIN SELECT value::numeric INTO v_global_small_cart_fee FROM platform_config WHERE key = 'small_cart_fee'; EXCEPTION WHEN OTHERS THEN v_global_small_cart_fee := 15.0; END;
  v_global_small_cart_fee := COALESCE(v_global_small_cart_fee, 15.0);
  BEGIN SELECT value::numeric INTO v_global_small_cart_threshold FROM platform_config WHERE key = 'small_cart_threshold'; EXCEPTION WHEN OTHERS THEN v_global_small_cart_threshold := 150.0; END;
  v_global_small_cart_threshold := COALESCE(v_global_small_cart_threshold, 150.0);

  IF v_sum_expected_total_amount > 0 AND v_sum_expected_total_amount < v_global_small_cart_threshold THEN
    IF ABS(v_sum_client_small_cart_fee - v_global_small_cart_fee) > 1.0 THEN
      RAISE EXCEPTION 'Small cart fee missing or incorrect. Expected: %, Got: %', v_global_small_cart_fee, v_sum_client_small_cart_fee;
    END IF;
  ELSE
    IF v_sum_client_small_cart_fee > 1.0 THEN
      RAISE EXCEPTION 'Small cart fee charged when not applicable. Cart total: %, Threshold: %', v_sum_expected_total_amount, v_global_small_cart_threshold;
    END IF;
  END IF;

  BEGIN SELECT value::numeric INTO v_global_heavy_order_fee FROM platform_config WHERE key = 'heavy_order_fee_per_kg'; EXCEPTION WHEN OTHERS THEN v_global_heavy_order_fee := 10.0; END;
  v_global_heavy_order_fee := COALESCE(v_global_heavy_order_fee, 10.0) * GREATEST(0, CEIL(v_total_weight_kg - 5));
  BEGIN SELECT value::numeric INTO v_global_heavy_order_threshold FROM platform_config WHERE key = 'heavy_order_threshold_kg'; EXCEPTION WHEN OTHERS THEN v_global_heavy_order_threshold := 5.0; END;
  v_global_heavy_order_threshold := COALESCE(v_global_heavy_order_threshold, 5.0);

  IF v_total_weight_kg > v_global_heavy_order_threshold THEN
    IF ABS(v_sum_client_heavy_order_fee - v_global_heavy_order_fee) > 1.0 THEN
      RAISE EXCEPTION 'Heavy order fee missing or incorrect. Expected: %, Got: %', v_global_heavy_order_fee, v_sum_client_heavy_order_fee;
    END IF;
  ELSE
    IF v_sum_client_heavy_order_fee > 1.0 THEN
      RAISE EXCEPTION 'Heavy order fee charged when not applicable. Weight: %, Threshold: %', v_total_weight_kg, v_global_heavy_order_threshold;
    END IF;
  END IF;

  BEGIN
    SELECT value::numeric INTO v_delivery_base_fee FROM platform_config WHERE key = 'delivery_base_fee';
  EXCEPTION WHEN OTHERS THEN v_delivery_base_fee := 10.0; END;
  v_delivery_base_fee := COALESCE(v_delivery_base_fee, 10.0);

  BEGIN
    SELECT value::numeric INTO v_delivery_rate_per_km FROM platform_config WHERE key = 'delivery_rate_per_km';
  EXCEPTION WHEN OTHERS THEN v_delivery_rate_per_km := 5.0; END;
  v_delivery_rate_per_km := COALESCE(v_delivery_rate_per_km, 5.0);

  v_cart_distance_km := COALESCE((p_orders->0->>'estimated_distance_km')::numeric, 0);
  v_expected_delivery_fee := v_delivery_base_fee + (v_cart_distance_km * v_delivery_rate_per_km);
  v_cross_shop_total_amount := v_sum_expected_total_amount;

  IF p_coupon_id IS NOT NULL THEN
    IF v_sum_expected_total_amount < COALESCE(v_coupon_min_order, 0) THEN
      RAISE EXCEPTION 'Order total does not meet coupon minimum requirement. Required: %, Actual: %', v_coupon_min_order, v_sum_expected_total_amount;
    END IF;

    IF v_coupon_type = 'fixed' THEN
      v_expected_coupon_discount := v_coupon_value;
    ELSIF v_coupon_type = 'percentage' THEN
      v_expected_coupon_discount := (v_sum_expected_total_amount * v_coupon_value) / 100.0;
      IF v_coupon_max_discount IS NOT NULL AND v_expected_coupon_discount > v_coupon_max_discount THEN
        v_expected_coupon_discount := v_coupon_max_discount;
      END IF;
    END IF;

    IF v_sum_client_coupon_discount > v_expected_coupon_discount + 1.0 THEN
      RAISE EXCEPTION 'Coupon discount spoofing detected. Max allowed: %, Claimed: %', v_expected_coupon_discount, v_sum_client_coupon_discount;
    END IF;
  ELSIF v_sum_client_coupon_discount > 0 THEN
    RAISE EXCEPTION 'Coupon discount applied without a valid coupon id.';
  END IF;


  -- 3. Loop through and validate individual shop orders
  FOR v_order_record IN SELECT * FROM jsonb_array_elements(p_orders) LOOP
    v_order := v_order_record.value;
    
    v_expected_total_amount := 0;
    v_s9_5_gst := 0;
    v_non_food_gst := 0;
    v_tcs_amount := 0;
    v_tds_amount := 0;
    v_pure_commission := 0;

    SELECT gst_override INTO v_gst_override FROM shops WHERE id = (v_order->>'shop_id')::uuid;

    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) AS x(product_id uuid, variant_name text, price numeric, quantity int, shop_id uuid) WHERE shop_id = (v_order->>'shop_id')::uuid LOOP
      SELECT category INTO v_category FROM products WHERE id = v_item.product_id;
      
      BEGIN
        SELECT value::numeric INTO v_cat_comm FROM platform_config WHERE key = 'commission_percent_' || v_category;
      EXCEPTION WHEN OTHERS THEN v_cat_comm := v_default_comm; END;
      v_cat_comm := COALESCE(v_cat_comm, v_default_comm);
      
      v_pure_commission := v_pure_commission + ((v_item.price * v_item.quantity * v_cat_comm) / 100.0);

      IF v_gst_override IS NOT NULL THEN
        v_gst_rate := v_gst_override;
        v_is_deemed := CASE WHEN v_category IN ('Restaurant', 'Fast Food', 'Bakery', 'Sweets & Mithai', 'Tea & Coffee', 'Ice Cream', 'Paan Shop') THEN true ELSE false END;
      ELSE
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

    IF ABS(v_expected_total_amount - COALESCE((v_order->>'total_amount')::numeric, 0)) > 0.01 THEN
      RAISE EXCEPTION 'Order base total mismatch. Expected: %, Got: %', v_expected_total_amount, (v_order->>'total_amount')::numeric;
    END IF;

    IF COALESCE((v_order->>'delivery_charges')::numeric, 0) < 0 THEN RAISE EXCEPTION 'delivery_charges cannot be negative'; END IF;
    IF COALESCE((v_order->>'multi_shop_surcharge')::numeric, 0) < 0 THEN RAISE EXCEPTION 'multi_shop_surcharge cannot be negative'; END IF;
    IF COALESCE((v_order->>'platform_fee')::numeric, 0) < 0 THEN RAISE EXCEPTION 'platform_fee cannot be negative'; END IF;
    IF COALESCE((v_order->>'small_cart_fee')::numeric, 0) < 0 THEN RAISE EXCEPTION 'small_cart_fee cannot be negative'; END IF;
    IF COALESCE((v_order->>'heavy_order_fee')::numeric, 0) < 0 THEN RAISE EXCEPTION 'heavy_order_fee cannot be negative'; END IF;
    IF COALESCE((v_order->>'coupon_discount')::numeric, 0) < 0 THEN RAISE EXCEPTION 'coupon_discount cannot be negative'; END IF;

    -- 100x FIX 2: Plug the systemic revenue bleed by strictly enforcing the collection of
    -- multi_shop_surcharge, small_cart_fee, and heavy_order_fee from the customer.
    -- Without these added to expected_grand_total, checkout validation would fail unless
    -- the client maliciously dropped them (free services funded by Enything's pocket).
    v_expected_grand_total :=
      v_expected_total_amount +
      v_s9_5_gst + v_non_food_gst +
      COALESCE((v_order->>'delivery_charges')::numeric, 0) +
      COALESCE((v_order->>'multi_shop_surcharge')::numeric, 0) +
      COALESCE((v_order->>'small_cart_fee')::numeric, 0) +
      COALESCE((v_order->>'heavy_order_fee')::numeric, 0) +
      COALESCE((v_order->>'platform_fee')::numeric, 0) -
      COALESCE((v_order->>'coupon_discount')::numeric, 0);

    IF v_expected_grand_total < 0 THEN v_expected_grand_total := 0; END IF;

    IF ABS(v_expected_grand_total - COALESCE((v_order->>'grand_total_collected')::numeric, 0)) > 1.00 THEN
      RAISE EXCEPTION 'Order grand total mismatch. Expected: %, Got: %', v_expected_grand_total, (v_order->>'grand_total_collected')::numeric;
    END IF;

    v_is_online := COALESCE(v_order->>'payment_method', 'cod') != 'cod';
    v_gw_deduct := CASE WHEN v_is_online THEN v_expected_grand_total * 0.0236 ELSE 0.0 END;
    
    v_seller_base_payout := v_expected_total_amount - v_pure_commission;
    v_seller_gw_share := CASE WHEN v_is_online THEN (v_seller_base_payout + v_non_food_gst) * 0.0236 ELSE 0.0 END;
    
    v_server_enything_commission := v_pure_commission + v_seller_gw_share;
    v_server_seller_payout := v_expected_total_amount + v_non_food_gst - v_server_enything_commission - v_tcs_amount - v_tds_amount;

    IF COALESCE((v_order->>'platform_fee')::numeric, 0) > 0 THEN
      v_server_gst_platform := (v_order->>'platform_fee')::numeric - ((v_order->>'platform_fee')::numeric / (1 + v_global_platform_gst_rate));
    ELSE
      v_server_gst_platform := 0;
    END IF;

    IF COALESCE((v_order->>'delivery_charges')::numeric, 0) > 0 THEN
      v_server_gst_delivery := (v_order->>'delivery_charges')::numeric - ((v_order->>'delivery_charges')::numeric / (1 + v_global_delivery_gst_rate));
    ELSE
      v_server_gst_delivery := 0;
    END IF;

    v_expected_rider_base := COALESCE((v_order->>'delivery_charges')::numeric, 0) + COALESCE((v_order->>'multi_shop_surcharge')::numeric, 0) + COALESCE((v_order->>'heavy_order_fee')::numeric, 0);
    v_server_rider_earnings := GREATEST(0, v_expected_rider_base * 0.80);

    SELECT elem INTO v_secure_order FROM jsonb_array_elements(p_orders) elem WHERE (elem->>'id')::uuid = (v_order->>'id')::uuid;
    
    v_req_status := COALESCE(v_secure_order->>'status', 'pending');
    v_req_seller_accepted := COALESCE((v_secure_order->>'seller_accepted')::boolean, false);
    v_req_partner_accepted := COALESCE((v_secure_order->>'partner_accepted')::boolean, false);
    v_req_payment_status := COALESCE(v_secure_order->>'payment_status', 'pending');

    IF v_req_status NOT IN ('awaiting_acceptance', 'awaiting_payment', 'pending') THEN
      v_req_status := 'pending';
    END IF;

    v_secure_order := v_secure_order || jsonb_build_object(
      'status', v_req_status,
      'seller_accepted', v_req_seller_accepted,
      'partner_accepted', v_req_partner_accepted,
      'payment_status', v_req_payment_status,
      
      'total_amount', v_expected_total_amount,
      'gst_item_total', v_s9_5_gst + v_non_food_gst,
      'platform_fee', COALESCE((v_order->>'platform_fee')::numeric, 0),
      'delivery_charges', COALESCE((v_order->>'delivery_charges')::numeric, 0),
      'multi_shop_surcharge', COALESCE((v_order->>'multi_shop_surcharge')::numeric, 0),
      'small_cart_fee', COALESCE((v_order->>'small_cart_fee')::numeric, 0),
      'heavy_order_fee', COALESCE((v_order->>'heavy_order_fee')::numeric, 0),
      'coupon_discount', COALESCE((v_order->>'coupon_discount')::numeric, 0),
      
      'grand_total', v_expected_grand_total,
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
      seller_accepted, partner_accepted, delivery_address,
      estimated_distance_km, delivery_instructions, cancellation_reason,
      
      total_amount, s9_5_gst_amount, non_food_gst_amount, gst_item_total,
      platform_fee, gst_platform,
      delivery_charges, multi_shop_surcharge, small_cart_fee, heavy_order_fee, gst_delivery,
      coupon_discount, grand_total, grand_total_collected,
      
      tcs_amount, tds_amount,
      gateway_deduction, seller_payout, enything_commission, rider_earnings,
      
      idempotency_key, coupon_id
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
      v_secure_order->'delivery_address',
      (v_secure_order->>'estimated_distance_km')::numeric,
      v_secure_order->>'delivery_instructions',
      v_secure_order->>'cancellation_reason',

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
      (v_secure_order->>'grand_total')::numeric,
      (v_secure_order->>'grand_total_collected')::numeric,

      (v_secure_order->>'tcs_amount')::numeric,
      (v_secure_order->>'tds_amount')::numeric,
      
      (v_secure_order->>'gateway_deduction')::numeric,
      (v_secure_order->>'seller_payout')::numeric,
      (v_secure_order->>'enything_commission')::numeric,
      (v_secure_order->>'rider_earnings')::numeric,

      p_idempotency_key,
      p_coupon_id
    ;

    v_inserted_ids := array_append(v_inserted_ids, (v_order->>'id')::uuid);
  END LOOP;

  -- 4. Secure Bulk Insert for Order Items (Using validated secure data)
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
        v_item.id,
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
    UPDATE coupons SET usage_count = usage_count + 1 WHERE id = p_coupon_id;
  END IF;
END;
$$;
