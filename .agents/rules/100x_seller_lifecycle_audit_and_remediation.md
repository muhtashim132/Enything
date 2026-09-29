# 100x Forensic Edge-Case Audit & Remediation: Seller Multi-Rider & Cross-Customer Lifecycle

## User Profile
- **User / Lead Developer**: Muhtashim Kamran Nazki

## Mandatory Architecture & Remediation Protocols (Seller Multi-Rider & Cross-Customer)
All AI models and developers working on this project MUST adhere to the architecture, edge cases, and remediation protocols specified in [100X_SELLER_LIFECYCLE_AUDIT_PLAN.md](file:///Users/muhtaashimnazki/Downloads/Enything/100X_SELLER_LIFECYCLE_AUDIT_PLAN.md):

1. **Rider Arrival Display Guard**: In `lib/pages/seller/seller_orders_page.dart`, whenever `order.arrivedAtShopTime != null`, order cards MUST display a prominent arrival badge (`"📍 Rider Arrived (Xm ago)"`) with amber/red alert highlighting if waiting time approaches the prep time deadline.
2. **Terminal Status Preservation in Done Tab**: In `lib/pages/seller/seller_orders_page.dart`, `_doneOrders()` MUST include all terminal statuses (`delivered, cancelled, seller_rejected, partner_rejected, verification_failed, pending_verification, shop_dispute_cancel, timeout, failed, returned, refunded, no_rider, payment_failed`). Disputed, timed-out, or cancelled orders MUST NEVER be dropped from the UI.
3. **Dropped/Reassigned Rider Map Reset**: In `lib/pages/seller/seller_order_map_page.dart`, `_subscribeToRider` must check if `delivery_partner_id` or coordinates are null. If the rider drops, immediately set `_riderLatLngNotifier.value = null;`, clear `_pickupRoute = [];`, and display `"Searching for new rider... 🛵"`. Never leave a dropped rider's GPS frozen on screen.
4. **Multi-Shop Sibling Drop Dispatch**: In `lib/pages/delivery/dashboard_page.dart`, when dropping a cart group order, fetch all distinct shops involved in that cart group and dispatch the `"🛵 Rider Dropped the Order"` notification to every affected seller.
5. **Reassigned Paid Order Push Suppression**: In `lib/pages/seller/seller_orders_page.dart`, before sending `"Pay Now"` push on seller accept, verify `order.paymentStatus != 'captured'`. If already paid, suppress payment push and send `"🏪 Shop Confirmed & Packing!"`.
6. **Graceful Preparation Cancellation**: In `lib/pages/seller/seller_orders_page.dart`, catch state machine transition exceptions from cancelled orders during `ready_for_pickup` and display a clear kitchen warning: `"⚠️ Customer cancelled this order. Do not pack."`, then refresh orders.
7. **Disputed Wait-Time Penalty Immunity**: In `update_order_status` RPC (`supabase/migrations/20290000000131_100x_seller_multirider_and_wait_dispute_fortress.sql`), suppress wait-time penalty calculations whenever `COALESCE(wait_time_disputed, false) = true`.
8. **Multi-Shop Order Clarity**: Order cards in `lib/pages/seller/seller_orders_page.dart` must display a `"🛒 Multi-Shop Order"` chip for orders with a non-null `cartGroupId`.
