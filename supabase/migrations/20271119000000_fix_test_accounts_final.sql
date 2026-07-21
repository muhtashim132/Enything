-- Hard reset of dummy test accounts to absolutely ensure they exist and can login

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
  -- 1. Purge any conflicting rows in auth.users that have these emails or phones but DIFFERENT IDs
  DELETE FROM auth.users 
  WHERE (email IN (v_seller_email, v_dp_email, v_customer_email)
         OR phone IN (v_seller_phone, v_dp_phone, v_customer_phone))
  AND id NOT IN (v_seller_id, v_dp_id, v_customer_id);

  -- 2. Purge any conflicting rows in profiles just in case
  DELETE FROM public.profiles 
  WHERE phone IN (v_seller_phone, v_dp_phone, v_customer_phone)
  AND id NOT IN (v_seller_id, v_dp_id, v_customer_id);

  -- 3. Upsert auth.users WITH the correct `aud` field! 
  -- Without `aud = 'authenticated'`, Supabase Auth `signInWithPassword` will silently fail with Invalid Credentials
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, 
    phone, phone_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
  ) VALUES 
  (
    v_seller_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', v_seller_email, 
    extensions.crypt('Dummy123', extensions.gen_salt('bf')), now(), 
    v_seller_phone, now(), '{"provider":"email","providers":["email", "phone"]}', '{"full_name":"Razorpay Seller Reviewer"}', now(), now()
  ),
  (
    v_dp_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', v_dp_email, 
    extensions.crypt('Dummy123', extensions.gen_salt('bf')), now(), 
    v_dp_phone, now(), '{"provider":"email","providers":["email", "phone"]}', '{"full_name":"Razorpay DP Reviewer"}', now(), now()
  ),
  (
    v_customer_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', v_customer_email, 
    extensions.crypt('Dummy123', extensions.gen_salt('bf')), now(), 
    v_customer_phone, now(), '{"provider":"email","providers":["email", "phone"]}', '{"full_name":"Razorpay Customer Reviewer"}', now(), now()
  )
  ON CONFLICT (id) DO UPDATE SET 
    aud = EXCLUDED.aud,
    role = EXCLUDED.role,
    email = EXCLUDED.email,
    encrypted_password = EXCLUDED.encrypted_password,
    email_confirmed_at = EXCLUDED.email_confirmed_at,
    phone = EXCLUDED.phone,
    phone_confirmed_at = EXCLUDED.phone_confirmed_at,
    raw_app_meta_data = EXCLUDED.raw_app_meta_data;

  -- 4. Upsert profiles
  INSERT INTO public.profiles (id, full_name, role, phone)
  VALUES 
    (v_seller_id, 'Razorpay Seller Reviewer', 'seller', v_seller_phone),
    (v_dp_id, 'Razorpay DP Reviewer', 'delivery_partner', v_dp_phone),
    (v_customer_id, 'Razorpay Customer Reviewer', 'customer', v_customer_phone)
  ON CONFLICT (id) DO UPDATE SET 
    full_name = EXCLUDED.full_name,
    role = EXCLUDED.role,
    phone = EXCLUDED.phone;

END $$;
