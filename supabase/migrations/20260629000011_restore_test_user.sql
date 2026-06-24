DO $$
DECLARE
  mock_id uuid := '00000000-0000-0000-0000-919999999996';
BEGIN
  -- 1. Clean up any broken users that might have hijacked the test email or phone
  DELETE FROM auth.users WHERE email = 'mock919999999996@enything.com';
  DELETE FROM auth.users WHERE phone = '+919999999996';
  
  -- 2. Clean up any orphaned profile data for the test phone
  DELETE FROM public.saved_addresses WHERE user_id IN (SELECT id FROM public.profiles WHERE phone LIKE '%9999999996%');
  DELETE FROM public.customers WHERE id IN (SELECT id FROM public.profiles WHERE phone LIKE '%9999999996%');
  DELETE FROM public.profiles WHERE phone LIKE '%9999999996%';

  -- 3. Insert the perfect test user with the known UUID
  INSERT INTO auth.users (
    id, instance_id, email, encrypted_password, email_confirmed_at, 
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at, 
    role, aud, confirmation_token, email_change_token_new, email_change_token_current, phone
  ) VALUES (
    mock_id, '00000000-0000-0000-0000-000000000000', 'mock919999999996@enything.com', 
    extensions.crypt('Dummy123', extensions.gen_salt('bf')), now(), 
    '{"provider":"email","providers":["email"]}', 
    '{"full_name":"Razorpay Reviewer","phone":"+919999999996"}', 
    now(), now(), 'authenticated', 'authenticated', '', '', '', '+919999999996'
  ) ON CONFLICT (id) DO UPDATE SET 
    aud = 'authenticated',
    role = 'authenticated',
    email_confirmed_at = now();

  -- 4. Create the profile for the test user
  INSERT INTO public.profiles (id, full_name, role, phone)
  VALUES (mock_id, 'Razorpay Reviewer', 'customer', '+919999999996')
  ON CONFLICT (id) DO UPDATE SET role = 'customer';

  -- 5. Create the customer row
  INSERT INTO public.customers (id, location, pincode)
  VALUES (mock_id, 'POINT(74.6366 34.4225)', '193502')
  ON CONFLICT (id) DO UPDATE SET 
    location = 'POINT(74.6366 34.4225)',
    pincode = '193502';

  -- 6. Ensure the saved address exists
  DELETE FROM public.saved_addresses WHERE user_id = mock_id;
  INSERT INTO public.saved_addresses (
    user_id, label, address, landmark, pincode, latitude, longitude, is_default
  ) VALUES (
    mock_id, 'Home', 'Main Market, Bandipora', 'Near Jamia Masjid', 
    '193502', 34.4225, 74.6366, true
  );

END $$;
