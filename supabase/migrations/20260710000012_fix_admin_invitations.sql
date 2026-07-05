-- ============================================================================
-- Fix Admin Invitations Grants & Columns
-- 
-- 1. Adds missing 'status' column to admin_invitations if it doesn't exist
-- 2. Grants SELECT on roles to authenticated
-- 3. Creates RLS policy to allow authenticated to select from roles
-- ============================================================================

-- 1. Ensure status column exists (Dart code inserts 'status': 'pending')
ALTER TABLE public.admin_invitations ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'pending';

-- 2. Explicitly grant permissions to authenticated for admin_invitations and roles
GRANT SELECT, INSERT, UPDATE, DELETE ON public.admin_invitations TO authenticated;
GRANT SELECT ON public.roles TO authenticated;

-- 3. Ensure RLS policies exist so that authenticated users can select roles during the join
DO $$
BEGIN
  -- Enable RLS on roles if not already enabled
  ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;
  
  -- Create policy for authenticated users to view roles
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'roles'
      AND policyname = 'Authenticated users can view roles'
  ) THEN
    CREATE POLICY "Authenticated users can view roles"
      ON public.roles
      FOR SELECT
      TO authenticated
      USING (true);
  END IF;

  -- Ensure RLS on admin_invitations allows insert/select for authenticated
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'admin_invitations'
      AND policyname = 'Admins can view and manage invitations'
  ) THEN
    CREATE POLICY "Admins can view and manage invitations"
      ON public.admin_invitations
      FOR ALL
      TO authenticated
      USING (true)
      WITH CHECK (true);
  END IF;

END $$;

-- 4. Reload schema cache for PostgREST
NOTIFY pgrst, 'reload schema';
