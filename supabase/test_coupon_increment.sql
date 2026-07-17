BEGIN;
DO $DO$
DECLARE
  v_coupon_id UUID := gen_random_uuid();
  v_cart_group_id UUID := gen_random_uuid();
  v_customer_id UUID;
  v_shop_id UUID;
  v_count INT;
BEGIN
  -- Setup dummy data
  SELECT id INTO v_customer_id FROM profiles LIMIT 1;
  SELECT id INTO v_shop_id FROM shops LIMIT 1;
  
  INSERT INTO coupons (id, code, discount_type, discount_value, min_order_amount, is_active)
  VALUES (v_coupon_id, 'TESTCOUPON1', 'percentage', 10, 0, true);

  -- Insert order simulating place_orders_transaction
  INSERT INTO orders (id, customer_id, shop_id, total_amount, status, payment_status, payment_method, cart_group_id, coupon_id)
  VALUES (gen_random_uuid(), v_customer_id, v_shop_id, 100, 'pending', 'pending', 'cod', v_cart_group_id, v_coupon_id);

  -- The exact logic from the codebase
  IF NOT EXISTS (
    SELECT 1 FROM orders 
    WHERE cart_group_id = v_cart_group_id 
      AND coupon_id = v_coupon_id
      AND status NOT IN ('cancelled', 'seller_rejected', 'verification_failed', 'timeout', 'payment_failed', 'shop_dispute_cancel')
  ) THEN
    UPDATE coupons SET usage_count = usage_count + 1 WHERE id = v_coupon_id;
  END IF;

  SELECT usage_count INTO v_count FROM coupons WHERE id = v_coupon_id;
  RAISE EXCEPTION 'Coupon usage count after logic: %', v_count;
END;
$DO$;
ROLLBACK;
