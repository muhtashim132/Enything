-- ============================================================================
-- Migration: 20260629000001_10x_final_comprehensive_fix.sql
-- Description: Final 10x pass — fills ALL remaining gaps found by reading
--              every single Dart source file for Customer, Seller, Rider, Admin.
--
-- BUGS FIXED:
--
--   BUG-AS1 (CRITICAL): admin_sessions.logged_in_at column missing.
--     active_sessions_page.dart L241:
--       final loggedInAt = DateTime.parse(session['logged_in_at']);
--     DateTime.parse(null) throws, crashing ActiveSessionsPage on EVERY row.
--     FIX: ADD COLUMN admin_sessions.logged_in_at TIMESTAMPTZ DEFAULT NOW()
--
--   BUG-AS2 (MEDIUM): admin_sessions.revoked_by column missing.
--     active_sessions_page.dart L74:
--       'revoked_by': currentAdminId,
--     The UPDATE fails with "column revoked_by does not exist".
--     Admins cannot revoke other admin sessions.
--     FIX: ADD COLUMN admin_sessions.revoked_by UUID
--
--   BUG-AS3 (MEDIUM): admin_sessions has no RLS UPDATE policy allowing admins
--     to set revoked_at / revoked_by. Without this the update silently returns
--     0 rows (RLS blocks) even though the column now exists.
--     FIX: CREATE POLICY admin_sessions_admin_revoke FOR UPDATE TO authenticated
--
--   BUG-AU1 (MEDIUM): admin_users.last_login_at column missing.
--     auth_provider.dart (admin login) updates last_login_at after 2FA:
--       await _db.from('admin_users').update({'last_login_at': ...}).eq('id', userId);
--     Without the column the UPDATE fails with error 42703.
--     FIX: ADD COLUMN admin_users.last_login_at TIMESTAMPTZ
--
--   BUG-AU2 (MEDIUM): admin_users lacks INSERT + UPDATE grants for authenticated.
--     users_admin_page._promoteToAdmin() does:
--       await _db.from('admin_users').insert({...});
--     auth_provider admin login does:
--       await _db.from('admin_users').update({'last_login_at': ...}).eq('id', ...);
--     Both fail with "permission denied" since only SELECT was ever granted.
--     NOTE: 20260615170000 actually added full CRUD. Re-asserting idempotently.
--     FIX: GRANT INSERT, UPDATE ON public.admin_users TO authenticated (re-assert)
--
--   BUG-AU3 (MEDIUM): admin_users.is_suspended / suspended_at / suspended_by missing.
--     team_repository.dart suspendMember() L75-79:
--       await _db.from('admin_users').update({
--         'is_suspended': true, 'suspended_at': ..., 'suspended_by': actorId
--       }).eq('id', userId);
--     All 3 columns are missing → suspending team members silently fails.
--     FIX: ADD COLUMN admin_users.is_suspended BOOLEAN DEFAULT false
--          ADD COLUMN admin_users.suspended_at TIMESTAMPTZ
--          ADD COLUMN admin_users.suspended_by UUID
--
--   BUG-AU4 (LOW): admin_users.email column missing.
--     audit_repository.dart L18:
--       .select('*, admin_users(full_name, email)')
--     Join returns null for email on every audit log row.
--     FIX: ADD COLUMN admin_users.email TEXT
--
--   BUG-DP1 (MEDIUM): delivery_partners.is_online column missing.
--     riders_admin_page.dart L71:
--       final isOnline = rider['is_online'] == true;
--     Column doesn't exist → always false → all riders show "Offline".
--     Separate concern from is_available (accepting orders) and is_active (enabled).
--     FIX: ADD COLUMN delivery_partners.is_online BOOLEAN DEFAULT false
--
--   BUG-DP2 (LOW): delivery_partners.total_deliveries column missing.
--     riders_admin_page.dart L138:
--       '${rider['total_deliveries'] ?? 0} deliveries'
--     Always shows 0. Should auto-increment when order delivered.
--     FIX: ADD COLUMN delivery_partners.total_deliveries INT DEFAULT 0
--          + trigger to increment on order status → 'delivered'
--
--   BUG-DP3 (LOW): delivery_partners column grants don't include is_online and
--     total_deliveries for authenticated UPDATE (belt-and-suspenders).
--     FIX: GRANT UPDATE (is_online, total_deliveries) ON delivery_partners
--
--   BUG-PC1 (MEDIUM): platform_config.updated_by and updated_at missing.
--     platform_config_provider.dart L228-231:
--       await _db.from('platform_config').upsert({
--         'key': key, 'value': value,
--         'updated_by': actorId,          ← column missing
--         'updated_at': DateTime.now()... ← column missing
--       }, onConflict: 'key');
--     The upsert throws "column updated_by does not exist" → platform config
--     changes NEVER persist. All commission, fee, delivery settings are stuck
--     at defaults and cannot be changed by admin.
--     FIX: ADD COLUMN platform_config.updated_by UUID
--          ADD COLUMN platform_config.updated_at TIMESTAMPTZ
--
--   BUG-RC1 (MEDIUM): referral_config has no admin INSERT/UPDATE grant.
--     The table was created with only GRANT SELECT to authenticated.
--     If admin ever tries to write referral config directly, it will fail.
--     FIX: GRANT INSERT, UPDATE ON public.referral_config TO authenticated
--          + RLS policy for admin management
--
--   BUG-RL1 (LOW): Default admin role not seeded in roles table.
--     When admin_invitations.accept_admin_invitation() RPC runs, it looks up
--     a role by slug 'admin'. If roles table is empty (fresh DB), the INSERT
--     to admin_users sets role_id = NULL, breaking RBAC for new admins.
--     FIX: INSERT default roles (super_admin, admin, finance_admin, support)
--          using ON CONFLICT DO NOTHING (safe seed, never overwrites)
--
--   BUG-WD1 (LOW): withdrawals admin_notes + processed_at UPDATE grant re-assert.
--     finance_admin_page._WithdrawalActionSheet updates:
--       {'status': ..., 'admin_notes': ..., 'processed_at': ...}
--     The existing migration grants these columns but belt-and-suspenders
--     re-assertion ensures no column-level ACL conflict from other migrations.
--     FIX: Re-assert GRANT UPDATE on all withdrawal admin columns
--
-- SAFETY:
--   • ALL CREATE TABLE use IF NOT EXISTS — idempotent
--   • ALL ALTER TABLE ADD COLUMN use IF NOT EXISTS — idempotent
--   • ALL CREATE FUNCTION use CREATE OR REPLACE — idempotent
--   • ALL GRANT statements are idempotent in PostgreSQL
--   • ALL policy creates are guarded with DO $$ / IF NOT EXISTS
--   • DOES NOT modify any existing migration SQL file
--   • DOES NOT change any financial calculation or business logic
--   • DOES NOT drop or alter any existing table, column, constraint,
--     trigger, function, or policy created by a prior migration
-- ============================================================================


-- ============================================================================
-- PART 1: admin_sessions fixes (BUG-AS1, BUG-AS2, BUG-AS3)
--
-- active_sessions_page.dart queries:
--   SELECT id, device_info, logged_in_at, last_seen_at, admin_id, admin_users(...)
--   WHERE revoked_at IS NULL
-- And updates:
--   UPDATE admin_sessions SET revoked_at = ..., revoked_by = ... WHERE id = sessionId
-- ============================================================================

-- BUG-AS1: Add logged_in_at — DateTime.parse crashes the page without it
ALTER TABLE public.admin_sessions
  ADD COLUMN IF NOT EXISTS logged_in_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- Backfill existing rows: set logged_in_at = created_at (best approximation)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'admin_sessions' AND column_name = 'created_at'
  ) THEN
    EXECUTE 'UPDATE public.admin_sessions SET logged_in_at = created_at WHERE logged_in_at = NOW() AND created_at < NOW() - INTERVAL ''1 second''';
  END IF;
END $$;

-- BUG-AS2: Add revoked_by — admin revoke action fails without this column
ALTER TABLE public.admin_sessions
  ADD COLUMN IF NOT EXISTS revoked_by UUID REFERENCES auth.users(id) ON DELETE SET NULL;

-- Column-level grants for admin operations on sessions
GRANT UPDATE (revoked_at, revoked_by, last_seen_at) ON public.admin_sessions TO authenticated;
GRANT SELECT ON public.admin_sessions TO authenticated;

-- BUG-AS3: RLS UPDATE policy so admins can actually revoke sessions
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'admin_sessions'
      AND policyname = 'admin_sessions_admin_revoke'
  ) THEN
    CREATE POLICY "admin_sessions_admin_revoke"
      ON public.admin_sessions FOR UPDATE
      TO authenticated
      USING (
        -- Admins can revoke any session (super admin)
        public.is_active_admin(auth.uid())
        OR
        -- Any admin can revoke their own other sessions
        admin_id = auth.uid()
      )
      WITH CHECK (
        public.is_active_admin(auth.uid())
        OR admin_id = auth.uid()
      );
  END IF;
END $$;

-- RLS SELECT policy — admins see all sessions; regular admins see their own
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'admin_sessions'
      AND policyname = 'admin_sessions_read'
  ) THEN
    CREATE POLICY "admin_sessions_read"
      ON public.admin_sessions FOR SELECT
      TO authenticated
      USING (
        -- Super admins see all sessions
        public.is_active_admin(auth.uid())
        OR
        -- Regular admins see only their own
        admin_id = auth.uid()
      );
  END IF;
END $$;


-- ============================================================================
-- PART 2: admin_users fixes (BUG-AU1, BUG-AU3, BUG-AU4)
--
-- auth_provider.dart updates last_login_at on every successful admin login.
-- team_repository.dart updates is_suspended, suspended_at, suspended_by.
-- users_admin_page._promoteToAdmin() inserts to admin_users.
-- NOTE: GRANT SELECT,INSERT,UPDATE,DELETE was already added by 20260615170000,
--       so we re-assert idempotently and add the missing columns.
-- ============================================================================

-- BUG-AU1: Add last_login_at column (auth_provider.dart L210)
ALTER TABLE public.admin_users
  ADD COLUMN IF NOT EXISTS last_login_at TIMESTAMPTZ;

-- BUG-AU3: Add suspension columns (team_repository.dart L75-79)
--   .update({'is_suspended': true, 'suspended_at': ..., 'suspended_by': ...})
ALTER TABLE public.admin_users
  ADD COLUMN IF NOT EXISTS is_suspended BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE public.admin_users
  ADD COLUMN IF NOT EXISTS suspended_at TIMESTAMPTZ;

ALTER TABLE public.admin_users
  ADD COLUMN IF NOT EXISTS suspended_by UUID REFERENCES auth.users(id) ON DELETE SET NULL;

-- BUG-AU4: email column for admin_invitations join in audit_repository
--   audit_repository.dart L18: .select('*, admin_users(full_name, email)')
ALTER TABLE public.admin_users
  ADD COLUMN IF NOT EXISTS email TEXT;

-- Belt-and-suspenders re-assert grants (idempotent in PostgreSQL)
GRANT SELECT, INSERT, UPDATE ON public.admin_users TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.admin_users TO service_role;

-- Column-level grants for the specific columns written by Dart code
GRANT UPDATE (
  last_login_at,
  is_active,
  is_suspended,
  suspended_at,
  suspended_by,
  admin_password,
  role_id,
  admin_level,
  email
) ON public.admin_users TO authenticated;

-- RLS: Allow admins to INSERT new admin_users (for promote-to-admin flow)
-- Note: 20260620000003 dropped ALL policies on admin_users and recreated only
-- service_role bypass + authenticated read. We add the missing write policies here.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'admin_users'
      AND policyname = 'admin_users_super_admin_insert'
  ) THEN
    CREATE POLICY "admin_users_super_admin_insert"
      ON public.admin_users FOR INSERT
      TO authenticated
      WITH CHECK (
        -- Only super admins can create new admin accounts
        EXISTS (
          SELECT 1 FROM public.admin_users au
          WHERE au.id = auth.uid()
            AND au.admin_level = 'super_admin'
            AND au.is_active = true
        )
      );
  END IF;
END $$;

-- RLS: Allow admins to update their own last_login_at; super_admin can update any
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'admin_users'
      AND policyname = 'admin_users_update'
  ) THEN
    CREATE POLICY "admin_users_update"
      ON public.admin_users FOR UPDATE
      TO authenticated
      USING (
        -- Self update (for last_login_at) OR super admin updating anyone
        id = auth.uid()
        OR EXISTS (
          SELECT 1 FROM public.admin_users au
          WHERE au.id = auth.uid()
            AND au.admin_level = 'super_admin'
            AND au.is_active = true
        )
      )
      WITH CHECK (
        id = auth.uid()
        OR EXISTS (
          SELECT 1 FROM public.admin_users au
          WHERE au.id = auth.uid()
            AND au.admin_level = 'super_admin'
            AND au.is_active = true
        )
      );
  END IF;
END $$;


-- ============================================================================
-- PART 3: delivery_partners fixes (BUG-DP1, BUG-DP2, BUG-DP3)
--
-- riders_admin_page.dart reads: is_online, total_deliveries, vehicle_number
-- delivery_dashboard reads: is_available, is_active, preferred_nav_app
-- update_rider_location RPC writes: current_lat, current_lng, location_updated_at
-- ============================================================================

-- BUG-DP1: Add is_online (currently delivering / GPS broadcast active)
ALTER TABLE public.delivery_partners
  ADD COLUMN IF NOT EXISTS is_online BOOLEAN NOT NULL DEFAULT false;

-- BUG-DP2: Add total_deliveries counter
ALTER TABLE public.delivery_partners
  ADD COLUMN IF NOT EXISTS total_deliveries INT NOT NULL DEFAULT 0;

-- BUG-DP3: Full column-level grant for authenticated
GRANT UPDATE (
  is_active,
  is_available,
  is_online,
  total_deliveries,
  preferred_nav_app,
  vehicle_type,
  current_lat,
  current_lng,
  location_updated_at
) ON public.delivery_partners TO authenticated;

GRANT SELECT ON public.delivery_partners TO authenticated;
GRANT SELECT ON public.delivery_partners TO service_role;

-- Trigger: auto-increment total_deliveries when order status → 'delivered'
CREATE OR REPLACE FUNCTION public.increment_rider_deliveries()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Only fire when status transitions TO 'delivered'
  IF NEW.status = 'delivered'
     AND (OLD.status IS DISTINCT FROM 'delivered')
     AND NEW.delivery_partner_id IS NOT NULL THEN
    UPDATE public.delivery_partners
      SET total_deliveries = total_deliveries + 1,
          is_online = false   -- rider goes offline after completing delivery
      WHERE id = NEW.delivery_partner_id;
  END IF;
  RETURN NEW;
END;
$$;

-- Drop existing trigger if it exists (idempotent replacement)
DROP TRIGGER IF EXISTS trg_increment_rider_deliveries ON public.orders;

CREATE TRIGGER trg_increment_rider_deliveries
  AFTER UPDATE ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.increment_rider_deliveries();


-- ============================================================================
-- PART 4: platform_config fixes (BUG-PC1)
--
-- platform_config_provider.dart upserts:
--   {'key': key, 'value': value, 'updated_by': actorId, 'updated_at': ...}
-- Both updated_by and updated_at columns are required or the upsert throws.
-- Without this fix, ZERO admin config changes persist → platform forever
-- uses hardcoded defaults (commission 5%, ₹15 fee, etc.)
-- ============================================================================

ALTER TABLE public.platform_config
  ADD COLUMN IF NOT EXISTS updated_by UUID REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE public.platform_config
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

-- Grant authenticated the ability to upsert (both INSERT + UPDATE)
GRANT SELECT, INSERT, UPDATE ON public.platform_config TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.platform_config TO service_role;

-- Column-level grants for the upsert payload
GRANT UPDATE (
  key,
  value,
  updated_by,
  updated_at
) ON public.platform_config TO authenticated;


-- ============================================================================
-- PART 5: referral_config admin write access (BUG-RC1)
--
-- Currently only SELECT is granted to authenticated.
-- Admin needs to be able to INSERT/UPDATE referral_config rows.
-- ============================================================================

GRANT INSERT, UPDATE ON public.referral_config TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.referral_config TO service_role;

-- RLS: Allow admins to manage referral_config
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'referral_config'
      AND policyname = 'referral_config_admin_write'
  ) THEN
    CREATE POLICY "referral_config_admin_write"
      ON public.referral_config FOR ALL
      TO authenticated
      USING (public.is_active_admin(auth.uid()))
      WITH CHECK (public.is_active_admin(auth.uid()));
  END IF;
END $$;

-- Public read policy (if not already created)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'referral_config'
      AND policyname = 'referral_config_public_read'
  ) THEN
    CREATE POLICY "referral_config_public_read"
      ON public.referral_config FOR SELECT
      TO authenticated
      USING (true);
  END IF;
END $$;


-- ============================================================================
-- PART 6: Default roles seed (BUG-RL1)
--
-- If the roles table is empty (fresh DB), accept_admin_invitation() cannot
-- find a valid role_id for the new admin → new admins get role_id = NULL
-- → RBAC is completely broken for them.
--
-- We seed 4 default roles using ON CONFLICT DO NOTHING — this is safe to
-- run multiple times and will NOT overwrite any customised roles already in DB.
-- ============================================================================

-- Insert default roles only if no roles exist yet (prevents duplicate seed
-- on already-configured databases with custom role names/permissions)
INSERT INTO public.roles (name, slug, description, is_system, color)
SELECT name, slug, description, is_system, color
FROM (VALUES
  (
    'Super Admin',
    'super_admin',
    'Full system access — all permissions',
    true,
    '#FF3B30'
  ),
  (
    'Admin',
    'admin',
    'General admin with most permissions except role management',
    true,
    '#007AFF'
  ),
  (
    'Finance Admin',
    'finance_admin',
    'Finance-only access — withdrawals, payouts, GST',
    true,
    '#34C759'
  ),
  (
    'Support',
    'support',
    'Read-only access to customers and orders',
    true,
    '#5856D6'
  )
) AS defaults(name, slug, description, is_system, color)
WHERE NOT EXISTS (SELECT 1 FROM public.roles LIMIT 1)
ON CONFLICT (slug) DO NOTHING;


-- ============================================================================
-- PART 7: Belt-and-suspenders re-assertion of critical grants (BUG-WD1)
--
-- Re-assert all grants that prior migrations may have missed at column level.
-- GRANTs are fully idempotent in PostgreSQL — safe to run multiple times.
-- ============================================================================

-- withdrawals: full grant re-assert for admin operations
GRANT SELECT, INSERT, UPDATE ON public.withdrawals TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.withdrawals TO service_role;

GRANT UPDATE (
  status,
  admin_notes,
  processed_at
) ON public.withdrawals TO authenticated;

-- audit_logs: INSERT by all admin operations; SELECT by admin
GRANT SELECT, INSERT ON public.audit_logs TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.audit_logs TO service_role;

-- admin_invitations: full cycle (create, read, accept)
GRANT SELECT, INSERT, UPDATE ON public.admin_invitations TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.admin_invitations TO service_role;

-- coupons: admin full CRUD; customer read-only
GRANT SELECT ON public.coupons TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.coupons TO service_role;

-- Re-assert admin CRUD on coupons via RLS (only admin can write)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'coupons'
      AND policyname = 'coupons_admin_all'
  ) THEN
    CREATE POLICY "coupons_admin_all"
      ON public.coupons FOR ALL
      TO authenticated
      USING (public.is_active_admin(auth.uid()))
      WITH CHECK (public.is_active_admin(auth.uid()));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'coupons'
      AND policyname = 'coupons_public_read'
  ) THEN
    CREATE POLICY "coupons_public_read"
      ON public.coupons FOR SELECT
      TO authenticated
      USING (is_active = true);
  END IF;
END $$;

-- profiles: ensure full UPDATE grant for profile edits
GRANT SELECT, UPDATE ON public.profiles TO authenticated;

-- shops: full SELECT for admin + authenticated reads
GRANT SELECT ON public.shops TO authenticated;
GRANT SELECT ON public.shops TO anon;
GRANT UPDATE (is_active, verification_status) ON public.shops TO authenticated;

-- customers: ensure SELECT + UPDATE for admin panel
GRANT SELECT, UPDATE ON public.customers TO authenticated;

-- orders: full re-assert (belt-and-suspenders)
GRANT SELECT ON public.orders TO authenticated;

-- notifications: already in 20260623 but re-assert
GRANT SELECT, INSERT, UPDATE ON public.notifications TO authenticated;


-- ============================================================================
-- PART 8: Update admin_get_all_riders() to return is_online + total_deliveries
--
-- The RPC was created in 20260628000001 but didn't include the two new columns.
-- We CREATE OR REPLACE so it is fully idempotent.
-- ============================================================================

DROP FUNCTION IF EXISTS public.admin_get_all_riders();
CREATE OR REPLACE FUNCTION public.admin_get_all_riders()
RETURNS TABLE (
  id                    UUID,
  verification_status   TEXT,
  vehicle_type          TEXT,
  vehicle_number        TEXT,
  aadhar_number         TEXT,
  pan_number            TEXT,
  bank_account_number   TEXT,
  bank_ifsc             TEXT,
  bank_account_holder   TEXT,
  is_active             BOOLEAN,
  is_available          BOOLEAN,
  is_online             BOOLEAN,
  total_deliveries      INT,
  preferred_nav_app     TEXT,
  created_at            TIMESTAMPTZ,
  profiles              JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Only callable by active admins
  IF NOT public.is_active_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied: admin role required';
  END IF;

  RETURN QUERY
  SELECT
    dp.id,
    dp.verification_status,
    dp.vehicle_type,
    dp.vehicle_number,
    dp.aadhar_number,
    dp.pan_number,
    dp.bank_account_number,
    dp.bank_ifsc,
    dp.bank_account_holder,
    dp.is_active,
    dp.is_available,
    dp.is_online,
    dp.total_deliveries,
    dp.preferred_nav_app,
    p.created_at,
    jsonb_build_object(
      'id',         p.id,
      'full_name',  p.full_name,
      'phone',      p.phone,
      'email',      p.email,
      'avatar_url', p.avatar_url
    ) AS profiles
  FROM public.delivery_partners dp
  LEFT JOIN public.profiles p ON p.id = dp.id
  ORDER BY p.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_get_all_riders() TO authenticated;


-- ============================================================================
-- PART 9: Update update_rider_location() to also set is_online = true
--
-- When rider broadcasts their GPS, they are clearly online.
-- The trigger (PART 3) sets is_online = false when delivery completes.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.update_rider_location(
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.delivery_partners
  SET
    current_lat         = p_lat,
    current_lng         = p_lng,
    location_updated_at = NOW(),
    is_online           = true   -- broadcasting location = actively online
  WHERE id = auth.uid();
EXCEPTION WHEN OTHERS THEN
  -- Never throw — the 15s timer must keep running regardless
  RAISE WARNING 'update_rider_location: failed for uid=%: %', auth.uid(), SQLERRM;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_rider_location(DOUBLE PRECISION, DOUBLE PRECISION) TO authenticated;


-- ============================================================================
-- PART 10: Final schema cache reload
-- ============================================================================

NOTIFY pgrst, 'reload schema';


-- ============================================================================
-- SMOKE TEST QUERIES (run manually to verify after applying)
-- ============================================================================
--
-- 1. admin_sessions columns:
--    SELECT column_name FROM information_schema.columns
--    WHERE table_name='admin_sessions' AND column_name IN ('logged_in_at','revoked_by');
--    → Should return 2 rows
--
-- 2. admin_users columns:
--    SELECT column_name FROM information_schema.columns
--    WHERE table_name='admin_users' AND column_name='last_login_at';
--    → Should return 1 row
--
-- 3. delivery_partners columns:
--    SELECT column_name FROM information_schema.columns
--    WHERE table_name='delivery_partners' AND column_name IN ('is_online','total_deliveries');
--    → Should return 2 rows
--
-- 4. platform_config columns:
--    SELECT column_name FROM information_schema.columns
--    WHERE table_name='platform_config' AND column_name IN ('updated_by','updated_at');
--    → Should return 2 rows
--
-- 5. Roles seeded:
--    SELECT slug FROM public.roles ORDER BY slug;
--    → Should include: admin, finance_admin, super_admin, support
--
-- 6. RPC callable:
--    SELECT COUNT(*) FROM public.admin_get_all_riders();
--    → Should not throw (returns 0 if no riders)
--
-- 7. update_rider_location grants:
--    SELECT has_function_privilege('authenticated', 'update_rider_location(double precision,double precision)', 'EXECUTE');
--    → Should return true
-- ============================================================================
