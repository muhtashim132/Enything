-- ============================================================================
-- KYC Debug Diagnostics
-- Run these ONE AT A TIME in Supabase SQL Editor
-- ============================================================================

-- STEP 0: Check if the admin RPC functions even exist!
-- If these return 0 rows, the functions are NOT deployed and you need to run admin_rpc_shops_riders.sql
SELECT routine_name, routine_type
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name IN ('admin_get_all_shops', 'admin_get_all_riders', 'is_active_admin')
ORDER BY routine_name;

-- STEP 1: Confirm your admin record exists and is active
-- (This works in SQL Editor — no auth session needed)
SELECT id, full_name, admin_level, is_active, is_suspended
FROM admin_users
WHERE id = '99da01b7-4f89-445d-b8a5-48a8b59cbcc6';

-- STEP 2: Test is_active_admin() with your specific UUID
-- (This works in SQL Editor — hardcoded UUID, no auth.uid() needed)
SELECT public.is_active_admin('99da01b7-4f89-445d-b8a5-48a8b59cbcc6');

-- STEP 3: Check what verification_status values actually exist in shops table
SELECT verification_status, COUNT(*) FROM shops GROUP BY verification_status;

-- NOTE: Running admin_get_all_shops() from the SQL Editor will ALWAYS fail with
-- 'Access denied' because the SQL editor has no auth session (auth.uid() = NULL).
-- This is NORMAL. The function works correctly from the Flutter app.

-- STEP 4: If Step 2 returned FALSE, fix your admin record:
-- UPDATE admin_users
-- SET is_active = TRUE, is_suspended = FALSE
-- WHERE id = '99da01b7-4f89-445d-b8a5-48a8b59cbcc6';

-- STEP 5: Find YOUR real UUID from the auth.users table
-- (Compare this with the UUID you inserted — they must match EXACTLY)
SELECT id, phone, created_at FROM auth.users ORDER BY created_at DESC LIMIT 10;
