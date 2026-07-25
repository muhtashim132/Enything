-- ============================================================================
-- Migration: 20271125000002_fix_auth_users_format.sql
-- Description: ADDITIVE FIX — corrects auth.users for the 3 reviewer accounts.
--
-- Root cause: The previous migration (20271125000000) used extra columns
-- (phone, phone_confirmed_at, aud, is_anonymous, is_super_admin, etc.) in
-- auth.users that differ from the format GoTrue expects for email+password
-- auth. The 'phone' column's UNIQUE constraint may also have caused silent
-- INSERT failures.
--
-- Fix: Delete and recreate the 3 auth.users using the EXACT minimal format
-- confirmed working in migration 20260629000012_add_seller_dp_test_accounts.sql.
-- Uses gen_salt('bf') — no cost factor — matching the old working migration.
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

  -- Step 1: Remove any existing identities for these 3 accounts first
  DELETE FROM auth.identities
    WHERE user_id IN (v_customer_id, v_seller_id, v_dp_id);

  -- Step 2: Remove the auth.users rows (safe — we recreate below)
  DELETE FROM auth.users
    WHERE id IN (v_customer_id, v_seller_id, v_dp_id);

  -- Step 3: Recreate auth.users using the exact minimal format
  -- that GoTrue/Supabase uses for email+password auth (same as 20260629000012).
  -- No phone column, no aud override, no is_anonymous — just the essentials.

  INSERT INTO auth.users (
    id, instance_id, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    role
  ) VALUES
  (
    v_customer_id,
    '00000000-0000-0000-0000-000000000000',
    v_customer_email,
    extensions.crypt('Dummy123', extensions.gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"full_name":"Rajesh Kumar"}',
    now(), now(),
    'authenticated'
  ),
  (
    v_seller_id,
    '00000000-0000-0000-0000-000000000000',
    v_seller_email,
    extensions.crypt('Dummy123', extensions.gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"full_name":"Amit Bandana"}',
    now(), now(),
    'authenticated'
  ),
  (
    v_dp_id,
    '00000000-0000-0000-0000-000000000000',
    v_dp_email,
    extensions.crypt('Dummy123', extensions.gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"full_name":"Kishan Nadda"}',
    now(), now(),
    'authenticated'
  );

  -- Step 4: Recreate auth.identities linked to those users
  INSERT INTO auth.identities (
    id, user_id, identity_data, provider, provider_id,
    last_sign_in_at, created_at, updated_at
  ) VALUES
  (
    gen_random_uuid(), v_customer_id,
    jsonb_build_object('sub', v_customer_id, 'email', v_customer_email, 'email_verified', true),
    'email', v_customer_email, now(), now(), now()
  ),
  (
    gen_random_uuid(), v_seller_id,
    jsonb_build_object('sub', v_seller_id, 'email', v_seller_email, 'email_verified', true),
    'email', v_seller_email, now(), now(), now()
  ),
  (
    gen_random_uuid(), v_dp_id,
    jsonb_build_object('sub', v_dp_id, 'email', v_dp_email, 'email_verified', true),
    'email', v_dp_email, now(), now(), now()
  );

  -- Step 5: Ensure profiles are still correct (upsert to be safe)
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
