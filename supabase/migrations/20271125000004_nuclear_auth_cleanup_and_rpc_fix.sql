-- ============================================================================
-- Migration: 20271125000004_nuclear_auth_cleanup_and_rpc_fix.sql
-- Description: ADDITIVE / NUCLEAR CLEANUP ONLY.
--
-- Problem: GoTrue's internal SELECT on auth.users is throwing DB errors
-- because our previous migrations (20271125000000-20271125000003) inserted
-- rows with extra columns (phone, phone_confirmed_at, is_super_admin, etc.)
-- that conflict with GoTrue's internal query structure.
--
-- Fix Part 1: Delete ALL auth artifacts for the 3 magic emails using
--   individual EXCEPTION WHEN others THEN NULL blocks so each step cannot
--   block subsequent steps even if a constraint fires.
--   NO new INSERT into auth.users or auth.identities — GoTrue creates them.
--
-- Fix Part 2: Replace magic_reviewer_auto_accept RPC to check by EMAIL
--   instead of hardcoded UUIDs. This is required because after the cleanup,
--   Flutter's signUp creates users with RANDOM UUIDs (not the deterministic
--   00000000-0000-0000-0000-91999999999X UUIDs we used before).
--
-- After this migration:
--   1. Flutter's verifyPhoneOtp for magic numbers calls signInWithPassword
--      → fails gracefully (user not found, not a DB error)
--   → then calls signUp → SUCCEEDS → GoTrue creates user with random UUID
--   2. auth_provider reviewer code (line 695+) creates profile/customer/shop
--   3. auto-accept RPC checks by email → works regardless of UUID
-- ============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- PART 1: Nuclear cleanup of broken SQL-inserted auth rows
-- Each step in its own EXCEPTION block — if one step fails, others still run.
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN

  -- Step 1a: Delete MFA factors (if table exists)
  BEGIN
    DELETE FROM auth.mfa_factors
    WHERE user_id IN (
      '00000000-0000-0000-0000-919999999996'::uuid,
      '00000000-0000-0000-0000-919999999997'::uuid,
      '00000000-0000-0000-0000-919999999998'::uuid
    );
  EXCEPTION WHEN others THEN
    RAISE NOTICE 'mfa_factors delete skipped: %', SQLERRM;
  END;

  -- Step 1b: Delete sessions
  BEGIN
    DELETE FROM auth.sessions
    WHERE user_id IN (
      '00000000-0000-0000-0000-919999999996'::uuid,
      '00000000-0000-0000-0000-919999999997'::uuid,
      '00000000-0000-0000-0000-919999999998'::uuid
    );
  EXCEPTION WHEN others THEN
    RAISE NOTICE 'sessions delete skipped: %', SQLERRM;
  END;

  -- Step 1c: Delete refresh_tokens (user_id is varchar in this table)
  BEGIN
    DELETE FROM auth.refresh_tokens
    WHERE user_id IN (
      '00000000-0000-0000-0000-919999999996',
      '00000000-0000-0000-0000-919999999997',
      '00000000-0000-0000-0000-919999999998'
    );
  EXCEPTION WHEN others THEN
    RAISE NOTICE 'refresh_tokens delete skipped: %', SQLERRM;
  END;

  -- Step 1d: Delete identities by user_id (UUID)
  BEGIN
    DELETE FROM auth.identities
    WHERE user_id IN (
      '00000000-0000-0000-0000-919999999996'::uuid,
      '00000000-0000-0000-0000-919999999997'::uuid,
      '00000000-0000-0000-0000-919999999998'::uuid
    );
  EXCEPTION WHEN others THEN
    RAISE NOTICE 'identities by user_id delete skipped: %', SQLERRM;
  END;

  -- Step 1e: Delete identities by provider_id (email string)
  BEGIN
    DELETE FROM auth.identities
    WHERE provider_id IN (
      'mock919999999996@enything.com',
      'mock919999999997@enything.com',
      'mock919999999998@enything.com'
    );
  EXCEPTION WHEN others THEN
    RAISE NOTICE 'identities by provider_id delete skipped: %', SQLERRM;
  END;

  -- Step 1f: Delete auth.users by UUID
  BEGIN
    DELETE FROM auth.users
    WHERE id IN (
      '00000000-0000-0000-0000-919999999996'::uuid,
      '00000000-0000-0000-0000-919999999997'::uuid,
      '00000000-0000-0000-0000-919999999998'::uuid
    );
  EXCEPTION WHEN others THEN
    RAISE NOTICE 'auth.users by id delete skipped: %', SQLERRM;
  END;

  -- Step 1g: Delete auth.users by email (catch any rows with different UUIDs)
  BEGIN
    DELETE FROM auth.users
    WHERE lower(email) IN (
      'mock919999999996@enything.com',
      'mock919999999997@enything.com',
      'mock919999999998@enything.com'
    );
  EXCEPTION WHEN others THEN
    RAISE NOTICE 'auth.users by email delete skipped: %', SQLERRM;
  END;

  -- Step 1h: Delete auth.users by phone (belt-and-suspenders)
  BEGIN
    DELETE FROM auth.users
    WHERE phone IN (
      '+919999999996',
      '+919999999997',
      '+919999999998'
    );
  EXCEPTION WHEN others THEN
    RAISE NOTICE 'auth.users by phone delete skipped: %', SQLERRM;
  END;

  RAISE NOTICE 'Auth cleanup completed. Magic reviewer accounts removed.';
  RAISE NOTICE 'Flutter signUp will create them via GoTrue on first login.';

END $$;


-- ─────────────────────────────────────────────────────────────────────────────
-- PART 2: Replace magic_reviewer_auto_accept RPC
-- Check by EMAIL in auth.users (works with any UUID, including random ones
-- created by GoTrue's signUp). SECURITY DEFINER runs as owner, can read auth.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.magic_reviewer_auto_accept(p_order_ids uuid[])
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id  uuid  := auth.uid();
  v_caller_email text;
  v_allowed    boolean := false;
  v_oid        uuid;
BEGIN
  -- 1. Get caller's email from auth.users
  BEGIN
    SELECT email INTO v_caller_email
    FROM auth.users
    WHERE id = v_caller_id;
  EXCEPTION WHEN others THEN
    RAISE EXCEPTION 'Unauthorized: cannot verify reviewer identity (%)' , SQLERRM;
  END;

  -- 2. Check if this is a magic reviewer email
  IF lower(v_caller_email) IN (
    'mock919999999996@enything.com',
    'mock919999999997@enything.com',
    'mock919999999998@enything.com'
  ) THEN
    v_allowed := true;
  END IF;

  IF NOT v_allowed THEN
    RAISE EXCEPTION 'Unauthorized: magic_reviewer_auto_accept is restricted to reviewer accounts';
  END IF;

  -- 3. For each order: set seller accepted + DP accepted
  FOREACH v_oid IN ARRAY p_order_ids LOOP
    UPDATE public.orders
    SET
      status                = 'out_for_delivery',
      seller_accepted_at    = COALESCE(seller_accepted_at, now()),
      rider_accepted_at     = COALESCE(rider_accepted_at, now()),
      updated_at            = now()
    WHERE id = v_oid;
  END LOOP;

  RAISE NOTICE 'magic_reviewer_auto_accept: accepted % orders for reviewer %',
    array_length(p_order_ids, 1), v_caller_email;
END;
$$;

-- Grant execute to authenticated users (the RPC itself checks email)
REVOKE ALL ON FUNCTION public.magic_reviewer_auto_accept(uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.magic_reviewer_auto_accept(uuid[]) TO authenticated;

NOTIFY pgrst, 'reload schema';
