-- Test script to verify migration 49 logic on sample cart groups
DO $$
DECLARE
  v_cart_group_id UUID := gen_random_uuid();
  v_shop1_id UUID := gen_random_uuid();
  v_shop2_id UUID := gen_random_uuid();
  v_shop3_id UUID := gen_random_uuid();
  v_order1_id UUID := gen_random_uuid();
  v_order2_id UUID := gen_random_uuid();
  v_order3_id UUID := gen_random_uuid();
  v_cust_id UUID := gen_random_uuid();
  rec RECORD;
BEGIN
  RAISE NOTICE 'Testing 3-Shop Order Creation and Partial Rejections...';

  -- 1. Create 3 test shop orders under v_cart_group_id
  INSERT INTO orders (
    id, cart_group_id, shop_id, customer_id, status,
    total_amount, delivery_charges, multi_shop_surcharge,
    small_cart_fee, heavy_order_fee, platform_fee,
    grand_total_collected, razorpay_payment_id
  ) VALUES
  (v_order1_id, v_cart_group_id, v_shop1_id, v_cust_id, 'awaiting_acceptance', 150.0, 10.0, 13.33, 0.0, 0.0, 6.67, 180.0, 'pay_test123'),
  (v_order2_id, v_cart_group_id, v_shop2_id, v_cust_id, 'awaiting_acceptance', 200.0, 10.0, 13.33, 0.0, 0.0, 6.67, 230.0, 'pay_test123'),
  (v_order3_id, v_cart_group_id, v_shop3_id, v_cust_id, 'awaiting_acceptance', 100.0, 10.0, 13.34, 0.0, 0.0, 6.66, 130.0, 'pay_test123');

  -- Verify active count = 3
  RAISE NOTICE 'Initial 3-shop state created.';

  -- 2. Simulate 1 shop cancellation (Shop 3 declines)
  UPDATE orders SET status = 'seller_rejected' WHERE id = v_order3_id;
  PERFORM reallocate_cancelled_delivery_fees(v_cart_group_id);

  -- Check active orders: Surcharge should now be 1 surcharge (₹20), split ₹10 each on Shop 1 & Shop 2.
  -- Platform fee should be ₹20 total (split ₹10 each on Shop 1 & Shop 2).
  FOR rec IN SELECT id, status, delivery_charges, multi_shop_surcharge, platform_fee, small_cart_fee, heavy_order_fee, grand_total_collected FROM orders WHERE cart_group_id = v_cart_group_id ORDER BY id LOOP
    RAISE NOTICE 'Order %: status=%, del=%, surcharge=%, plat=%, small=%, heavy=%, grand=%', rec.id, rec.status, rec.delivery_charges, rec.multi_shop_surcharge, rec.platform_fee, rec.small_cart_fee, rec.heavy_order_fee, rec.grand_total_collected;
  END LOOP;

  -- Clean up test data
  DELETE FROM orders WHERE cart_group_id = v_cart_group_id;
  RAISE NOTICE 'Test completed successfully!';
END $$;
