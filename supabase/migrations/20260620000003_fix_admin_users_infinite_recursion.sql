-- ============================================================================
-- Migration: 20260620000003_fix_admin_users_infinite_recursion.sql
-- Description: Drops all existing policies on admin_users to eliminate any
--              recursive policies (e.g. policies that call functions which
--              query admin_users), and recreates only the safe non-recursive ones.
-- ============================================================================

DO $$
DECLARE
  pol RECORD;
BEGIN
  -- Dynamically drop ALL policies on admin_users to ensure no hidden recursive policies remain
  FOR pol IN 
    SELECT policyname 
    FROM pg_policies 
    WHERE schemaname = 'public' AND tablename = 'admin_users'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.admin_users', pol.policyname);
  END LOOP;
END $$;

-- Ensure RLS is enabled
ALTER TABLE public.admin_users ENABLE ROW LEVEL SECURITY;

-- Recreate only the safe, non-recursive policies

-- 1. Admin users can always read their own record directly (no function calls)
CREATE POLICY "Admin users can read their own data"
  ON public.admin_users
  FOR SELECT
  TO authenticated
  USING (id = auth.uid());

-- 2. System/Authenticated users can read all admin_users (required so is_active_admin can be evaluated without recursion if invoked as invoker, and so the app can verify roles).
-- This uses a simple boolean, which CANNOT cause recursion.
CREATE POLICY "System can read all admin users"
  ON public.admin_users
  FOR SELECT
  TO authenticated
  USING (true);

-- Ensure is_active_admin is properly defined as SECURITY DEFINER
CREATE OR REPLACE FUNCTION public.is_active_admin(p_uid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $func$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.admin_users
    WHERE id = p_uid AND is_active = TRUE AND (is_suspended IS DISTINCT FROM TRUE)
  );
END;
$func$;

-- Reload Schema Cache
NOTIFY pgrst, 'reload schema';
