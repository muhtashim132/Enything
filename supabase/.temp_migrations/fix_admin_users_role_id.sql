-- Migration to fix role_ids for existing admins
-- This ensures users with 'superadmin' admin_level are properly mapped to the new RBAC system

BEGIN;

DO $$ 
DECLARE
  super_admin_role_id UUID;
  admin_role_id UUID;
BEGIN
  -- First, fix the missing updated_at column which causes the trigger to fail on existing tables
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='admin_users' AND column_name='updated_at') THEN
    ALTER TABLE public.admin_users ADD COLUMN updated_at TIMESTAMPTZ DEFAULT NOW();
  END IF;

  -- Get the super admin role id
  SELECT id INTO super_admin_role_id FROM public.roles WHERE slug = 'super_admin' LIMIT 1;
  
  -- Get the admin role id
  SELECT id INTO admin_role_id FROM public.roles WHERE slug = 'admin' LIMIT 1;

  IF super_admin_role_id IS NOT NULL THEN
    -- Update users who were explicitly superadmin before the RBAC migration
    UPDATE public.admin_users 
    SET role_id = super_admin_role_id
    WHERE (admin_level = 'superadmin' OR admin_level = 'super_admin')
      AND role_id IS NULL;
      
    -- Update regular admins
    UPDATE public.admin_users 
    SET role_id = admin_role_id
    WHERE admin_level = 'admin' AND role_id IS NULL;
    
    -- Fallback: If there are any remaining admin users without a role, grant them super admin
    -- so they don't get locked out of their own system.
    UPDATE public.admin_users 
    SET role_id = super_admin_role_id
    WHERE role_id IS NULL;
  END IF;
END $$;

COMMIT;
