-- Verify Phase 22 logic
DO $$
DECLARE
  v_customer_id uuid;
  v_shop1_id uuid;
  v_shop2_id uuid;
  v_product1_id uuid;
  v_product2_id uuid;
  v_cart_group_id uuid;
  v_order1_id uuid;
  v_order2_id uuid;
  v_orders jsonb;
  v_items jsonb;
  v_rider_id uuid;
  v_rider_earnings1 numeric;
BEGIN
  -- We just need a customer and rider that exist in both auth.users and profiles
  v_customer_id := (SELECT p.id FROM profiles p JOIN auth.users u ON p.id = u.id LIMIT 1);
  v_rider_id := (SELECT p.id FROM profiles p JOIN auth.users u ON p.id = u.id WHERE p.id != v_customer_id LIMIT 1);

  -- 100x FIX: Instead of relying on random existing data, let's CREATE deterministic test data
  v_shop1_id := gen_random_uuid();
  v_shop2_id := gen_random_uuid();
  v_product1_id := gen_random_uuid();
  v_product2_id := gen_random_uuid();
  v_cart_group_id := gen_random_uuid();
  v_order1_id := gen_random_uuid();
  v_order2_id := gen_random_uuid();

  -- Insert fake shops
  INSERT INTO shops (id, seller_id, name, is_active) VALUES (v_shop1_id, v_customer_id, 'Test Shop 1', true);
  INSERT INTO shops (id, seller_id, name, is_active) VALUES (v_shop2_id, v_customer_id, 'Test Shop 2', true);

  -- Insert fake products
  INSERT INTO products (id, shop_id, name, price, is_available) VALUES (v_product1_id, v_shop1_id, 'Item 1', 1000.0, true);
  INSERT INTO products (id, shop_id, name, price, is_available) VALUES (v_product2_id, v_shop2_id, 'Item 2', 1000.0, true);

  -- Create payload for 2 shops
  v_orders := jsonb_build_array(
    jsonb_build_object(
      'id', v_order1_id,
      'shop_id', v_shop1_id,
      'customer_id', v_customer_id,
      'status', 'pending',
      'total_amount', 1000.0,
      'grand_total', 1292.5,
      'platform_fee', 2.5,
      'delivery_charges', 100.0,
      'multi_shop_surcharge', 10.0,
      'small_cart_fee', 0.0,
      'heavy_order_fee', 0.0,
      'coupon_discount', 0.0,
      'payment_method', 'cod',
      'delivery_lat', 0.0,
      'delivery_lng', 0.0,
      'estimated_distance_km', 5.0
    ),
    jsonb_build_object(
      'id', v_order2_id,
      'shop_id', v_shop2_id,
      'customer_id', v_customer_id,
      'status', 'pending',
      'total_amount', 1000.0,
      'grand_total', 1292.5,
      'platform_fee', 2.5,
      'delivery_charges', 100.0,
      'multi_shop_surcharge', 10.0,
      'small_cart_fee', 0.0,
      'heavy_order_fee', 0.0,
      'coupon_discount', 0.0,
      'payment_method', 'cod',
      'delivery_lat', 0.0,
      'delivery_lng', 0.0,
      'estimated_distance_km', 5.0
    )
  );

  v_items := jsonb_build_array(
    jsonb_build_object('order_id', v_order1_id, 'shop_id', v_shop1_id, 'product_id', v_product1_id, 'quantity', 1, 'price', 1000.0),
    jsonb_build_object('order_id', v_order2_id, 'shop_id', v_shop2_id, 'product_id', v_product2_id, 'quantity', 1, 'price', 1000.0)
  );

  -- Mock user session to bypass RLS in place_orders_transaction
  PERFORM set_config('request.jwt.claims', format('{"sub": "%s"}', v_customer_id), true);

  PERFORM place_orders_transaction(v_orders, v_items, v_cart_group_id, NULL, gen_random_uuid()::text, NULL);

  -- 1. Accept both (simulating seller)
  UPDATE orders SET seller_accepted = true, status = 'confirmed' WHERE cart_group_id = v_cart_group_id;
  UPDATE orders SET status = 'preparing' WHERE cart_group_id = v_cart_group_id;
  UPDATE orders SET status = 'ready_for_pickup' WHERE cart_group_id = v_cart_group_id;

  -- 2. Rider accepts both
  UPDATE orders SET delivery_partner_id = v_rider_id, partner_accepted = true WHERE cart_group_id = v_cart_group_id;
  
  -- 3. Rider marks order 1 as picked_up
  UPDATE orders SET status = 'picked_up' WHERE id = v_order1_id;
  
  -- 4. Shop 2 cancels the order (simulating out of stock/support)
  ALTER TABLE orders DISABLE TRIGGER trg_prevent_reject_after_payment;
  UPDATE orders SET status = 'cancelled' WHERE id = v_order2_id;
  ALTER TABLE orders ENABLE TRIGGER trg_prevent_reject_after_payment;
  
  -- Trigger reallocation
  PERFORM reallocate_cancelled_delivery_fees(v_cart_group_id);
  
  -- Check Order 1 Delivery Fee
  SELECT delivery_charges INTO v_rider_earnings1 FROM orders WHERE id = v_order1_id;
  
  -- Rollback test data BEFORE assertion to ensure cleanliness
  DELETE FROM order_items WHERE order_id IN (v_order1_id, v_order2_id);
  DELETE FROM orders WHERE cart_group_id = v_cart_group_id;
  DELETE FROM products WHERE id IN (v_product1_id, v_product2_id);
  DELETE FROM shops WHERE id IN (v_shop1_id, v_shop2_id);

  -- Expected: Original 100 + Cancelled 100 = 200
  RAISE EXCEPTION 'TEST COMPLETED. Final Rider Delivery Fee: %', v_rider_earnings1;

END;
$$;
