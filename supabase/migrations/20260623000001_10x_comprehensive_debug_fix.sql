-- ============================================================================
-- Migration: 20260623000001_10x_comprehensive_debug_fix.sql
-- Description: 10x debug pass — creates missing tables (app_logs, device_tokens),
--              fixes grants, and adds belt-and-suspenders RLS for robust operation.
--
-- WHAT THIS FIXES:
--   M1. app_logs table was used by Dart code (delivery/seller dashboards) but never
--       created. All error logging was silently failing with a "relation does not exist"
--       error that was caught and swallowed by try/catch.
--
--   M2. device_tokens table was used by notification_provider.dart for FCM token
--       registration. If the table or its unique constraint (user_id, token) didn't
--       exist, ALL push notifications silently failed — upsert would throw, caught,
--       and the token was never persisted.
--
--   EXTRA. Belt-and-suspenders GRANTs for platform_config, tax_config, and the
--          notifications table to prevent any lingering "Grant SELECT" errors.
--
-- SAFETY:
--   • All CREATE TABLE / ALTER TABLE use IF NOT EXISTS — fully idempotent.
--   • All GRANT statements are idempotent in Postgres.
--   • All policy CREATEs are guarded with IF NOT EXISTS checks.
--   • Does NOT modify any existing migration SQL.
-- ============================================================================


-- ============================================================================
-- PART 1: Create app_logs table (M1)
-- Used by delivery_dashboard and seller_orders_page for error/debug logging.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.app_logs (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  message     TEXT        NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Grant INSERT to authenticated so dashboards can write error logs
GRANT INSERT ON public.app_logs TO authenticated;
-- Admins can read logs to debug production issues
GRANT SELECT ON public.app_logs TO authenticated;

ALTER TABLE public.app_logs ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  -- Authenticated users can insert their own logs
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'app_logs'
      AND policyname = 'Users can insert app logs'
  ) THEN
    CREATE POLICY "Users can insert app logs"
      ON public.app_logs FOR INSERT TO authenticated
      WITH CHECK (true);
  END IF;

  -- Authenticated users can read logs (admins will filter on their end)
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'app_logs'
      AND policyname = 'Users can read app logs'
  ) THEN
    CREATE POLICY "Users can read app logs"
      ON public.app_logs FOR SELECT TO authenticated
      USING (true);
  END IF;
END $$;


-- ============================================================================
-- PART 2: Create device_tokens table (M2)
-- Used by notification_provider.dart to persist FCM device tokens.
-- Without this table the upsert throws, FCM tokens are never saved,
-- and ALL background push notifications silently fail.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.device_tokens (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  token       TEXT        NOT NULL,
  platform    TEXT        NOT NULL DEFAULT 'android', -- 'android' | 'ios'
  role        TEXT,                                   -- 'customer' | 'seller' | 'delivery'
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- Unique constraint required for the upsert onConflict: 'user_id,token'
  CONSTRAINT device_tokens_user_token_unique UNIQUE (user_id, token)
);

-- Index for fast lookup by user when sending pushes
CREATE INDEX IF NOT EXISTS idx_device_tokens_user_id ON public.device_tokens (user_id);

-- Index for querying by role (used by send-broadcast edge function)
CREATE INDEX IF NOT EXISTS idx_device_tokens_role ON public.device_tokens (role);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.device_tokens TO authenticated;
-- service_role needs access so Edge Functions can query tokens
GRANT SELECT, INSERT, UPDATE, DELETE ON public.device_tokens TO service_role;

ALTER TABLE public.device_tokens ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  -- Users can read and manage only their own tokens
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'device_tokens'
      AND policyname = 'Users can manage their own device tokens'
  ) THEN
    CREATE POLICY "Users can manage their own device tokens"
      ON public.device_tokens FOR ALL TO authenticated
      USING (user_id = auth.uid())
      WITH CHECK (user_id = auth.uid());
  END IF;

  -- service_role bypass (for Edge Functions sending push notifications)
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'device_tokens'
      AND policyname = 'Service role full access to device tokens'
  ) THEN
    CREATE POLICY "Service role full access to device tokens"
      ON public.device_tokens FOR ALL TO service_role
      USING (true)
      WITH CHECK (true);
  END IF;
END $$;


-- ============================================================================
-- PART 3: Belt-and-suspenders GRANTs for tables that previously caused
--         "Grant SELECT" errors in production
-- ============================================================================

-- platform_config: read by PlatformConfigProvider on app startup
GRANT SELECT ON public.platform_config TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.platform_config TO authenticated;

-- tax_config: read by PlatformConfigProvider for GST rate lookup
GRANT SELECT ON public.tax_config TO authenticated;

-- notifications: full access (read/write/delete for notification history)
GRANT SELECT, INSERT, UPDATE, DELETE ON public.notifications TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.notifications TO service_role;

-- profiles: authenticated users must read their own phone number at checkout
GRANT SELECT ON public.profiles TO authenticated;

-- ratings: readers + writers
GRANT SELECT, INSERT ON public.ratings TO authenticated;

-- saved_addresses: already in migration 20260622000002 but re-stating for idempotency
GRANT SELECT, INSERT, UPDATE, DELETE ON public.saved_addresses TO authenticated;

-- order_items: needed by all order views
GRANT SELECT, INSERT ON public.order_items TO authenticated;


-- ============================================================================
-- PART 4: Reload PostgREST schema cache
-- ============================================================================

NOTIFY pgrst, 'reload schema';
