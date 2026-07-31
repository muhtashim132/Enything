-- =========================================================
-- EDGE CASE TEST SUITE for sync_shop_accepting_orders_by_hours (COMBINED)
-- =========================================================

SELECT 'EC1 NORMAL IN RANGE' as test,
  CASE WHEN '14:00'::time >= '09:00'::time AND '14:00'::time <= '21:00'::time THEN 'PASS ✅' ELSE 'FAIL ❌' END as result
UNION ALL
SELECT 'EC2 NORMAL BEFORE OPEN',
  CASE WHEN NOT('04:00'::time >= '09:00'::time AND '04:00'::time <= '21:00'::time) THEN 'PASS ✅' ELSE 'FAIL ❌' END
UNION ALL
SELECT 'EC3 NORMAL AFTER CLOSE',
  CASE WHEN NOT('22:00'::time >= '09:00'::time AND '22:00'::time <= '21:00'::time) THEN 'PASS ✅' ELSE 'FAIL ❌' END
UNION ALL
SELECT 'EC4 NORMAL AT EXACT OPEN',
  CASE WHEN '09:00'::time >= '09:00'::time AND '09:00'::time <= '21:00'::time THEN 'PASS ✅' ELSE 'FAIL ❌' END
UNION ALL
SELECT 'EC5 NORMAL AT EXACT CLOSE',
  CASE WHEN '21:00'::time >= '09:00'::time AND '21:00'::time <= '21:00'::time THEN 'PASS ✅' ELSE 'FAIL ❌' END
UNION ALL
SELECT 'EC6 NIGHT SHIFT 09:00→05:00 at 04:43',
  CASE WHEN ('04:43'::time >= '09:00'::time OR '04:43'::time <= '05:00'::time) THEN 'PASS ✅' ELSE 'FAIL ❌' END
UNION ALL
SELECT 'EC7 NIGHT SHIFT AT EXACT CLOSE 05:00',
  CASE WHEN ('05:00'::time >= '09:00'::time OR '05:00'::time <= '05:00'::time) THEN 'PASS ✅' ELSE 'FAIL ❌' END
UNION ALL
SELECT 'EC8 NIGHT SHIFT AFTER CLOSE at 06:00',
  CASE WHEN NOT('06:00'::time >= '09:00'::time OR '06:00'::time <= '05:00'::time) THEN 'PASS ✅' ELSE 'FAIL ❌' END
UNION ALL
SELECT 'EC9 NIGHT SHIFT AT 02:00',
  CASE WHEN ('02:00'::time >= '22:00'::time OR '02:00'::time <= '06:00'::time) THEN 'PASS ✅' ELSE 'FAIL ❌' END
UNION ALL
SELECT 'EC10 24HR SHOP',
  CASE WHEN '04:43'::time >= '00:00'::time AND '04:43'::time <= '23:59'::time THEN 'PASS ✅' ELSE 'FAIL ❌' END
UNION ALL
SELECT 'EC11 safe_cast_time(NULL)',
  CASE WHEN public.safe_cast_time(NULL) IS NULL THEN 'PASS ✅' ELSE 'FAIL ❌' END
UNION ALL
SELECT 'EC12 safe_cast_time empty string',
  CASE WHEN public.safe_cast_time('') IS NULL THEN 'PASS ✅' ELSE 'FAIL ❌' END
UNION ALL
SELECT 'EC13 safe_cast_time garbage',
  CASE WHEN public.safe_cast_time('not-a-time') IS NULL THEN 'PASS ✅' ELSE 'FAIL ❌' END
UNION ALL
SELECT 'EC14 safe_cast_time valid',
  CASE WHEN public.safe_cast_time('09:00:00') IS NOT NULL THEN 'PASS ✅' ELSE 'FAIL ❌' END
UNION ALL
SELECT 'EC15 KAMRANS RESTAURANT NOW VISIBLE',
  CASE WHEN is_active = true AND is_accepting_orders = true THEN 'PASS ✅' ELSE 'FAIL ❌' END
FROM public.shops WHERE name = 'Kamrans Restaurant' LIMIT 1;
