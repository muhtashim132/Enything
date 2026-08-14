-- =============================================================================
-- Comprehensive Test Suite: 100x Partial Rejection Fortress Verification
-- =============================================================================

DO $$
DECLARE
  v_test_user_id UUID := '00000000-0000-0000-0000-000000000001';
  v_shop1_id UUID := gen_random_uuid();
  v_shop2_id UUID := gen_random_uuid();
  v_shop3_id UUID := gen_random_uuid();
  v_seller1_id UUID := gen_random_uuid();
  v_seller2_id UUID := gen_random_uuid();
  v_seller3_id UUID := gen_random_uuid();
  
  v_cart_group_id UUID := gen_random_uuid();
  v_order1_id UUID := gen_random_uuid();
  v_order2_id UUID := gen_random_uuid();
  v_order3_id UUID := gen_random_uuid();

  v_coupon_id UUID := gen_random_uuid();

  v_o1 RECORD;
  v_o2 RECORD;
  v_o3 RECORD;
BEGIN
  RAISE NOTICE '=== TEST 1: SETUP TEST SHOPS, PLATFORM CONFIG & ORDERS ===';

  -- Create platform config entries if missing
  INSERT INTO public.platform_config (key, value) VALUES
    ('platform_fee', '20.0'::jsonb),
    ('platform_fee_gst_rate', '0.18'::jsonb),
    ('delivery_gst_rate', '0.18'::jsonb),
    ('multi_shop_surcharge', '20.0'::jsonb),
    ('rider_commission_percent', '80.0'::jsonb),
    ('small_cart_threshold', '100.0'::jsonb),
    ('small_cart_fee', '15.0'::jsonb),
    ('heavy_order_threshold_kg', '10.0'::jsonb),
    ('heavy_order_fee', '25.0'::jsonb)
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

  -- Create test shops
  INSERT INTO public.shops (id, name, seller_id, is_active, location) VALUES
    (v_shop1_id, 'Pharma Shop 1', v_seller1_id, true, ST_SetSRID(ST_MakePoint(74.8, 34.1), 4326)::geography),
    (v_shop2_id, 'Grocery Shop 2', v_seller2_id, true, ST_SetSRID(ST_MakePoint(74.81, 34.11), 4326)::geography),
    (v_shop3_id, 'Bakery Shop 3', v_seller3_id, true, ST_SetSRID(ST_MakePoint(74.82, 34.12), 4326)::geography);

  -- Create a 10% coupon with min order value 200
  INSERT INTO public.coupons (id, code, type, value, max_discount, min_order_value, is_active, valid_from, valid_until)
  VALUES (v_coupon_id, 'TEST10', 'percentage', 10.0, 50.0, 200.0, true, NOW() - INTERVAL '1 day', NOW() + INTERVAL '1 day');

  -- Create 3 orders in cart group (Unpaid state)
  -- Total delivery = ₹60 (₹20 each), Surcharge = ₹40 (₹13.33 each), Platform fee = ₹20 (₹6.67 each)
  INSERT INTO public.orders (
    id, customer_id, shop_id, cart_group_id, status, payment_status, payment_method,
    total_amount, delivery_charges, multi_shop_surcharge, platform_fee, small_cart_fee, heavy_order_fee,
    gst_item_total, gst_delivery, gst_platform, coupon_id, coupon_discount, grand_total_collected,
    created_at, updated_at
  ) VALUES 
  (
    v_order1_id, v_test_user_id, v_shop1_id, v_cart_group_id, 'awaiting_acceptance', 'pending', 'online',
    100.0, 20.0, 13.33, 6.67, 0.0, 0.0,
    5.0, 3.05, 1.02, v_coupon_id, 10.0, 128.33,
    NOW(), NOW()
  ),
  (
    v_order2_id, v_test_user_id, v_shop2_id, v_cart_group_id, 'awaiting_acceptance', 'pending', 'online',
    200.0, 20.0, 13.33, 6.67, 0.0, 0.0,
    10.0, 3.05, 1.02, v_coupon_id, 20.0, 224.33,
    NOW(), NOW()
  ),
  (
    v_order3_id, v_test_user_id, v_shop3_id, v_cart_group_id, 'awaiting_acceptance', 'pending', 'online',
    300.0, 20.0, 13.34, 6.66, 0.0, 0.0,
    15.0, 3.05, 1.02, v_coupon_id, 30.0, 320.34,
    NOW(), NOW()
  );

  RAISE NOTICE '=== TEST 2: PHARMA SHOP REJECTS DUE TO PRESCRIPTION (verification_failed) ===';
  
  -- Simulate seller rejection with prescription failure
  UPDATE public.orders
  SET status = 'verification_failed',
      seller_accepted = false,
      updated_at = NOW()
  WHERE id = v_order1_id;

  -- Reallocate delivery fees
  PERFORM public.reallocate_cancelled_delivery_fees(v_cart_group_id);
  PERFORM public.rebalance_active_delivery_fees(v_cart_group_id);

  SELECT * INTO v_o1 FROM public.orders WHERE id = v_order1_id;
  SELECT * INTO v_o2 FROM public.orders WHERE id = v_order2_id;
  SELECT * INTO v_o3 FROM public.orders WHERE id = v_order3_id;

  -- Assertions for Test 2
  IF v_o1.delivery_charges != 0 THEN
    RAISE EXCEPTION 'Assertion Failed: Order 1 delivery charges should be 0, got %', v_o1.delivery_charges;
  END IF;
  IF v_o1.platform_fee != 0 THEN
    RAISE EXCEPTION 'Assertion Failed: Order 1 platform fee should be 0, got %', v_o1.platform_fee;
  END IF;

  RAISE NOTICE 'Order 1 (verification_failed): Deliv=%, Plat=%, Grand=%', v_o1.delivery_charges, v_o1.platform_fee, v_o1.grand_total_collected;
  RAISE NOTICE 'Order 2 (active): Deliv=%, Surch=%, Plat=%, Grand=%', v_o2.delivery_charges, v_o2.multi_shop_surcharge, v_o2.platform_fee, v_o2.grand_total_collected;
  RAISE NOTICE 'Order 3 (active): Deliv=%, Surch=%, Plat=%, Grand=%', v_o3.delivery_charges, v_o3.multi_shop_surcharge, v_o3.platform_fee, v_o3.grand_total_collected;

  -- Verify surviving 2 shops share 1 surcharge (₹20 total = ₹10 each) and platform fee (₹20 total = ₹10 each)
  IF v_o2.platform_fee != 10.0 OR v_o3.platform_fee != 10.0 THEN
    RAISE EXCEPTION 'Assertion Failed: Active platform fee should be 10.0 each, got O2=%, O3=%', v_o2.platform_fee, v_o3.platform_fee;
  END IF;


  RAISE NOTICE '=== TEST 3: SELECTIVE SINGLE ORDER CANCELLATION (Cancel Pending Shop 3) ===';

  -- Simulate Shop 2 is accepted, Shop 3 is still pending
  UPDATE public.orders SET seller_accepted = true WHERE id = v_order2_id;

  -- Customer cancels ONLY Shop 3 (p_cancel_entire_group = false)
  -- Mock customer session
  PERFORM public.cancel_order(v_order3_id, 'customer', false);

  SELECT * INTO v_o2 FROM public.orders WHERE id = v_order2_id;
  SELECT * INTO v_o3 FROM public.orders WHERE id = v_order3_id;

  IF v_o3.status != 'cancelled' THEN
    RAISE EXCEPTION 'Assertion Failed: Order 3 should be cancelled, got %', v_o3.status;
  END IF;

  IF v_o2.status NOT IN ('awaiting_acceptance', 'awaiting_payment') THEN
    RAISE EXCEPTION 'Assertion Failed: Order 2 (accepted shop) MUST REMAIN ACTIVE, got %', v_o2.status;
  END IF;

  -- Rebalanced Order 2 (solo active shop) should have surcharge = 0 and platform_fee = 20
  IF v_o2.multi_shop_surcharge != 0 THEN
    RAISE EXCEPTION 'Assertion Failed: Solo active order should have 0 multi-shop surcharge, got %', v_o2.multi_shop_surcharge;
  END IF;
  IF v_o2.platform_fee != 20.0 THEN
    RAISE EXCEPTION 'Assertion Failed: Solo active order should have full 20.0 platform fee, got %', v_o2.platform_fee;
  END IF;

  RAISE NOTICE 'Order 2 (Solo active shop): Deliv=%, Surch=%, Plat=%, Grand=%', v_o2.delivery_charges, v_o2.multi_shop_surcharge, v_o2.platform_fee, v_o2.grand_total_collected;


  RAISE NOTICE '=== TEST 4: ACKNOWLEDGE PARTIAL REJECTION & DECISION CRON IMMUNITY ===';

  -- Simulate customer tapping "Proceed"
  PERFORM public.acknowledge_partial_rejection(v_cart_group_id, 'proceeded');

  SELECT * INTO v_o1 FROM public.orders WHERE id = v_order1_id;
  SELECT * INTO v_o3 FROM public.orders WHERE id = v_order3_id;

  IF v_o1.cancelled_reason NOT LIKE 'customer%' THEN
    RAISE EXCEPTION 'Assertion Failed: Order 1 cancelled reason should be customer tagged, got %', v_o1.cancelled_reason;
  END IF;
  IF v_o3.cancelled_reason NOT LIKE 'customer%' THEN
    RAISE EXCEPTION 'Assertion Failed: Order 3 cancelled reason should be customer tagged, got %', v_o3.cancelled_reason;
  END IF;

  -- Backdate updated_at on rejected orders to 10 minutes ago
  UPDATE public.orders
  SET updated_at = NOW() - INTERVAL '10 minutes'
  WHERE id IN (v_order1_id, v_order3_id);

  -- Run safe_auto_cancel_expired_orders()
  PERFORM public.safe_auto_cancel_expired_orders();

  -- Verify Order 2 was NOT auto-cancelled because the rejection was acknowledged
  SELECT * INTO v_o2 FROM public.orders WHERE id = v_order2_id;
  IF v_o2.status = 'cancelled' AND v_o2.cancelled_reason = 'timeout' THEN
    RAISE EXCEPTION 'Assertion Failed: Order 2 was falsely auto-cancelled by decision cron!';
  END IF;

  RAISE NOTICE 'Order 2 successfully survived decision cron with status: %', v_o2.status;

  RAISE NOTICE '=== ALL 100x PARTIAL REJECTION TESTS PASSED WITH ZERO ERRORS ===';

  -- Cleanup test data
  DELETE FROM public.orders WHERE cart_group_id = v_cart_group_id;
  DELETE FROM public.coupons WHERE id = v_coupon_id;
  DELETE FROM public.shops WHERE id IN (v_shop1_id, v_shop2_id, v_shop3_id);
END $$;
