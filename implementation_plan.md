# Goal Description
Fix UI and backend calculations for partial order rejection and searching alternative items.

## Proposed Changes
1. **Fix `TrackOrderPage` Search Alternatives Crash**
   - The user gets an error when searching for different items after a realtime update changes the state.
   - The crash happens in `_showMissingItemsSheet` when calling `rejectedOrders.firstWhere((o) => o.items.contains(item))`. Since `OrderItem` doesn't override `==` and the list is recreated from the database on reconnect, reference equality fails.
   - **Fix:** Change `o.items.contains(item)` to `o.items.any((i) => i.productId == item.productId)`.

2. **Fix Backend Reallocation Math (`reallocate_cancelled_delivery_fees`)**
   - In `20290000000001_fix_reallocate_unpaid_grand_total.sql` (and its predecessors), `v_net_delivery` and `rider_earnings` explicitly add `multi_shop_surcharge`, `small_cart_fee`, and `heavy_order_fee`.
   - However, in `place_orders_transaction.txt`, `delivery_charges` **already includes** all these surcharges.
   - Adding them again double-counts the surcharges, artificially inflating `grand_total_collected` and `rider_earnings`.
   - **Fix:** Create a new migration `20290000000013_100x_partial_rejection_math_double_count_fix.sql` to correct `reallocate_cancelled_delivery_fees`. The formulas will simply use `rec.delivery_charges + v_split_delivery` for delivery, and correctly subtract only `small_cart_fee` for rider earnings, matching the checkout logic exactly.

3. **Fix `TrackOrderPage` Bill Summary Display**
   - The UI Bill Summary does not show `small_cart_fee`, `heavy_order_fee`, and `multi_shop_surcharge` rows, leading to confusion when the math does not add up visually. Wait, if `delivery_charges` includes them, should we separate them out in the UI? 
   - Actually, in `checkout_page.dart`, they ARE separated out for display! Checkout subtracts them from `effectiveBase` to show them cleanly. I will align `TrackOrderPage`'s Bill Summary to match `checkout_page.dart` exactly so the numbers sum up beautifully.

## User Review Required
Please confirm this plan. The SQL fix handles the core backend math, and the UI fixes resolve the visual display and crashes.
