-- Migration: tax_and_sessions.sql
-- Description: Creates tax_config for per-category GST overrides,
--              and admin_sessions for session tracking + revocation.

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. tax_config — per-category GST rate overrides
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS tax_config (
  category        TEXT PRIMARY KEY,
  gst_rate        NUMERIC(5,4) NOT NULL DEFAULT 0.18,   -- e.g. 0.05 = 5%
  is_deemed_supplier BOOLEAN NOT NULL DEFAULT FALSE,    -- Section 9(5) food/restaurant
  is_custom       BOOLEAN NOT NULL DEFAULT FALSE,       -- FALSE = using code default
  updated_by      UUID REFERENCES admin_users(id),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Seed with the canonical defaults from TaxConfig (Dart side)
INSERT INTO tax_config (category, gst_rate, is_deemed_supplier, is_custom) VALUES
  ('Restaurant',      0.05, TRUE,  FALSE),
  ('Fast Food',       0.05, TRUE,  FALSE),
  ('Bakery',          0.05, TRUE,  FALSE),
  ('Sweets & Mithai', 0.05, TRUE,  FALSE),
  ('Tea & Coffee',    0.05, TRUE,  FALSE),
  ('Ice Cream',       0.05, TRUE,  FALSE),
  ('Paan Shop',       0.05, TRUE,  FALSE),
  ('Fruits & Vegs',   0.00, FALSE, FALSE),
  ('Butcher',         0.00, FALSE, FALSE),
  ('Fish & Seafood',  0.00, FALSE, FALSE),
  ('Dairy & Eggs',    0.05, FALSE, FALSE),
  ('Grocery',         0.05, FALSE, FALSE),
  ('Organic',         0.05, FALSE, FALSE),
  ('Beverages',       0.12, FALSE, FALSE),
  ('Pharmacy',        0.05, FALSE, FALSE),
  ('Medical Store',   0.05, FALSE, FALSE),
  ('Clothing',        0.05, FALSE, FALSE),
  ('Footwear',        0.05, FALSE, FALSE),
  ('Electronics',     0.18, FALSE, FALSE),
  ('Mobile & Repair', 0.18, FALSE, FALSE),
  ('Jewellery',       0.03, FALSE, FALSE),
  ('Stationery',      0.12, FALSE, FALSE),
  ('Toys & Games',    0.12, FALSE, FALSE),
  ('Sports',          0.12, FALSE, FALSE),
  ('Pet Supplies',    0.18, FALSE, FALSE),
  ('Salon & Beauty',  0.18, FALSE, FALSE),
  ('Flowers',         0.05, FALSE, FALSE),
  ('Home Decor',      0.18, FALSE, FALSE),
  ('Furniture',       0.18, FALSE, FALSE),
  ('Hardware Store',  0.18, FALSE, FALSE),
  ('Auto Parts',      0.18, FALSE, FALSE),
  ('Other',           0.18, FALSE, FALSE)
ON CONFLICT (category) DO NOTHING;

-- Add service tax overrides to platform_config
INSERT INTO platform_config (key, value, label, description) VALUES
  ('delivery_gst_rate',    '0.18', 'Delivery GST Rate', 'GST rate on delivery charges (SAC 9965)'),
  ('platform_fee_gst_rate','0.18', 'Platform Fee GST Rate', 'GST rate on platform/handling fee (SAC 9985)')
ON CONFLICT (key) DO NOTHING;

-- RLS on tax_config
ALTER TABLE tax_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "tax_config_read_all" ON tax_config
  FOR SELECT TO authenticated USING (TRUE);

CREATE POLICY "tax_config_write_superadmin" ON tax_config
  FOR ALL TO authenticated
  USING (is_super_admin(auth.uid()))
  WITH CHECK (is_super_admin(auth.uid()));

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. admin_sessions — track admin logins for view & revocation
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS admin_sessions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id        UUID NOT NULL REFERENCES admin_users(id) ON DELETE CASCADE,
  device_info     TEXT,                              -- e.g. "Android 14 · Samsung M115F"
  logged_in_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  revoked_at      TIMESTAMPTZ,                       -- NULL = still active
  revoked_by      UUID REFERENCES admin_users(id)    -- who revoked it
);

-- Index for fast lookup by admin
CREATE INDEX IF NOT EXISTS idx_admin_sessions_admin_id ON admin_sessions(admin_id);

-- RLS on admin_sessions
ALTER TABLE admin_sessions ENABLE ROW LEVEL SECURITY;

-- Super-admins can read all sessions; regular admins only see their own
CREATE POLICY "sessions_read" ON admin_sessions
  FOR SELECT TO authenticated
  USING (
    is_super_admin(auth.uid())
    OR admin_id = auth.uid()
  );

-- Any admin can insert their own session row (on login)
CREATE POLICY "sessions_insert_own" ON admin_sessions
  FOR INSERT TO authenticated
  WITH CHECK (admin_id = auth.uid());

-- Any admin can update their own last_seen_at; super-admin can revoke any
CREATE POLICY "sessions_update" ON admin_sessions
  FOR UPDATE TO authenticated
  USING (
    admin_id = auth.uid()
    OR is_super_admin(auth.uid())
  );

-- Any admin can delete their own session (on logout); super-admin can delete any
CREATE POLICY "sessions_delete" ON admin_sessions
  FOR DELETE TO authenticated
  USING (
    admin_id = auth.uid()
    OR is_super_admin(auth.uid())
  );

COMMIT;
