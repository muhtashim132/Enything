# 100x Forensic Rules: Rider Multi-Customer & Cross-Cart Lifecycle

All AI models and developers working on this project MUST adhere to the architecture, edge cases, and remediation protocols specified in `100X_RIDER_CROSS_CUSTOMER_EDGE_CASES_PLAN.md`:

1. **COD vs Prepaid Financial Isolation**: In `OrderGroup` (`lib/models/order_group.dart`), provide `isCod`, `isPrepaid`, and `codAmountToCollect`. `codAmountToCollect` MUST dynamically sum `grandTotal` strictly across `activeOrders.where((o) => o.paymentStatus != 'captured' && o.paymentMethod == 'cod')` so cancelled or disputed sub-orders are never billed.
2. **Delivery Card Payment Banner**: In `lib/pages/delivery/dashboard_page.dart`, every active order card MUST display a prominent payment badge: `[ 💵 COLLECT ₹X CASH (COD) ]` or `[ 💳 PREPAID · ₹0 TO COLLECT ]`, plus total bill and rider earnings.
3. **Cash Handover Confirmation Guard**: In `lib/pages/delivery/dashboard_page.dart`, when tapping "Mark All Delivered" on an order where `group.isCod && group.codAmountToCollect > 0`, intercept with a confirmation dialog: `"💵 Confirm Cash Collection: Did you collect ₹X in cash?"` to prevent unpaid deliveries.
4. **Capacity Ceiling UI Lockout**: In `lib/pages/delivery/dashboard_page.dart`, when `_myGroups.length >= 3` (backend max limit), the Accept button on Available Orders MUST be disabled with label `"Max 3 Orders Active"`, preventing unnecessary RPC failures.
5. **COD Push Notification Sanitization**: In `_acceptOrderGroup` and `_acceptOrder`, if `group.isCod`, suppress `"Ready for Payment! 💳"` and send `"Order Confirmed! 🛵"`. Do NOT send online payment countdown pushes to COD customers or "Waiting for payment" to sellers.
6. **Master Route Financial Stop Info**: In `OrderRouteMapPage` (`lib/pages/delivery/order_route_map_page.dart`), the customer drop-off bottom sheet card MUST display the COD collection amount or Prepaid chip.
7. **Customer Map Stacked Delivery Reassurance**: In customer tracking views, when a rider is assigned to multiple orders, reassure the customer that the rider is completing an earlier delivery on schedule to prevent panic or false disputes.
