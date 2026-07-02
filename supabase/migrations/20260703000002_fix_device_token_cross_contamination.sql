-- ============================================================================
-- Migration: 20260703000002_fix_device_token_cross_contamination.sql
-- Description: SECURITY FIX — prevents admin/role push notifications from
--   leaking to devices where a different user was previously logged in.
--
-- Root Cause:
--   When Admin A logs in on Device X, a device_tokens row is created:
--     (user_id=ADMIN_A, token=DEVICE_X_FCM_TOKEN)
--   When Admin A logs out (via adminSignOut), the row is NEVER deleted.
--   When User B then logs in on Device X, a second row is created:
--     (user_id=USER_B, token=DEVICE_X_FCM_TOKEN)
--   Now BOTH rows exist. When a KYC notification fires for ADMIN_A,
--   the send-push Edge Function finds DEVICE_X_FCM_TOKEN and delivers
--   the admin notification to USER B's device — a security breach.
--
-- Fix:
--   1. Add a `device_id` column — a stable per-device identifier stored
--      in SharedPreferences by the Flutter app (generated once, UUID).
--   2. Add a BEFORE INSERT trigger that deletes any OTHER user's tokens
--      that share the same physical FCM token before inserting the new row.
--      This is the DB-level enforcement of "one device = one active user".
--   3. Clean up existing stale duplicate token rows immediately.
--
-- Constraints:
--   - NO existing SQL is modified
--   - ADDITIVE ONLY — all changes are new columns, new indexes, new trigger
--   - Safe to re-run (all statements are idempotent)
-- ============================================================================

-- ── STEP 1: Add device_id column (nullable, so existing rows are unaffected) ──
ALTER TABLE public.device_tokens
  ADD COLUMN IF NOT EXISTS device_id TEXT DEFAULT NULL;

-- ── STEP 2: Add index for fast device_id lookups ──────────────────────────────
CREATE INDEX IF NOT EXISTS idx_device_tokens_device_id
  ON public.device_tokens (device_id)
  WHERE device_id IS NOT NULL;

-- ── STEP 3: Create the cross-contamination prevention trigger ─────────────────
-- This trigger fires BEFORE each INSERT on device_tokens.
-- It deletes any existing rows where:
--   - The FCM token is the same (same physical device) BUT
--   - The user_id is different (a different user was previously logged in)
-- This enforces: one physical FCM token → one user_id at a time.
-- NOTE: Uses SECURITY DEFINER so it runs with superuser privilege and can
--   bypass RLS policies (service_role bypass is already granted, but we
--   need the trigger itself to delete across users).

CREATE OR REPLACE FUNCTION public.enforce_single_token_per_device()
RETURNS TRIGGER AS $$
BEGIN
  -- Delete any token rows for OTHER users that have the exact same FCM token.
  -- This handles the scenario: Admin logs in on Device X, logs out,
  -- then Friend logs in on Device X — the stale admin token is purged.
  DELETE FROM public.device_tokens
  WHERE token = NEW.token
    AND user_id != NEW.user_id;

  -- If device_id is provided, also clean up by device_id for any other user.
  -- This is a secondary safety net (device_id is more stable than FCM tokens
  -- which can rotate on uninstall/reinstall).
  IF NEW.device_id IS NOT NULL THEN
    DELETE FROM public.device_tokens
    WHERE device_id = NEW.device_id
      AND user_id != NEW.user_id;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop and recreate to ensure latest version is active
DROP TRIGGER IF EXISTS tr_enforce_single_token_per_device ON public.device_tokens;

CREATE TRIGGER tr_enforce_single_token_per_device
  BEFORE INSERT ON public.device_tokens
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_single_token_per_device();

-- ── STEP 4: Clean up existing stale duplicate token rows ─────────────────────
-- Find tokens that exist for multiple users (the exact contamination scenario)
-- and keep only the most recently updated row per token value.
-- This one-time cleanup removes all pre-existing cross-user contamination.
DELETE FROM public.device_tokens AS old_row
WHERE id IN (
  SELECT id FROM (
    SELECT
      id,
      ROW_NUMBER() OVER (
        PARTITION BY token
        ORDER BY updated_at DESC, created_at DESC
      ) AS rn
    FROM public.device_tokens
  ) ranked
  WHERE rn > 1
);

-- ── STEP 5: Grant EXECUTE on the new function to authenticated & service_role ──
GRANT EXECUTE ON FUNCTION public.enforce_single_token_per_device() TO service_role;
GRANT EXECUTE ON FUNCTION public.enforce_single_token_per_device() TO authenticated;
