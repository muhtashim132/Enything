-- ============================================================================
-- 100x RBAC SECURITY, PRIVILEGE ISOLATION & STAFF ONBOARDING FORTRESS
-- Migration: 20290000000134_100x_rbac_security_and_privilege_fortress.sql
-- ============================================================================

-- ── 1. HARDEN verify_admin_password: FAIL CLOSED IF SUSPENDED OR INACTIVE ────
DROP FUNCTION IF EXISTS public.verify_admin_password(UUID, TEXT);
CREATE OR REPLACE FUNCTION public.verify_admin_password(
  p_admin_id UUID,
  p_password TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_stored_password TEXT;
  v_is_active       BOOLEAN;
  v_is_suspended    BOOLEAN;
BEGIN
  IF p_admin_id IS NULL OR p_password IS NULL OR trim(p_password) = '' THEN
    RETURN FALSE;
  END IF;

  -- Fetch stored password, active status, and suspended status
  SELECT admin_password, is_active, is_suspended
    INTO v_stored_password, v_is_active, v_is_suspended
  FROM public.admin_users
  WHERE id = p_admin_id;

  -- Fail closed: admin must exist, must be active, and MUST NOT be suspended
  IF NOT FOUND OR v_is_active IS DISTINCT FROM TRUE OR v_is_suspended IS TRUE THEN
    RETURN FALSE;
  END IF;

  -- Constant-time comparison using HMAC to prevent timing attacks
  RETURN encode(hmac(trim(p_password), 'enything-admin-verify-key', 'sha256'), 'hex')
       = encode(hmac(COALESCE(v_stored_password, ''), 'enything-admin-verify-key', 'sha256'), 'hex');
EXCEPTION WHEN OTHERS THEN
  -- Fallback if pgcrypto is unavailable: direct equality check with active/suspended guard
  RETURN (v_is_active IS TRUE AND (v_is_suspended IS DISTINCT FROM TRUE) AND COALESCE(v_stored_password, '') = trim(p_password));
END;
$$;

GRANT EXECUTE ON FUNCTION public.verify_admin_password(UUID, TEXT) TO authenticated, service_role;

-- ── 2. HARDEN admin_add_team_member_by_phone: STRICT PERMISSIONS & 10-DIGIT NORMALIZATION ──
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

GRANT EXECUTE ON FUNCTION public.admin_add_team_member_by_phone(TEXT, TEXT, UUID, TEXT) TO authenticated, service_role;

-- ── 3. HARDEN handle_pending_admin_invitation TRIGGER ON profiles ────────────
CREATE OR REPLACE FUNCTION public.handle_pending_admin_invitation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inv RECORD;
  v_user_10 TEXT;
BEGIN
  IF NEW.phone IS NOT NULL AND NEW.phone <> '' THEN
    v_user_10 := right(regexp_replace(NEW.phone, '\D', '', 'g'), 10);

    -- Match on last 10 digits
    SELECT * INTO v_inv
    FROM public.admin_invitations
    WHERE right(regexp_replace(COALESCE(email, ''), '\D', '', 'g'), 10) = v_user_10
      AND status = 'pending'
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_inv.id IS NOT NULL THEN
      -- Provision admin_users entry immediately
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
        NEW.id,
        COALESCE(NEW.email, '91' || v_user_10 || '@auth.enything.app'),
        COALESCE(NULLIF(NEW.full_name, ''), 'Staff Member'),
        '+91' || v_user_10,
        'admin',
        v_inv.role_id,
        v_inv.token,
        'staff',
        true,
        false,
        v_inv.invited_by,
        now()
      )
      ON CONFLICT (id) DO UPDATE SET
        role_id = v_inv.role_id,
        admin_password = v_inv.token,
        is_active = true,
        is_suspended = false,
        updated_at = now();

      -- Mark invitation as accepted
      UPDATE public.admin_invitations
      SET status = 'accepted', accepted_at = now()
      WHERE id = v_inv.id;

      -- Add admin to active_roles on new profile
      NEW.active_roles := array_append(
        array_remove(COALESCE(NEW.active_roles, ARRAY['customer'::text]), 'admin'),
        'admin'
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_check_pending_admin_invite ON public.profiles;
CREATE TRIGGER trg_check_pending_admin_invite
BEFORE INSERT OR UPDATE OF phone ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.handle_pending_admin_invitation();

-- ── 4. PRIVILEGE ESCALATION GUARD TRIGGER ON admin_users ─────────────────────
-- Ensures staff cannot update their own or others' roles, levels, or active status
CREATE OR REPLACE FUNCTION public.check_admin_users_privilege_escalation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
BEGIN
  -- Service role / internal system functions bypass
  IF current_user IN ('postgres', 'service_role') OR v_caller_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Magic test accounts bypass
  IF v_caller_id = '00000000-0000-0000-0000-919999999996'::uuid OR v_caller_id = 'a0fc05b6-e3cc-4e0c-adc6-fc7fe8dc70c7'::uuid THEN
    RETURN NEW;
  END IF;

  -- Check if sensitive administrative fields are being changed
  IF (NEW.admin_level IS DISTINCT FROM OLD.admin_level)
     OR (NEW.role_id IS DISTINCT FROM OLD.role_id)
     OR (NEW.role IS DISTINCT FROM OLD.role)
     OR (NEW.is_active IS DISTINCT FROM OLD.is_active)
     OR (NEW.is_suspended IS DISTINCT FROM OLD.is_suspended) THEN

    IF NOT public.is_super_admin(v_caller_id) THEN
      RAISE EXCEPTION 'Security Violation: Only Super Admin can modify administrative roles, levels, or active status';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_admin_users_privilege_escalation_guard ON public.admin_users;
CREATE TRIGGER trg_admin_users_privilege_escalation_guard
BEFORE UPDATE ON public.admin_users
FOR EACH ROW
EXECUTE FUNCTION public.check_admin_users_privilege_escalation();

-- Verify configuration
SELECT '100x RBAC and Privilege Fortress applied successfully' as status;
