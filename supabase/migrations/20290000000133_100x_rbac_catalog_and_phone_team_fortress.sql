-- Migration: 20290000000133_100x_rbac_catalog_and_phone_team_fortress.sql
-- Description: 100x RBAC Catalog Management Permissions, Schema Dedup, and Phone-Based Team Member Provisioning

-- ── 1. Drop Duplicate Foreign Key Constraints (Fixes PGRST201 PostgREST Embedding) ──
ALTER TABLE public.role_permissions DROP CONSTRAINT IF EXISTS fk_role_permissions_role;
ALTER TABLE public.role_permissions DROP CONSTRAINT IF EXISTS fk_role_permissions_perm;
ALTER TABLE public.admin_users DROP CONSTRAINT IF EXISTS fk_admin_users_roles;

-- ── 2. Add Products Module Permissions ──────────────────────────────────────────────
INSERT INTO public.permissions (id, code, name, module, description)
VALUES 
  (gen_random_uuid(), 'products.view', 'View Products', 'Products', 'View products and catalog across all shops'),
  (gen_random_uuid(), 'products.manage', 'Manage Products', 'Products', 'Add, edit, toggle availability and manage products across all shops'),
  (gen_random_uuid(), 'products.create', 'Create Products', 'Products', 'Upload and create new products for shops'),
  (gen_random_uuid(), 'products.delete', 'Delete Products', 'Products', 'Delete products from shops')
ON CONFLICT (code) DO UPDATE SET 
  name = EXCLUDED.name,
  module = EXCLUDED.module,
  description = EXCLUDED.description;

-- Grant permissions to Super Admin and Admin roles
DO $$
DECLARE
  v_perm_id UUID;
  v_super_admin_id UUID;
  v_admin_id UUID;
  v_perm_code TEXT;
BEGIN
  SELECT id INTO v_super_admin_id FROM public.roles WHERE slug = 'super_admin' LIMIT 1;
  SELECT id INTO v_admin_id FROM public.roles WHERE slug = 'admin' LIMIT 1;

  FOR v_perm_code IN SELECT unnest(ARRAY['products.view', 'products.manage', 'products.create', 'products.delete'])
  LOOP
    SELECT id INTO v_perm_id FROM public.permissions WHERE code = v_perm_code;
    
    IF v_super_admin_id IS NOT NULL AND v_perm_id IS NOT NULL THEN
      INSERT INTO public.role_permissions (id, role_id, permission_id)
      VALUES (gen_random_uuid(), v_super_admin_id, v_perm_id)
      ON CONFLICT DO NOTHING;
    END IF;

    IF v_admin_id IS NOT NULL AND v_perm_id IS NOT NULL THEN
      INSERT INTO public.role_permissions (id, role_id, permission_id)
      VALUES (gen_random_uuid(), v_admin_id, v_perm_id)
      ON CONFLICT DO NOTHING;
    END IF;
  END LOOP;
END $$;

-- ── 3. Seed "Catalog Manager" Role ──────────────────────────────────────────────────
DO $$
DECLARE
  v_cat_role_id UUID;
  v_perm_id UUID;
  v_code TEXT;
BEGIN
  -- Check if catalog_manager role exists, if not create it
  SELECT id INTO v_cat_role_id FROM public.roles WHERE slug = 'catalog_manager' LIMIT 1;
  
  IF v_cat_role_id IS NULL THEN
    INSERT INTO public.roles (id, name, slug, description, is_system, color, icon)
    VALUES (
      gen_random_uuid(),
      'Catalog Manager',
      'catalog_manager',
      'Upload, edit, and manage product catalogs, pricing and inventory for all shops.',
      true,
      '#10B981',
      'inventory'
    )
    RETURNING id INTO v_cat_role_id;
  END IF;

  -- Attach appropriate permissions to Catalog Manager
  FOR v_code IN SELECT unnest(ARRAY['dashboard.view', 'products.manage', 'products.view', 'products.create', 'sellers.view'])
  LOOP
    SELECT id INTO v_perm_id FROM public.permissions WHERE code = v_code;
    IF v_perm_id IS NOT NULL THEN
      INSERT INTO public.role_permissions (id, role_id, permission_id)
      VALUES (gen_random_uuid(), v_cat_role_id, v_perm_id)
      ON CONFLICT DO NOTHING;
    END IF;
  END LOOP;
END $$;

-- ── 4. RPC: Add Team Member by Phone Number ──────────────────────────────────────────
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
  v_clean_phone TEXT;
  v_user_id UUID;
  v_role_name TEXT;
BEGIN
  -- Strict Authorization: Only active admins can add team members
  IF NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied: admin only';
  END IF;

  -- Sanitize phone
  v_clean_phone := trim(p_phone);
  IF NOT v_clean_phone LIKE '+%' THEN
    IF length(v_clean_phone) = 10 THEN
      v_clean_phone := '+91' || v_clean_phone;
    ELSE
      v_clean_phone := '+' || v_clean_phone;
    END IF;
  END IF;

  -- Get role name
  SELECT name INTO v_role_name FROM public.roles WHERE id = p_role_id;
  IF v_role_name IS NULL THEN
    RAISE EXCEPTION 'Invalid role ID';
  END IF;

  -- 1. Check if user already exists in profiles
  SELECT id INTO v_user_id 
  FROM public.profiles 
  WHERE phone = v_clean_phone 
     OR phone = replace(v_clean_phone, '+', '')
     OR phone = substring(v_clean_phone from 4)
  LIMIT 1;

  IF v_user_id IS NOT NULL THEN
    -- User already registered: immediately provision admin_users entry
    INSERT INTO public.admin_users (
      id,
      full_name,
      phone,
      role,
      role_id,
      admin_password,
      admin_level,
      is_active,
      is_suspended,
      created_by
    )
    VALUES (
      v_user_id,
      COALESCE(NULLIF(trim(p_full_name), ''), 'Staff Member'),
      v_clean_phone,
      'admin',
      p_role_id,
      trim(p_admin_password),
      'staff',
      true,
      false,
      auth.uid()
    )
    ON CONFLICT (id) DO UPDATE SET
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
      'message', 'Team member provisioned and activated successfully!'
    );
  ELSE
    -- 2. User has not registered yet: record in admin_invitations with phone
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
      v_clean_phone, -- store phone in email column
      p_role_id,
      v_role_name,
      trim(p_admin_password), -- store admin password in token
      auth.uid(),
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

-- ── 5. Trigger: Auto-activate Pending Admin on Profile Creation ──────────────────────
CREATE OR REPLACE FUNCTION public.handle_pending_admin_invitation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inv RECORD;
BEGIN
  IF NEW.phone IS NOT NULL AND NEW.phone <> '' THEN
    SELECT * INTO v_inv
    FROM public.admin_invitations
    WHERE (email = NEW.phone OR email = '+' || NEW.phone OR email = substring(NEW.phone from 4))
      AND status = 'pending'
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_inv.id IS NOT NULL THEN
      -- Provision admin_users entry
      INSERT INTO public.admin_users (
        id,
        full_name,
        phone,
        role,
        role_id,
        admin_password,
        admin_level,
        is_active,
        is_suspended,
        created_by
      )
      VALUES (
        NEW.id,
        COALESCE(NULLIF(NEW.full_name, ''), 'Staff Member'),
        NEW.phone,
        'admin',
        v_inv.role_id,
        v_inv.token,
        'staff',
        true,
        false,
        v_inv.invited_by
      )
      ON CONFLICT (id) DO UPDATE SET
        role_id = v_inv.role_id,
        admin_password = v_inv.token,
        is_active = true,
        is_suspended = false;

      -- Mark invitation as accepted
      UPDATE public.admin_invitations
      SET status = 'accepted', accepted_at = now()
      WHERE id = v_inv.id;

      -- Add admin to active_roles
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
