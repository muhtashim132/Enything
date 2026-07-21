-- Additive migration to create test shops and products for all categories
-- These can be deleted safely using the existing delete_test_data.sql script.

DO $$
DECLARE
  v_seller_id uuid := '00000000-0000-0000-0000-919999999997';
  v_category text;
  v_shop_id uuid;
  v_product_id uuid;
  v_categories text[] := ARRAY[
    'Supermarket / Hypermarket', 'Grocery', 'Restaurant', 'Fast Food', 'Bakery',
    'Butcher', 'Fish & Seafood', 'Dairy & Eggs', 'Fruits & Vegs', 'Sweets & Mithai',
    'Beverages', 'Pharmacy', 'Medical Store', 'Electronics', 'Mobile & Repair',
    'Clothing', 'Footwear', 'Jewellery', 'Hardware Store', 'Stationery',
    'Toys & Games', 'Sports', 'Pet Supplies', 'Cosmetics & Beauty', 'Salon & Beauty',
    'Flowers', 'Home Decor', 'Furniture', 'Auto Parts', 'Paan Shop',
    'Tea & Coffee', 'Ice Cream', 'Organic', 'Other'
  ];
  i int;
BEGIN
  -- 1. Ensure the seller exists (just in case)
  INSERT INTO auth.users (
    id, instance_id, email, encrypted_password, email_confirmed_at, 
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at, 
    role
  ) VALUES (
    v_seller_id, '00000000-0000-0000-0000-000000000000', 'mock919999999997@enything.com', 
    extensions.crypt('Dummy123', extensions.gen_salt('bf')), now(), 
    '{"provider":"email","providers":["email"]}', 
    '{"full_name":"Razorpay Seller Reviewer"}', 
    now(), now(), 'authenticated'
  ) ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.profiles (id, full_name, role, phone)
  VALUES (v_seller_id, 'Razorpay Seller Reviewer', 'seller', '+919999999997')
  ON CONFLICT (id) DO NOTHING;

  -- 2. Iterate through categories and create shops and products
  FOREACH v_category IN ARRAY v_categories
  LOOP
    -- Generate shop ID
    v_shop_id := gen_random_uuid();

    -- Insert Shop
    INSERT INTO public.shops (
      id, seller_id, name, category, categories,
      address, location, is_active, is_accepting_orders,
      opening_hours, open_time, close_time
    ) VALUES (
      v_shop_id, v_seller_id, v_category || ' Test Shop', v_category, jsonb_build_array(v_category),
      'Test Address, ' || v_category || ' Street',
      ST_SetSRID(ST_MakePoint(77.2090, 28.6139), 4326)::geography,
      true, true,
      '00:00 - 23:59', '00:00:00', '23:59:59'
    );

    -- Insert 6 Products for the Shop
    FOR i IN 1..6 LOOP
      v_product_id := gen_random_uuid();
      INSERT INTO public.products (
        id, shop_id, name, category, price, is_available,
        total_quantity, unit_type, description, images
      ) VALUES (
        v_product_id, v_shop_id, v_category || ' Test Product ' || i,
        v_category,
        ROUND((RANDOM() * 500 + 50)::numeric, 2),
        true,
        100,
        'pieces',
        'This is a test product for the ' || v_category || ' category.',
        '{}'::jsonb
      );
    END LOOP;
  END LOOP;
END $$;
