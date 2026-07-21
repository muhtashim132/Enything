-- Fix dummy test accounts to properly have phone numbers in auth.users
-- This prevents Supabase Auth from attempting to create a new user when logging in with these phone numbers,
-- which would otherwise cause a unique constraint violation in public.profiles.

DO $$
DECLARE
  v_seller_id uuid := '00000000-0000-0000-0000-919999999997';
  v_seller_phone text := '+919999999997';
  
  v_dp_id uuid := '00000000-0000-0000-0000-919999999998';
  v_dp_phone text := '+919999999998';
  
  v_customer_id uuid := '00000000-0000-0000-0000-919999999999';
  v_customer_phone text := '+919999999999';
BEGIN

  -- 1. Delete any mistakenly created duplicate auth.users that have these phone numbers 
  -- but a DIFFERENT id than our hardcoded test IDs.
  -- (This cleans up the failed login attempts that created new auth.users)
  DELETE FROM auth.users 
  WHERE phone IN (v_seller_phone, v_dp_phone, v_customer_phone)
  AND id NOT IN (v_seller_id, v_dp_id, v_customer_id);

  -- 2. Update the hardcoded test users to include the phone number directly in auth.users
  UPDATE auth.users 
  SET phone = v_seller_phone, 
      phone_confirmed_at = COALESCE(phone_confirmed_at, now()),
      raw_app_meta_data = raw_app_meta_data || '{"providers":["email", "phone"]}'::jsonb
  WHERE id = v_seller_id;

  UPDATE auth.users 
  SET phone = v_dp_phone, 
      phone_confirmed_at = COALESCE(phone_confirmed_at, now()),
      raw_app_meta_data = raw_app_meta_data || '{"providers":["email", "phone"]}'::jsonb
  WHERE id = v_dp_id;
  
  UPDATE auth.users 
  SET phone = v_customer_phone, 
      phone_confirmed_at = COALESCE(phone_confirmed_at, now()),
      raw_app_meta_data = raw_app_meta_data || '{"providers":["email", "phone"]}'::jsonb
  WHERE id = v_customer_id;

END $$;
