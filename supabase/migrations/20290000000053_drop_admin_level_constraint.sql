-- =============================================================================
-- Migration: 20290000000053_drop_admin_level_constraint.sql
-- Description:
--   1. Drops admin_users_admin_level_check constraint.
--   2. Updates accept_admin_invitation to use 'super_admin'.
-- =============================================================================

-- Drop restrictive admin_level check constraint
ALTER TABLE public.admin_users DROP CONSTRAINT IF EXISTS admin_users_admin_level_check;
ALTER TABLE public.admin_users ALTER COLUMN admin_level DROP NOT NULL;

-- Patch accept_admin_invitation RPC
CREATE OR REPLACE FUNCTION public.accept_admin_invitation(
  p_token         TEXT,
  p_auth_user_id  UUID,
  p_full_name     TEXT,
  p_admin_password TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invite public.admin_invitations%ROWTYPE;
  v_role_id UUID;
BEGIN
  -- Fetch and validate the invitation
  SELECT * INTO v_invite
  FROM public.admin_invitations
  WHERE token = p_token
    AND expires_at > NOW()
    AND accepted_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid or expired invite code.';
  END IF;

  -- Use role_id directly if present, else look up by role_name or fallback to first role
  IF v_invite.role_id IS NOT NULL THEN
    v_role_id := v_invite.role_id;
  ELSE
    SELECT id INTO v_role_id
    FROM public.roles
    WHERE slug = v_invite.role_name OR name = v_invite.role_name
    LIMIT 1;
  END IF;

  IF v_role_id IS NULL THEN
    SELECT id INTO v_role_id FROM public.roles LIMIT 1;
  END IF;

  -- Insert into admin_users
  INSERT INTO public.admin_users (
    id, full_name, role_id, admin_level, admin_password, is_active
  ) VALUES (
    p_auth_user_id,
    p_full_name,
    v_role_id,
    'super_admin',
    p_admin_password,
    true
  )
  ON CONFLICT (id) DO UPDATE SET
    full_name      = EXCLUDED.full_name,
    role_id        = COALESCE(EXCLUDED.role_id, admin_users.role_id),
    admin_level    = 'super_admin',
    is_active      = true;

  -- Mark invitation as accepted
  UPDATE public.admin_invitations
  SET accepted_at = NOW(),
      status = 'accepted'
  WHERE token = p_token;

  -- Upsert profile
  INSERT INTO public.profiles (id, full_name, role, phone)
  VALUES (p_auth_user_id, p_full_name, 'customer', '')
  ON CONFLICT (id) DO UPDATE SET
    full_name = EXCLUDED.full_name;
END;
$$;

GRANT EXECUTE ON FUNCTION public.accept_admin_invitation(TEXT, UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.accept_admin_invitation(TEXT, UUID, TEXT, TEXT) TO anon;

NOTIFY pgrst, 'reload schema';
