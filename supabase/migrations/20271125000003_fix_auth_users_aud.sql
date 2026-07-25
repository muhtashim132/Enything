-- ============================================================================
-- Migration: 20271125000003_fix_auth_users_aud.sql
-- Description: Definitive fix for "Database error finding user" on magic login.
--
-- ROOT CAUSE: GoTrue's FindUserByEmailAndAudience queries:
--   SELECT * FROM auth.users WHERE email = $1 AND aud = 'authenticated'
-- Our previous migrations created rows WITHOUT setting aud, so aud = NULL.
-- GoTrue finds nothing → falls to signUp → UNIQUE email constraint fires
-- → GoTrue catches the DB error → returns "Database error finding user".
--
-- FIX: Delete and recreate all 3 reviewer auth.users with aud = 'authenticated'
-- explicitly set. Zero impact on any real user.
-- ============================================================================

DO $$
DECLARE
  v_customer_id   uuid := '00000000-0000-0000-0000-919999999996';
  v_customer_email text := 'mock919999999996@enything.com';

  v_seller_id     uuid := '00000000-0000-0000-0000-919999999997';
  v_seller_email  text := 'mock919999999997@enything.com';

  v_dp_id         uuid := '00000000-0000-0000-0000-919999999998';
  v_dp_email      text := 'mock919999999998@enything.com';
BEGIN

  -- Remove identities first (FK dependency)
  DELETE FROM auth.identities
    WHERE user_id IN (v_customer_id, v_seller_id, v_dp_id);

  -- Also remove any orphan identities that match these emails
  DELETE FROM auth.identities
    WHERE provider_id IN (v_customer_email, v_seller_email, v_dp_email);

  -- Remove sessions so FK checks don't block user deletion
  DELETE FROM auth.sessions
    WHERE user_id IN (v_customer_id, v_seller_id, v_dp_id);

  -- Remove refresh_tokens (user_id is varchar in auth.refresh_tokens)
  DELETE FROM auth.refresh_tokens
    WHERE user_id IN (
      v_customer_id::text,
      v_seller_id::text,
      v_dp_id::text
    );

  -- Remove the users
  DELETE FROM auth.users
    WHERE id IN (v_customer_id, v_seller_id, v_dp_id);

  -- Also remove any duplicate users that might exist with same email but different ID
  DELETE FROM auth.users
    WHERE lower(email) IN (
      lower(v_customer_email),
      lower(v_seller_email),
      lower(v_dp_email)
    );

  -- Recreate with aud = 'authenticated' EXPLICITLY SET — this is the critical fix.
  -- GoTrue FindUserByEmailAndAudience: WHERE email = $1 AND aud = 'authenticated'
  INSERT INTO auth.users (
    id,
    instance_id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at
  ) VALUES
  (
    v_customer_id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',                          -- aud: REQUIRED for signInWithPassword
    'authenticated',                          -- role
    v_customer_email,
    extensions.crypt('Dummy123', extensions.gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"full_name":"Rajesh Kumar"}'::jsonb,
    now(),
    now()
  ),
  (
    v_seller_id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    v_seller_email,
    extensions.crypt('Dummy123', extensions.gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"full_name":"Amit Bandana"}'::jsonb,
    now(),
    now()
  ),
  (
    v_dp_id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    v_dp_email,
    extensions.crypt('Dummy123', extensions.gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"full_name":"Kishan Nadda"}'::jsonb,
    now(),
    now()
  );

  -- Recreate identities
  INSERT INTO auth.identities (
    id, user_id, identity_data, provider, provider_id,
    last_sign_in_at, created_at, updated_at
  ) VALUES
  (
    gen_random_uuid(), v_customer_id,
    jsonb_build_object('sub', v_customer_id::text, 'email', v_customer_email, 'email_verified', true),
    'email', v_customer_email, now(), now(), now()
  ),
  (
    gen_random_uuid(), v_seller_id,
    jsonb_build_object('sub', v_seller_id::text, 'email', v_seller_email, 'email_verified', true),
    'email', v_seller_email, now(), now(), now()
  ),
  (
    gen_random_uuid(), v_dp_id,
    jsonb_build_object('sub', v_dp_id::text, 'email', v_dp_email, 'email_verified', true),
    'email', v_dp_email, now(), now(), now()
  );

  -- Ensure profiles are intact
  INSERT INTO public.profiles (id, full_name, role, phone)
  VALUES
    (v_customer_id, 'Rajesh Kumar',  'customer',         '+919999999996'),
    (v_seller_id,   'Amit Bandana',  'seller',            '+919999999997'),
    (v_dp_id,       'Kishan Nadda',  'delivery_partner',  '+919999999998')
  ON CONFLICT (id) DO UPDATE
    SET full_name = EXCLUDED.full_name,
        role      = EXCLUDED.role;

END $$;

NOTIFY pgrst, 'reload schema';
