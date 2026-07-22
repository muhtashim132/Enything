DO $$
DECLARE
  v_test_id uuid := gen_random_uuid();
  v_test_email text := 'test_manual@enything.com';
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, 
    phone, phone_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    is_super_admin, is_sso_user, deleted_at, is_anonymous
  ) VALUES 
  (
    v_test_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', v_test_email, 
    extensions.crypt('Dummy123', extensions.gen_salt('bf', 10)), now(), 
    NULL, NULL, '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(),
    false, false, NULL, false
  );

  INSERT INTO auth.identities (
    id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at
  ) VALUES 
  (
    gen_random_uuid(), v_test_id, 
    jsonb_build_object('sub', v_test_id, 'email', v_test_email, 'email_verified', true), 
    'email', v_test_email, now(), now(), now()
  );
END $$;
