-- =============================================================================
-- Migration: 100x Checkout Payout Audit Fixes
-- Description:
--   1. Fixes double deduction of TCS and TDS in admin and seller RPCs.
--      (seller_payout already has TCS/TDS deducted natively by place_orders_transaction)
--   2. Preserves frontend-injected statuses (awaiting_acceptance, awaiting_payment) 
--      to prevent breaking the acceptance timeout rings and magic test flows.
-- =============================================================================

-- Fix 1: Update admin_get_finance_stats to prevent double deduction
CREATE OR REPLACE FUNCTION admin_get_finance_stats()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_gmv NUMERIC;
  v_pure_profit NUMERIC;
  v_seller_payouts NUMERIC;
  v_rider_earnings NUMERIC;
  v_pending_settlements INT;
BEGIN
  -- Strict Authorization Barrier
  IF NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;

  SELECT 
    COALESCE(SUM(grand_total_collected), 0),
    COALESCE(SUM(
      COALESCE(enything_commission, 0) + 
      (COALESCE(platform_fee, 0) - COALESCE(gst_platform, 0)) + 
      (COALESCE(delivery_charges, 0) - COALESCE(gst_delivery, 0) - COALESCE(rider_earnings, 0)) - 
      COALESCE(gateway_deduction, 0)
    ), 0)
  INTO v_gmv, v_pure_profit
  FROM orders WHERE status NOT IN ('cancelled', 'seller_rejected', 'partner_rejected', 'verification_failed', 'shop_dispute_cancel');

  SELECT 
    COALESCE(SUM(COALESCE(seller_payout, 0)), 0),
    COALESCE(SUM(rider_earnings), 0),
    COUNT(*)
  INTO v_seller_payouts, v_rider_earnings, v_pending_settlements
  FROM orders WHERE status = 'delivered';

  RETURN jsonb_build_object(
    'gmv', v_gmv,
    'pure_profit', v_pure_profit,
    'seller_payouts', v_seller_payouts,
    'rider_earnings', v_rider_earnings,
    'pending_settlements', v_pending_settlements
  );
END;
$$;

-- Fix 2: Update get_seller_daily_stats to prevent double deduction
CREATE OR REPLACE FUNCTION get_seller_daily_stats(p_shop_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_total_orders integer := 0;
    v_pending_orders integer := 0;
    v_todays_earning numeric := 0.0;
    v_products integer := 0;
BEGIN
    -- Get total orders
    SELECT count(*) INTO v_total_orders
    FROM orders
    WHERE shop_id = p_shop_id
      AND status NOT IN ('cancelled', 'seller_rejected');

    -- Get pending orders
    SELECT count(*) INTO v_pending_orders
    FROM orders
    WHERE shop_id = p_shop_id
      AND status IN ('pending', 'awaiting_acceptance');

    -- Get today's earnings (Fix: DO NOT subtract tds_amount and tcs_amount again)
    SELECT COALESCE(SUM(COALESCE(seller_payout, 0)), 0.0) INTO v_todays_earning
    FROM orders
    WHERE shop_id = p_shop_id
      AND status = 'delivered'
      AND DATE(created_at AT TIME ZONE 'Asia/Kolkata') = DATE(CURRENT_TIMESTAMP AT TIME ZONE 'Asia/Kolkata');

    -- Get products count
    SELECT count(*) INTO v_products
    FROM products
    WHERE shop_id = p_shop_id;

    RETURN json_build_object(
        'total_orders', v_total_orders,
        'pending_orders', v_pending_orders,
        'todays_earning', v_todays_earning,
        'products', v_products
    );
END;
$$;

GRANT EXECUTE ON FUNCTION get_seller_daily_stats(uuid) TO authenticated;

-- Fix 3: Update place_orders_transaction to preserve status flow
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
  v_total_qty INT;
  v_expected_total_amount NUMERIC;
  v_expected_grand_total NUMERIC;
  v_coupon_max_uses INT;
  v_coupon_current_uses INT;
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
  v_s9_5_gst NUMERIC;
  v_non_food_gst NUMERIC;
  v_gst_rate NUMERIC;
  v_is_deemed BOOLEAN;
  v_line_gst NUMERIC;
  v_tcs_rate NUMERIC;
  v_tds_amount NUMERIC;
  v_tcs_amount NUMERIC;

  -- Incoming status overrides variables
  v_req_status TEXT;
  v_req_seller_accepted BOOLEAN;
  v_req_partner_accepted BOOLEAN;
  v_req_payment_status TEXT;
BEGIN
  -- Idempotency Check: if this key already exists, return successfully
  IF p_idempotency_key IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM orders WHERE idempotency_key = p_idempotency_key) THEN
      RETURN;
    END IF;
  END IF;

  -- Fetch default commission rate from platform_config
  BEGIN
    SELECT value::numeric INTO v_default_comm FROM platform_config WHERE key = 'commission_percent';
  EXCEPTION WHEN OTHERS THEN v_default_comm := 5.0; END;
  v_default_comm := COALESCE(v_default_comm, 5.0);

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

  -- 1. Validate Base Prices (variant-aware)
  FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) AS x(product_id uuid, variant_name text, price numeric) LOOP
    IF v_item.variant_name IS NULL THEN
      SELECT price INTO v_db_price FROM products WHERE id = v_item.product_id;
    ELSE
      SELECT (elem->>'price')::numeric INTO v_db_price
      FROM products, jsonb_array_elements(variants) elem
      WHERE id = v_item.product_id AND elem->>'name' = v_item.variant_name;
    END IF;

    IF v_db_price IS NULL THEN
      RAISE EXCEPTION 'Product or variant not found: % / %', v_item.product_id, COALESCE(v_item.variant_name, 'None');
    END IF;

    IF ABS(v_db_price - v_item.price) > 0.01 THEN
      RAISE EXCEPTION 'Price spoofing detected for product %. Expected: %, Got: %', v_item.product_id, v_db_price, v_item.price;
    END IF;
  END LOOP;

  -- 2. Secure Order Reconstruction & Exact Backend Math
  FOR v_order IN SELECT * FROM jsonb_to_recordset(p_orders) AS x(
    id uuid,
    total_amount numeric,
    delivery_charges numeric,
    multi_shop_surcharge numeric,
    platform_fee numeric,
    small_cart_fee numeric,
    heavy_order_fee numeric,
    delivery_discount numeric,
    coupon_discount numeric,
    gst_item_total numeric,
    gst_delivery numeric,
    gst_platform numeric,
    grand_total_collected numeric,
    payment_method text
  ) LOOP

    -- Prevent forged coupon discounts
    IF p_coupon_id IS NULL AND COALESCE(v_order.coupon_discount, 0) > 0 THEN
      RAISE EXCEPTION 'Cannot apply coupon discount without a valid coupon code.';
    END IF;

    v_expected_total_amount := 0;
    v_pure_commission := 0;
    v_s9_5_gst := 0;
    v_non_food_gst := 0;
    v_tcs_amount := 0;
    v_tds_amount := 0;

    -- Calculate item totals securely using the DB-verified prices
    FOR v_item IN 
      SELECT y.product_id, y.quantity, y.price 
      FROM jsonb_to_recordset(p_items) AS y(order_id uuid, product_id uuid, quantity int, price numeric) 
      WHERE y.order_id = v_order.id 
    LOOP
      v_expected_total_amount := v_expected_total_amount + (v_item.quantity * v_item.price);
      
      -- Fetch Category to determine Commission and GST rules
      SELECT category INTO v_category FROM products WHERE id = v_item.product_id;
      
      -- Calculate Pure Commission
      BEGIN
        SELECT value::numeric INTO v_cat_comm FROM platform_config WHERE key = 'commission_percent_' || v_category;
      EXCEPTION WHEN OTHERS THEN v_cat_comm := NULL; END;
      
      v_pure_commission := v_pure_commission + (v_item.price * v_item.quantity * COALESCE(v_cat_comm, v_default_comm) / 100.0);
      
      -- Calculate GST
      BEGIN
        SELECT gst_rate::numeric, is_deemed_supplier INTO v_gst_rate, v_is_deemed FROM tax_config WHERE category = v_category;
      EXCEPTION WHEN OTHERS THEN v_gst_rate := NULL; END;
      
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
      
      -- Calculate TCS and TDS based on TaxConfig laws
      v_tcs_rate := CASE WHEN v_category IN ('Restaurant', 'Fast Food', 'Bakery', 'Sweets & Mithai', 'Tea & Coffee', 'Ice Cream', 'Paan Shop', 'Fruits & Vegs', 'Butcher', 'Fish & Seafood') THEN 0.0 ELSE 0.01 END;
      v_tcs_amount := v_tcs_amount + (v_item.price * v_item.quantity * v_tcs_rate);
      v_tds_amount := v_tds_amount + (v_item.price * v_item.quantity * 0.001);
    END LOOP;

    IF ABS(v_expected_total_amount - COALESCE(v_order.total_amount, 0)) > 0.01 THEN
      RAISE EXCEPTION 'Order base total mismatch. Expected: %, Got: %', v_expected_total_amount, v_order.total_amount;
    END IF;

    -- Security Bounds Validation: Enforce non-negative fees
    IF COALESCE(v_order.delivery_charges, 0) < 0 THEN RAISE EXCEPTION 'delivery_charges cannot be negative'; END IF;
    IF COALESCE(v_order.multi_shop_surcharge, 0) < 0 THEN RAISE EXCEPTION 'multi_shop_surcharge cannot be negative'; END IF;
    IF COALESCE(v_order.platform_fee, 0) < 0 THEN RAISE EXCEPTION 'platform_fee cannot be negative'; END IF;
    IF COALESCE(v_order.small_cart_fee, 0) < 0 THEN RAISE EXCEPTION 'small_cart_fee cannot be negative'; END IF;
    IF COALESCE(v_order.heavy_order_fee, 0) < 0 THEN RAISE EXCEPTION 'heavy_order_fee cannot be negative'; END IF;
    IF COALESCE(v_order.delivery_discount, 0) < 0 THEN RAISE EXCEPTION 'delivery_discount cannot be negative'; END IF;
    IF COALESCE(v_order.coupon_discount, 0) < 0 THEN RAISE EXCEPTION 'coupon_discount cannot be negative'; END IF;

    v_expected_grand_total :=
      v_expected_total_amount +
      v_s9_5_gst + v_non_food_gst + -- Use securely calculated GST
      COALESCE(v_order.delivery_charges, 0) +
      COALESCE(v_order.platform_fee, 0) -
      COALESCE(v_order.coupon_discount, 0);

    IF v_expected_grand_total < 0 THEN
      v_expected_grand_total := 0;
    END IF;

    -- 1 rupee tolerance for rounding differences between Dart and Postgres
    IF ABS(v_expected_grand_total - COALESCE(v_order.grand_total_collected, 0)) > 1.00 THEN
      RAISE EXCEPTION 'Order grand total mismatch. Expected: %, Got: %', v_expected_grand_total, v_order.grand_total_collected;
    END IF;

    -- SERVER-SIDE PAYOUT CALCULATIONS (Ignoring client completely)
    v_is_online := COALESCE(v_order.payment_method, 'cod') != 'cod';
    v_gw_deduct := CASE WHEN v_is_online THEN v_expected_grand_total * 0.0236 ELSE 0.0 END;
    
    v_seller_base_payout := v_expected_total_amount - v_pure_commission;
    v_seller_gw_share := CASE WHEN v_is_online THEN (v_seller_base_payout + v_non_food_gst) * 0.0236 ELSE 0.0 END;
    
    v_server_enything_commission := v_pure_commission + v_seller_gw_share;
    
    v_server_seller_payout := v_expected_total_amount + v_non_food_gst - v_server_enything_commission - v_tcs_amount - v_tds_amount;
    v_server_rider_earnings := COALESCE(v_order.delivery_charges, 0) * 0.80;

    -- Build Secure JSON Object (Override Client Injections safely)
    SELECT elem INTO v_secure_order FROM jsonb_array_elements(p_orders) elem WHERE (elem->>'id')::uuid = v_order.id;
    
    -- Extract and validate the intended frontend states
    v_req_status := COALESCE(v_secure_order->>'status', 'pending');
    v_req_seller_accepted := COALESCE((v_secure_order->>'seller_accepted')::boolean, false);
    v_req_partner_accepted := COALESCE((v_secure_order->>'partner_accepted')::boolean, false);
    v_req_payment_status := COALESCE(v_secure_order->>'payment_status', 'pending');

    -- Restrict acceptable statuses to prevent injection attacks
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
      'gateway_deduction', v_gw_deduct,
      'tcs_amount', v_tcs_amount,
      'tds_amount', v_tds_amount,
      'grand_total_collected', v_expected_grand_total
    );
    
    IF p_idempotency_key IS NOT NULL THEN
      v_secure_order := v_secure_order || jsonb_build_object('idempotency_key', p_idempotency_key);
    END IF;

    v_secure_orders := v_secure_orders || v_secure_order;

  END LOOP;

  -- 3. Validate coupon usage limit
  IF p_coupon_id IS NOT NULL THEN
    SELECT usage_limit, current_uses INTO v_coupon_max_uses, v_coupon_current_uses
    FROM coupons
    WHERE id = p_coupon_id FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Coupon does not exist.';
    END IF;

    IF v_coupon_max_uses IS NOT NULL AND v_coupon_current_uses >= v_coupon_max_uses THEN
      RAISE EXCEPTION 'Coupon has reached its maximum usage limit.';
    END IF;
  END IF;

  -- 4. Insert Orders securely using server-calculated clean JSON
  INSERT INTO orders
  SELECT * FROM jsonb_populate_recordset(null::orders, v_secure_orders);

  -- 5. Insert Order Items
  INSERT INTO order_items
  SELECT * FROM jsonb_populate_recordset(null::order_items, p_items);

  -- 6. Decrement stock safely WITH DEADLOCK PREVENTION
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
      UPDATE products
      SET total_quantity = total_quantity - v_item.total_qty_req
      WHERE id = v_item.product_id;
    END IF;
  END LOOP;

  -- 7. Increment coupon usage
  IF p_coupon_id IS NOT NULL THEN
    UPDATE coupons
    SET current_uses = current_uses + 1
    WHERE id = p_coupon_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION place_orders_transaction(JSONB, JSONB, UUID, UUID) TO authenticated;
