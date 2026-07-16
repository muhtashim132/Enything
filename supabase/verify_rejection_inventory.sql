-- =============================================================================
-- TEST: Seller Rejection & Inventory Re-addition
-- Purpose: 
--   1. Simulates an order creation with a specific product.
--   2. Simulates a seller rejecting the order with 'out_of_stock'.
--   3. Validates that the product's is_available flag becomes FALSE.
--   4. Validates that the product's total_quantity is mathematically RESTORED by the statement trigger.
--   5. Validates that the get_order_reorder_data_v3 RPC strictly filters out the product, returning '[]'.
-- =============================================================================

DO $$
DECLARE
  v_customer_id UUID;
  v_seller_id UUID;
  v_shop_id UUID;
  v_product_id UUID;
  v_order_id UUID;
  v_initial_quantity INT := 10;
  v_order_quantity INT := 2;
  v_current_quantity INT;
  v_is_available BOOLEAN;
  v_reorder_data JSON;
BEGIN
  -- 1. Setup Test Data
  -- Find an active customer and seller for simulation
  SELECT id INTO v_customer_id FROM auth.users LIMIT 1;
  IF v_customer_id IS NULL THEN
    RAISE NOTICE 'Skipping test: No auth users found.';
    RETURN;
  END IF;

  v_seller_id := v_customer_id; -- Just use same user as seller for test ease

  -- Create a mock shop
  INSERT INTO shops (id, seller_id, name, is_active, business_status)
  VALUES (gen_random_uuid(), v_seller_id, 'Test Shop 100x', true, 'approved')
  RETURNING id INTO v_shop_id;

  -- Create a mock product
  INSERT INTO products (id, shop_id, name, price, total_quantity, is_available)
  VALUES (gen_random_uuid(), v_shop_id, 'Test Product 100x', 10.0, v_initial_quantity, true)
  RETURNING id INTO v_product_id;

  -- Create a mock order
  INSERT INTO orders (id, customer_id, shop_id, status, grand_total, payment_status, total_amount)
  VALUES (gen_random_uuid(), v_customer_id, v_shop_id, 'pending', 20.0, 'pending', 20.0)
  RETURNING id INTO v_order_id;

  -- Deduct inventory to simulate order placement (since triggers might not deduct on INSERT automatically in test context)
  UPDATE products SET total_quantity = total_quantity - v_order_quantity WHERE id = v_product_id;

  INSERT INTO order_items (id, order_id, product_id, quantity, unit_price, subtotal)
  VALUES (gen_random_uuid(), v_order_id, v_product_id, v_order_quantity, 10.0, 20.0);

  -- Validate state before rejection
  SELECT total_quantity, is_available INTO v_current_quantity, v_is_available 
  FROM products WHERE id = v_product_id;
  
  IF v_current_quantity != (v_initial_quantity - v_order_quantity) THEN
    RAISE EXCEPTION 'Pre-condition failed: Product quantity not correctly deducted.';
  END IF;

  -- 2. Simulate Seller Rejection (out_of_stock)
  -- Temporarily bypass RLS by setting the auth context so the reject_order_seller function passes 'seller_id = auth.uid()' check.
  PERFORM set_config('request.jwt.claims', format('{"sub": "%s"}', v_seller_id), true);
  
  -- Execute the target RPC
  PERFORM reject_order_seller(v_order_id, 'out_of_stock', 'Sorry out of stock');

  -- 3. Validate post-rejection state
  SELECT total_quantity, is_available INTO v_current_quantity, v_is_available 
  FROM products WHERE id = v_product_id;

  IF v_is_available = true THEN
    RAISE EXCEPTION 'TEST FAILED: Product is_available should be false after out_of_stock rejection.';
  END IF;

  IF v_current_quantity != v_initial_quantity THEN
    RAISE EXCEPTION 'TEST FAILED: Product total_quantity was not restored by the trigger! Expected %, got %', v_initial_quantity, v_current_quantity;
  END IF;

  -- 4. Validate reorder RPC behavior
  -- Set auth context to customer
  PERFORM set_config('request.jwt.claims', format('{"sub": "%s"}', v_customer_id), true);
  SELECT get_order_reorder_data_v3(v_order_id) INTO v_reorder_data;

  IF json_array_length(v_reorder_data) > 0 THEN
    RAISE EXCEPTION 'TEST FAILED: Reorder RPC returned products even though they are strictly unavailable! Output: %', v_reorder_data;
  END IF;

  -- 5. Cleanup Test Data (rollback)
  -- Since this is an anonymous block, we can just throw an exception to rollback everything safely.
  RAISE NOTICE '100x TEST PASSED: Inventory flawlessly restored (%). Ghost orders prevented (is_available=false). Reorder cleanly returned empty (%).', v_current_quantity, v_reorder_data;
  RAISE EXCEPTION 'Rolling back test data - Test Successful!';
END;
$$;
