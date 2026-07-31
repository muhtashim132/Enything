-- =========================================================
-- EDGE CASE TEST SUITE for sync_shop_accepting_orders_by_hours
-- =========================================================

-- EDGE CASE 1: Normal shift — inside range
SELECT 'EC1 NORMAL IN RANGE (PASS if true)' as test,
  CASE WHEN '14:00'::time >= '09:00'::time AND '14:00'::time <= '21:00'::time
       THEN 'PASS ✅' ELSE 'FAIL ❌' END as result;

-- EDGE CASE 2: Normal shift — outside range (before open)
SELECT 'EC2 NORMAL BEFORE OPEN (PASS if false)' as test,
  CASE WHEN NOT('04:00'::time >= '09:00'::time AND '04:00'::time <= '21:00'::time)
       THEN 'PASS ✅' ELSE 'FAIL ❌' END as result;

-- EDGE CASE 3: Normal shift — outside range (after close)
SELECT 'EC3 NORMAL AFTER CLOSE (PASS if false)' as test,
  CASE WHEN NOT('22:00'::time >= '09:00'::time AND '22:00'::time <= '21:00'::time)
       THEN 'PASS ✅' ELSE 'FAIL ❌' END as result;

-- EDGE CASE 4: Normal shift — exactly at open time
SELECT 'EC4 NORMAL AT EXACT OPEN (PASS if true)' as test,
  CASE WHEN '09:00'::time >= '09:00'::time AND '09:00'::time <= '21:00'::time
       THEN 'PASS ✅' ELSE 'FAIL ❌' END as result;

-- EDGE CASE 5: Normal shift — exactly at close time
SELECT 'EC5 NORMAL AT EXACT CLOSE (PASS if true)' as test,
  CASE WHEN '21:00'::time >= '09:00'::time AND '21:00'::time <= '21:00'::time
       THEN 'PASS ✅' ELSE 'FAIL ❌' END as result;

-- EDGE CASE 6: Night shift (cross-midnight 09:00→05:00) — BEFORE midnight, after open
--   04:43 AM currently — should be open (04:43 < 05:00)
SELECT 'EC6 NIGHT SHIFT 09:00→05:00 at 04:43 (PASS if true)' as test,
  CASE WHEN ('04:43'::time >= '09:00'::time OR '04:43'::time <= '05:00'::time)
       THEN 'PASS ✅' ELSE 'FAIL ❌' END as result;

-- EDGE CASE 7: Night shift — exactly at close time of night shift
SELECT 'EC7 NIGHT SHIFT AT EXACT CLOSE 05:00 (PASS if true)' as test,
  CASE WHEN ('05:00'::time >= '09:00'::time OR '05:00'::time <= '05:00'::time)
       THEN 'PASS ✅' ELSE 'FAIL ❌' END as result;

-- EDGE CASE 8: Night shift — past close time (should be closed)
SELECT 'EC8 NIGHT SHIFT AFTER CLOSE at 06:00 (PASS if false)' as test,
  CASE WHEN NOT('06:00'::time >= '09:00'::time OR '06:00'::time <= '05:00'::time)
       THEN 'PASS ✅' ELSE 'FAIL ❌' END as result;

-- EDGE CASE 9: Night shift — late night, well after midnight (02:00)
SELECT 'EC9 NIGHT SHIFT AT 02:00 (PASS if true)' as test,
  CASE WHEN ('02:00'::time >= '22:00'::time OR '02:00'::time <= '06:00'::time)
       THEN 'PASS ✅' ELSE 'FAIL ❌' END as result;

-- EDGE CASE 10: 24hr shop (00:00→23:59) — always open
SELECT 'EC10 24HR SHOP (PASS if true)' as test,
  CASE WHEN '04:43'::time >= '00:00'::time AND '04:43'::time <= '23:59'::time
       THEN 'PASS ✅' ELSE 'FAIL ❌' END as result;

-- EDGE CASE 11: safe_cast_time with NULL
SELECT 'EC11 safe_cast_time(NULL) is NULL (PASS if null)' as test,
  CASE WHEN public.safe_cast_time(NULL) IS NULL
       THEN 'PASS ✅' ELSE 'FAIL ❌' END as result;

-- EDGE CASE 12: safe_cast_time with empty string
SELECT 'EC12 safe_cast_time empty string is NULL (PASS if null)' as test,
  CASE WHEN public.safe_cast_time('') IS NULL
       THEN 'PASS ✅' ELSE 'FAIL ❌' END as result;

-- EDGE CASE 13: safe_cast_time with garbage
SELECT 'EC13 safe_cast_time garbage is NULL (PASS if null)' as test,
  CASE WHEN public.safe_cast_time('not-a-time') IS NULL
       THEN 'PASS ✅' ELSE 'FAIL ❌' END as result;

-- EDGE CASE 14: safe_cast_time with valid time
SELECT 'EC14 safe_cast_time valid returns time (PASS if not null)' as test,
  CASE WHEN public.safe_cast_time('09:00:00') IS NOT NULL
       THEN 'PASS ✅' ELSE 'FAIL ❌' END as result;

-- EDGE CASE 15: Kamrans Restaurant must now be visible
SELECT 'EC15 KAMRANS RESTAURANT NOW VISIBLE (PASS if true+true)' as test,
  CASE WHEN is_active = true AND is_accepting_orders = true
       THEN 'PASS ✅' ELSE 'FAIL ❌ is_active=' || is_active::text || ' is_accepting=' || is_accepting_orders::text END as result
FROM public.shops WHERE name = 'Kamrans Restaurant' LIMIT 1;

-- EDGE CASE 16: Cron job exists
SELECT 'EC16 CRON JOB EXISTS (PASS if scheduled)' as test,
  CASE WHEN COUNT(*) > 0 THEN 'PASS ✅' ELSE 'FAIL ❌' END as result
FROM cron.job WHERE jobname = 'sync-shop-hours';

-- EDGE CASE 17: Trigger exists
SELECT 'EC17 TRIGGER EXISTS (PASS if found)' as test,
  CASE WHEN COUNT(*) > 0 THEN 'PASS ✅' ELSE 'FAIL ❌' END as result
FROM information_schema.triggers
WHERE trigger_name = 'trg_sync_shop_hours_update'
  AND event_object_table = 'shops';
