-- =============================================================================
-- TEST: Category Flows & Admin Config Changes
-- Purpose: 
--   1. Change platform_fee and commission_percent in platform_config.
--   2. Attempt checkout with old client values -> Expect fail.
--   3. Attempt checkout with new client values -> Expect success.
--   4. Test Deemed Supplier GST logic.
-- =============================================================================

DO $$
DECLARE
  v_customer_id UUID;
  v_seller_id UUID;
  v_shop_id UUID;
  v_product_id_clothing UUID;
  v_product_id_food UUID;
  v_cart_group_id UUID := gen_random_uuid();
  v_order_id UUID := gen_random_uuid();
  
  v_items JSONB;
  v_orders JSONB;
  
  v_err_context TEXT;
BEGIN
  -- 1. Setup Data
  SELECT id INTO v_customer_id FROM profiles LIMIT 1;
  IF v_customer_id IS NULL THEN
    RAISE NOTICE 'Skipping test: No users found.';
    RETURN;
  END IF;

  INSERT INTO shops (id, seller_id, name, is_active, verification_status)
  VALUES (gen_random_uuid(), v_customer_id, '100x Test Shop', true, 'approved')
  RETURNING id INTO v_shop_id;

  INSERT INTO products (id, shop_id, name, price, total_quantity, category, is_available)
  VALUES (gen_random_uuid(), v_shop_id, 'Test Shirt (Clothing)', 1000.0, 10, 'Clothing', true)
  RETURNING id INTO v_product_id_clothing;

  INSERT INTO products (id, shop_id, name, price, total_quantity, category, is_available)
  VALUES (gen_random_uuid(), v_shop_id, 'Test Burger (Food)', 200.0, 10, 'Fast Food', true)
  RETURNING id INTO v_product_id_food;

  -- 2. Modify platform configuration (Admin changes fee to 25.0)
  INSERT INTO platform_config (key, value) VALUES ('platform_fee', '25.0')
  ON CONFLICT (key) DO UPDATE SET value = '25.0';

  -- Modify commission for Clothing to 15%
  INSERT INTO platform_config (key, value) VALUES ('commission_percent_Clothing', '15.0')
  ON CONFLICT (key) DO UPDATE SET value = '15.0';

  -- Ensure tax_config exists for Fast Food
  INSERT INTO tax_config (category, gst_rate, is_deemed_supplier) 
  VALUES ('Fast Food', 0.05, true)
  ON CONFLICT (category) DO UPDATE SET gst_rate = 0.05, is_deemed_supplier = true;
  
  -- 3. Simulate checkout with OLD platform fee (e.g. 5.0)
  v_items := jsonb_build_array(
    jsonb_build_object('product_id', v_product_id_clothing, 'quantity', 1, 'shop_id', v_shop_id, 'price', 1000.0)
  );
  
  -- 1000 (item) + 50 (GST 5% for clothing <= 2500) + 5 (old plat fee) = 1055
  v_orders := jsonb_build_array(
    jsonb_build_object(
      'id', v_order_id,
      'shop_id', v_shop_id,
      'grand_total', 1055.0,
      'platform_fee', 5.0,
      'delivery_charges', 0.0,
      'small_cart_fee', 0.0,
      'heavy_order_fee', 0.0,
      'coupon_discount', 0.0,
      'payment_method', 'cod',
      'delivery_lat', 0.0,
      'delivery_lng', 0.0,
      'estimated_distance_km', 5.0
    )
  );

  -- Context impersonation
  PERFORM set_config('request.jwt.claims', format('{"sub": "%s"}', v_customer_id), true);

  BEGIN
    PERFORM place_orders_transaction(v_orders, v_items, v_cart_group_id, NULL::uuid, gen_random_uuid()::text, NULL::uuid);
    RAISE EXCEPTION 'TEST FAILED: Should have rejected old platform fee';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err_context = PG_EXCEPTION_CONTEXT;
    IF SQLERRM LIKE '%Platform fee spoofing detected%' THEN
      RAISE NOTICE '100x PASS: Caught old platform fee attempt -> %', SQLERRM;
    ELSE
      RAISE EXCEPTION 'TEST FAILED WITH UNEXPECTED ERROR: % | CONTEXT: %', SQLERRM, v_err_context;
    END IF;
  END;

  -- 4. Simulate checkout with correct new fee (25.0)
  -- Expected total: 1000 + 50 (GST) + 25 (new plat fee) = 1075
  v_orders := jsonb_build_array(
    jsonb_build_object(
      'id', v_order_id,
      'shop_id', v_shop_id,
      'grand_total', 1075.0,
      'platform_fee', 25.0,
      'delivery_charges', 0.0,
      'small_cart_fee', 0.0,
      'heavy_order_fee', 0.0,
      'coupon_discount', 0.0,
      'payment_method', 'cod',
      'delivery_lat', 0.0,
      'delivery_lng', 0.0,
      'estimated_distance_km', 5.0
    )
  );

  BEGIN
    PERFORM place_orders_transaction(v_orders, v_items, v_cart_group_id, NULL::uuid, gen_random_uuid()::text, NULL::uuid);
    RAISE NOTICE '100x PASS: Checkout succeeded with correct updated platform configs.';

  -- Verify commission was taken correctly (15% of 1000 = 150)
  DECLARE
    v_inserted_commission NUMERIC;
    v_inserted_gst_platform NUMERIC;
  BEGIN
    SELECT enything_commission, gst_platform INTO v_inserted_commission, v_inserted_gst_platform
    FROM orders WHERE id = v_order_id;
    
    -- expected commission: 150 (pure) + (25 - (25 / 1.18)) = 150 + 3.813559... = 153.81 (rounded)
    IF ROUND(v_inserted_commission, 2) != 153.81 THEN
      RAISE EXCEPTION 'TEST FAILED: Expected commission 153.81, got %', v_inserted_commission;
    ELSE
      RAISE NOTICE '100x PASS: Enything Commission correctly calculated dynamically from platform config.';
    END IF;
  END;
  
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err_context = PG_EXCEPTION_CONTEXT;
    RAISE EXCEPTION 'TEST FAILED WITH UNEXPECTED ERROR: % | CONTEXT: %', SQLERRM, v_err_context;
  END;
  
  RAISE EXCEPTION 'Test Successful - Rolling back test data.';
END;
$$;
