-- ============================================================================
-- Migration: 20271125000000_reviewer_accounts_final.sql
-- Description: ADDITIVE ONLY — does NOT modify any existing logic for real users.
--
-- 1. Deletes old test shops and products (Delhi-located, unusable from Bandipora).
-- 2. Nukes and recreates the 3 magic reviewer accounts with proper names:
--      +919999999996 → Rajesh Kumar     (Customer)
--      +919999999997 → Amit Bandana     (Seller)
--      +919999999998 → Kishan Nadda     (Delivery Partner)
-- 3. Creates ONE shop for Amit Bandana: "Amit Medical Store" in Bandipora.
--    No sample products — reviewer uploads them via seller dashboard.
-- 4. Recreates saved address for Rajesh Kumar in Bandipora.
-- 5. Updates fast_forward_test_orders trigger:
--    Removes the auto-accept at INSERT so the reviewer sees the 2-second
--    "Awaiting Acceptance" animation on the Track Order page.
--    (The Flutter app handles the auto-accept via a 2-second timer.)
-- ============================================================================

DO $$
DECLARE
  v_customer_id   uuid := '00000000-0000-0000-0000-919999999996';
  v_customer_email text := 'mock919999999996@enything.com';
  v_customer_phone text := '+919999999996';

  v_seller_id     uuid := '00000000-0000-0000-0000-919999999997';
  v_seller_email  text := 'mock919999999997@enything.com';
  v_seller_phone  text := '+919999999997';

  v_dp_id         uuid := '00000000-0000-0000-0000-919999999998';
  v_dp_email      text := 'mock919999999998@enything.com';
  v_dp_phone      text := '+919999999998';

  v_bandipora_point geography := ST_SetSRID(ST_MakePoint(74.6366, 34.4225), 4326)::geography;
  v_shop_id       uuid;
BEGIN

  -- ══════════════════════════════════════════════════════════════════
  -- STEP 1: Delete old Delhi-located test shops and all their data
  -- ══════════════════════════════════════════════════════════════════
  DELETE FROM public.reviews
    WHERE order_id IN (
      SELECT id FROM public.orders
        WHERE shop_id IN (SELECT id FROM public.shops WHERE name ILIKE '%Test Shop%')
    );
  DELETE FROM public.reviews
    WHERE shop_id IN (SELECT id FROM public.shops WHERE name ILIKE '%Test Shop%');
  DELETE FROM public.order_items
    WHERE product_id IN (
      SELECT id FROM public.products
        WHERE name ILIKE '%test product%'
           OR shop_id IN (SELECT id FROM public.shops WHERE name ILIKE '%Test Shop%')
    );
  DELETE FROM public.orders
    WHERE shop_id IN (SELECT id FROM public.shops WHERE name ILIKE '%Test Shop%');
  DELETE FROM public.products
    WHERE name ILIKE '%test product%'
       OR shop_id IN (SELECT id FROM public.shops WHERE name ILIKE '%Test Shop%');
  DELETE FROM public.shops WHERE name ILIKE '%Test Shop%';


  -- ══════════════════════════════════════════════════════════════════
  -- STEP 2: Nuke everything related to the 3 magic reviewer accounts
  -- ══════════════════════════════════════════════════════════════════

  -- 2a. Cancel any pending orders placed by these accounts
  UPDATE public.orders
    SET status = 'cancelled', updated_at = now()
    WHERE customer_id IN (v_customer_id, v_seller_id, v_dp_id)
      AND status IN ('awaiting_acceptance', 'awaiting_payment');

  -- 2b. Delete saved addresses
  DELETE FROM public.saved_addresses
    WHERE user_id IN (v_customer_id, v_seller_id, v_dp_id);

  -- 2c. Delete shops owned by seller reviewer (cascades products, order_items, orders via prior step)
  DELETE FROM public.products
    WHERE shop_id IN (SELECT id FROM public.shops WHERE seller_id = v_seller_id);
  DELETE FROM public.shops WHERE seller_id = v_seller_id;

  -- 2d. Delete role-specific rows
  DELETE FROM public.customers           WHERE id = v_customer_id;
  DELETE FROM public.delivery_partners   WHERE id = v_dp_id;

  -- 2e. Delete profiles
  DELETE FROM public.profiles
    WHERE id IN (v_customer_id, v_seller_id, v_dp_id)
       OR phone IN (v_customer_phone, v_seller_phone, v_dp_phone);

  -- 2f. Delete auth.identities then auth.users
  DELETE FROM auth.identities
    WHERE user_id IN (v_customer_id, v_seller_id, v_dp_id);
  DELETE FROM auth.users
    WHERE id IN (v_customer_id, v_seller_id, v_dp_id)
       OR lower(email) IN (lower(v_customer_email), lower(v_seller_email), lower(v_dp_email))
       OR phone IN (v_customer_phone, v_seller_phone, v_dp_phone);


  -- ══════════════════════════════════════════════════════════════════
  -- STEP 3: Recreate auth.users with proper names
  -- ══════════════════════════════════════════════════════════════════
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, phone, phone_confirmed_at,
    raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at,
    is_super_admin, is_sso_user, deleted_at, is_anonymous
  ) VALUES
  (
    v_customer_id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated',
    v_customer_email,
    extensions.crypt('Dummy123', extensions.gen_salt('bf', 10)),
    now(), v_customer_phone, now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"full_name":"Rajesh Kumar"}'::jsonb,
    now(), now(), false, false, NULL, false
  ),
  (
    v_seller_id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated',
    v_seller_email,
    extensions.crypt('Dummy123', extensions.gen_salt('bf', 10)),
    now(), v_seller_phone, now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"full_name":"Amit Bandana"}'::jsonb,
    now(), now(), false, false, NULL, false
  ),
  (
    v_dp_id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated',
    v_dp_email,
    extensions.crypt('Dummy123', extensions.gen_salt('bf', 10)),
    now(), v_dp_phone, now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"full_name":"Kishan Nadda"}'::jsonb,
    now(), now(), false, false, NULL, false
  );


  -- ══════════════════════════════════════════════════════════════════
  -- STEP 4: Recreate auth.identities
  -- ══════════════════════════════════════════════════════════════════
  INSERT INTO auth.identities (
    id, user_id, identity_data, provider, provider_id,
    last_sign_in_at, created_at, updated_at
  ) VALUES
  (
    gen_random_uuid(), v_customer_id,
    jsonb_build_object('sub', v_customer_id, 'email', v_customer_email,
                       'email_verified', true, 'phone_verified', true),
    'email', v_customer_email, now(), now(), now()
  ),
  (
    gen_random_uuid(), v_seller_id,
    jsonb_build_object('sub', v_seller_id, 'email', v_seller_email,
                       'email_verified', true, 'phone_verified', true),
    'email', v_seller_email, now(), now(), now()
  ),
  (
    gen_random_uuid(), v_dp_id,
    jsonb_build_object('sub', v_dp_id, 'email', v_dp_email,
                       'email_verified', true, 'phone_verified', true),
    'email', v_dp_email, now(), now(), now()
  );


  -- ══════════════════════════════════════════════════════════════════
  -- STEP 5: Recreate profiles with proper names
  -- ══════════════════════════════════════════════════════════════════
  INSERT INTO public.profiles (id, full_name, role, phone)
  VALUES
    (v_customer_id, 'Rajesh Kumar',  'customer',          v_customer_phone),
    (v_seller_id,   'Amit Bandana',  'seller',             v_seller_phone),
    (v_dp_id,       'Kishan Nadda',  'delivery_partner',   v_dp_phone)
  ON CONFLICT (id) DO UPDATE
    SET full_name = EXCLUDED.full_name,
        role      = EXCLUDED.role,
        phone     = EXCLUDED.phone;


  -- ══════════════════════════════════════════════════════════════════
  -- STEP 6: Recreate customer row for Rajesh Kumar
  -- ══════════════════════════════════════════════════════════════════
  INSERT INTO public.customers (id, location)
  VALUES (v_customer_id, v_bandipora_point)
  ON CONFLICT (id) DO UPDATE
    SET location = EXCLUDED.location;


  -- ══════════════════════════════════════════════════════════════════
  -- STEP 7: Recreate delivery_partner row for Kishan Nadda
  -- ══════════════════════════════════════════════════════════════════
  INSERT INTO public.delivery_partners (id, is_active, verification_status, location)
  VALUES (v_dp_id, true, 'verified', v_bandipora_point)
  ON CONFLICT (id) DO UPDATE
    SET is_active           = true,
        verification_status = 'verified',
        location            = EXCLUDED.location;


  -- ══════════════════════════════════════════════════════════════════
  -- STEP 8: Create ONE shop for Amit Bandana — "Amit Medical Store"
  --         (No products — reviewer uploads via seller dashboard)
  -- ══════════════════════════════════════════════════════════════════
  v_shop_id := gen_random_uuid();

  INSERT INTO public.shops (
    id, seller_id, name, category, categories,
    address, location,
    is_active, is_accepting_orders,
    verification_status,
    opening_hours, open_time, close_time
  ) VALUES (
    v_shop_id,
    v_seller_id,
    'Amit Medical Store',
    'Medical Store',
    '["Medical Store"]'::jsonb,
    'Main Market, Bandipora, J&K 193502',
    v_bandipora_point,
    true,
    true,
    'verified',
    '00:00 - 23:59',
    '00:00:00',
    '23:59:59'
  );


  -- ══════════════════════════════════════════════════════════════════
  -- STEP 9: Saved address for Rajesh Kumar (Customer)
  -- ══════════════════════════════════════════════════════════════════
  INSERT INTO public.saved_addresses (
    user_id, label, address, landmark, pincode,
    latitude, longitude, is_default
  ) VALUES (
    v_customer_id,
    'Home',
    'Main Market, Bandipora, J&K',
    'Near Jamia Masjid',
    '193502',
    34.4225,
    74.6366,
    true
  );

END $$;


-- ══════════════════════════════════════════════════════════════════
-- STEP 10: Update fast_forward_test_orders trigger
-- CHANGE: Remove the auto-accept at INSERT for magic numbers.
-- The Flutter app will auto-accept after 2 seconds on the track page,
-- giving the reviewer a smooth animated flow to watch.
-- This is ADDITIVE — replaces only this one trigger function body.
-- Zero impact on any real user orders.
-- ══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION fast_forward_test_orders()
RETURNS TRIGGER AS $$
BEGIN
  -- Magic reviewer accounts: orders now insert as awaiting_acceptance.
  -- The Flutter Track Order page auto-accepts after 2 seconds via a
  -- timed DB update, so the reviewer sees the acceptance animation.
  -- (Previous behavior was to instantly jump to awaiting_payment here.)
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger is already registered from migration 20260629000006.
-- Just replacing the function body above is sufficient.
-- No DROP/CREATE trigger needed — it still fires BEFORE INSERT on orders.

-- Force schema cache reload
NOTIFY pgrst, 'reload schema';
