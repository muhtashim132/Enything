-- ============================================================
-- ENYTHING RBAC SYSTEM - Complete Database Migration
-- ============================================================

-- ── 1. PERMISSIONS TABLE ────────────────────────────────────
CREATE TABLE IF NOT EXISTS permissions (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code        TEXT UNIQUE NOT NULL,
  name        TEXT NOT NULL,
  description TEXT,
  module      TEXT NOT NULL,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ── 2. ROLES TABLE ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS roles (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT UNIQUE NOT NULL,
  slug        TEXT UNIQUE NOT NULL,
  description TEXT,
  is_system   BOOLEAN DEFAULT FALSE,
  color       TEXT DEFAULT '#8B2FC9',
  icon        TEXT DEFAULT 'shield',
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  updated_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ── 3. ROLE_PERMISSIONS TABLE ────────────────────────────────
CREATE TABLE IF NOT EXISTS role_permissions (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  role_id       UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
  permission_id UUID NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (role_id, permission_id)
);

-- ── 4. ADMIN_USERS TABLE (RBAC enhanced) ─────────────────────
CREATE TABLE IF NOT EXISTS admin_users (
  id             UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email          TEXT NOT NULL,
  full_name      TEXT NOT NULL,
  phone          TEXT,
  avatar_url     TEXT,
  role_id        UUID REFERENCES roles(id),
  admin_level    TEXT NOT NULL DEFAULT 'admin',
  admin_password TEXT,
  is_active      BOOLEAN DEFAULT TRUE,
  is_suspended   BOOLEAN DEFAULT FALSE,
  suspended_at   TIMESTAMPTZ,
  suspended_by   UUID,
  last_login_at  TIMESTAMPTZ,
  created_at     TIMESTAMPTZ DEFAULT NOW(),
  updated_at     TIMESTAMPTZ DEFAULT NOW()
);

-- ── UPGRADE EXISTING ADMIN_USERS ─────────────────────────────
-- If the table already existed, it might be missing the new columns.
-- This safely adds them so the rest of the script doesn't fail.
DO $$ 
BEGIN 
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='admin_users' AND column_name='role_id') THEN
        ALTER TABLE admin_users ADD COLUMN role_id UUID REFERENCES roles(id);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='admin_users' AND column_name='phone') THEN
        ALTER TABLE admin_users ADD COLUMN phone TEXT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='admin_users' AND column_name='avatar_url') THEN
        ALTER TABLE admin_users ADD COLUMN avatar_url TEXT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='admin_users' AND column_name='is_suspended') THEN
        ALTER TABLE admin_users ADD COLUMN is_suspended BOOLEAN DEFAULT FALSE;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='admin_users' AND column_name='suspended_at') THEN
        ALTER TABLE admin_users ADD COLUMN suspended_at TIMESTAMPTZ;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='admin_users' AND column_name='suspended_by') THEN
        ALTER TABLE admin_users ADD COLUMN suspended_by UUID;
    END IF;
END $$;

-- ── 5. USER_ROLE_OVERRIDES TABLE ─────────────────────────────
CREATE TABLE IF NOT EXISTS user_role_overrides (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES admin_users(id) ON DELETE CASCADE,
  permission_id UUID NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
  granted       BOOLEAN NOT NULL DEFAULT TRUE,
  reason        TEXT,
  granted_by    UUID,
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (user_id, permission_id)
);

-- ── 6. ADMIN_INVITATIONS TABLE ───────────────────────────────
CREATE TABLE IF NOT EXISTS admin_invitations (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email        TEXT NOT NULL,
  role_id      UUID NOT NULL REFERENCES roles(id),
  token        TEXT UNIQUE NOT NULL DEFAULT encode(gen_random_bytes(32), 'hex'),
  invited_by   UUID NOT NULL,
  status       TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','accepted','expired','revoked')),
  expires_at   TIMESTAMPTZ DEFAULT NOW() + INTERVAL '7 days',
  accepted_at  TIMESTAMPTZ,
  created_at   TIMESTAMPTZ DEFAULT NOW()
);

-- ── 7. AUDIT_LOGS TABLE ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS audit_logs (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id    UUID,
  actor_role  TEXT,
  action      TEXT NOT NULL,
  entity_type TEXT,
  entity_id   UUID,
  metadata    JSONB DEFAULT '{}',
  ip_address  INET,
  device_info TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ── INDEXES ──────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_audit_logs_actor     ON audit_logs(actor_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action    ON audit_logs(action);
CREATE INDEX IF NOT EXISTS idx_audit_logs_entity    ON audit_logs(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created   ON audit_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_role_permissions_rid ON role_permissions(role_id);
CREATE INDEX IF NOT EXISTS idx_admin_users_role     ON admin_users(role_id);
CREATE INDEX IF NOT EXISTS idx_invitations_email    ON admin_invitations(email);
CREATE INDEX IF NOT EXISTS idx_invitations_token    ON admin_invitations(token);

-- ── SEED: PERMISSIONS ─────────────────────────────────────────
INSERT INTO permissions (code, name, module, description) VALUES
-- Dashboard
('dashboard.view','View Dashboard','Dashboard','Access the main admin dashboard'),
-- Orders
('orders.view','View Orders','Orders','View all orders'),
('orders.assign','Assign Orders','Orders','Assign orders to riders'),
('orders.cancel','Cancel Orders','Orders','Cancel customer orders'),
('orders.refund','Refund Orders','Orders','Issue order refunds'),
('orders.override_status','Override Order Status','Orders','Manually override order status'),
-- Customers
('customers.view','View Customers','Customers','View customer list and details'),
('customers.edit','Edit Customers','Customers','Edit customer profiles'),
('customers.block','Block Customers','Customers','Block/unblock customers'),
-- Sellers
('sellers.view','View Sellers','Sellers','View seller list and details'),
('sellers.approve','Approve Sellers','Sellers','Approve new seller applications'),
('sellers.reject','Reject Sellers','Sellers','Reject seller applications'),
('sellers.suspend','Suspend Sellers','Sellers','Suspend seller accounts'),
('sellers.payouts','Manage Seller Payouts','Sellers','Manage seller payout settings'),
-- Riders
('riders.view','View Riders','Riders','View rider list and details'),
('riders.approve','Approve Riders','Riders','Approve new rider applications'),
('riders.suspend','Suspend Riders','Riders','Suspend rider accounts'),
('riders.earnings','Manage Rider Earnings','Riders','View and manage rider earnings'),
-- Payments
('payments.view','View Payments','Payments','View payment transactions'),
('payments.refund','Refund Payments','Payments','Process payment refunds'),
('payments.manual_adjustment','Manual Payment Adjustment','Payments','Apply manual adjustments'),
-- Withdrawals
('withdrawals.view','View Withdrawals','Withdrawals','View withdrawal requests'),
('withdrawals.approve','Approve Withdrawals','Withdrawals','Approve withdrawal requests'),
('withdrawals.reject','Reject Withdrawals','Withdrawals','Reject withdrawal requests'),
-- Marketing
('marketing.view','View Marketing','Marketing','View campaigns and marketing data'),
('marketing.send_push','Send Push Notifications','Marketing','Send push notifications'),
('marketing.send_sms','Send SMS','Marketing','Send SMS campaigns'),
('marketing.send_email','Send Emails','Marketing','Send email campaigns'),
-- Support
('support.view','View Support Tickets','Support','View customer support tickets'),
('support.reply','Reply to Tickets','Support','Reply to support tickets'),
('support.close','Close Tickets','Support','Close support tickets'),
-- Finance
('finance.view','View Finance','Finance','View financial reports'),
('finance.export','Export Finance Data','Finance','Export financial data'),
('finance.payouts','Manage Payouts','Finance','Manage payout schedules'),
-- Analytics
('analytics.view','View Analytics','Analytics','View analytics dashboards'),
('analytics.export','Export Analytics','Analytics','Export analytics data'),
-- Settings
('settings.view','View Settings','Settings','View system settings'),
('settings.edit','Edit Settings','Settings','Modify system settings'),
-- Roles
('roles.view','View Roles','Roles','View role list'),
('roles.create','Create Roles','Roles','Create new roles'),
('roles.edit','Edit Roles','Roles','Edit existing roles'),
('roles.delete','Delete Roles','Roles','Delete custom roles'),
('roles.assign','Assign Roles','Roles','Assign roles to team members'),
-- Audit
('audit.view','View Audit Logs','Audit','View system audit logs'),
-- System
('system.backup','System Backup','System','Trigger system backups'),
('system.restore','System Restore','System','Restore from backups'),
('system.maintenance','System Maintenance','System','Toggle maintenance mode')
ON CONFLICT (code) DO NOTHING;

-- ── SEED: ROLES ───────────────────────────────────────────────
INSERT INTO roles (name, slug, description, is_system, color, icon) VALUES
('Super Admin', 'super_admin', 'Full unrestricted access to all modules and actions', TRUE, '#F4C542', 'crown'),
('Admin', 'admin', 'Full operational access except billing and system settings', TRUE, '#8B2FC9', 'shield'),
('Operations Manager', 'operations_manager', 'Orders, sellers, riders, support, analytics', TRUE, '#2196F3', 'operations'),
('Customer Support Agent', 'customer_support', 'Customer support, tickets, limited refunds', TRUE, '#4CAF50', 'support_agent'),
('Seller Manager', 'seller_manager', 'Seller onboarding, approvals, suspensions, payouts', TRUE, '#FF9800', 'store'),
('Rider Manager', 'rider_manager', 'Rider approvals, assignments, earnings management', TRUE, '#00BCD4', 'delivery_dining'),
('Finance Manager', 'finance_manager', 'Payments, settlements, withdrawals, exports', TRUE, '#E91E63', 'account_balance'),
('Marketing Manager', 'marketing_manager', 'Campaigns, coupons, push notifications', TRUE, '#9C27B0', 'campaign'),
('Compliance Moderator', 'compliance_moderator', 'KYC verification, disputes, review moderation', TRUE, '#FF5722', 'gavel'),
('Analytics Viewer', 'analytics_viewer', 'Read-only reports and analytics access', TRUE, '#607D8B', 'bar_chart')
ON CONFLICT (slug) DO NOTHING;

-- ── SEED: ROLE_PERMISSIONS (Super Admin = All) ─────────────────
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p
WHERE r.slug = 'super_admin'
ON CONFLICT DO NOTHING;

-- Admin (all except system.*)
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p
WHERE r.slug = 'admin' AND p.code NOT IN ('system.backup','system.restore','system.maintenance')
ON CONFLICT DO NOTHING;

-- Operations Manager
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p
WHERE r.slug = 'operations_manager'
  AND p.code IN (
    'dashboard.view','orders.view','orders.assign','orders.cancel','orders.override_status',
    'sellers.view','sellers.approve','sellers.reject','sellers.suspend',
    'riders.view','riders.approve','riders.suspend',
    'support.view','support.reply','support.close',
    'analytics.view','analytics.export','customers.view'
  )
ON CONFLICT DO NOTHING;

-- Customer Support Agent
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p
WHERE r.slug = 'customer_support'
  AND p.code IN (
    'dashboard.view','orders.view','orders.refund',
    'customers.view','customers.edit',
    'support.view','support.reply','support.close'
  )
ON CONFLICT DO NOTHING;

-- Seller Manager
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p
WHERE r.slug = 'seller_manager'
  AND p.code IN (
    'dashboard.view','sellers.view','sellers.approve','sellers.reject',
    'sellers.suspend','sellers.payouts','analytics.view'
  )
ON CONFLICT DO NOTHING;

-- Rider Manager
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p
WHERE r.slug = 'rider_manager'
  AND p.code IN (
    'dashboard.view','riders.view','riders.approve','riders.suspend',
    'riders.earnings','orders.assign','analytics.view'
  )
ON CONFLICT DO NOTHING;

-- Finance Manager
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p
WHERE r.slug = 'finance_manager'
  AND p.code IN (
    'dashboard.view','payments.view','payments.refund','payments.manual_adjustment',
    'withdrawals.view','withdrawals.approve','withdrawals.reject',
    'finance.view','finance.export','finance.payouts','analytics.view','analytics.export'
  )
ON CONFLICT DO NOTHING;

-- Marketing Manager
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p
WHERE r.slug = 'marketing_manager'
  AND p.code IN (
    'dashboard.view','marketing.view','marketing.send_push',
    'marketing.send_sms','marketing.send_email','analytics.view'
  )
ON CONFLICT DO NOTHING;

-- Compliance Moderator
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p
WHERE r.slug = 'compliance_moderator'
  AND p.code IN (
    'dashboard.view','sellers.view','sellers.approve','sellers.reject',
    'riders.view','riders.approve','customers.view','customers.block',
    'support.view','support.close','audit.view'
  )
ON CONFLICT DO NOTHING;

-- Analytics Viewer
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p
WHERE r.slug = 'analytics_viewer'
  AND p.code IN ('dashboard.view','analytics.view','analytics.export','finance.view')
ON CONFLICT DO NOTHING;

-- ── HELPER FUNCTIONS ──────────────────────────────────────────

-- Get all effective permissions for a user (role + overrides)
CREATE OR REPLACE FUNCTION get_user_permissions(p_user_id UUID)
RETURNS TABLE(code TEXT) AS $$
DECLARE
  v_role_id UUID;
  v_is_super BOOLEAN;
BEGIN
  SELECT au.role_id INTO v_role_id FROM admin_users au WHERE au.id = p_user_id;

  SELECT EXISTS(
    SELECT 1 FROM roles r WHERE r.id = v_role_id AND r.slug = 'super_admin'
  ) INTO v_is_super;

  IF v_is_super THEN
    RETURN QUERY SELECT p.code FROM permissions p;
    RETURN;
  END IF;

  RETURN QUERY
    SELECT p.code
    FROM role_permissions rp
    JOIN permissions p ON p.id = rp.permission_id
    WHERE rp.role_id = v_role_id
    UNION
    SELECT p.code
    FROM user_role_overrides uro
    JOIN permissions p ON p.id = uro.permission_id
    WHERE uro.user_id = p_user_id AND uro.granted = TRUE
    EXCEPT
    SELECT p.code
    FROM user_role_overrides uro
    JOIN permissions p ON p.id = uro.permission_id
    WHERE uro.user_id = p_user_id AND uro.granted = FALSE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Check if user has a specific permission
CREATE OR REPLACE FUNCTION has_permission(p_user_id UUID, p_code TEXT)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS(SELECT 1 FROM get_user_permissions(p_user_id) WHERE code = p_code);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Check if user is super admin
CREATE OR REPLACE FUNCTION is_super_admin(p_user_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS(
    SELECT 1 FROM admin_users au
    JOIN roles r ON r.id = au.role_id
    WHERE au.id = p_user_id AND r.slug = 'super_admin' AND au.is_active = TRUE
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Audit log helper
CREATE OR REPLACE FUNCTION log_audit_event(
  p_actor_id    UUID,
  p_actor_role  TEXT,
  p_action      TEXT,
  p_entity_type TEXT DEFAULT NULL,
  p_entity_id   UUID DEFAULT NULL,
  p_metadata    JSONB DEFAULT '{}'
) RETURNS VOID AS $$
BEGIN
  INSERT INTO audit_logs(actor_id, actor_role, action, entity_type, entity_id, metadata)
  VALUES (p_actor_id, p_actor_role, p_action, p_entity_type, p_entity_id, p_metadata);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_roles_updated_at
  BEFORE UPDATE ON roles FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE OR REPLACE TRIGGER trg_admin_users_updated_at
  BEFORE UPDATE ON admin_users FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ── ROW LEVEL SECURITY ────────────────────────────────────────
ALTER TABLE roles              ENABLE ROW LEVEL SECURITY;
ALTER TABLE permissions        ENABLE ROW LEVEL SECURITY;
ALTER TABLE role_permissions   ENABLE ROW LEVEL SECURITY;
ALTER TABLE admin_users        ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_role_overrides ENABLE ROW LEVEL SECURITY;
ALTER TABLE admin_invitations  ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs         ENABLE ROW LEVEL SECURITY;

-- Roles: readable by all authenticated admins, writable by super admin
CREATE POLICY "admins_read_roles" ON roles
  FOR SELECT TO authenticated
  USING (EXISTS(SELECT 1 FROM admin_users WHERE id = auth.uid() AND is_active = TRUE));

CREATE POLICY "superadmin_write_roles" ON roles
  FOR ALL TO authenticated
  USING (is_super_admin(auth.uid()))
  WITH CHECK (is_super_admin(auth.uid()));

-- Permissions: read by all admins
CREATE POLICY "admins_read_permissions" ON permissions
  FOR SELECT TO authenticated
  USING (EXISTS(SELECT 1 FROM admin_users WHERE id = auth.uid() AND is_active = TRUE));

-- Role permissions: read by admins, write by super admin
CREATE POLICY "admins_read_role_permissions" ON role_permissions
  FOR SELECT TO authenticated
  USING (EXISTS(SELECT 1 FROM admin_users WHERE id = auth.uid() AND is_active = TRUE));

CREATE POLICY "superadmin_write_role_permissions" ON role_permissions
  FOR ALL TO authenticated
  USING (is_super_admin(auth.uid()))
  WITH CHECK (is_super_admin(auth.uid()));

-- Admin users: admins see all, only super admin can modify
CREATE POLICY "admins_read_admin_users" ON admin_users
  FOR SELECT TO authenticated
  USING (has_permission(auth.uid(), 'roles.view') OR id = auth.uid());

CREATE POLICY "superadmin_write_admin_users" ON admin_users
  FOR ALL TO authenticated
  USING (is_super_admin(auth.uid()) OR id = auth.uid())
  WITH CHECK (is_super_admin(auth.uid()) OR id = auth.uid());

-- Audit logs: readable by users with audit.view
CREATE POLICY "audit_readers" ON audit_logs
  FOR SELECT TO authenticated
  USING (has_permission(auth.uid(), 'audit.view'));

CREATE POLICY "audit_insert" ON audit_logs
  FOR INSERT TO authenticated WITH CHECK (TRUE);

-- Invitations: super admin manages
CREATE POLICY "superadmin_invitations" ON admin_invitations
  FOR ALL TO authenticated
  USING (is_super_admin(auth.uid()) OR invited_by = auth.uid());

-- User overrides: super admin manages
CREATE POLICY "superadmin_overrides" ON user_role_overrides
  FOR ALL TO authenticated
  USING (is_super_admin(auth.uid()));

