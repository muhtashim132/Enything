-- ============================================================================
-- Migration: add_admin_system.sql
-- Purpose  : Create the Enything Admin (God Mode) access control system.
--            Supports superadmin + sub-admin roles with granular permissions.
-- ============================================================================

-- ── 1. Admin Users Table ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS admin_users (
  id              UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name       TEXT NOT NULL,
  phone           TEXT,
  admin_level     TEXT NOT NULL DEFAULT 'operations'
                  CHECK (admin_level IN ('superadmin','operations','verification','finance','support')),
  permissions     JSONB NOT NULL DEFAULT '{
    "view_financials": false,
    "manage_shops": false,
    "manage_riders": false,
    "manage_admins": false,
    "view_master_pnl": false,
    "ban_users": false
  }',
  is_active       BOOLEAN NOT NULL DEFAULT true,
  created_by      UUID REFERENCES admin_users(id),
  admin_password  TEXT,           -- bcrypt hash of secondary password
  notes           TEXT,           -- e.g. "Operations - Bangalore office"
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_login_at   TIMESTAMPTZ
);

COMMENT ON TABLE admin_users IS
  'Enything platform admin roster. superadmin has all privileges. Others get JSONB-based permissions.';

COMMENT ON COLUMN admin_users.admin_level IS
  'superadmin=owner, operations=back-office, verification=KYC team, finance=CA-facing, support=L1';

COMMENT ON COLUMN admin_users.admin_password IS
  'Secondary password checked after OTP — extra security layer for God Mode access.';

-- ── 2. Row Level Security ────────────────────────────────────────────────────
ALTER TABLE admin_users ENABLE ROW LEVEL SECURITY;

-- Only admins can read the admin_users table
CREATE POLICY "admin_users_read" ON admin_users
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM admin_users a
      WHERE a.id = auth.uid() AND a.is_active = true
    )
  );

-- Only superadmin can insert/update other admins
CREATE POLICY "admin_users_write" ON admin_users
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM admin_users a
      WHERE a.id = auth.uid()
        AND a.admin_level = 'superadmin'
        AND a.is_active = true
    )
  );

-- ── 3. Protect financial views — only admins can access ─────────────────────
-- Grant SELECT on the views we created in add_financial_snapshot_columns.sql
-- (Run this after that migration has also been applied)

-- ── 4. Admin Activity Log ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS admin_activity_log (
  id          BIGSERIAL PRIMARY KEY,
  admin_id    UUID NOT NULL REFERENCES admin_users(id),
  action      TEXT NOT NULL,       -- e.g. 'ban_shop', 'approve_kyc', 'login'
  target_type TEXT,                -- e.g. 'shop', 'user', 'order'
  target_id   TEXT,
  details     JSONB DEFAULT '{}',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE admin_activity_log IS
  'Audit trail of all admin actions for compliance and accountability.';

-- ── 5. Superadmin Bootstrap ──────────────────────────────────────────────────
-- IMPORTANT: Replace 'YOUR-USER-UUID-HERE' with your actual Supabase Auth User ID.
-- Run this ONCE after you sign up with your phone number.
-- Find your UUID in: Supabase Dashboard > Authentication > Users

-- INSERT INTO admin_users (id, full_name, admin_level, permissions, admin_password)
-- VALUES (
--   'YOUR-USER-UUID-HERE',
--   'Enything Owner',
--   'superadmin',
--   '{
--     "view_financials": true,
--     "manage_shops": true,
--     "manage_riders": true,
--     "manage_admins": true,
--     "view_master_pnl": true,
--     "ban_users": true
--   }',
--   'YOUR-HASHED-PASSWORD'   -- use bcrypt or store plain for dev, hash in prod
-- );

-- ── 6. Helper function: check if caller is superadmin ───────────────────────
CREATE OR REPLACE FUNCTION is_superadmin()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM admin_users
    WHERE id = auth.uid()
      AND admin_level = 'superadmin'
      AND is_active = true
  );
$$ LANGUAGE sql SECURITY DEFINER;

