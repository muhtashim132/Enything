# Enything Project Rules

## User Profile
- **User / Lead Developer**: Muhtashim Kamran Nazki

## Business Model & Payments
- **100% Prepaid Model (Zero COD)**: Enything operates strictly on a 100% prepaid model (online payments via UPI/Razorpay). Cash on Delivery (COD) is NOT available in this system. Riders never collect cash from customers at doorstep. All orders must be paid online before preparation/delivery.

## Database Queries
- **Soft Deletes**: The `products` table uses soft deletes (`is_deleted` boolean flag). Whenever querying the `products` table using Supabase (e.g. `supabase.from('products').select()`), you MUST ALWAYS include `.eq('is_deleted', false)` to ensure deleted products are not fetched.

## Testing Discipline & Zero Test Leftovers
- **Immediate Test Cleanup**: Whenever running tests, integration test scripts, or creating mock records, you MUST ALWAYS immediately delete/purge any test products, test orders, and test shops once testing finishes. Never leave test entities in the live database.

## 100x Forensic Edge-Case Audit & Remediation (Rider Multi-Shop & Cross-Customer Lifecycle)
All AI models and developers working on this project MUST adhere to the architecture, edge cases, and remediation protocols specified in [100X_RIDER_LIFECYCLE_AUDIT_PLAN.md](file:///Users/muhtaashimnazki/Downloads/Enything/100X_RIDER_LIFECYCLE_AUDIT_PLAN.md) and [.agents/rules/100x_rider_lifecycle_audit_and_remediation.md](file:///Users/muhtaashimnazki/Downloads/Enything/.agents/rules/100x_rider_lifecycle_audit_and_remediation.md):

1. **Dead Sub-Order Acceptance Guard**: In `_acceptOrderGroup` (`lib/pages/delivery/dashboard_page.dart`), never assume `group.orders.first` is active. Pass `group.activeOrders.firstWhere((o) => o.status == 'awaiting_acceptance' || o.status == 'pending', orElse: () => group.activeOrders.first)`.
2. **Mark All Out for Delivery Guard**: In `lib/pages/delivery/dashboard_page.dart`, loop strictly over `group.activeOrders.where((o) => o.status == 'picked_up').toList()` to prevent invalid state transition exceptions on cancelled/disputed sub-orders.
3. **Rider Drop Order Whitelist**: `reject_order_rider` RPC must permit dropping orders in `'confirmed'` status (right after payment capture before shop starts preparing) in addition to `'awaiting_acceptance', 'pending', 'preparing', 'ready_for_pickup', 'awaiting_payment'`. All backend additions reside in migration `supabase/migrations/20290000000130_100x_rider_confirmed_drop_and_query_fortress.sql`.
4. **Zombie Group Filtering**: In `lib/pages/delivery/dashboard_page.dart`, `_loadOrders()` must exclude terminal statuses (`delivered, cancelled, seller_rejected, partner_rejected, shop_dispute_cancel, timeout, failed, returned, refunded, verification_failed, no_rider`), and `_myGroups` must filter `.where((g) => g.activeOrders.isNotEmpty)`.
5. **Reassigned Paid Order Push Suppression**: In `_acceptOrder`, select `status, payment_status`. If `payment_status == 'captured'`, suppress payment push ("Ready for Payment") and send `"New Rider Assigned! 🛵"`.
6. **Master Multi-Customer Route & Realtime**: In `lib/pages/delivery/order_route_map_page.dart`, subscribe to all cart groups in `widget.groups`, whitelist active unpicked shops (`confirmed, preparing, ready_for_pickup` - strictly excluding `delivered`), and chain intermediate customer drop-offs as waypoints in external Google Maps navigation.
7. **OrderGroup Terminal Fallback Guard**: In `lib/models/order_group.dart`, if `activeOrders.isEmpty`, getters `allArrived`, `allPickedUp`, and `allOutForDelivery` MUST strictly return `false`.

## 100x Forensic Edge-Case Audit & Remediation (Seller Multi-Rider & Cross-Customer Lifecycle)
All AI models and developers working on this project MUST adhere to the architecture, edge cases, and remediation protocols specified in [100X_SELLER_LIFECYCLE_AUDIT_PLAN.md](file:///Users/muhtaashimnazki/Downloads/Enything/100X_SELLER_LIFECYCLE_AUDIT_PLAN.md) and [.agents/rules/100x_seller_lifecycle_audit_and_remediation.md](file:///Users/muhtaashimnazki/Downloads/Enything/.agents/rules/100x_seller_lifecycle_audit_and_remediation.md):

1. **Rider Arrival Display Guard**: In `lib/pages/seller/seller_orders_page.dart`, whenever `order.arrivedAtShopTime != null`, order cards MUST display a prominent arrival badge (`"📍 Rider Arrived (Xm ago)"`) with amber/red alert highlighting if waiting time approaches the prep time deadline.
2. **Terminal Status Preservation in Done Tab**: In `lib/pages/seller/seller_orders_page.dart`, `_doneOrders()` MUST include all terminal statuses (`delivered, cancelled, seller_rejected, partner_rejected, verification_failed, pending_verification, shop_dispute_cancel, timeout, failed, returned, refunded, no_rider, payment_failed`). Disputed, timed-out, or cancelled orders MUST NEVER be dropped from the UI.
3. **Dropped/Reassigned Rider Map Reset**: In `lib/pages/seller/seller_order_map_page.dart`, `_subscribeToRider` must check if `delivery_partner_id` or coordinates are null. If the rider drops, immediately set `_riderLatLngNotifier.value = null;`, clear `_pickupRoute = [];`, and display `"Searching for new rider... 🛵"`. Never leave a dropped rider's GPS frozen on screen.
4. **Multi-Shop Sibling Drop Dispatch**: In `lib/pages/delivery/dashboard_page.dart`, when dropping a cart group order, fetch all distinct shops involved in that cart group and dispatch the `"🛵 Rider Dropped the Order"` notification to every affected seller.
5. **Reassigned Paid Order Push Suppression**: In `lib/pages/seller/seller_orders_page.dart`, before sending `"Pay Now"` push on seller accept, verify `order.paymentStatus != 'captured'`. If already paid, suppress payment push and send `"🏪 Shop Confirmed & Packing!"`.
6. **Graceful Preparation Cancellation**: In `lib/pages/seller/seller_orders_page.dart`, catch state machine transition exceptions from cancelled orders during `ready_for_pickup` and display a clear kitchen warning: `"⚠️ Customer cancelled this order. Do not pack."`, then refresh orders.
7. **Disputed Wait-Time Penalty Immunity**: In `update_order_status` RPC (`supabase/migrations/20290000000131_100x_seller_multirider_and_wait_dispute_fortress.sql`), suppress wait-time penalty calculations whenever `COALESCE(wait_time_disputed, false) = true`.
8. **Multi-Shop Order Clarity**: Order cards in `lib/pages/seller/seller_orders_page.dart` must display a `"🛒 Multi-Shop Order"` chip for orders with a non-null `cartGroupId`.

## 100x Forensic Edge-Case Audit & Remediation (Rider Multi-Cart & Cross-Customer Map Lifecycle)
All AI models and developers working on this project MUST adhere to the architecture, edge cases, and remediation protocols specified in [100X_RIDER_MULTI_CART_MAP_AUDIT_PLAN.md](file:///Users/muhtaashimnazki/Downloads/Enything/100X_RIDER_MULTI_CART_MAP_AUDIT_PLAN.md) and [.agents/rules/100x_rider_multi_cart_map_fortress.md](file:///Users/muhtaashimnazki/Downloads/Enything/.agents/rules/100x_rider_multi_cart_map_fortress.md):

1. **Shared Shop Co-Location & Single Stop Clustering**: In `OrderRouteMapPage` (`lib/pages/delivery/order_route_map_page.dart`), whenever multiple orders belong to the same physical shop, cluster them into a single `UnifiedShopStop`. Never render duplicate shop markers, duplicate bottom sheet tabs, or duplicate consecutive coordinates to routing APIs.
2. **Precedence-Constrained Greedy TSP Drop-off Reordering**: In `_fetchRoutes`, customer drop-off points MUST NOT be visited in arbitrary array index order. Sequence them using nearest-neighbor greedy TSP starting from the last shop location (or rider GPS if all shops are already picked up), strictly excluding delivered or cancelled groups.
3. **Multi-Customer Stop Tabs & Card Carousel**: The bottom sheet stop selector in `OrderRouteMapPage` MUST generate dedicated tabs for every active customer drop-off (`Drop 1`, `Drop 2`, `Drop 3`). Selecting a customer drop-off tab MUST display that specific customer's address, delivery notes, order items, and one-tap call button.
4. **Realtime Mutation Index Clamping**: In `OrderRouteMapPage`, whenever `_orders` is mutated via Supabase Realtime, `_selectedStopIndex` MUST be strictly clamped to `math.max(0, totalStops - 1)` to prevent `RangeError` crashes.
5. **Cancelled vs Delivered Group Distinction**: In `_isGroupDelivered(OrderGroup g)`, if all active orders are empty due to rejections or cancellations, it MUST return `false`. A cancelled order group must NEVER be displayed with a "Delivered" badge.
6. **External Navigation Waypoint Sanitization & Cap**: In `_openInExternalMap`, waypoints MUST be deduplicated and capped to a maximum of 8 immediate upcoming stops to prevent Google Maps directory URL HTTP 400 Bad Request errors.
7. **Master Route Shop Info Resolution**: In `lib/pages/delivery/dashboard_page.dart`, when launching Master Route for `_myGroups`, populate `shops` using `_shopInfoCache` across all active groups instead of passing `shops: const []`.
8. **Routing Coordinate Sanitization**: In `GeoUtils.fetchMultiStopRoute` (`lib/utils/geo_utils.dart`), consecutive waypoints within 5 meters of each other must be stripped to prevent routing engine failures.

## 100x Forensic Edge-Case Audit & Remediation (Rider Multi-Customer & Cross-Cart Lifecycle)
All AI models and developers working on this project MUST adhere to the architecture, edge cases, and remediation protocols specified in [100X_RIDER_CROSS_CUSTOMER_EDGE_CASES_PLAN.md](file:///Users/muhtaashimnazki/Downloads/Enything/100X_RIDER_CROSS_CUSTOMER_EDGE_CASES_PLAN.md) and [.agents/rules/100x_rider_cross_customer_fortress.md](file:///Users/muhtaashimnazki/Downloads/Enything/.agents/rules/100x_rider_cross_customer_fortress.md):

1. **100% Prepaid Model (Zero COD Doorstep Collection)**: Enything operates strictly on a 100% prepaid model (online payment only via UPI/Razorpay). Cash on Delivery (COD) is NOT available in this system. In `OrderGroup` (`lib/models/order_group.dart`), `isCod` is strictly `false`, `isPrepaid` is strictly `true`, and `codAmountToCollect` is `0.0`. Doorstep cash collection is never requested.
2. **Delivery Card Payment Banner**: In `lib/pages/delivery/dashboard_page.dart`, every active order card MUST display the prepaid payment badge: `[ 💳 PREPAID · ₹0 TO COLLECT ]`, plus total bill and rider earnings.
3. **Zero Cash Collection Prompt on Delivery**: In `lib/pages/delivery/dashboard_page.dart`, completing deliveries never prompts riders for cash collection since all orders are prepaid.
4. **Capacity Ceiling UI Lockout**: In `lib/pages/delivery/dashboard_page.dart`, when `_myGroups.length >= 3` (backend max limit), the Accept button on Available Orders MUST be disabled with label `"Max 3 Orders Active"`, preventing unnecessary RPC failures.
5. **Prepaid Payment Push Notification Sanitization**: In `_acceptOrderGroup` and `_acceptOrder`, dispatch `"Ready for Payment! 💳"` when waiting for customer online payment, or `"New Rider Assigned! 🛵"` when online payment is already captured. Never send COD pushes.
6. **Master Route Financial Stop Info**: In `OrderRouteMapPage` (`lib/pages/delivery/order_route_map_page.dart`), the customer drop-off bottom sheet card displays the `💳 Prepaid (₹0)` chip.
7. **Customer Map Stacked Delivery Reassurance**: In customer tracking views, when a rider is assigned to multiple orders, reassure the customer that the rider is completing an earlier delivery on schedule to prevent panic or false disputes.

## 100x Forensic Edge-Case Audit & Remediation (Multi-Shop & Multi-Cart Lifecycle Deep Fortress)
All AI models and developers working on this project MUST adhere to the architecture, edge cases, and remediation protocols specified in `100x_deep_forensic_edge_case_plan.md`:

1. **Sibling Order Survival on Store Rejection**: In `lib/pages/seller/seller_orders_page.dart`, when a seller rejects an order that belongs to a multi-shop cart group (`cartGroupId != null`), the system must query for surviving active sibling orders before notifying the assigned rider. If active sibling orders remain, the rider MUST NOT receive `"You are free for new deliveries"`; instead, notify `"⚠️ Store Declined Items: A store declined their part of the order. You are still delivering the remaining store(s)."`, preventing premature abandonment of customer orders.
2. **Intermediate Multi-Shop Pickup Notification**: In `lib/pages/delivery/dashboard_page.dart`, when a rider marks an order as `picked_up`, inspect whether there are remaining unpicked shops in that cart group (`remainingUnpicked > 0`). If unpicked stores remain, notify the customer: `"🛍️ Items Picked Up: Rider collected items from $shopName. Heading to the next stop!"` rather than a premature `"Your order is on its way!"`, preventing customer panic when the rider navigates towards another shop instead of their house.
3. **Dead Sub-Order Fallback Notification Sanitization**: In `_acceptOrderGroup` (`lib/pages/delivery/dashboard_page.dart`), payload resolution for customer notifications MUST use `targetOrder` (`group.activeOrders.isNotEmpty ? group.activeOrders.first : group.orders.first`) instead of blindly accessing `group.orders.first`, which could be a rejected/dead order.
4. **Dynamic Geolocation Resolution Guard**: In `CustomerOrderMapPage` (`lib/pages/customer/customer_order_map_page.dart`), never use hardcoded geographic fallback coordinates during realtime GPS updates. Fallback dynamically to `_currentOrder` shop/delivery coordinates to avoid camera snapping across states/cities during temporary GPS packet loss.

