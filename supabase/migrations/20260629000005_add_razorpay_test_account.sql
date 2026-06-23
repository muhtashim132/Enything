-- Migration to add a test account for Razorpay Reviewers
-- This uses the magic number bypass built into the app (+919999999996)
-- It forces the Bandipora coordinates so the reviewer can bypass the 15km geofence.

DO $$
DECLARE
  mock_id uuid := '00000000-0000-0000-0000-919999999996';
BEGIN
  -- 1. Insert mockId into auth.users (to satisfy foreign key constraints)
  INSERT INTO auth.users (
    id, instance_id, email, encrypted_password, email_confirmed_at, 
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at, 
    role
  ) VALUES (
    mock_id, '00000000-0000-0000-0000-000000000000', 'mock919999999996@enything.com', 
    extensions.crypt('Dummy123', extensions.gen_salt('bf')), now(), 
    '{"provider":"email","providers":["email"]}', 
    '{"full_name":"Razorpay Reviewer"}', 
    now(), now(), 'authenticated'
  ) ON CONFLICT (id) DO NOTHING;

  -- 2. Upsert into public.profiles (Required by the app's bypass logic)
  INSERT INTO public.profiles (id, full_name, role, phone)
  VALUES (mock_id, 'Razorpay Reviewer', 'customer', '+919999999996')
  ON CONFLICT (id) DO NOTHING;

  -- 3. Upsert into public.customers with exact Bandipora coordinates
  INSERT INTO public.customers (id, location, pincode)
  VALUES (mock_id, 'POINT(74.6366 34.4225)', '193502')
  ON CONFLICT (id) DO UPDATE SET 
    location = 'POINT(74.6366 34.4225)',
    pincode = '193502';

  -- 4. Clear old addresses and insert the default Saved Address for Bandipora
  DELETE FROM public.saved_addresses WHERE user_id = mock_id;

  INSERT INTO public.saved_addresses (
    user_id, label, address, landmark, pincode, latitude, longitude, is_default
  ) VALUES (
    mock_id, 'Home', 'Main Market, Bandipora', 'Near Jamia Masjid', 
    '193502', 34.4225, 74.6366, true
  );

END $$;
