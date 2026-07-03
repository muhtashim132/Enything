-- ============================================================================
-- Migration: 20260707000001_pre_release_fixes.sql
-- Description: Additive-only fixes for all issues found during pre-release audit.
--
-- CHANGES (all ADDITIVE -- no existing SQL altered, no columns dropped):
--
--  1. profiles table: Add missing notification-preference columns used by
--     profile_settings_dialogs.dart (_BellNotifSettingsSheet):
--       * notif_orders  (BOOLEAN) -- read/written at lines 831, 995
--       * notif_promos  (BOOLEAN) -- read/written at lines 832, 1009
--       * notif_system  (BOOLEAN) -- read/written at lines 833, 1023
--     Without these columns the Notification & Bell Settings bottom-sheet
--     crashes with PostgreSQL error 42703 "column does not exist".
--
--  2. reviews table: Add missing GRANT SELECT, INSERT, UPDATE for authenticated.
--     The table was created in 20260706000001 with RLS policies but no
--     explicit GRANT -- PostgREST requires both RLS + GRANT to allow DML.
--
--  3. NOTIFY pgrst to reload schema cache so new columns are immediately
--     visible to the PostgREST query planner.
--
-- SAFETY GUARANTEES:
--   * Every DDL uses ADD COLUMN IF NOT EXISTS -- fully idempotent.
--   * GRANT statements are always idempotent in PostgreSQL.
--   * No existing column is altered or dropped.
--   * No existing RLS policy is modified.
--   * No existing function or trigger is changed.
--   * No data loss possible.
-- ============================================================================


-- ============================================================================
-- 1. ADD MISSING NOTIFICATION-PREFERENCE COLUMNS TO profiles TABLE
-- ============================================================================
-- These three columns are SELECT-ed and UPDATE-d by the Notification & Bell
-- Settings bottom-sheet in profile_settings_dialogs.dart.
-- Default value is TRUE so existing users automatically receive all alerts
-- (opt-out model -- matches the app's existing UX intent).

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS notif_orders BOOLEAN NOT NULL DEFAULT true;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS notif_promos BOOLEAN NOT NULL DEFAULT true;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS notif_system BOOLEAN NOT NULL DEFAULT true;

-- Belt-and-suspenders: ensure authenticated users can UPDATE these new columns.
GRANT UPDATE (notif_orders, notif_promos, notif_system) ON public.profiles TO authenticated;
GRANT SELECT (notif_orders, notif_promos, notif_system) ON public.profiles TO authenticated;


-- ============================================================================
-- 2. GRANT ON reviews TABLE
-- ============================================================================
-- Migration 20260706000001 created the reviews table with RLS policies but
-- did not issue the explicit object-level GRANT that PostgREST requires.
-- Without this GRANT, even authenticated users with matching RLS policies
-- receive a "permission denied for table reviews" error.

DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'reviews'
  ) THEN
    EXECUTE 'GRANT SELECT, INSERT, UPDATE ON public.reviews TO authenticated';
  END IF;
END $$;


-- ============================================================================
-- 3. NOTIFY PostgREST to reload its schema cache
-- ============================================================================

NOTIFY pgrst, 'reload schema';
