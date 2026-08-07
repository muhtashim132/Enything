1. The bug is that `reallocate_cancelled_delivery_fees` checks `AND COALESCE(rider_earnings, 0) = 0`.
2. Since `rider_earnings` is populated at checkout with a projected value (> 0), the condition ALWAYS fails.
3. As a result, `reallocate_cancelled_delivery_fees` has been silently aborting for EVERY cancellation.
4. The fix is to create Migration 28 `20290000000028_100x_rider_earnings_blocker_fix.sql` which removes the `rider_earnings = 0` check from both the outer loop and inner query in `reallocate_cancelled_delivery_fees`.
