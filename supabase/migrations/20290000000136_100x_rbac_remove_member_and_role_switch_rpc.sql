-- ============================================================================
-- 100x RBAC SECURITY: PERMANENT TEAM MEMBER REMOVAL & ROLE SWITCH RPCs
-- Migration: 20290000000136_100x_rbac_remove_member_and_role_switch_rpc.sql
-- ============================================================================

-- ── 1. RPC: admin_remove_team_member ─────────────────────────────────────────
-- Permanently removes a staff member from admin_users, removes admin role from
-- profiles.active_roles, revokes admin sessions, and cleans up any invitations.
CREATE OR REPLACE FUNCTION public.admin_remove_team_member(
  p_user_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_target_phone TEXT;
  v_target_email TEXT;
  v_10 TEXT;
BEGIN
  -- Strict Authorization: Only Super Admin can permanently remove team members
  IF NOT public.is_super_admin(v_caller_id) THEN
    RAISE EXCEPTION 'Access denied: Only Super Admins can remove team members';
  END IF;

  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'User ID is required';
  END IF;

  -- Prevent self-deletion
  IF p_user_id = v_caller_id THEN
    RAISE EXCEPTION 'Cannot remove your own account from the team';
  END IF;

  -- Fetch target phone / email for cleaning invitations and active sessions
  SELECT phone, email INTO v_target_phone, v_target_email
  FROM public.admin_users
  WHERE id = p_user_id;

  -- 1. Delete from admin_users
  DELETE FROM public.admin_users WHERE id = p_user_id;

  -- 2. Remove 'admin' from profiles active_roles and reset role if necessary
  UPDATE public.profiles
  SET active_roles = array_remove(COALESCE(active_roles, ARRAY['customer'::text]), 'admin'),
      role = CASE WHEN role = 'admin' THEN 'customer' ELSE role END
  WHERE id = p_user_id;

  -- 3. Delete any active admin sessions
  DELETE FROM public.admin_sessions WHERE admin_id = p_user_id;

  -- 4. Revoke/delete any admin invitations for this phone or email
  IF v_target_phone IS NOT NULL AND v_target_phone <> '' THEN
    v_10 := right(regexp_replace(v_target_phone, '\D', '', 'g'), 10);
    DELETE FROM public.admin_invitations
    WHERE right(regexp_replace(COALESCE(email, ''), '\D', '', 'g'), 10) = v_10;
  END IF;

  IF v_target_email IS NOT NULL AND v_target_email <> '' THEN
    DELETE FROM public.admin_invitations WHERE email = v_target_email;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'message', 'Team member permanently removed'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_remove_team_member(UUID) TO authenticated, service_role;

-- ── 2. RPC: admin_assign_member_role ─────────────────────────────────────────
-- Assigns a new role to an existing staff member, updating role_id and role slug.
CREATE OR REPLACE FUNCTION public.admin_assign_member_role(
  p_user_id UUID,
  p_role_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_role RECORD;
BEGIN
  IF NOT (public.is_super_admin(v_caller_id) OR public.has_permission(v_caller_id, 'roles.assign')) THEN
    RAISE EXCEPTION 'Access denied: Super Admin or roles.assign permission required to change roles';
  END IF;

  IF p_user_id IS NULL OR p_role_id IS NULL THEN
    RAISE EXCEPTION 'Both User ID and Role ID are required';
  END IF;

  SELECT * INTO v_role FROM public.roles WHERE id = p_role_id;
  IF v_role.id IS NULL THEN
    RAISE EXCEPTION 'The specified role does not exist';
  END IF;

  IF v_role.slug = 'super_admin' AND NOT public.is_super_admin(v_caller_id) THEN
    RAISE EXCEPTION 'Security violation: Only Super Admins can assign the Super Admin role';
  END IF;

  -- Update admin_users with new role_id and role slug
  UPDATE public.admin_users
  SET role_id = p_role_id,
      role = v_role.slug,
      updated_at = now()
  WHERE id = p_user_id;

  RETURN jsonb_build_object(
    'success', true,
    'role_name', v_role.name,
    'role_slug', v_role.slug,
    'message', 'Role updated to ' || v_role.name
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_assign_member_role(UUID, UUID) TO authenticated, service_role;
