-- ============================================================================
-- 100x RBAC SECURITY: AUTH.USERS PHONE LOOKUP & ZERO-FRICTION ACTIVATION
-- Migration: 20290000000135_100x_rbac_auth_users_phone_lookup.sql
-- ============================================================================

CREATE OR REPLACE FUNCTION public.admin_add_team_member_by_phone(
  p_phone TEXT,
  p_full_name TEXT,
  p_role_id UUID,
  p_admin_password TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_raw_digits TEXT;
  v_last_10 TEXT;
  v_clean_phone TEXT;
  v_user_id UUID;
  v_profile_email TEXT;
  v_role_name TEXT;
  v_role_slug TEXT;
BEGIN
  -- Strict Authorization: Only Super Admin or authorized roles.assign can add staff
  IF NOT (public.is_super_admin(v_caller_id) OR public.has_permission(v_caller_id, 'roles.assign')) THEN
    RAISE EXCEPTION 'Access denied: Super Admin or roles.assign permission required to add team members';
  END IF;

  -- Validate inputs
  IF p_phone IS NULL OR trim(p_phone) = '' THEN
    RAISE EXCEPTION 'Phone number is required';
  END IF;

  IF p_admin_password IS NULL OR length(trim(p_admin_password)) < 6 THEN
    RAISE EXCEPTION 'Admin password must be at least 6 characters';
  END IF;

  -- Normalize phone: extract last 10 digits for universal India format
  v_raw_digits := regexp_replace(p_phone, '\D', '', 'g');
  IF length(v_raw_digits) < 10 THEN
    RAISE EXCEPTION 'Invalid phone number: must contain at least 10 digits';
  END IF;
  v_last_10 := right(v_raw_digits, 10);
  v_clean_phone := '+91' || v_last_10;

  -- Validate role existence and protect Super Admin role assignment
  SELECT name, slug INTO v_role_name, v_role_slug 
  FROM public.roles 
  WHERE id = p_role_id;
  
  IF v_role_name IS NULL THEN
    RAISE EXCEPTION 'The specified role does not exist';
  END IF;

  IF v_role_slug = 'super_admin' AND NOT public.is_super_admin(v_caller_id) THEN
    RAISE EXCEPTION 'Security Violation: Only Super Admins can assign the Super Admin role';
  END IF;

  -- 1. Check if user already exists in profiles (match last 10 digits)
  SELECT id, email INTO v_user_id, v_profile_email
  FROM public.profiles
  WHERE right(regexp_replace(COALESCE(phone, ''), '\D', '', 'g'), 10) = v_last_10
  LIMIT 1;

  -- 1b. Fallback: Check if user exists in auth.users (phone column, raw_user_meta_data, or synthetic email)
  IF v_user_id IS NULL THEN
    SELECT id, email INTO v_user_id, v_profile_email
    FROM auth.users
    WHERE right(regexp_replace(COALESCE(phone, ''), '\D', '', 'g'), 10) = v_last_10
       OR right(regexp_replace(COALESCE(raw_user_meta_data->>'phone', ''), '\D', '', 'g'), 10) = v_last_10
       OR email = '91' || v_last_10 || '@auth.enything.app'
       OR email = '+91' || v_last_10 || '@auth.enything.app'
    LIMIT 1;

    IF v_user_id IS NOT NULL THEN
      -- Create the profiles row if missing
      INSERT INTO public.profiles (id, phone, full_name, email, role, active_roles)
      VALUES (
        v_user_id,
        v_clean_phone,
        COALESCE(NULLIF(trim(p_full_name), ''), 'Staff Member'),
        COALESCE(v_profile_email, '91' || v_last_10 || '@auth.enything.app'),
        'customer',
        ARRAY['customer', 'admin']
      )
      ON CONFLICT (id) DO UPDATE SET
        phone = COALESCE(profiles.phone, v_clean_phone),
        active_roles = array_append(
          array_remove(COALESCE(profiles.active_roles, ARRAY['customer'::text]), 'admin'),
          'admin'
        );
    END IF;
  END IF;

  IF v_user_id IS NOT NULL THEN
    -- User already registered: immediately provision active admin_users entry
    INSERT INTO public.admin_users (
      id,
      email,
      full_name,
      phone,
      role,
      role_id,
      admin_password,
      admin_level,
      is_active,
      is_suspended,
      created_by,
      updated_at
    )
    VALUES (
      v_user_id,
      COALESCE(v_profile_email, '91' || v_last_10 || '@auth.enything.app'),
      COALESCE(NULLIF(trim(p_full_name), ''), 'Staff Member'),
      v_clean_phone,
      'admin',
      p_role_id,
      trim(p_admin_password),
      'staff',
      true,
      false,
      v_caller_id,
      now()
    )
    ON CONFLICT (id) DO UPDATE SET
      email = COALESCE(admin_users.email, v_profile_email, '91' || v_last_10 || '@auth.enything.app'),
      full_name = COALESCE(NULLIF(trim(p_full_name), ''), admin_users.full_name),
      phone = v_clean_phone,
      role_id = p_role_id,
      admin_password = trim(p_admin_password),
      admin_level = 'staff',
      is_active = true,
      is_suspended = false,
      updated_at = now();

    -- Ensure profile active_roles contains admin
    UPDATE public.profiles
    SET active_roles = array_append(
      array_remove(COALESCE(active_roles, ARRAY['customer'::text]), 'admin'),
      'admin'
    )
    WHERE id = v_user_id;

    -- If there was a pending invitation, mark it accepted
    UPDATE public.admin_invitations
    SET status = 'accepted', accepted_at = now()
    WHERE right(regexp_replace(COALESCE(email, ''), '\D', '', 'g'), 10) = v_last_10
      AND status = 'pending';

    RETURN jsonb_build_object(
      'success', true,
      'status', 'active',
      'user_id', v_user_id,
      'message', 'Team member ' || v_clean_phone || ' provisioned and activated as ' || v_role_name || '!'
    );
  ELSE
    -- 2. User has not registered yet: record in admin_invitations with normalized phone
    INSERT INTO public.admin_invitations (
      id,
      email,
      role_id,
      role_name,
      token,
      invited_by,
      status,
      expires_at
    )
    VALUES (
      gen_random_uuid(),
      v_clean_phone,
      p_role_id,
      v_role_name,
      trim(p_admin_password),
      v_caller_id,
      'pending',
      now() + interval '30 days'
    );

    RETURN jsonb_build_object(
      'success', true,
      'status', 'pending',
      'message', 'Invitation registered for ' || v_clean_phone || '. When this user logs in via phone OTP, their ' || v_role_name || ' access will activate automatically!'
    );
  END IF;
END;
$$;

-- ── 2. Retroactively resolve existing pending invitations for auth.users ─────
DO $$
DECLARE
  r RECORD;
  v_uid UUID;
  v_10 TEXT;
  v_profile_email TEXT;
BEGIN
  FOR r IN SELECT * FROM public.admin_invitations WHERE status = 'pending' LOOP
    v_10 := right(regexp_replace(COALESCE(r.email, ''), '\D', '', 'g'), 10);
    SELECT id, email INTO v_uid, v_profile_email
    FROM auth.users
    WHERE right(regexp_replace(COALESCE(phone, ''), '\D', '', 'g'), 10) = v_10
       OR right(regexp_replace(COALESCE(raw_user_meta_data->>'phone', ''), '\D', '', 'g'), 10) = v_10
       OR email = '91' || v_10 || '@auth.enything.app'
       OR email = '+91' || v_10 || '@auth.enything.app'
    LIMIT 1;

    IF v_uid IS NOT NULL THEN
      -- Create or update profile
      INSERT INTO public.profiles (id, phone, full_name, email, role, active_roles)
      VALUES (
        v_uid,
        '+91' || v_10,
        'Product Manager',
        COALESCE(v_profile_email, '91' || v_10 || '@auth.enything.app'),
        'customer',
        ARRAY['customer', 'admin']
      )
      ON CONFLICT (id) DO UPDATE SET
        phone = '+91' || v_10,
        active_roles = array_append(
          array_remove(COALESCE(profiles.active_roles, ARRAY['customer'::text]), 'admin'),
          'admin'
        );

      -- Provision admin_users
      INSERT INTO public.admin_users (
        id, email, full_name, phone, role, role_id, admin_password,
        admin_level, is_active, is_suspended, created_by, updated_at
      )
      VALUES (
        v_uid,
        COALESCE(v_profile_email, '91' || v_10 || '@auth.enything.app'),
        'Product Manager',
        '+91' || v_10,
        'admin',
        r.role_id,
        r.token,
        'staff',
        true,
        false,
        r.invited_by,
        now()
      )
      ON CONFLICT (id) DO UPDATE SET
        role_id = r.role_id,
        admin_password = r.token,
        is_active = true,
        is_suspended = false,
        updated_at = now();

      -- Mark invitation accepted
      UPDATE public.admin_invitations
      SET status = 'accepted', accepted_at = now()
      WHERE id = r.id;
    END IF;
  END LOOP;
END;
$$;
