-- Additive migration to pre-seed test accounts for Seller (97) and DP (98)
-- This ensures they bypass any sign-up restrictions during edge case testing.

DO $$
DECLARE
  seller_mock_id uuid := '00000000-0000-0000-0000-919999999997';
  dp_mock_id uuid := '00000000-0000-0000-0000-919999999998';
BEGIN
  -- 1. Insert seller_mock_id into auth.users 
  INSERT INTO auth.users (
    id, instance_id, email, encrypted_password, email_confirmed_at, 
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at, 
    role
  ) VALUES (
    seller_mock_id, '00000000-0000-0000-0000-000000000000', 'mock919999999997@enything.com', 
    extensions.crypt('Dummy123', extensions.gen_salt('bf')), now(), 
    '{"provider":"email","providers":["email"]}', 
    '{"full_name":"Razorpay Seller Reviewer"}', 
    now(), now(), 'authenticated'
  ) ON CONFLICT (id) DO NOTHING;

  -- Upsert seller into public.profiles
  INSERT INTO public.profiles (id, full_name, role, phone)
  VALUES (seller_mock_id, 'Razorpay Seller Reviewer', 'seller', '+919999999997')
  ON CONFLICT (id) DO NOTHING;

  -- 2. Insert dp_mock_id into auth.users 
  INSERT INTO auth.users (
    id, instance_id, email, encrypted_password, email_confirmed_at, 
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at, 
    role
  ) VALUES (
    dp_mock_id, '00000000-0000-0000-0000-000000000000', 'mock919999999998@enything.com', 
    extensions.crypt('Dummy123', extensions.gen_salt('bf')), now(), 
    '{"provider":"email","providers":["email"]}', 
    '{"full_name":"Razorpay DP Reviewer"}', 
    now(), now(), 'authenticated'
  ) ON CONFLICT (id) DO NOTHING;

  -- Upsert dp into public.profiles
  INSERT INTO public.profiles (id, full_name, role, phone)
  VALUES (dp_mock_id, 'Razorpay DP Reviewer', 'delivery_partner', '+919999999998')
  ON CONFLICT (id) DO NOTHING;

END $$;
