-- 100x Definitive Database Cleanup: Remove all test shops, mock products, reviewer accounts, and magic auto-accept RPC

DO $$
BEGIN
  -- 1. Drop magic reviewer auto-accept RPC function
  DROP FUNCTION IF EXISTS public.magic_reviewer_auto_accept(uuid[]);
  DROP FUNCTION IF EXISTS public.magic_reviewer_auto_accept(UUID[]);

  -- 2. Create temporary table of test shop IDs
  CREATE TEMP TABLE temp_test_shop_ids AS
  SELECT id FROM public.shops
  WHERE name ILIKE 'Amit Medical Store%'
     OR name ILIKE 'Test Shop%'
     OR name ILIKE 'CustomerTestShop_%'
     OR name ILIKE 'SellerShop_+919733333%'
     OR name ILIKE 'Shop_+919722222%'
     OR name ILIKE 'Shop_+919622222%'
     OR name ILIKE 'Shop_+919422222%'
     OR name ILIKE 'Shop +918888887%'
     OR name ILIKE 'Finance Test Shop%'
     OR name = 'bsbsnd';

  -- 3. Create temporary table of test product IDs
  CREATE TEMP TABLE temp_test_product_ids AS
  SELECT id FROM public.products
  WHERE shop_id IN (SELECT id FROM temp_test_shop_ids)
     OR name ILIKE 'Test Item%'
     OR name ILIKE 'Test Item Shop%'
     OR name ILIKE 'Stock Test%'
     OR name ILIKE 'Refund Test Item%'
     OR name ILIKE 'Item S1%'
     OR name ILIKE 'Item S2%';

  -- 4. Create temporary table of test user IDs
  CREATE TEMP TABLE temp_test_user_ids AS
  SELECT id FROM public.profiles
  WHERE phone LIKE '+9199999%'
     OR phone LIKE '99999%'
     OR phone LIKE '+919744444%'
     OR phone LIKE '+919644444%'
     OR phone LIKE '+919733333%'
     OR phone LIKE '+919722222%'
     OR phone LIKE '+919622222%'
     OR phone LIKE '+919422222%'
     OR phone LIKE '+918888887%'
     OR id = '00000000-0000-0000-0000-919999999996'
     OR id = '00000000-0000-0000-0000-919999999997'
     OR id = '00000000-0000-0000-0000-919999999998'
     OR id = '00000000-0000-0000-0000-919999999991'
     OR id = '00000000-0000-0000-0000-919999999992'
     OR id = '00000000-0000-0000-0000-919999999993'
     OR id = '00000000-0000-0000-0000-919999999994'
     OR id = '00000000-0000-0000-0000-919999999995';

  -- 5. Delete dependent reviews & ratings
  DELETE FROM public.reviews WHERE shop_id IN (SELECT id FROM temp_test_shop_ids);
  DELETE FROM public.reviews WHERE product_id IN (SELECT id FROM temp_test_product_ids);
  DELETE FROM public.reviews WHERE customer_id IN (SELECT id FROM temp_test_user_ids);
  DELETE FROM public.reviews WHERE order_id IN (
    SELECT id FROM public.orders WHERE shop_id IN (SELECT id FROM temp_test_shop_ids)
                                    OR customer_id IN (SELECT id FROM temp_test_user_ids)
  );

  -- 6. Delete dependent order items
  DELETE FROM public.order_items WHERE product_id IN (SELECT id FROM temp_test_product_ids);
  DELETE FROM public.order_items WHERE order_id IN (
    SELECT id FROM public.orders WHERE shop_id IN (SELECT id FROM temp_test_shop_ids)
                                    OR customer_id IN (SELECT id FROM temp_test_user_ids)
  );

  -- 7. Delete dependent orders
  DELETE FROM public.orders WHERE shop_id IN (SELECT id FROM temp_test_shop_ids);
  DELETE FROM public.orders WHERE customer_id IN (SELECT id FROM temp_test_user_ids);
  DELETE FROM public.orders WHERE partner_id IN (SELECT id FROM temp_test_user_ids);

  -- 8. Delete dependent cart items
  DELETE FROM public.cart_items WHERE product_id IN (SELECT id FROM temp_test_product_ids);
  DELETE FROM public.cart_items WHERE user_id IN (SELECT id FROM temp_test_user_ids);

  -- 9. Delete dependent favorites & addresses
  DELETE FROM public.favorite_shops WHERE shop_id IN (SELECT id FROM temp_test_shop_ids);
  DELETE FROM public.favorite_shops WHERE user_id IN (SELECT id FROM temp_test_user_ids);
  DELETE FROM public.favorite_products WHERE product_id IN (SELECT id FROM temp_test_product_ids);
  DELETE FROM public.favorite_products WHERE user_id IN (SELECT id FROM temp_test_user_ids);
  DELETE FROM public.saved_addresses WHERE user_id IN (SELECT id FROM temp_test_user_ids);

  -- 10. Delete shop operating hours & coupons for test shops
  DELETE FROM public.shop_operating_hours WHERE shop_id IN (SELECT id FROM temp_test_shop_ids);
  DELETE FROM public.coupons WHERE shop_id IN (SELECT id FROM temp_test_shop_ids);

  -- 11. Delete test products & test shops
  DELETE FROM public.products WHERE id IN (SELECT id FROM temp_test_product_ids);
  DELETE FROM public.shops WHERE id IN (SELECT id FROM temp_test_shop_ids);

  -- 12. Delete role-specific test rows
  DELETE FROM public.customers WHERE id IN (SELECT id FROM temp_test_user_ids);
  DELETE FROM public.delivery_partners WHERE id IN (SELECT id FROM temp_test_user_ids);
  DELETE FROM public.admin_users WHERE id IN (SELECT id FROM temp_test_user_ids);
  DELETE FROM public.profiles WHERE id IN (SELECT id FROM temp_test_user_ids);

  -- Drop temporary tables
  DROP TABLE IF EXISTS temp_test_shop_ids;
  DROP TABLE IF EXISTS temp_test_product_ids;
  DROP TABLE IF EXISTS temp_test_user_ids;

  RAISE NOTICE '100x test cleanup migration executed successfully.';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Error during test cleanup: %', SQLERRM;
END $$;
