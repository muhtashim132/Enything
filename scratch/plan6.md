# Partial Order Rejection Banner Bug
The user is stuck on the Partial Order Rejection banner because:
1. The customer wants to continue with the accepted Shop 1.
2. The button says "Cancel Pending Shops", but there are NO pending shops.
3. If they click it, it just shows a snackbar. It DOES NOT stop the timer.
4. The timer will eventually hit 0 and cancel their entire order!

# Plan
In `track_order_page.dart`:
1. We need to introduce a boolean flag, e.g., `_customerAcceptedPartial` stored in `SharedPreferences`.
2. When the user clicks the green button (which we will rename to "Continue with Accepted Items" if there are no pending shops), we set `_customerAcceptedPartial = true`.
3. If `_customerAcceptedPartial` is true, we immediately `_decisionCountdownTimer?.cancel()` and hide the Partial Rejection Banner!
4. We need to load this flag in `initState` so it persists across page reloads.
