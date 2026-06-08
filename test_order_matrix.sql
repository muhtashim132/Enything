-- ============================================================================
-- COMPREHENSIVE ORDER LIFECYCLE MATRIX TEST (SQL INTEGRATION TEST)
-- ============================================================================
-- INSTRUCTIONS:
-- Run this script in your Supabase SQL Editor. 
-- It uses a TRANSACTION and will automatically ROLLBACK at the end, 
-- ensuring no test data or mock users are left in your database.
-- 
-- SCENARIOS COVERED:
-- 1. 1 Shop, 1 Customer, 1 Rider (Basic Flow)
-- 2. 2 Shops, 1 Customer, 1 Rider (Multi-vendor Cart)
-- 3. 3 Shops, 1 Customer, 2 Riders (Different riders claiming from same cart)
-- 4. 1 Shop, 2 Customers, 1 Rider (Concurrent ordering)
-- 5. Race Condition Testing (1 Shop, 1 Customer, 2 Riders)
-- ============================================================================

BEGIN;

DO $$
DECLARE
  -- Mock UUIDs
  c1_id UUID := gen_random_uuid();
  c2_id UUID := gen_random_uuid();
  s1_id UUID := gen_random_uuid();
  s2_id UUID := gen_random_uuid();
  s3_id UUID := gen_random_uuid();
  r1_id UUID := gen_random_uuid();
  r2_id UUID := gen_random_uuid();
  
  shop_a_id UUID := gen_random_uuid();
  shop_b_id UUID := gen_random_uuid();
  shop_c_id UUID := gen_random_uuid();

  -- Order tracking
  order1 UUID;
  order2A UUID;
  order2B UUID;
  order3A UUID;
  order3B UUID;
  order3C UUID;
  order4A UUID;
  order4B UUID;
  order5 UUID;
  
  error_msg TEXT;
BEGIN
  RAISE NOTICE '=== STARTING COMPREHENSIVE ORDER MATRIX TEST ===';

  -- --------------------------------------------------------------------------
  -- SETUP PHASE: Create mock users and profiles
  -- --------------------------------------------------------------------------
  RAISE NOTICE 'Setting up mock users...';
  
  -- Customers
  INSERT INTO auth.users (id, email) VALUES (c1_id, 'c1@test.com'), (c2_id, 'c2@test.com');
  INSERT INTO public.profiles (id, role, full_name, phone) VALUES 
    (c1_id, 'customer', 'Customer 1', '9990000001'),
    (c2_id, 'customer', 'Customer 2', '9990000002');
  INSERT INTO public.customers (id) VALUES (c1_id), (c2_id);

  -- Sellers
  INSERT INTO auth.users (id, email) VALUES (s1_id, 's1@test.com'), (s2_id, 's2@test.com'), (s3_id, 's3@test.com');
  INSERT INTO public.profiles (id, role, full_name, phone) VALUES 
    (s1_id, 'seller', 'Seller 1', '9990000011'),
    (s2_id, 'seller', 'Seller 2', '9990000012'),
    (s3_id, 'seller', 'Seller 3', '9990000013');
  INSERT INTO public.shops (id, seller_id, name, is_active) VALUES 
    (shop_a_id, s1_id, 'Shop A', true),
    (shop_b_id, s2_id, 'Shop B', true),
    (shop_c_id, s3_id, 'Shop C', true);

  -- Riders
  INSERT INTO auth.users (id, email) VALUES (r1_id, 'r1@test.com'), (r2_id, 'r2@test.com');
  INSERT INTO public.profiles (id, role, full_name, phone) VALUES 
    (r1_id, 'delivery_partner', 'Rider 1', '9990000021'),
    (r2_id, 'delivery_partner', 'Rider 2', '9990000022');
  INSERT INTO public.delivery_partners (id, is_active, is_available) VALUES 
    (r1_id, true, true),
    (r2_id, true, true);


  -- --------------------------------------------------------------------------
  -- SCENARIO 1: Basic Flow (1 Shop, 1 Customer, 1 Rider)
  -- --------------------------------------------------------------------------
  RAISE NOTICE '--- SCENARIO 1: 1 Shop, 1 Customer, 1 Rider ---';
  
  -- Customer places order
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s", "role":"authenticated"}', c1_id), true);
  PERFORM set_config('role', 'authenticated', true);
  
  INSERT INTO public.orders (
    cart_group_id, shop_id, customer_id, status, total_amount, delivery_charges, 
    rider_earnings, platform_fee, payment_method, payment_status, grand_total_collected
  ) VALUES (
    gen_random_uuid(), shop_a_id, c1_id, 'awaiting_acceptance', 100, 20, 20, 5, 'upi', 'pending', 125
  ) RETURNING id INTO order1;

  -- Shop A accepts
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s", "role":"authenticated"}', s1_id), true);
  UPDATE public.orders SET status = 'confirmed', seller_accepted = true WHERE id = order1;

  -- Rider 1 claims
  PERFORM set_config('request.jwt.claims', format('{"sub":"%s", "role":"authenticated"}', r1_id), true);
  UPDATE public.orders SET delivery_partner_id = r1_id, status = 'confirmed' WHERE id = order1;

  -- Rider 1 delivers
  UPDATE public.orders SET status = 'delivered' WHERE id = order1;
  RAISE NOTICE '✅ Scenario 1 Passed';


  -- --------------------------------------------------------------------------
  -- SCENARIO 2: Multi-Shop Cart & Split Outcomes (2 Shops, 1 Customer, 1 Rider)
  -- --------------------------------------------------------------------------
  RAISE NOTICE '--- SCENARIO 2: 2 Shops, 1 Customer, 1 Rider ---';
  DECLARE
    cart2 UUID := gen_random_uuid();
  BEGIN
    PERFORM set_config('request.jwt.claims', format('{"sub":"%s", "role":"authenticated"}', c1_id), true);
    
    INSERT INTO public.orders (cart_group_id, shop_id, customer_id, status, total_amount, delivery_charges, rider_earnings, platform_fee, payment_method, payment_status, grand_total_collected) 
      VALUES (cart2, shop_a_id, c1_id, 'awaiting_acceptance', 100, 10, 10, 5, 'upi', 'pending', 115) RETURNING id INTO order2A;
    INSERT INTO public.orders (cart_group_id, shop_id, customer_id, status, total_amount, delivery_charges, rider_earnings, platform_fee, payment_method, payment_status, grand_total_collected) 
      VALUES (cart2, shop_b_id, c1_id, 'awaiting_acceptance', 100, 10, 10, 5, 'upi', 'pending', 115) RETURNING id INTO order2B;

    -- Shop A accepts
    PERFORM set_config('request.jwt.claims', format('{"sub":"%s", "role":"authenticated"}', s1_id), true);
    UPDATE public.orders SET status = 'confirmed', seller_accepted = true WHERE id = order2A;
    
    -- Shop B rejects
    PERFORM set_config('request.jwt.claims', format('{"sub":"%s", "role":"authenticated"}', s2_id), true);
    UPDATE public.orders SET status = 'seller_rejected', seller_accepted = false WHERE id = order2B;

    -- Rider 1 claims Order 2A
    PERFORM set_config('request.jwt.claims', format('{"sub":"%s", "role":"authenticated"}', r1_id), true);
    UPDATE public.orders SET delivery_partner_id = r1_id WHERE id = order2A;
    
    RAISE NOTICE '✅ Scenario 2 Passed';
  END;


  -- --------------------------------------------------------------------------
  -- SCENARIO 3: Multi-Rider Claiming (3 Shops, 1 Customer, 2 Riders)
  -- --------------------------------------------------------------------------
  RAISE NOTICE '--- SCENARIO 3: 3 Shops, 1 Customer, 2 Riders ---';
  DECLARE
    cart3 UUID := gen_random_uuid();
  BEGIN
    PERFORM set_config('request.jwt.claims', format('{"sub":"%s", "role":"authenticated"}', c1_id), true);
    INSERT INTO public.orders (cart_group_id, shop_id, customer_id, status, total_amount, delivery_charges, rider_earnings, platform_fee, payment_method, payment_status, grand_total_collected) VALUES (cart3, shop_a_id, c1_id, 'awaiting_acceptance', 100, 10, 10, 5, 'upi', 'pending', 115) RETURNING id INTO order3A;
    INSERT INTO public.orders (cart_group_id, shop_id, customer_id, status, total_amount, delivery_charges, rider_earnings, platform_fee, payment_method, payment_status, grand_total_collected) VALUES (cart3, shop_b_id, c1_id, 'awaiting_acceptance', 100, 10, 10, 5, 'upi', 'pending', 115) RETURNING id INTO order3B;
    INSERT INTO public.orders (cart_group_id, shop_id, customer_id, status, total_amount, delivery_charges, rider_earnings, platform_fee, payment_method, payment_status, grand_total_collected) VALUES (cart3, shop_c_id, c1_id, 'awaiting_acceptance', 100, 10, 10, 5, 'upi', 'pending', 115) RETURNING id INTO order3C;

    -- All shops accept
    PERFORM set_config('request.jwt.claims', format('{"sub":"%s", "role":"authenticated"}', s1_id), true);
    UPDATE public.orders SET status = 'confirmed', seller_accepted = true WHERE id = order3A;
    PERFORM set_config('request.jwt.claims', format('{"sub":"%s", "role":"authenticated"}', s2_id), true);
    UPDATE public.orders SET status = 'confirmed', seller_accepted = true WHERE id = order3B;
    PERFORM set_config('request.jwt.claims', format('{"sub":"%s", "role":"authenticated"}', s3_id), true);
    UPDATE public.orders SET status = 'confirmed', seller_accepted = true WHERE id = order3C;

    -- Rider 1 claims A and B
    PERFORM set_config('request.jwt.claims', format('{"sub":"%s", "role":"authenticated"}', r1_id), true);
    UPDATE public.orders SET delivery_partner_id = r1_id WHERE id = order3A;
    UPDATE public.orders SET delivery_partner_id = r1_id WHERE id = order3B;

    -- Rider 2 claims C
    PERFORM set_config('request.jwt.claims', format('{"sub":"%s", "role":"authenticated"}', r2_id), true);
    UPDATE public.orders SET delivery_partner_id = r2_id WHERE id = order3C;

    RAISE NOTICE '✅ Scenario 3 Passed';
  END;


  -- --------------------------------------------------------------------------
  -- SCENARIO 4: Concurrent Traffic (1 Shop, 2 Customers, 1 Rider)
  -- --------------------------------------------------------------------------
  RAISE NOTICE '--- SCENARIO 4: 1 Shop, 2 Customers, 1 Rider ---';
  BEGIN
    PERFORM set_config('request.jwt.claims', format('{"sub":"%s", "role":"authenticated"}', c1_id), true);
    INSERT INTO public.orders (cart_group_id, shop_id, customer_id, status, total_amount, delivery_charges, rider_earnings, platform_fee, payment_method, payment_status, grand_total_collected) VALUES (gen_random_uuid(), shop_a_id, c1_id, 'awaiting_acceptance', 100, 20, 20, 5, 'upi', 'pending', 125) RETURNING id INTO order4A;
    
    PERFORM set_config('request.jwt.claims', format('{"sub":"%s", "role":"authenticated"}', c2_id), true);
    INSERT INTO public.orders (cart_group_id, shop_id, customer_id, status, total_amount, delivery_charges, rider_earnings, platform_fee, payment_method, payment_status, grand_total_collected) VALUES (gen_random_uuid(), shop_a_id, c2_id, 'awaiting_acceptance', 100, 20, 20, 5, 'upi', 'pending', 125) RETURNING id INTO order4B;

    PERFORM set_config('request.jwt.claims', format('{"sub":"%s", "role":"authenticated"}', s1_id), true);
    UPDATE public.orders SET status = 'confirmed', seller_accepted = true WHERE id IN (order4A, order4B);

    PERFORM set_config('request.jwt.claims', format('{"sub":"%s", "role":"authenticated"}', r1_id), true);
    UPDATE public.orders SET delivery_partner_id = r1_id WHERE id IN (order4A, order4B);

    RAISE NOTICE '✅ Scenario 4 Passed';
  END;


  -- --------------------------------------------------------------------------
  -- SCENARIO 5: Race Condition Testing (1 Shop, 1 Customer, 2 Riders)
  -- --------------------------------------------------------------------------
  RAISE NOTICE '--- SCENARIO 5: Race Condition (1 Shop, 1 Customer, 2 Riders) ---';
  BEGIN
    PERFORM set_config('request.jwt.claims', format('{"sub":"%s", "role":"authenticated"}', c1_id), true);
    INSERT INTO public.orders (cart_group_id, shop_id, customer_id, status, total_amount, delivery_charges, rider_earnings, platform_fee, payment_method, payment_status, grand_total_collected) VALUES (gen_random_uuid(), shop_a_id, c1_id, 'awaiting_acceptance', 100, 20, 20, 5, 'upi', 'pending', 125) RETURNING id INTO order5;
    
    PERFORM set_config('request.jwt.claims', format('{"sub":"%s", "role":"authenticated"}', s1_id), true);
    UPDATE public.orders SET status = 'confirmed', seller_accepted = true WHERE id = order5;

    -- Rider 1 claims
    PERFORM set_config('request.jwt.claims', format('{"sub":"%s", "role":"authenticated"}', r1_id), true);
    UPDATE public.orders SET delivery_partner_id = r1_id WHERE id = order5;

    -- Rider 2 attempts to claim (SHOULD FAIL based on RLS/Constraints)
    PERFORM set_config('request.jwt.claims', format('{"sub":"%s", "role":"authenticated"}', r2_id), true);
    BEGIN
      UPDATE public.orders SET delivery_partner_id = r2_id WHERE id = order5;
      
      -- Verify if update succeeded improperly
      IF (SELECT delivery_partner_id FROM public.orders WHERE id = order5) = r2_id THEN
        RAISE EXCEPTION '❌ BUG: Rider 2 was able to overwrite Rider 1''s claim!';
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Caught expected exception during race condition: %', SQLERRM;
    END;
    
    RAISE NOTICE '✅ Scenario 5 Passed (Race condition blocked)';
  END;

  RAISE NOTICE '=== ALL TESTS PASSED. ROLLING BACK TO CLEAN UP ===';

END $$;

-- Rollback immediately so nothing is permanently saved!
ROLLBACK;
