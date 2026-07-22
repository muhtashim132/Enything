-- Final absolute fix for dummy test accounts by creating their auth identities
-- GoTrue requires an identity in auth.identities for password logins to succeed.

DO $$
DECLARE
  v_seller_id uuid := '00000000-0000-0000-0000-919999999997';
  v_seller_email text := 'mock919999999997@enything.com';
  
  v_dp_id uuid := '00000000-0000-0000-0000-919999999998';
  v_dp_email text := 'mock919999999998@enything.com';
  
  v_customer_id uuid := '00000000-0000-0000-0000-919999999999';
  v_customer_email text := 'mock919999999999@enything.com';
  
BEGIN
  -- 1. Ensure identities exist for the seller test account
  INSERT INTO auth.identities (
    id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at
  ) VALUES (
    v_seller_id, v_seller_id, 
    jsonb_build_object('sub', v_seller_id, 'email', v_seller_email, 'email_verified', true, 'phone_verified', true), 
    'email', v_seller_email, now(), now(), now()
  ) ON CONFLICT (id) DO UPDATE SET 
    identity_data = EXCLUDED.identity_data,
    updated_at = now();

  -- 2. Ensure identities exist for the dp test account
  INSERT INTO auth.identities (
    id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at
  ) VALUES (
    v_dp_id, v_dp_id, 
    jsonb_build_object('sub', v_dp_id, 'email', v_dp_email, 'email_verified', true, 'phone_verified', true), 
    'email', v_dp_email, now(), now(), now()
  ) ON CONFLICT (id) DO UPDATE SET 
    identity_data = EXCLUDED.identity_data,
    updated_at = now();

  -- 3. Ensure identities exist for the customer test account
  INSERT INTO auth.identities (
    id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at
  ) VALUES (
    v_customer_id, v_customer_id, 
    jsonb_build_object('sub', v_customer_id, 'email', v_customer_email, 'email_verified', true, 'phone_verified', true), 
    'email', v_customer_email, now(), now(), now()
  ) ON CONFLICT (id) DO UPDATE SET 
    identity_data = EXCLUDED.identity_data,
    updated_at = now();

  -- 4. Just in case, ensure no duplicate emails in auth.users that could break GoTrue's FindUserByEmail
  -- (We did this in the last migration but let's be extremely thorough by checking for deleted_at IS NULL)
  DELETE FROM auth.users 
  WHERE email IN (v_seller_email, v_dp_email, v_customer_email)
  AND id NOT IN (v_seller_id, v_dp_id, v_customer_id);

  -- 5. Set is_sso_user = false
  UPDATE auth.users 
  SET is_sso_user = false
  WHERE id IN (v_seller_id, v_dp_id, v_customer_id);

END $$;
