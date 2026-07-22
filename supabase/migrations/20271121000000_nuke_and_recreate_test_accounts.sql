-- Absolute final purge and recreate of dummy accounts.
-- If GoTrue panics with "Database error querying schema", it's almost always because 
-- a SELECT query returned multiple rows (e.g., duplicated emails with different case or soft deletes)
-- or because a JSONB column contains an invalid GoTrue struct.

DO $$
DECLARE
  v_seller_id uuid := '00000000-0000-0000-0000-919999999997';
  v_seller_email text := 'mock919999999997@enything.com';
  v_seller_phone text := '+919999999997';
  
  v_dp_id uuid := '00000000-0000-0000-0000-919999999998';
  v_dp_email text := 'mock919999999998@enything.com';
  v_dp_phone text := '+919999999998';
  
  v_customer_id uuid := '00000000-0000-0000-0000-919999999999';
  v_customer_email text := 'mock919999999999@enything.com';
  v_customer_phone text := '+919999999999';
  
BEGIN
  -- 1. NUKE EVERYTHING related to these emails and phones from auth.users and auth.identities
  DELETE FROM auth.identities WHERE user_id IN (
    SELECT id FROM auth.users WHERE 
      lower(email) IN (lower(v_seller_email), lower(v_dp_email), lower(v_customer_email))
      OR phone IN (v_seller_phone, v_dp_phone, v_customer_phone)
      OR id IN (v_seller_id, v_dp_id, v_customer_id)
  );

  DELETE FROM auth.users WHERE 
    lower(email) IN (lower(v_seller_email), lower(v_dp_email), lower(v_customer_email))
    OR phone IN (v_seller_phone, v_dp_phone, v_customer_phone)
    OR id IN (v_seller_id, v_dp_id, v_customer_id);

  -- 2. NUKE profiles just in case
  DELETE FROM public.profiles WHERE 
    phone IN (v_seller_phone, v_dp_phone, v_customer_phone)
    OR id IN (v_seller_id, v_dp_id, v_customer_id);

  -- 3. RECREATE PERFECTLY from scratch
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, 
    phone, phone_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    is_super_admin, is_sso_user, deleted_at, is_anonymous
  ) VALUES 
  (
    v_seller_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', v_seller_email, 
    extensions.crypt('Dummy123', extensions.gen_salt('bf', 10)), now(), 
    v_seller_phone, now(), '{"provider":"email","providers":["email"]}'::jsonb, '{"full_name":"Razorpay Seller Reviewer"}'::jsonb, now(), now(),
    false, false, NULL, false
  ),
  (
    v_dp_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', v_dp_email, 
    extensions.crypt('Dummy123', extensions.gen_salt('bf', 10)), now(), 
    v_dp_phone, now(), '{"provider":"email","providers":["email"]}'::jsonb, '{"full_name":"Razorpay DP Reviewer"}'::jsonb, now(), now(),
    false, false, NULL, false
  ),
  (
    v_customer_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', v_customer_email, 
    extensions.crypt('Dummy123', extensions.gen_salt('bf', 10)), now(), 
    v_customer_phone, now(), '{"provider":"email","providers":["email"]}'::jsonb, '{"full_name":"Razorpay Customer Reviewer"}'::jsonb, now(), now(),
    false, false, NULL, false
  );

  -- 4. RECREATE IDENTITIES
  INSERT INTO auth.identities (
    id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at
  ) VALUES 
  (
    gen_random_uuid(), v_seller_id, 
    jsonb_build_object('sub', v_seller_id, 'email', v_seller_email, 'email_verified', true, 'phone_verified', true), 
    'email', v_seller_email, now(), now(), now()
  ),
  (
    gen_random_uuid(), v_dp_id, 
    jsonb_build_object('sub', v_dp_id, 'email', v_dp_email, 'email_verified', true, 'phone_verified', true), 
    'email', v_dp_email, now(), now(), now()
  ),
  (
    gen_random_uuid(), v_customer_id, 
    jsonb_build_object('sub', v_customer_id, 'email', v_customer_email, 'email_verified', true, 'phone_verified', true), 
    'email', v_customer_email, now(), now(), now()
  );

  -- 5. RECREATE PROFILES
  INSERT INTO public.profiles (id, full_name, role, phone)
  VALUES 
    (v_seller_id, 'Razorpay Seller Reviewer', 'seller', v_seller_phone),
    (v_dp_id, 'Razorpay DP Reviewer', 'delivery_partner', v_dp_phone),
    (v_customer_id, 'Razorpay Customer Reviewer', 'customer', v_customer_phone);

END $$;
