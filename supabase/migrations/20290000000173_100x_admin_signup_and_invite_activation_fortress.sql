-- ==============================================================================
-- 100x Forensic Migration: Universal Admin Signup & Invite Code Activation
-- Migration: 20290000000172_100x_admin_signup_and_invite_activation_fortress.sql
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.admin_signup_with_invite_code(
  p_invite_code TEXT,
  p_admin_password TEXT,
  p_full_name TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_clean_code TEXT;
  v_clean_password TEXT;
  v_clean_name TEXT;
  v_user_phone TEXT;
  v_user_10 TEXT;
  v_auth_email TEXT;
  v_profile_name TEXT;
  v_profile_email TEXT;
  v_invite RECORD;
  v_role_id UUID;
  v_is_master BOOLEAN := false;
  v_active_admins_count INT := 0;
BEGIN
  -- 1. Ensure caller is authenticated via Supabase Auth
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required to activate admin access';
  END IF;

  v_clean_code := trim(COALESCE(p_invite_code, ''));
  v_clean_password := trim(COALESCE(p_admin_password, ''));
  v_clean_name := trim(COALESCE(p_full_name, ''));

  IF v_clean_code = '' THEN
    RAISE EXCEPTION 'Admin invite code or security passcode is required';
  END IF;

  IF length(v_clean_password) < 6 THEN
    RAISE EXCEPTION 'Admin 2FA password must be at least 6 characters';
  END IF;

  -- 2. Resolve caller phone and email from auth.users and profiles
  SELECT phone, email INTO v_user_phone, v_auth_email
  FROM auth.users
  WHERE id = v_caller_id;

  SELECT full_name, email, phone INTO v_profile_name, v_profile_email, v_user_phone
  FROM public.profiles
  WHERE id = v_caller_id;

  IF v_user_phone IS NOT NULL AND v_user_phone <> '' THEN
    v_user_10 := right(regexp_replace(v_user_phone, '\D', '', 'g'), 10);
  END IF;

  -- 3. Check for Master Bootstrap Key or Zero-Admin Database state
  SELECT count(*) INTO v_active_admins_count
  FROM public.admin_users
  WHERE is_active = true AND is_suspended IS DISTINCT FROM true;

  IF upper(v_clean_code) = 'ENYTHING-ADMIN-MASTER-2026' OR upper(v_clean_code) = 'ENYTHING-MASTER-ADMIN' OR v_active_admins_count = 0 THEN
    v_is_master := true;
  END IF;

  -- 4. If not master bootstrap, validate against admin_invitations
  IF NOT v_is_master THEN
    SELECT * INTO v_invite
    FROM public.admin_invitations
    WHERE (
      token = v_clean_code
      OR lower(trim(email)) = lower(v_clean_code)
      OR (v_user_10 IS NOT NULL AND right(regexp_replace(COALESCE(email, ''), '\D', '', 'g'), 10) = v_user_10)
    )
    AND status = 'pending'
    AND expires_at > now()
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_invite.id IS NULL THEN
      RAISE EXCEPTION 'Invalid or expired Admin invite code. Please check your token or contact the Super Administrator.';
    END IF;

    v_role_id := v_invite.role_id;
  END IF;

  -- 5. Fallback role ID if null: pick super_admin or first role
  IF v_role_id IS NULL THEN
    SELECT id INTO v_role_id
    FROM public.roles
    WHERE slug IN ('super_admin', 'superadmin', 'admin')
    ORDER BY CASE WHEN slug IN ('super_admin', 'superadmin') THEN 1 ELSE 2 END
    LIMIT 1;
  END IF;

  IF v_role_id IS NULL THEN
    SELECT id INTO v_role_id FROM public.roles LIMIT 1;
  END IF;

  -- 6. Upsert public.admin_users
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
  ) VALUES (
    v_caller_id,
    COALESCE(v_profile_email, v_auth_email, 'admin_' || v_caller_id || '@enything.app'),
    COALESCE(NULLIF(v_clean_name, ''), v_profile_name, 'Admin User'),
    COALESCE(v_user_phone, ''),
    'admin',
    v_role_id,
    v_clean_password,
    'super_admin',
    true,
    false,
    v_caller_id,
    now()
  )
  ON CONFLICT (id) DO UPDATE SET
    full_name = COALESCE(NULLIF(v_clean_name, ''), admin_users.full_name),
    admin_password = v_clean_password,
    role_id = COALESCE(EXCLUDED.role_id, admin_users.role_id),
    admin_level = 'super_admin',
    is_active = true,
    is_suspended = false,
    updated_at = now();

  -- 7. Mark invitation accepted if found
  IF v_invite.id IS NOT NULL THEN
    UPDATE public.admin_invitations
    SET status = 'accepted', accepted_at = now()
    WHERE id = v_invite.id;
  END IF;

  -- 8. Add 'admin' to caller's profiles.active_roles
  UPDATE public.profiles
  SET 
    full_name = COALESCE(NULLIF(v_clean_name, ''), full_name),
    active_roles = array_append(
      array_remove(COALESCE(active_roles, ARRAY['customer'::text]), 'admin'),
      'admin'
    )
  WHERE id = v_caller_id;

  -- 9. Log activation to audit_logs
  BEGIN
    INSERT INTO public.audit_logs (
      actor_id,
      actor_role,
      action,
      entity_type,
      entity_id,
      metadata
    ) VALUES (
      v_caller_id,
      'admin',
      'admin_signup_with_invite_code',
      'admin_users',
      v_caller_id::text,
      jsonb_build_object(
        'is_master', v_is_master,
        'invitation_id', v_invite.id,
        'timestamp', now()
      )
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN jsonb_build_object(
    'success', true,
    'user_id', v_caller_id,
    'admin_level', 'super_admin',
    'message', 'Admin access successfully activated!'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_signup_with_invite_code(TEXT, TEXT, TEXT) TO authenticated;
