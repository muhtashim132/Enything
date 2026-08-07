# Root Cause Analysis: The Checkout Crash & Spoofing Error
The customer is getting "Platform fee spoofing detected. Expected: 5.0, Got: 40.0" when placing an order.
This happens because:
1. In Postgres, you **cannot** directly cast a `jsonb` scalar number to numeric using `::numeric`. It throws an error. You must extract it as text first using `(value#>>'{}')::numeric`.
2. When the admin changes a config (e.g. `platform_fee` to 20), the Flutter app saves it as a JSONB number in the database.
3. During checkout, `place_orders_transaction` attempts `SELECT value::numeric FROM platform_config`. This implicitly crashes.
4. Because the `SELECT` is wrapped in a `BEGIN ... EXCEPTION WHEN OTHERS`, it silently swallows the crash and falls back to the default `2.5` per shop! So it expects `5.0` (for 2 shops), but the app correctly passes `40.0`.
5. BOOM: Spoofing detected!

Additionally, **Migration 27 was a complete dud for the checkout flow**. I accidentally used an ancient, obsolete signature for `place_orders_transaction` (with 13 parameters) instead of the one the app actually calls (with 6 parameters). So the database just created a second, unused function, and the app continued running the buggy Migration 25 version!

# The Ultimate Plan (Migration 32)
1. **Drop the phantom function**: `DROP FUNCTION IF EXISTS public.place_orders_transaction(uuid, uuid, text, text, text, double precision, double precision, text, text, jsonb, jsonb, text, uuid);`
2. **Rewrite the REAL `place_orders_transaction`** (the 6-parameter one from Migration 25).
3. Integrate the missing fees fix for `grand_total_collected` (that I attempted in Migration 27) into this correct function.
4. Replace EVERY instance of `value::numeric` with `(value#>>'{}')::numeric` across both `place_orders_transaction` AND `reallocate_cancelled_delivery_fees`.
