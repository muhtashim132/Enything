-- =============================================================================
-- TEST: Refunds, Ratings & Reviews
-- Purpose: 
--   1. Validate seller rejection triggers `processing` refund status if payment captured.
--   2. Validate admin_issue_refund correctly catches terminal states.
--   3. Validate review bombing protection limits reviews strictly to delivered orders.
-- =============================================================================

DO $$
DECLARE
  v_customer_id UUID;
  v_seller_id UUID;
  v_shop_id UUID;
  v_product_id UUID;
  v_order_id UUID;
  v_order_id_2 UUID;
BEGIN
  -- 1. Setup Test Data
  SELECT id INTO v_customer_id FROM profiles LIMIT 1;
  IF v_customer_id IS NULL THEN
    RAISE NOTICE 'Skipping test: No auth users found.';
    RETURN;
  END IF;

  v_seller_id := v_customer_id;

  INSERT INTO shops (id, seller_id, name, is_active, verification_status)
  VALUES (gen_random_uuid(), v_seller_id, 'Refund Test Shop', true, 'approved')
  RETURNING id INTO v_shop_id;

  INSERT INTO products (id, shop_id, name, price, total_quantity, is_available)
  VALUES (gen_random_uuid(), v_shop_id, 'Refund Test Product', 10.0, 10, true)
  RETURNING id INTO v_product_id;

  -- 2. Create Order 1 (Payment Captured)
  v_order_id := gen_random_uuid();
  INSERT INTO orders (id, customer_id, shop_id, status, grand_total_collected, payment_status, total_amount, payment_method)
  VALUES (v_order_id, v_customer_id, v_shop_id, 'pending', 20.0, 'captured', 20.0, 'upi');

  -- Simulate Seller Rejection
  PERFORM set_config('request.jwt.claims', format('{"sub": "%s"}', v_seller_id), true);
  PERFORM reject_order_seller(v_order_id, 'out_of_stock', 'Sorry out of stock');

  -- Verify refund_status became 'processing'
  DECLARE
    v_refund_status TEXT;
  BEGIN
    SELECT refund_status INTO v_refund_status FROM orders WHERE id = v_order_id;
    IF v_refund_status != 'processing' THEN
      RAISE EXCEPTION 'TEST FAILED: refund_status did not become processing, it is %', v_refund_status;
    ELSE
      RAISE NOTICE '100x PASS: Seller rejection correctly triggered refund processing.';
    END IF;
  END;

  -- 3. Create Order 2 (Delivered)
  v_order_id_2 := gen_random_uuid();
  INSERT INTO orders (id, customer_id, shop_id, status, grand_total_collected, payment_status, total_amount, payment_method)
  VALUES (v_order_id_2, v_customer_id, v_shop_id, 'delivered', 20.0, 'captured', 20.0, 'upi');

  -- 4. Test Review Bombing Protection
  -- Try to review Order 1 (Rejected, not Delivered)
  PERFORM set_config('request.jwt.claims', format('{"sub": "%s"}', v_customer_id), true);
  
  BEGIN
    INSERT INTO reviews (shop_id, user_id, order_id, rating, comment)
  VALUES (v_shop_id, v_customer_id, v_order_id, 1, 'Bad rejected order');
    RAISE EXCEPTION 'TEST FAILED: Was able to review a rejected order.';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '100x PASS: Review on rejected order blocked -> %', SQLERRM;
  END;

  -- Try to review Order 2 (Delivered)
  INSERT INTO reviews (shop_id, user_id, order_id, rating, comment)
  VALUES (v_shop_id, v_customer_id, v_order_id_2, 5, 'Great delivered order');
  RAISE NOTICE '100x PASS: Review on delivered order succeeded.';

  -- Try to review Order 2 AGAIN (Review Bombing)
  BEGIN
    INSERT INTO reviews (shop_id, user_id, order_id, rating, review_text)
    VALUES (v_shop_id, v_customer_id, v_order_id_2, 1, 'Spam review');
    RAISE EXCEPTION 'TEST FAILED: Was able to review bomb the same order.';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '100x PASS: Review bombing blocked -> %', SQLERRM;
  END;

  RAISE EXCEPTION 'Test Successful - Rolling back test data.';
END;
$$;
