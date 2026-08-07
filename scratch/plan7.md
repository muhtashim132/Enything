# Updating Walkthrough
I need to update the walkthrough to reflect the front-end fix I just made.
The user got stuck on the "Partial Order Rejection" banner because:
1. Shop 1 was accepted.
2. Shop 2 was cancelled.
3. Because Shop 1 is accepted, there are no "pending" shops, but the order is still technically "awaiting_acceptance" because the rider hasn't accepted.
4. This causes the UI to show the banner and run the timer, but clicking "Cancel Pending Shops" does nothing (as there are none), and doesn't cancel the timer.
5. The timer would eventually run out and cancel the entire order.
I fixed this by letting the button cancel the timer and saving a `_partialRejectionResolved` state in SharedPreferences.
