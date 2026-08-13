-- =============================================================================
-- Migration: 20290000000057_comprehensive_backend_fortification.sql
-- Description:
--   1. Implements public.is_super_admin(p_user_id UUID) helper.
--   2. Implements public.get_user_permissions(p_user_id UUID) RPC returning TABLE(code TEXT).
--   3. Implements public.has_permission(p_user_id UUID, p_code TEXT) RPC returning BOOLEAN.
--   4. Implements public.rider_reject_order(p_order_id UUID, p_rider_id UUID) RPC
--      to handle lock-screen / notification decline actions gracefully.
--   5. Sets REPLICA IDENTITY FULL on platform_config, tax_config, and custom_categories
--      to ensure full row data in Realtime publication payloads.
-- =============================================================================

-- ── 1. Function: is_super_admin ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.is_super_admin(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF p_user_id IS NULL THEN
    RETURN FALSE;
  END IF;

  RETURN EXISTS (
    SELECT 1 
    FROM public.admin_users au
    LEFT JOIN public.roles r ON r.id = au.role_id
    WHERE au.id = p_user_id 
      AND au.is_active = TRUE 
      AND (au.is_suspended IS DISTINCT FROM TRUE)
      AND (
        au.admin_level IN ('super_admin', 'superadmin', '100')
        OR r.slug IN ('super_admin', 'superadmin')
        OR r.name ILIKE '%super%admin%'
      )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.is_super_admin(UUID) TO authenticated, service_role, anon;


-- ── 2. Function: get_user_permissions ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_user_permissions(p_user_id UUID)
RETURNS TABLE(code TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF p_user_id IS NULL THEN
    RETURN;
  END IF;

  -- If user is a super admin, grant all defined permissions
  IF public.is_super_admin(p_user_id) THEN
    RETURN QUERY
    SELECT p.code::TEXT
    FROM public.permissions p;
    RETURN;
  END IF;

  -- Otherwise, resolve effective permissions through assigned role
  RETURN QUERY
  SELECT DISTINCT p.code::TEXT
  FROM public.admin_users au
  JOIN public.role_permissions rp ON rp.role_id = au.role_id
  JOIN public.permissions p ON p.id = rp.permission_id
  WHERE au.id = p_user_id
    AND au.is_active = TRUE
    AND (au.is_suspended IS DISTINCT FROM TRUE);
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_user_permissions(UUID) TO authenticated, service_role, anon;


-- ── 3. Function: has_permission ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.has_permission(p_user_id UUID, p_code TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF p_user_id IS NULL OR p_code IS NULL THEN
    RETURN FALSE;
  END IF;

  -- Super admin has all permissions
  IF public.is_super_admin(p_user_id) THEN
    RETURN TRUE;
  END IF;

  -- Check if specific permission code is granted to user
  RETURN EXISTS (
    SELECT 1
    FROM public.get_user_permissions(p_user_id) g
    WHERE g.code = p_code
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.has_permission(UUID, TEXT) TO authenticated, service_role, anon;


-- ── 4. Function: rider_reject_order ──────────────────────────────────────────
-- Safe decline RPC called from notification action handlers in Flutter client
CREATE OR REPLACE FUNCTION public.rider_reject_order(
  p_order_id UUID,
  p_rider_id UUID DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_rider_id UUID;
  v_assigned_dp_id UUID;
BEGIN
  IF p_order_id IS NULL THEN
    RETURN;
  END IF;

  v_rider_id := COALESCE(p_rider_id, auth.uid());

  SELECT delivery_partner_id INTO v_assigned_dp_id
  FROM public.orders
  WHERE id = p_order_id;

  -- If order is assigned to this rider, perform a formal order drop via reject_order_rider
  IF v_assigned_dp_id IS NOT NULL AND v_assigned_dp_id = v_rider_id THEN
    PERFORM public.reject_order_rider(p_order_id, 'Declined via notification', false);
  END IF;

  -- If unassigned (e.g. broadcast notification), the decline action is acknowledged safely
END;
$$;

GRANT EXECUTE ON FUNCTION public.rider_reject_order(UUID, UUID) TO authenticated, service_role, anon;


-- ── 5. Realtime Replica Identity Fortification ──────────────────────────────
ALTER TABLE public.platform_config REPLICA IDENTITY FULL;
ALTER TABLE public.tax_config REPLICA IDENTITY FULL;
ALTER TABLE public.custom_categories REPLICA IDENTITY FULL;


-- ── 6. Reload PostgREST Schema Cache ─────────────────────────────────────────
NOTIFY pgrst, 'reload schema';
