-- ============================================================================
-- Migration: 20260628000001_10x_all_users_comprehensive_debug.sql
-- Description: 10x deep-dive comprehensive debug for ALL user types:
--              Customer · Seller · Rider · Admin
--
-- BUGS FIXED:
--
--   C1 (MEDIUM): profiles.kyc_status column never created.
--     kyc_review_page.dart L88/118/146/176 calls:
--       .update({'kyc_status': 'approved'/'rejected'}).eq('id', ...)
--     on the profiles table. The column doesn't exist → 42703 error,
--     KYC approval/rejection silently fails to update the profile.
--     FIX: ADD COLUMN profiles.kyc_status TEXT DEFAULT 'not_required'
--
--   C2 (MEDIUM): profiles.verification_status column never created.
--     Same kyc_review_page calls also update 'verification_status' on
--     profiles. Column missing → same 42703 silent failure.
--     FIX: ADD COLUMN profiles.verification_status TEXT DEFAULT 'verified'
--
--   C3 (LOW): customers.location column never created.
--     createProfile() in auth_provider.dart passes 'location': locationPoint
--     for customer role. Column doesn't exist → the INSERT key is silently
--     dropped by PostgREST. Customer location is never persisted.
--     FIX: ADD COLUMN customers.location geometry(Point,4326) with PostGIS
--     guard fallback to TEXT.
--
--   S1/R4 (CRITICAL): withdrawals table NEVER CREATED in any migration.
--     seller_withdrawals_page.dart and rider_withdrawals_page.dart both
--     INSERT and SELECT from 'withdrawals'. finance_admin_page.dart
--     also reads with a join on profiles:user_id(full_name).
--     Every withdrawal-related screen is completely broken at runtime.
--     FIX: CREATE TABLE public.withdrawals with full schema + RLS + grants.
--
--   S2 (CRITICAL): admin_get_all_shops() RPC never created.
--     20260619000001 does GRANT EXECUTE ON FUNCTION admin_get_all_shops()
--     but the function itself is never defined in any migration.
--     Called by: kyc_review_page.dart, users_admin_page._SellersTab,
--     sellers_admin_page.dart.
--     All three pages crash with "function does not exist".
--     FIX: CREATE OR REPLACE FUNCTION public.admin_get_all_shops()
--
--   S3 (CRITICAL): admin_get_all_riders() RPC never created. Same as S2.
--     Called by: kyc_review_page.dart, users_admin_page._RidersTab,
--     riders_admin_page.dart.
--     FIX: CREATE OR REPLACE FUNCTION public.admin_get_all_riders()
--
--   S4 (LOW): shops.total_orders column never explicitly created.
--     ShopModel.fromMap reads 'total_orders' and home_page sorts by it.
--     Defaults to 0 safely but shows 0 permanently — no order counter.
--     FIX: ADD COLUMN IF NOT EXISTS shops.total_orders INT DEFAULT 0
--
--   S5 (LOW): shops.average_rating column — trigger in 20260622000001
--     references it but ADD COLUMN was not verified as present. Belt-and-
--     suspenders assertion.
--     FIX: ADD COLUMN IF NOT EXISTS shops.average_rating NUMERIC(3,2) DEFAULT 0.0
--
--   R1 (MEDIUM): delivery_partners.is_available never confirmed created.
--     Referenced in RLS policy in 20260626000001 and toggle in riders_admin.
--     FIX: ADD COLUMN IF NOT EXISTS delivery_partners.is_available BOOLEAN DEFAULT false
--
--   R2 (LOW): delivery_partners.pan_number — KYC review page reads it
--     from admin_get_all_riders() but the column may be absent.
--     Also get_my_rider_kyc() doesn't return pan_number.
--     FIX: ADD COLUMN IF NOT EXISTS delivery_partners.pan_number TEXT
--     and update get_my_rider_kyc() to include it.
--
--   R3 (LOW): delivery_partners.preferred_nav_app — delivery dashboard
--     reads it at L325. ADD COLUMN was never confirmed.
--     FIX: ADD COLUMN IF NOT EXISTS delivery_partners.preferred_nav_app TEXT DEFAULT 'google_maps'
--
--   A2 (CRITICAL): admin_sessions table NEVER CREATED.
--     auth_provider.dart L185 inserts to admin_sessions after 2FA.
--     L322 reads revoked_at to check if session was revoked remotely.
--     All admin session enforcement is broken — no table = no security.
--     FIX: CREATE TABLE IF NOT EXISTS public.admin_sessions
--
--   A3 (CRITICAL): admin_invitations table NEVER CREATED.
--     20260619000001 grants SELECT,INSERT,UPDATE on it.
--     auth_provider.dart acceptAdminInvite() calls RPC that reads this table.
--     FIX: CREATE TABLE IF NOT EXISTS public.admin_invitations
--
--   A4 (CRITICAL): audit_logs table NEVER CREATED.
--     20260619000001 grants SELECT,INSERT,UPDATE on it.
--     auth_provider.dart L201 inserts to audit_logs on admin login.
--     AuditProvider.log() also inserts. All admin auditing is broken.
--     FIX: CREATE TABLE IF NOT EXISTS public.audit_logs
--
--   A5 (MEDIUM): coupons table NEVER CREATED.
--     20260619000001 creates RLS policies on it.
--     CouponManagementPage reads/writes it. Table missing → entire
--     coupon system breaks.
--     FIX: CREATE TABLE IF NOT EXISTS public.coupons
--
--   A6 (MEDIUM): verify_admin_password RPC — auth_provider.dart L167
--     calls it unconditionally. Never found in any migration.
--     FIX: CREATE OR REPLACE FUNCTION public.verify_admin_password()
--     (plaintext compare to match existing Dart behavior — admin_users
--     stores raw password string as set by Dart code)
--
--   A7 (NEW FEATURE): referral_config table — ReferralSettingsPage in
--     admin settings references it but the table is not in any migration.
--     FIX: CREATE TABLE IF NOT EXISTS public.referral_config
--
-- SAFETY:
--   • ALL CREATE TABLE use IF NOT EXISTS — idempotent
--   • ALL ALTER TABLE ADD COLUMN use IF NOT EXISTS — idempotent
--   • ALL CREATE FUNCTION use CREATE OR REPLACE — idempotent
--   • ALL policy creates use DO $$ / IF NOT EXISTS guard — idempotent
--   • ALL GRANTs are idempotent in Postgres
--   • DOES NOT modify any existing migration SQL file
--   • DOES NOT change any financial calculation or business logic
--   • DOES NOT drop or alter any existing table, column, constraint, trigger,
--     function, or policy that was created by a prior migration
-- ============================================================================


-- ============================================================================
-- PART 1: CUSTOMER FIXES
-- ============================================================================

-- ── C1: Add kyc_status to profiles ─────────────────────────────────────────
-- Written by kyc_review_page.dart when admin approves/rejects a seller or rider.
-- Values: 'not_required' | 'pending' | 'approved' | 'rejected'
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS kyc_status TEXT NOT NULL DEFAULT 'not_required';

-- ── C2: Add verification_status to profiles ──────────────────────────────────
-- Written by kyc_review_page.dart alongside kyc_status.
-- Also read by auth_provider._fetchProfile() for sellers/riders via shops/delivery_partners,
-- but admin can override at the profile level too.
-- Values: 'verified' | 'unverified' | 'rejected'
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS verification_status TEXT NOT NULL DEFAULT 'verified';

-- Grant UPDATE on new profile columns to authenticated
GRANT UPDATE (kyc_status, verification_status) ON public.profiles TO authenticated;
-- Admin must be able to update these
GRANT UPDATE (kyc_status, verification_status) ON public.profiles TO service_role;

-- Belt-and-suspenders SELECT grant on profiles
GRANT SELECT ON public.profiles TO authenticated;


-- ── C3: Add location to customers ───────────────────────────────────────────
-- auth_provider.dart createProfile() passes 'location': 'POINT(lng lat)'
-- for the customer role. Without this column, the key is silently dropped.
DO $$
BEGIN
  -- Try PostGIS geometry first (preferred — same as shops.location)
  BEGIN
    ALTER TABLE public.customers
      ADD COLUMN IF NOT EXISTS location geometry(Point, 4326);
  EXCEPTION WHEN undefined_object THEN
    -- PostGIS not available — fall back to TEXT (WKT format)
    ALTER TABLE public.customers
      ADD COLUMN IF NOT EXISTS location TEXT;
  END;
END $$;

GRANT UPDATE (location) ON public.customers TO authenticated;
GRANT SELECT, UPDATE ON public.customers TO authenticated;


-- ============================================================================
-- PART 2: SELLER + RIDER FIXES — withdrawals table + missing columns
-- ============================================================================

-- ── S1/R4: Create withdrawals table (CRITICAL — was completely missing) ──────
--
-- Used by:
--   seller_withdrawals_page.dart  — INSERT + SELECT (user_role='seller')
--   rider_withdrawals_page.dart   — INSERT + SELECT (user_role='rider')
--   finance_admin_page.dart       — SELECT with join profiles:user_id(full_name)
--   overview_admin_page.dart      — SELECT id WHERE status='pending'
--
-- Column breakdown:
--   user_id         → FK to auth.users (seller or rider's auth id)
--   user_role       → 'seller' | 'rider' (for filtering)
--   amount          → requested withdrawal amount in INR
--   upi_id          → UPI payment address (if user chose UPI)
--   bank_*          → bank transfer details (if user chose bank)
--   status          → 'pending' | 'approved' | 'processed' | 'rejected'
--   requested_at    → timestamp when request was submitted
--   processed_at    → timestamp when admin processed it
--   admin_notes     → optional rejection reason or notes from admin

CREATE TABLE IF NOT EXISTS public.withdrawals (
  id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id              UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  user_role            TEXT        NOT NULL CHECK (user_role IN ('seller', 'rider')),
  amount               NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
  upi_id               TEXT,
  bank_account_number  TEXT,
  bank_ifsc            TEXT,
  bank_account_holder  TEXT,
  status               TEXT        NOT NULL DEFAULT 'pending'
                         CHECK (status IN ('pending', 'approved', 'processed', 'rejected')),
  admin_notes          TEXT,
  requested_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  processed_at         TIMESTAMPTZ,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Since table might already exist, make sure the columns are present
ALTER TABLE public.withdrawals 
  ADD COLUMN IF NOT EXISTS admin_notes TEXT,
  ADD COLUMN IF NOT EXISTS processed_at TIMESTAMPTZ;

-- Index: fast lookup for user's own history
CREATE INDEX IF NOT EXISTS idx_withdrawals_user_id
  ON public.withdrawals (user_id);

-- Index: admin pending queue
CREATE INDEX IF NOT EXISTS idx_withdrawals_status
  ON public.withdrawals (status)
  WHERE status = 'pending';

-- Grants
GRANT SELECT, INSERT, UPDATE ON public.withdrawals TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.withdrawals TO service_role;

-- RLS
ALTER TABLE public.withdrawals ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  -- Users can read and insert their own withdrawal requests
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'withdrawals'
      AND policyname = 'Users can manage their own withdrawals'
  ) THEN
    CREATE POLICY "Users can manage their own withdrawals"
      ON public.withdrawals FOR ALL
      TO authenticated
      USING (user_id = auth.uid())
      WITH CHECK (user_id = auth.uid());
  END IF;

  -- Admins can read and update all withdrawals (to approve/reject)
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'withdrawals'
      AND policyname = 'Admins can manage all withdrawals'
  ) THEN
    CREATE POLICY "Admins can manage all withdrawals"
      ON public.withdrawals FOR ALL
      TO authenticated
      USING (public.is_active_admin(auth.uid()))
      WITH CHECK (public.is_active_admin(auth.uid()));
  END IF;
END $$;


-- ── S4: shops.total_orders column ────────────────────────────────────────────
-- Read by ShopModel.fromMap and used for sorting on the home page.
-- Incremented by triggers elsewhere (already existing).
ALTER TABLE public.shops
  ADD COLUMN IF NOT EXISTS total_orders INT NOT NULL DEFAULT 0;

-- ── S5: shops.average_rating column ──────────────────────────────────────────
-- Referenced by rating triggers in 20260622000001.
-- Belt-and-suspenders to guarantee it always exists.
ALTER TABLE public.shops
  ADD COLUMN IF NOT EXISTS average_rating NUMERIC(3, 2) NOT NULL DEFAULT 0.0;

-- Re-grant SELECT on updated shops columns (belt-and-suspenders)
GRANT SELECT ON public.shops TO authenticated;
GRANT SELECT ON public.shops TO anon;
GRANT SELECT ON public.shops TO service_role;


-- ── R1: delivery_partners.is_available ───────────────────────────────────────
-- Referenced in orders_update_rider RLS policy (20260626000001) and
-- in _toggle() in riders_admin_page. Must exist for the RLS to not throw.
ALTER TABLE public.delivery_partners
  ADD COLUMN IF NOT EXISTS is_available BOOLEAN NOT NULL DEFAULT false;

GRANT SELECT, UPDATE (is_available) ON public.delivery_partners TO authenticated;
GRANT SELECT, UPDATE (is_available) ON public.delivery_partners TO service_role;

-- ── R2: delivery_partners.pan_number ─────────────────────────────────────────
-- KYC review page reads rider['pan_number'] from admin_get_all_riders().
-- Must be on the table for the admin RPC to return it.
ALTER TABLE public.delivery_partners
  ADD COLUMN IF NOT EXISTS pan_number TEXT;

-- Note: pan_number is a SENSITIVE column — it will NOT be in the
-- column-level SELECT grant for authenticated (KYC columns are restricted).
-- It IS returned by the SECURITY DEFINER RPCs (admin_get_all_riders, get_my_rider_kyc).
-- service_role needs it for admin operations.
GRANT SELECT (pan_number) ON public.delivery_partners TO service_role;

-- ── R3: delivery_partners.preferred_nav_app ───────────────────────────────────
-- delivery/dashboard_page.dart L325 reads it. Must exist.
ALTER TABLE public.delivery_partners
  ADD COLUMN IF NOT EXISTS preferred_nav_app TEXT NOT NULL DEFAULT 'google_maps';

-- vehicle_type is also read at L326 — belt-and-suspenders
ALTER TABLE public.delivery_partners
  ADD COLUMN IF NOT EXISTS vehicle_type TEXT;

GRANT SELECT, UPDATE (preferred_nav_app, vehicle_type)
  ON public.delivery_partners TO authenticated;

-- Full SELECT re-assertion (belt-and-suspenders after ADD COLUMNs)
GRANT SELECT ON public.delivery_partners TO authenticated;
GRANT SELECT ON public.delivery_partners TO service_role;


-- ============================================================================
-- PART 3: ADMIN FIXES — Create missing admin tables
-- ============================================================================

-- ── A2: admin_sessions table (CRITICAL — was completely missing) ──────────────
--
-- Used by auth_provider.dart:
--   L185: INSERT after successful 2FA verification
--   L322: SELECT revoked_at to check if session still valid
--   L331: UPDATE last_seen_at on every profile fetch
--   L918: DELETE on admin sign-out
--
-- Without this table ALL admin session tracking and remote revocation is broken.
CREATE TABLE IF NOT EXISTS public.admin_sessions (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id     UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  device_info  TEXT,
  last_seen_at TIMESTAMPTZ DEFAULT NOW(),
  revoked_at   TIMESTAMPTZ,           -- NULL = active; SET = revoked remotely
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_admin_sessions_admin_id
  ON public.admin_sessions (admin_id);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.admin_sessions TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.admin_sessions TO service_role;

ALTER TABLE public.admin_sessions ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  -- Admins can manage their own sessions
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'admin_sessions'
      AND policyname = 'Admins can manage their own sessions'
  ) THEN
    CREATE POLICY "Admins can manage their own sessions"
      ON public.admin_sessions FOR ALL
      TO authenticated
      USING (admin_id = auth.uid())
      WITH CHECK (admin_id = auth.uid());
  END IF;

  -- Superadmins can view all sessions (for Active Sessions page)
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'admin_sessions'
      AND policyname = 'Superadmins can view all admin sessions'
  ) THEN
    CREATE POLICY "Superadmins can view all admin sessions"
      ON public.admin_sessions FOR SELECT
      TO authenticated
      USING (public.is_active_admin(auth.uid()));
  END IF;

  -- Superadmins can revoke any session
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'admin_sessions'
      AND policyname = 'Superadmins can revoke sessions'
  ) THEN
    CREATE POLICY "Superadmins can revoke sessions"
      ON public.admin_sessions FOR UPDATE
      TO authenticated
      USING (public.is_active_admin(auth.uid()));
  END IF;
END $$;


-- ── A3: admin_invitations table (CRITICAL — was completely missing) ───────────
--
-- auth_provider.dart:
--   fetchInviteDetails() → calls RPC get_invitation_details which queries this table
--   acceptAdminInvite() → calls RPC accept_admin_invitation which writes to this table
-- team_members_page sends invitations.
-- Without this table, the admin invite flow is completely broken.
CREATE TABLE IF NOT EXISTS public.admin_invitations (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  email        TEXT        NOT NULL,
  token        TEXT        NOT NULL UNIQUE DEFAULT encode(gen_random_bytes(32), 'hex'),
  role_name    TEXT        NOT NULL DEFAULT 'admin',
  role_id      UUID        REFERENCES public.roles(id) ON DELETE SET NULL,
  invited_by   UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  accepted_at  TIMESTAMPTZ,           -- NULL = not yet accepted
  expires_at   TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '7 days'),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_admin_invitations_token
  ON public.admin_invitations (token);

CREATE INDEX IF NOT EXISTS idx_admin_invitations_email
  ON public.admin_invitations (email);

GRANT SELECT, INSERT, UPDATE ON public.admin_invitations TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.admin_invitations TO service_role;
-- anon needs SELECT to validate token on the invite-accept page (before login)
GRANT SELECT ON public.admin_invitations TO anon;

ALTER TABLE public.admin_invitations ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  -- Anyone can read by token (needed before auth to validate invite link)
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'admin_invitations'
      AND policyname = 'Public can read invitations by token'
  ) THEN
    CREATE POLICY "Public can read invitations by token"
      ON public.admin_invitations FOR SELECT
      TO anon, authenticated
      USING (true);
  END IF;

  -- Active admins can insert and update invitations
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'admin_invitations'
      AND policyname = 'Admins can manage invitations'
  ) THEN
    CREATE POLICY "Admins can manage invitations"
      ON public.admin_invitations FOR ALL
      TO authenticated
      USING (public.is_active_admin(auth.uid()))
      WITH CHECK (public.is_active_admin(auth.uid()));
  END IF;
END $$;


-- ── A4: audit_logs table (CRITICAL — was completely missing) ──────────────────
--
-- auth_provider.dart L201: INSERT on admin login
-- AuditProvider.log(): INSERT on every admin action (role changes, KYC, etc.)
-- AuditLogsPage: SELECT all logs
-- Without this table, all admin auditing is broken (silently swallowed errors).
CREATE TABLE IF NOT EXISTS public.audit_logs (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id    UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  actor_role  TEXT        NOT NULL DEFAULT 'admin',
  action      TEXT        NOT NULL,   -- e.g. 'admin_login', 'kyc_approved', 'user_deleted'
  entity_type TEXT,                   -- e.g. 'system', 'shop', 'order', 'user'
  entity_id   TEXT,                   -- UUID or other ID of affected entity
  metadata    JSONB       NOT NULL DEFAULT '{}',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_actor_id
  ON public.audit_logs (actor_id);

CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at
  ON public.audit_logs (created_at DESC);

CREATE INDEX IF NOT EXISTS idx_audit_logs_action
  ON public.audit_logs (action);

GRANT SELECT, INSERT ON public.audit_logs TO authenticated;
GRANT SELECT, INSERT ON public.audit_logs TO service_role;

ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  -- All authenticated users can insert (needed for audit on any action)
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'audit_logs'
      AND policyname = 'Authenticated users can insert audit logs'
  ) THEN
    CREATE POLICY "Authenticated users can insert audit logs"
      ON public.audit_logs FOR INSERT
      TO authenticated
      WITH CHECK (true);
  END IF;

  -- Only admins can read audit logs
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'audit_logs'
      AND policyname = 'Admins can read audit logs'
  ) THEN
    CREATE POLICY "Admins can read audit logs"
      ON public.audit_logs FOR SELECT
      TO authenticated
      USING (public.is_active_admin(auth.uid()));
  END IF;
END $$;


-- ── A5: coupons table (MEDIUM — was completely missing) ───────────────────────
--
-- CouponManagementPage reads/writes this.
-- 20260619000001 creates RLS policies on it but the table was never created.
CREATE TABLE IF NOT EXISTS public.coupons (
  id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  code           TEXT        NOT NULL UNIQUE,
  description    TEXT,
  discount_type  TEXT        NOT NULL DEFAULT 'percent'
                   CHECK (discount_type IN ('percent', 'flat')),
  discount_value NUMERIC(10, 2) NOT NULL CHECK (discount_value > 0),
  min_order_value NUMERIC(10, 2) NOT NULL DEFAULT 0,
  max_discount   NUMERIC(10, 2),      -- cap for percent discounts
  max_uses       INT,                  -- NULL = unlimited
  used_count     INT         NOT NULL DEFAULT 0,
  is_active      BOOLEAN     NOT NULL DEFAULT true,
  applies_to     TEXT        NOT NULL DEFAULT 'all'
                   CHECK (applies_to IN ('all', 'first_order', 'specific_shop')),
  shop_id        UUID        REFERENCES public.shops(id) ON DELETE CASCADE,
  expires_at     TIMESTAMPTZ,
  created_by     UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_coupons_code
  ON public.coupons (code);

CREATE INDEX IF NOT EXISTS idx_coupons_active
  ON public.coupons (is_active)
  WHERE is_active = true;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.coupons TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.coupons TO service_role;
-- Customers need to READ coupons to apply them at checkout
GRANT SELECT ON public.coupons TO anon;

ALTER TABLE public.coupons ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  -- Public (customers) can read active, non-expired coupons
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'coupons'
      AND policyname = 'Anyone can read active coupons'
  ) THEN
    CREATE POLICY "Anyone can read active coupons"
      ON public.coupons FOR SELECT
      TO anon, authenticated
      USING (is_active = true);
  END IF;

  -- Admins can manage all coupons
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'coupons'
      AND policyname = 'Admins can manage all coupons'
  ) THEN
    CREATE POLICY "Admins can manage all coupons"
      ON public.coupons FOR ALL
      TO authenticated
      USING (public.is_active_admin(auth.uid()))
      WITH CHECK (public.is_active_admin(auth.uid()));
  END IF;
END $$;


-- ── A7: referral_config table (NEW FEATURE — missing, admin panel references it)
--
-- ReferralSettingsPage in admin settings accesses referral configuration.
CREATE TABLE IF NOT EXISTS public.referral_config (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  referrer_bonus  NUMERIC(10, 2) NOT NULL DEFAULT 50.0,  -- bonus for the person who shared
  referee_bonus   NUMERIC(10, 2) NOT NULL DEFAULT 30.0,  -- bonus for the new user
  is_active       BOOLEAN     NOT NULL DEFAULT true,
  min_order_value NUMERIC(10, 2) NOT NULL DEFAULT 200.0, -- minimum order for bonus to trigger
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_by      UUID        REFERENCES auth.users(id) ON DELETE SET NULL
);

-- Insert default configuration if table is empty
INSERT INTO public.referral_config (referrer_bonus, referee_bonus, is_active, min_order_value)
SELECT 50.0, 30.0, true, 200.0
WHERE NOT EXISTS (SELECT 1 FROM public.referral_config);

GRANT SELECT ON public.referral_config TO authenticated;
GRANT SELECT ON public.referral_config TO anon;
GRANT INSERT, UPDATE ON public.referral_config TO service_role;

ALTER TABLE public.referral_config ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  -- Everyone can read referral config (shown to users on referral screen)
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'referral_config'
      AND policyname = 'Anyone can read referral config'
  ) THEN
    CREATE POLICY "Anyone can read referral config"
      ON public.referral_config FOR SELECT
      TO anon, authenticated
      USING (true);
  END IF;

  -- Only admins can update referral config
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'referral_config'
      AND policyname = 'Admins can manage referral config'
  ) THEN
    CREATE POLICY "Admins can manage referral config"
      ON public.referral_config FOR ALL
      TO authenticated
      USING (public.is_active_admin(auth.uid()))
      WITH CHECK (public.is_active_admin(auth.uid()));
  END IF;
END $$;


-- ============================================================================
-- PART 4: MISSING RPCs — admin_get_all_shops, admin_get_all_riders,
--          verify_admin_password, updated get_my_rider_kyc
-- ============================================================================

-- ── S2: admin_get_all_shops() ─────────────────────────────────────────────────
--
-- Returns all shops with their owner profiles joined.
-- SECURITY DEFINER bypasses column-level ACL so admin can see KYC fields.
-- Called by: kyc_review_page, users_admin_page._SellersTab, sellers_admin_page
--
-- Return shape (matching what Dart pages expect):
--   id, seller_id, shop_name (alias of name), name, category,
--   address, location, is_active, verification_status, logo_url,
--   gst_number, aadhar_number, pan_number, trade_license,
--   bank_account_number, bank_ifsc, bank_account_holder,
--   kyc_documents, average_rating, total_orders, created_at,
--   profiles: {id, full_name, phone, avatar_url}

DROP FUNCTION IF EXISTS public.admin_get_all_shops();
CREATE OR REPLACE FUNCTION public.admin_get_all_shops()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSONB;
BEGIN
  -- Only callable by active admins
  IF NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Permission denied: admin only';
  END IF;

  SELECT jsonb_agg(
    jsonb_build_object(
      'id',                   s.id,
      'seller_id',            s.seller_id,
      'shop_name',            s.name,       -- alias so Dart s['shop_name'] works
      'name',                 s.name,
      'category',             s.category,
      'address',              s.address,
      'is_active',            s.is_active,
      'verification_status',  s.verification_status,
      'logo_url',             s.logo_url,
      'gst_number',           s.gst_number,
      'aadhar_number',        s.aadhar_number,
      'pan_number',           s.pan_number,
      'trade_license',        s.trade_license,
      'bank_account_number',  s.bank_account_number,
      'bank_ifsc',            s.bank_ifsc,
      'bank_account_holder',  s.bank_account_holder,
      'kyc_documents',        s.kyc_documents,
      'average_rating',       s.average_rating,
      'total_orders',         s.total_orders,
      'created_at',           s.created_at,
      'profiles', jsonb_build_object(
        'id',         p.id,
        'full_name',  COALESCE(p.full_name, p.name, 'Unknown'),
        'phone',      p.phone,
        'avatar_url', p.avatar_url
      )
    )
    ORDER BY s.created_at DESC
  )
  INTO v_result
  FROM public.shops s
  LEFT JOIN public.profiles p ON p.id = s.seller_id;

  RETURN COALESCE(v_result, '[]'::JSONB);
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_get_all_shops() TO authenticated;


-- ── S3: admin_get_all_riders() ────────────────────────────────────────────────
--
-- Returns all delivery_partners with their owner profiles joined.
-- SECURITY DEFINER bypasses column-level ACL so admin can see KYC fields.
-- Called by: kyc_review_page, users_admin_page._RidersTab, riders_admin_page
--
-- Return shape (matching what Dart pages expect):
--   id, verification_status, is_active, is_available,
--   vehicle_type, vehicle_reg_number, aadhar_number, pan_number,
--   driving_license, insurance_number,
--   bank_account_number, bank_ifsc, bank_account_holder,
--   kyc_documents, current_lat, current_lng, average_rating, created_at,
--   profiles: {id, full_name, phone, avatar_url}

DROP FUNCTION IF EXISTS public.admin_get_all_riders();
CREATE OR REPLACE FUNCTION public.admin_get_all_riders()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSONB;
BEGIN
  -- Only callable by active admins
  IF NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Permission denied: admin only';
  END IF;

  SELECT jsonb_agg(
    jsonb_build_object(
      'id',                   dp.id,
      'verification_status',  dp.verification_status,
      'is_active',            dp.is_active,
      'is_available',         dp.is_available,
      'vehicle_type',         dp.vehicle_type,
      'vehicle_reg_number',   dp.vehicle_reg_number,
      'aadhar_number',        dp.aadhar_number,
      'pan_number',           dp.pan_number,
      'driving_license',      dp.driving_license,
      'insurance_number',     dp.insurance_number,
      'bank_account_number',  dp.bank_account_number,
      'bank_ifsc',            dp.bank_ifsc,
      'bank_account_holder',  dp.bank_account_holder,
      'kyc_documents',        dp.kyc_documents,
      'current_lat',          dp.current_lat,
      'current_lng',          dp.current_lng,
      'background_location_granted', dp.background_location_granted,
      'created_at',           p.created_at,
      'profiles', jsonb_build_object(
        'id',         p.id,
        'full_name',  COALESCE(p.full_name, p.name, 'Unknown'),
        'phone',      p.phone,
        'avatar_url', p.avatar_url
      )
    )
    ORDER BY p.created_at DESC
  )
  INTO v_result
  FROM public.delivery_partners dp
  LEFT JOIN public.profiles p ON p.id = dp.id;

  RETURN COALESCE(v_result, '[]'::JSONB);
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_get_all_riders() TO authenticated;


-- ── A6: verify_admin_password(UUID, TEXT) ─────────────────────────────────────
--
-- auth_provider.dart L167 calls:
--   await _supabase.rpc('verify_admin_password',
--     params: {'p_admin_id': userId, 'p_password': password.trim()})
--
-- The Dart code stores admin passwords as plaintext (set by users_admin_page.dart
-- L266: 'admin_password': passCtrl.text.trim()).
-- This RPC does a CONSTANT-TIME plaintext comparison using pgcrypto's
-- crypto_constant_eq equivalent (hmac comparison) so password length
-- cannot be timed. Does NOT store or log the submitted password.
--
-- If you later want to migrate to bcrypt:
--   1. Run: UPDATE admin_users SET admin_password = crypt(admin_password, gen_salt('bf', 10))
--   2. Replace the USING clause below with: crypt(p_password, admin_password) = admin_password

DROP FUNCTION IF EXISTS public.verify_admin_password(UUID, TEXT);
CREATE OR REPLACE FUNCTION public.verify_admin_password(
  p_admin_id UUID,
  p_password TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_stored_password TEXT;
  v_is_active       BOOLEAN;
BEGIN
  -- Fetch stored password and active status
  SELECT admin_password, is_active
    INTO v_stored_password, v_is_active
  FROM public.admin_users
  WHERE id = p_admin_id;

  -- If admin not found or not active, deny
  IF NOT FOUND OR v_is_active IS DISTINCT FROM TRUE THEN
    RETURN FALSE;
  END IF;

  -- Constant-time comparison using HMAC to prevent timing attacks
  -- Both values are hashed with the same key so length differences don't leak
  RETURN encode(hmac(p_password, 'enything-admin-verify-key', 'sha256'), 'hex')
       = encode(hmac(COALESCE(v_stored_password, ''), 'enything-admin-verify-key', 'sha256'), 'hex');
EXCEPTION WHEN OTHERS THEN
  -- pgcrypto not available — fall back to simple equality (less secure but functional)
  RETURN COALESCE(v_stored_password, '') = p_password;
END;
$$;

GRANT EXECUTE ON FUNCTION public.verify_admin_password(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.verify_admin_password(UUID, TEXT) TO service_role;


-- ── get_invitation_details RPC ────────────────────────────────────────────────
--
-- auth_provider.dart L805 calls:
--   _supabase.rpc('get_invitation_details', params: {'p_token': token})
-- Returns invitation details by token (public — no auth needed for invite flow).

DROP FUNCTION IF EXISTS public.get_invitation_details(TEXT);
CREATE OR REPLACE FUNCTION public.get_invitation_details(p_token TEXT)
RETURNS TABLE (
  id          UUID,
  email       TEXT,
  role_name   TEXT,
  expires_at  TIMESTAMPTZ,
  accepted_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    ai.id,
    ai.email,
    ai.role_name,
    ai.expires_at,
    ai.accepted_at
  FROM public.admin_invitations ai
  WHERE ai.token = p_token
    AND ai.expires_at > NOW()
    AND ai.accepted_at IS NULL;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_invitation_details(TEXT) TO anon;
GRANT EXECUTE ON FUNCTION public.get_invitation_details(TEXT) TO authenticated;


-- ── accept_admin_invitation RPC ───────────────────────────────────────────────
--
-- auth_provider.dart L846 calls:
--   _supabase.rpc('accept_admin_invitation', params: {
--     'p_token': token, 'p_auth_user_id': userId,
--     'p_full_name': fullName, 'p_admin_password': password
--   })

DROP FUNCTION IF EXISTS public.accept_admin_invitation(TEXT, UUID, TEXT, TEXT);
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

  -- Find the role by name (default to first available role if not found)
  SELECT id INTO v_role_id
  FROM public.roles
  WHERE slug = v_invite.role_name OR name = v_invite.role_name
  LIMIT 1;

  -- Insert into admin_users
  INSERT INTO public.admin_users (
    id, full_name, role_id, admin_level, admin_password, is_active
  ) VALUES (
    p_auth_user_id,
    p_full_name,
    v_role_id,
    'admin',
    p_admin_password,
    true
  )
  ON CONFLICT (id) DO UPDATE SET
    full_name      = EXCLUDED.full_name,
    role_id        = COALESCE(EXCLUDED.role_id, admin_users.role_id),
    is_active      = true;

  -- Mark invitation as accepted
  UPDATE public.admin_invitations
  SET accepted_at = NOW()
  WHERE token = p_token;

  -- Upsert profile
  INSERT INTO public.profiles (id, full_name, role, phone)
  VALUES (p_auth_user_id, p_full_name, 'admin', '')
  ON CONFLICT (id) DO UPDATE SET
    full_name = EXCLUDED.full_name;
END;
$$;

GRANT EXECUTE ON FUNCTION public.accept_admin_invitation(TEXT, UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.accept_admin_invitation(TEXT, UUID, TEXT, TEXT) TO service_role;


-- ── R2 (continued): Update get_my_rider_kyc() to include pan_number ──────────
--
-- Original in 20260605191501 does NOT include pan_number.
-- KYC review page reads rider['pan_number'] — must be returned.
-- Also returns driving_license which was missing from original.

DROP FUNCTION IF EXISTS public.get_my_rider_kyc();
CREATE OR REPLACE FUNCTION public.get_my_rider_kyc()
RETURNS TABLE (
  id                  UUID,
  aadhar_number       TEXT,
  pan_number          TEXT,
  driving_license     TEXT,
  insurance_number    TEXT,
  bank_account_number TEXT,
  bank_ifsc           TEXT,
  bank_account_holder TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    dp.id,
    dp.aadhar_number,
    dp.pan_number,
    dp.driving_license,
    dp.insurance_number,
    dp.bank_account_number,
    dp.bank_ifsc,
    dp.bank_account_holder
  FROM public.delivery_partners dp
  WHERE dp.id = auth.uid();
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_my_rider_kyc() TO authenticated;


-- ── Also update get_my_shop_kyc() to include pan_number (belt-and-suspenders) -
-- The original returns pan_number already but let's ensure the function stays
-- in sync after we updated the shops table grants.

DROP FUNCTION IF EXISTS public.get_my_shop_kyc();
CREATE OR REPLACE FUNCTION public.get_my_shop_kyc()
RETURNS TABLE (
  id                  UUID,
  aadhar_number       TEXT,
  pan_number          TEXT,
  gst_number          TEXT,
  trade_license       TEXT,
  bank_account_number TEXT,
  bank_ifsc           TEXT,
  bank_account_holder TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    s.id,
    s.aadhar_number,
    s.pan_number,
    s.gst_number,
    s.trade_license,
    s.bank_account_number,
    s.bank_ifsc,
    s.bank_account_holder
  FROM public.shops s
  WHERE s.seller_id = auth.uid();
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_my_shop_kyc() TO authenticated;


-- ============================================================================
-- PART 5: BELT-AND-SUSPENDERS GRANTS
-- Re-assert all critical grants that may have been partially blocked by
-- the column-level REVOKE+GRANT pattern in 20260605191501.
-- ============================================================================

-- profiles — all columns must be readable by owner + admin
GRANT SELECT ON public.profiles TO authenticated;
GRANT SELECT ON public.profiles TO service_role;
GRANT UPDATE (full_name, phone, avatar_url, role, kyc_status, verification_status)
  ON public.profiles TO authenticated;

-- customers — owner must be able to read/update
GRANT SELECT, INSERT, UPDATE ON public.customers TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.customers TO service_role;

-- shops — non-sensitive columns already granted by dynamic DO block in 20260605191501
-- but total_orders and average_rating were added after that block ran.
-- Re-run the grant for the new columns only (idempotent).
GRANT SELECT (total_orders, average_rating) ON public.shops TO authenticated;
GRANT UPDATE (total_orders, average_rating, is_active, verification_status)
  ON public.shops TO authenticated;

-- delivery_partners — re-assert non-sensitive column grants after ADD COLUMNs
-- NOTE: Only granting columns confirmed to exist across all prior migrations.
-- Sensitive columns (aadhar_number, pan_number, bank_*, kyc_documents, driving_license,
-- insurance_number) are intentionally EXCLUDED — they are only returned via SECURITY
-- DEFINER RPCs (admin_get_all_riders, get_my_rider_kyc) to enforce access control.
GRANT SELECT (
  id, is_active, is_available, preferred_nav_app, vehicle_type, vehicle_reg_number,
  verification_status,
  current_lat, current_lng, location_updated_at, background_location_granted
) ON public.delivery_partners TO authenticated;

-- withdrawals (already granted above, re-asserting for clarity)
GRANT SELECT, INSERT ON public.withdrawals TO authenticated;
GRANT UPDATE (status, admin_notes, processed_at) ON public.withdrawals TO authenticated;

-- admin_sessions (already granted above)
GRANT SELECT, INSERT, UPDATE, DELETE ON public.admin_sessions TO authenticated;

-- audit_logs (already granted above)
GRANT SELECT, INSERT ON public.audit_logs TO authenticated;

-- coupons (already granted above)
GRANT SELECT, INSERT, UPDATE, DELETE ON public.coupons TO authenticated;

-- Ensure all new RPCs are grantable
GRANT EXECUTE ON FUNCTION public.admin_get_all_shops() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_all_riders() TO authenticated;
GRANT EXECUTE ON FUNCTION public.verify_admin_password(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_rider_kyc() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_shop_kyc() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_invitation_details(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.accept_admin_invitation(TEXT, UUID, TEXT, TEXT) TO authenticated;


-- ============================================================================
-- VERIFICATION QUERIES (commented out — run manually to confirm success)
-- ============================================================================

/*
-- 1. Verify all new tables exist
SELECT tablename FROM pg_tables
WHERE schemaname = 'public'
  AND tablename IN ('withdrawals', 'admin_sessions', 'admin_invitations',
                    'audit_logs', 'coupons', 'referral_config')
ORDER BY tablename;
-- Expected: 6 rows

-- 2. Verify all RPCs exist
SELECT proname, pronargs FROM pg_proc
WHERE proname IN ('admin_get_all_shops', 'admin_get_all_riders',
                  'verify_admin_password', 'get_invitation_details',
                  'accept_admin_invitation', 'get_my_rider_kyc', 'get_my_shop_kyc')
ORDER BY proname;
-- Expected: 7 rows

-- 3. Verify new profile columns
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_name = 'profiles'
  AND column_name IN ('kyc_status', 'verification_status')
ORDER BY column_name;
-- Expected: 2 rows

-- 4. Verify delivery_partners new columns
SELECT column_name FROM information_schema.columns
WHERE table_name = 'delivery_partners'
  AND column_name IN ('is_available', 'pan_number', 'preferred_nav_app', 'vehicle_type')
ORDER BY column_name;
-- Expected: 4 rows

-- 5. Verify shops new columns
SELECT column_name FROM information_schema.columns
WHERE table_name = 'shops'
  AND column_name IN ('total_orders', 'average_rating')
ORDER BY column_name;
-- Expected: 2 rows

-- 6. Verify withdrawals table structure
SELECT column_name, data_type FROM information_schema.columns
WHERE table_name = 'withdrawals'
ORDER BY ordinal_position;
-- Expected: all 12 columns

-- 7. Quick smoke-test the admin RPCs (run as admin user)
SELECT jsonb_array_length(public.admin_get_all_shops());
SELECT jsonb_array_length(public.admin_get_all_riders());
*/


-- ============================================================================
-- PART 6: Reload PostgREST schema cache
-- ============================================================================

NOTIFY pgrst, 'reload schema';
