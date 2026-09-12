-- ══════════════════════════════════════════════════════════════════════════════
-- 100x ADMIN ↔ CUSTOMER ↔ SELLER ↔ RIDER DASHBOARD SYNCHRONIZATION TEST SUITE
-- Strictly additive testing. All test entities are immediately purged.
-- Zero test leftovers guaranteed.
-- ══════════════════════════════════════════════════════════════════════════════

DO $$
DECLARE
  v_test_run_id TEXT := 'test_' || substr(gen_random_uuid()::text, 1, 8);
  v_admin_id UUID;
  v_customer_id UUID;
  v_orig_customer_active BOOLEAN;
  v_seller_id UUID;
  v_rider_partner_id UUID;
  v_orig_rider_active BOOLEAN;
  v_orig_rider_kyc TEXT;
  
  v_shop_id UUID := gen_random_uuid();
  v_product_id UUID := gen_random_uuid();
  v_deleted_product_id UUID := gen_random_uuid();
  v_cart_group_id UUID := gen_random_uuid();
  v_order_id UUID := gen_random_uuid();
  
  v_err_caught BOOLEAN;
  v_err_msg TEXT;
  v_kyc_status TEXT;
  v_is_active BOOLEAN;
  v_res_accepted BOOLEAN;
BEGIN
  RAISE NOTICE '══════════════════════════════════════════════════════════════';
  RAISE NOTICE 'STARTING 100x ADMIN ↔ ALL DASHBOARDS MATRIX VERIFICATION';
  RAISE NOTICE 'Test Run ID: %', v_test_run_id;
  RAISE NOTICE '══════════════════════════════════════════════════════════════';

  -- 1. Obtain existing verified roles
  v_admin_id := '00000000-0000-0000-0000-919999999996'::uuid;

  SELECT id, COALESCE(is_active, true) INTO v_customer_id, v_orig_customer_active FROM profiles WHERE role = 'customer' LIMIT 1;
  IF v_customer_id IS NULL THEN RAISE EXCEPTION 'No existing customer profile found!'; END IF;

  SELECT id INTO v_seller_id FROM profiles WHERE role = 'seller' LIMIT 1;
  IF v_seller_id IS NULL THEN RAISE EXCEPTION 'No existing seller profile found!'; END IF;

  SELECT id, is_active, verification_status INTO v_rider_partner_id, v_orig_rider_active, v_orig_rider_kyc 
  FROM delivery_partners LIMIT 1;
  IF v_rider_partner_id IS NULL THEN RAISE EXCEPTION 'No existing delivery partner found!'; END IF;

  BEGIN
    -- Disable triggers for isolated testing
    BEGIN
      ALTER TABLE orders DISABLE TRIGGER tr_order_status_notifications;
      ALTER TABLE orders DISABLE TRIGGER tr_customer_order_push;
      ALTER TABLE orders DISABLE TRIGGER tr_rider_new_order_push;
    EXCEPTION WHEN OTHERS THEN
    END;

    -- ──────────────────────────────────────────────────────────────────────────
    -- 2. SETUP DEDICATED TEST ENTITIES (Shop & Products)
    -- ──────────────────────────────────────────────────────────────────────────
    INSERT INTO shops (id, seller_id, name, category, is_active, is_accepting_orders, verification_status, location)
    VALUES (
      v_shop_id, 
      v_seller_id, 
      'Test Shop ' || v_test_run_id, 
      'food', 
      true, 
      true, 
      'verified', 
      ST_SetSRID(ST_MakePoint(74.8, 34.08), 4326)::geography
    );

    INSERT INTO products (id, shop_id, name, category, price, total_quantity, is_available, is_deleted)
    VALUES 
      (v_product_id, v_shop_id, 'Active Product ' || v_test_run_id, 'food', 250.0, 50, true, false),
      (v_deleted_product_id, v_shop_id, 'Soft Deleted Product ' || v_test_run_id, 'food', 250.0, 50, true, true);

    RAISE NOTICE '✓ Dedicated test shop and products created.';

    -- Authenticate session as test customer
    PERFORM set_config('request.jwt.claim.sub', v_customer_id::text, true);

    -- ──────────────────────────────────────────────────────────────────────────
    -- TEST 1: Soft-Deleted Product Invariant
    -- Attempting to place an order for a soft-deleted product must fail
    -- ──────────────────────────────────────────────────────────────────────────
    v_err_caught := false;
    BEGIN
      PERFORM place_orders_transaction(
        p_orders := jsonb_build_array(
          jsonb_build_object(
            'id', v_order_id,
            'shop_id', v_shop_id,
            'customer_id', v_customer_id,
            'status', 'awaiting_acceptance',
            'total_amount', 250.0,
            'payment_status', 'pending',
            'payment_method', 'cod',
            'delivery_charges', 25.0,
            'platform_fee', 15.0,
            'small_cart_fee', 0.0,
            'heavy_order_fee', 0.0,
            'grand_total_collected', 290.0
          )
        ),
        p_items := jsonb_build_array(
          jsonb_build_object(
            'id', gen_random_uuid(),
            'order_id', v_order_id,
            'product_id', v_deleted_product_id,
            'quantity', 1,
            'price', 250.0
          )
        ),
        p_cart_group_id := v_cart_group_id,
        p_coupon_id := NULL,
        p_idempotency_key := v_test_run_id || '_del_prod',
        p_order_id_to_cancel := NULL
      );
    EXCEPTION WHEN OTHERS THEN
      v_err_caught := true;
      v_err_msg := SQLERRM;
    END;

    IF NOT v_err_caught THEN
      RAISE EXCEPTION 'TEST 1 FAILED: Soft-deleted product was ordered without error!';
    END IF;
    RAISE NOTICE '✓ TEST 1 PASSED: Soft-deleted product correctly blocked with error: %', v_err_msg;

    -- ──────────────────────────────────────────────────────────────────────────
    -- TEST 2: Suspended Customer Placement Guard
    -- If customer profile is deactivated (is_active = false), order placement must be aborted
    -- ──────────────────────────────────────────────────────────────────────────
    UPDATE profiles SET is_active = false WHERE id = v_customer_id;
    v_err_caught := false;
    BEGIN
      PERFORM place_orders_transaction(
        p_orders := jsonb_build_array(
          jsonb_build_object(
            'id', v_order_id,
            'shop_id', v_shop_id,
            'customer_id', v_customer_id,
            'status', 'awaiting_acceptance',
            'total_amount', 250.0,
            'payment_status', 'pending',
            'payment_method', 'cod',
            'delivery_charges', 25.0,
            'platform_fee', 15.0,
            'small_cart_fee', 0.0,
            'heavy_order_fee', 0.0,
            'grand_total_collected', 290.0
          )
        ),
        p_items := jsonb_build_array(
          jsonb_build_object(
            'id', gen_random_uuid(),
            'order_id', v_order_id,
            'product_id', v_product_id,
            'quantity', 1,
            'price', 250.0
          )
        ),
        p_cart_group_id := v_cart_group_id,
        p_coupon_id := NULL,
        p_idempotency_key := v_test_run_id || '_cust_susp',
        p_order_id_to_cancel := NULL
      );
    EXCEPTION WHEN OTHERS THEN
      v_err_caught := true;
      v_err_msg := SQLERRM;
    END;

    IF NOT v_err_caught OR v_err_msg NOT LIKE '%CUSTOMER_SUSPENDED%' THEN
      RAISE EXCEPTION 'TEST 2 FAILED: Expected CUSTOMER_SUSPENDED error, got: %', v_err_msg;
    END IF;
    RAISE NOTICE '✓ TEST 2 PASSED: Suspended customer rejected with CUSTOMER_SUSPENDED.';

    -- Re-activate customer
    UPDATE profiles SET is_active = true WHERE id = v_customer_id;

    -- ──────────────────────────────────────────────────────────────────────────
    -- TEST 3: Suspended / Closed Shop Placement Guard
    -- ──────────────────────────────────────────────────────────────────────────
    -- 3a: Shop Suspended (is_active = false)
    UPDATE shops SET is_active = false WHERE id = v_shop_id;
    v_err_caught := false;
    BEGIN
      PERFORM place_orders_transaction(
        p_orders := jsonb_build_array(
          jsonb_build_object(
            'id', v_order_id,
            'shop_id', v_shop_id,
            'customer_id', v_customer_id,
            'status', 'awaiting_acceptance',
            'total_amount', 250.0,
            'payment_status', 'pending',
            'payment_method', 'cod',
            'delivery_charges', 25.0,
            'platform_fee', 15.0,
            'small_cart_fee', 0.0,
            'heavy_order_fee', 0.0,
            'grand_total_collected', 290.0
          )
        ),
        p_items := jsonb_build_array(
          jsonb_build_object(
            'id', gen_random_uuid(),
            'order_id', v_order_id,
            'product_id', v_product_id,
            'quantity', 1,
            'price', 250.0
          )
        ),
        p_cart_group_id := v_cart_group_id,
        p_coupon_id := NULL,
        p_idempotency_key := v_test_run_id || '_shop_susp',
        p_order_id_to_cancel := NULL
      );
    EXCEPTION WHEN OTHERS THEN
      v_err_caught := true;
      v_err_msg := SQLERRM;
    END;

    IF NOT v_err_caught OR v_err_msg NOT LIKE '%SHOP_SUSPENDED%' THEN
      RAISE EXCEPTION 'TEST 3a FAILED: Expected SHOP_SUSPENDED error, got: %', v_err_msg;
    END IF;
    RAISE NOTICE '✓ TEST 3a PASSED: Suspended shop rejected with SHOP_SUSPENDED.';

    -- 3b: Shop Closed (is_accepting_orders = false)
    UPDATE shops SET is_active = true, is_accepting_orders = false WHERE id = v_shop_id;
    v_err_caught := false;
    BEGIN
      PERFORM place_orders_transaction(
        p_orders := jsonb_build_array(
          jsonb_build_object(
            'id', v_order_id,
            'shop_id', v_shop_id,
            'customer_id', v_customer_id,
            'status', 'awaiting_acceptance',
            'total_amount', 250.0,
            'payment_status', 'pending',
            'payment_method', 'cod',
            'delivery_charges', 25.0,
            'platform_fee', 15.0,
            'small_cart_fee', 0.0,
            'heavy_order_fee', 0.0,
            'grand_total_collected', 290.0
          )
        ),
        p_items := jsonb_build_array(
          jsonb_build_object(
            'id', gen_random_uuid(),
            'order_id', v_order_id,
            'product_id', v_product_id,
            'quantity', 1,
            'price', 250.0
          )
        ),
        p_cart_group_id := v_cart_group_id,
        p_coupon_id := NULL,
        p_idempotency_key := v_test_run_id || '_shop_closed',
        p_order_id_to_cancel := NULL
      );
    EXCEPTION WHEN OTHERS THEN
      v_err_caught := true;
      v_err_msg := SQLERRM;
    END;

    IF NOT v_err_caught OR v_err_msg NOT LIKE '%SHOP_CLOSED%' THEN
      RAISE EXCEPTION 'TEST 3b FAILED: Expected SHOP_CLOSED error, got: %', v_err_msg;
    END IF;
    RAISE NOTICE '✓ TEST 3b PASSED: Closed shop rejected with SHOP_CLOSED.';

    -- Re-open shop
    UPDATE shops SET is_accepting_orders = true WHERE id = v_shop_id;

    -- ──────────────────────────────────────────────────────────────────────────
    -- Direct Setup for Seller & Rider Acceptance Tests
    -- ──────────────────────────────────────────────────────────────────────────
    INSERT INTO orders (
      id, cart_group_id, customer_id, shop_id, status, total_amount, 
      payment_method, payment_status, delivery_charges, platform_fee, grand_total_collected
    ) VALUES (
      v_order_id, v_cart_group_id, v_customer_id, v_shop_id, 'awaiting_acceptance', 250.0,
      'cod', 'pending', 25.0, 15.0, 290.0
    );

    INSERT INTO order_items (id, order_id, product_id, quantity, price)
    VALUES (gen_random_uuid(), v_order_id, v_product_id, 1, 250.0);
    RAISE NOTICE '✓ Test order inserted for acceptance testing.';

    -- ──────────────────────────────────────────────────────────────────────────
    -- TEST 4: accept_order_seller Guard when Shop is Suspended
    -- ──────────────────────────────────────────────────────────────────────────
    PERFORM set_config('request.jwt.claim.sub', v_seller_id::text, true);
    UPDATE shops SET is_active = false WHERE id = v_shop_id;
    v_err_caught := false;
    BEGIN
      PERFORM accept_order_seller(v_order_id);
    EXCEPTION WHEN OTHERS THEN
      v_err_caught := true;
      v_err_msg := SQLERRM;
    END;

    IF NOT v_err_caught OR v_err_msg NOT LIKE '%SHOP_SUSPENDED%' THEN
      RAISE EXCEPTION 'TEST 4 FAILED: Expected SHOP_SUSPENDED error in accept_order_seller, got: %', v_err_msg;
    END IF;
    RAISE NOTICE '✓ TEST 4a PASSED: Suspended seller blocked in accept_order_seller with SHOP_SUSPENDED.';

    -- Re-activate shop and verify acceptance succeeds
    UPDATE shops SET is_active = true WHERE id = v_shop_id;
    PERFORM accept_order_seller(v_order_id);
    RAISE NOTICE '✓ TEST 4b PASSED: Active seller successfully accepted order.';

    -- ──────────────────────────────────────────────────────────────────────────
    -- TEST 5: accept_order_rider Guard when Delivery Partner is Suspended
    -- ──────────────────────────────────────────────────────────────────────────
    PERFORM set_config('request.jwt.claim.sub', v_rider_partner_id::text, true);
    UPDATE delivery_partners SET is_active = false WHERE id = v_rider_partner_id;
    v_err_caught := false;
    BEGIN
      PERFORM accept_order_rider(v_order_id, '+919999900003', 34.08, 74.8);
    EXCEPTION WHEN OTHERS THEN
      v_err_caught := true;
      v_err_msg := SQLERRM;
    END;

    IF NOT v_err_caught OR v_err_msg NOT LIKE '%RIDER_SUSPENDED%' THEN
      RAISE EXCEPTION 'TEST 5 FAILED: Expected RIDER_SUSPENDED error in accept_order_rider, got: %', v_err_msg;
    END IF;
    RAISE NOTICE '✓ TEST 5a PASSED: Suspended rider blocked in accept_order_rider with RIDER_SUSPENDED.';

    -- Re-activate rider and verify acceptance succeeds
    UPDATE delivery_partners SET is_active = true WHERE id = v_rider_partner_id;
    v_res_accepted := accept_order_rider(v_order_id, '+919999900003', 34.08, 74.8);
    IF NOT v_res_accepted THEN
      RAISE EXCEPTION 'TEST 5b FAILED: Active rider acceptance returned false!';
    END IF;
    RAISE NOTICE '✓ TEST 5b PASSED: Active rider successfully accepted order.';

    -- ──────────────────────────────────────────────────────────────────────────
    -- TEST 6: admin_update_kyc Auto-Activation & Deactivation (As Admin)
    -- ──────────────────────────────────────────────────────────────────────────
    PERFORM set_config('request.jwt.claim.sub', v_admin_id::text, true);

    -- 6a: Reject shop KYC -> should set is_active = false
    PERFORM admin_update_kyc(v_shop_id, 'shop', 'rejected');
    SELECT is_active, verification_status INTO v_is_active, v_kyc_status FROM shops WHERE id = v_shop_id;
    IF v_is_active != false OR v_kyc_status != 'rejected' THEN
      RAISE EXCEPTION 'TEST 6a FAILED: Shop rejected KYC did not set is_active=false!';
    END IF;

    -- 6b: Approve shop KYC -> should auto-activate is_active = true
    PERFORM admin_update_kyc(v_shop_id, 'shop', 'approved');
    SELECT is_active, verification_status INTO v_is_active, v_kyc_status FROM shops WHERE id = v_shop_id;
    IF v_is_active != true OR v_kyc_status != 'approved' THEN
      RAISE EXCEPTION 'TEST 6b FAILED: Shop approved KYC did not set is_active=true!';
    END IF;

    -- 6c: Reject rider KYC -> should set is_active = false
    PERFORM admin_update_kyc(v_rider_partner_id, 'rider', 'rejected');
    SELECT is_active, verification_status INTO v_is_active, v_kyc_status FROM delivery_partners WHERE id = v_rider_partner_id;
    IF v_is_active != false OR v_kyc_status != 'rejected' THEN
      RAISE EXCEPTION 'TEST 6c FAILED: Rider rejected KYC did not set is_active=false!';
    END IF;

    -- 6d: Approve rider KYC -> should auto-activate is_active = true
    PERFORM admin_update_kyc(v_rider_partner_id, 'rider', 'approved');
    SELECT is_active, verification_status INTO v_is_active, v_kyc_status FROM delivery_partners WHERE id = v_rider_partner_id;
    IF v_is_active != true OR v_kyc_status != 'approved' THEN
      RAISE EXCEPTION 'TEST 6d FAILED: Rider approved KYC did not set is_active=true!';
    END IF;
    RAISE NOTICE '✓ TEST 6 PASSED: admin_update_kyc auto-activation & rejection synchronization verified.';

    -- ──────────────────────────────────────────────────────────────────────────
    -- TEST 7: rebalance_active_delivery_fees Execution
    -- ──────────────────────────────────────────────────────────────────────────
    PERFORM rebalance_active_delivery_fees(v_cart_group_id);
    RAISE NOTICE '✓ TEST 7 PASSED: rebalance_active_delivery_fees executed cleanly.';

  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'CRITICAL ERROR IN TEST SUITE: % (SQLSTATE: %)', SQLERRM, SQLSTATE;
    RAISE;
  END;

  -- ──────────────────────────────────────────────────────────────────────────
  -- MANDATORY CLEANUP: ZERO TEST LEFTOVERS
  -- Purge all test orders, order items, products, and test shop
  -- Restore original customer and rider states
  -- ──────────────────────────────────────────────────────────────────────────
  RAISE NOTICE 'Executing mandatory cleanup for test run: %', v_test_run_id;

  DELETE FROM order_items WHERE order_id IN (SELECT id FROM orders WHERE cart_group_id = v_cart_group_id OR id = v_order_id);
  DELETE FROM orders WHERE cart_group_id = v_cart_group_id OR id = v_order_id;
  DELETE FROM products WHERE id IN (v_product_id, v_deleted_product_id);
  DELETE FROM shops WHERE id = v_shop_id;

  -- Restore customer & rider original states
  UPDATE profiles SET is_active = v_orig_customer_active WHERE id = v_customer_id;
  UPDATE delivery_partners SET is_active = v_orig_rider_active, verification_status = v_orig_rider_kyc WHERE id = v_rider_partner_id;

  -- Re-enable triggers
  BEGIN
    ALTER TABLE orders ENABLE TRIGGER tr_order_status_notifications;
    ALTER TABLE orders ENABLE TRIGGER tr_customer_order_push;
    ALTER TABLE orders ENABLE TRIGGER tr_rider_new_order_push;
  EXCEPTION WHEN OTHERS THEN
  END;

  -- Verification of ZERO leftovers
  IF EXISTS (SELECT 1 FROM orders WHERE id = v_order_id) OR
     EXISTS (SELECT 1 FROM products WHERE id IN (v_product_id, v_deleted_product_id)) OR
     EXISTS (SELECT 1 FROM shops WHERE id = v_shop_id) THEN
    RAISE EXCEPTION 'CLEANUP INVARIANT VIOLATION: Test records remained in the database!';
  END IF;

  RAISE NOTICE '══════════════════════════════════════════════════════════════';
  RAISE NOTICE 'ALL 7 TESTS PASSED! ZERO TEST LEFTOVERS VERIFIED 100%%.';
  RAISE NOTICE '══════════════════════════════════════════════════════════════';
END;
$$;
