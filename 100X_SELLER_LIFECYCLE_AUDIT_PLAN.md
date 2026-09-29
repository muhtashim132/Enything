# 100x Forensic Edge-Case Audit & Remediation Plan: Seller Multi-Rider & Cross-Customer Lifecycle

## Executive Summary

Following the successful hardening and verification of the Rider Lifecycle (26/26 tests passing, 0 lint errors), a line-by-line 100x forensic audit was conducted across the entire **Seller Multi-Rider & Cross-Customer Lifecycle**—inspecting seller state machines, wait-time penalty calculations, Realtime channels, push notification pipelines, multi-shop dependency gates, and live tracking map synchronizations.

This deep dive uncovered **8 critical edge cases** that cause seller blindspots, silent financial penalties, frozen ghost GPS markers on seller maps, terminal order disappearances, and confusing duplicate payment prompts to customers.

> [!IMPORTANT]
> **Strict Non-Destructive / Additive Policy**:
> All backend fixes will reside in a new additive migration (`supabase/migrations/20290000000131_100x_seller_multirider_and_wait_dispute_fortress.sql`).
> No existing tables or schemas will be altered.
> Soft deletes rule (`.eq('is_deleted', false)` on `products`) and immediate test cleanup will be strictly enforced.

---

## 1. Forensic Audit Matrix: 8 Uncovered Edge Cases

| # | Edge Case Category | File & Location | Root Cause | Real-World Impact | Remediation |
|---|--------------------|-----------------|------------|-------------------|-------------|
| **1** | **Rider Arrival Blindspot on Seller Cards & Dashboard** | [`lib/pages/seller/seller_orders_page.dart:1520`](file:///Users/muhtaashimnazki/Downloads/Enything/lib/pages/seller/seller_orders_page.dart#L1520) & [`dashboard_page.dart:270`](file:///Users/muhtaashimnazki/Downloads/Enything/lib/pages/seller/dashboard_page.dart#L270) | `set_arrived_at_shop` sets `arrived_at_shop_time` in DB, but the seller UI never displays rider arrival status or elapsed waiting time. | In a rush with multiple riders, seller doesn't know which rider is waiting outside. The wait-time penalty timer runs silently, deducting money from seller payout without warning! | Add prominent arrival chip: `"📍 Rider Arrived (Xm ago)"` on active order cards with dynamic amber/red alert when approaching prep deadline. |
| **2** | **Terminal Status Black Hole in Seller "Done" Orders Tab** | [`lib/pages/seller/seller_orders_page.dart:938-950`](file:///Users/muhtaashimnazki/Downloads/Enything/lib/pages/seller/seller_orders_page.dart#L938-L950) | `_doneOrders()` only checks `delivered, cancelled, seller_rejected, partner_rejected, verification_failed, pending_verification`. | Orders terminated with `shop_dispute_cancel, timeout, failed, returned, refunded, no_rider` vanish from the UI! Seller cannot see dispute outcomes or cancelled order history. | Expand `_doneOrders()` to include all terminal statuses (`shop_dispute_cancel, timeout, failed, returned, refunded, no_rider, payment_failed`). |
| **3** | **Dropped/Reassigned Rider Ghost GPS on Seller Tracking Map** | [`lib/pages/seller/seller_order_map_page.dart:143-168`](file:///Users/muhtaashimnazki/Downloads/Enything/lib/pages/seller/seller_order_map_page.dart#L143-L168) | `_subscribeToRider` checks `if (lat != null && lng != null && lat != 0.0)`. If rider drops, `delivery_partner_id` and coords become `null`. The code ignores nulls. | Dropped rider's last known marker stays frozen on the seller's map. Seller thinks rider is still coming to pick up, unaware the rider dropped 15 mins ago! | In `_subscribeToRider`, if `delivery_partner_id == null`, clear `_riderLatLngNotifier.value = null;`, clear `_pickupRoute = [];`, and display `"Searching for new rider... 🛵"`. |
| **4** | **Multi-Shop Sibling Shop Notification Blackout on Rider Drop** | [`lib/pages/delivery/dashboard_page.dart:1201-1221`](file:///Users/muhtaashimnazki/Downloads/Enything/lib/pages/delivery/dashboard_page.dart#L1201-L1221) | Backend atomically drops all sibling sub-orders in `cart_group_id`, but Flutter client only pushes notification to `order.shopId` (the single order clicked). | In multi-shop orders (Shop A + Shop B), if rider drops, Shop A gets notified but Shop B gets ZERO notification! Shop B packs food and waits for a nonexistent rider. | Push `"🛵 Rider Dropped the Order"` to all distinct shops in the cart group. |
| **5** | **Erroneous Payment Prompt to Customer on Partial Group Acceptance for Paid Orders** | [`lib/pages/seller/seller_orders_page.dart:298-336`](file:///Users/muhtaashimnazki/Downloads/Enything/lib/pages/seller/seller_orders_page.dart#L298-L336) | When seller accepts and `allGroupAccepted` is true, it unconditionally sends `"✅ Shop & Rider Ready! Pay Now 💳"` without checking if customer already paid. | On reassigned orders where customer already paid, customer receives a panic-inducing push: `"Pay Now within 10 minutes"`. | Check `order.paymentStatus != 'captured'` before sending payment push; if already paid, send `"🏪 Shop Confirmed & Packing!"`. |
| **6** | **Cryptic State Machine Exception on Customer Cancellation During Food Prep** | [`lib/pages/seller/seller_orders_page.dart:796-857`](file:///Users/muhtaashimnazki/Downloads/Enything/lib/pages/seller/seller_orders_page.dart#L796-L857) | Catch block prints raw Postgres error: `"Cannot mark ready_for_pickup from state: cancelled"`. | Kitchen staff gets confused by technical database message, assumes a software bug, and finishes packing food for an order already cancelled by the customer. | Catch `Cannot mark ready_for_pickup from state: cancelled` and show user-friendly alert: `"⚠️ Order was cancelled by customer. Do not pack."` and trigger `_loadOrders()`. |
| **7** | **Automated Wait-Time Penalty Deducted on Disputed / False Arrivals** | [`supabase/migrations/20271229000000_100x_admin_cross_role_null_bypass_fix.sql:259`](file:///Users/muhtaashimnazki/Downloads/Enything/supabase/migrations/20271229000000_100x_admin_cross_role_null_bypass_fix.sql#L259) | `update_order_status` computes `wait_time_penalty` if `v_arrived_at_shop_time IS NOT NULL`, without verifying `wait_time_disputed != true`. | If an arrival was false, fraudulent, or disputed (`wait_time_disputed = true`), the seller is still unfairly fined and payout is deducted! | In `update_order_status`, suppress penalty calculation if `COALESCE(v_wait_time_disputed, false) = true`. |
| **8** | **Cross-Customer Multi-Shop Order Identification Gap on Seller Cards** | [`lib/pages/seller/seller_orders_page.dart:1400-1550`](file:///Users/muhtaashimnazki/Downloads/Enything/lib/pages/seller/seller_orders_page.dart#L1400-L1550) | Seller cards do not indicate whether an order belongs to a multi-shop cart group. | Seller cannot tell if this order is holding up a cross-shop delivery or if the rider will be picking up items for multiple shops. | Add a `"🛒 Multi-Shop Order"` chip with sibling shop count indicator on order cards. |

---

## 2. Technical Architecture & State Machine Flow

```mermaid
flowchart TD
    subgraph MultiRider["1. Multi-Rider Interaction & Arrival Tracking"]
        A[Rider Arrives at Shop & Taps 'Arrived'] --> B[set_arrived_at_shop RPC: arrived_at_shop_time = NOW]
        B --> C[Edge Case S-EC-01 Fix: Seller UI Displays '📍 Rider Arrived (Xm ago)']
        C --> D{Is Wait Time Exceeding Prep Time?}
        D -- Yes --> E[Visual Amber Alert on Seller Card]
        D -- No --> F[Normal Pickup Standby]
        G[Rider Drops Order] --> H[reject_order_rider: resets cart group]
        H --> I[Edge Case S-EC-03 Fix: Clear Ghost GPS on Seller Map]
        H --> J[Edge Case S-EC-04 Fix: Notify ALL Sibling Shops in Cart Group]
    end

    subgraph Preparation["2. Kitchen Preparation & Dispatch Gate"]
        K[Seller Taps 'Start Preparing'] --> L[Status -> 'preparing']
        L --> M{Customer Cancels While Cooking?}
        M -- Yes --> N[Edge Case S-EC-06 Fix: Friendly SnackBar 'Order Cancelled. Do Not Pack']
        M -- No --> O[Seller Taps 'Mark Ready for Pickup']
        O --> P{Was Wait Time Disputed?}
        P -- Yes --> Q[Edge Case S-EC-07 Fix: Suppress Penalty Calculation]
        P -- No --> R[Compute Standard Penalty if Exceeded Prep Time]
        Q --> S[Status -> 'ready_for_pickup']
        R --> S
    end

    subgraph CrossCustomer["3. Cross-Customer Multi-Shop Coordination"]
        T[Customer Cart with Shop A + Shop B] --> U[Shop A Accepts Order]
        U --> V{Is Sibling Order Already Paid or Reassigned?}
        V -- Yes --> W[Edge Case S-EC-05 Fix: Send 'Shop Confirmed' - Suppress 'Pay Now']
        V -- No --> X[Send 'Pay Now 💳' Push to Customer]
        Y[Order Terminal State Reached] --> Z[Edge Case S-EC-02 Fix: Show in 'Done' Tab for All Terminal Statuses]
        AA[Multi-Shop Order Loaded] --> AB[Edge Case S-EC-08 Fix: Display 'Multi-Shop Order' Badge]
    end
```

---

## 3. Step-by-Step Remediation Plan

### Step 1: Rider Arrival Indicator & Multi-Shop Badge on Seller Order Cards
**File**: [`lib/pages/seller/seller_orders_page.dart`](file:///Users/muhtaashimnazki/Downloads/Enything/lib/pages/seller/seller_orders_page.dart)
1. **Edge Case S-EC-01 (Rider Arrival Chip)**:
   - In active order card header, if `order.arrivedAtShopTime != null`:
     - Calculate elapsed waiting minutes: `DateTime.now().difference(order.arrivedAtShopTime!).inMinutes`.
     - Display a prominent chip: `"📍 Rider Arrived (${mins}m ago)"`.
     - If `mins > 10`: highlight in amber/red alert style.
2. **Edge Case S-EC-08 (Multi-Shop Identification)**:
   - If `order.cartGroupId != null`:
     - Display `"🛒 Multi-Shop Order"` chip next to the order ID.

### Step 2: Terminal Status Expansion in Seller "Done" Orders Tab
**File**: [`lib/pages/seller/seller_orders_page.dart`](file:///Users/muhtaashimnazki/Downloads/Enything/lib/pages/seller/seller_orders_page.dart)
- In `_doneOrders()` (lines 938-950), expand the status whitelist:
  ```dart
  List<OrderModel> _doneOrders() => _orders
      .where((o) =>
          [
            'delivered',
            'cancelled',
            'seller_rejected',
            'partner_rejected',
            'verification_failed',
            'pending_verification',
            'shop_dispute_cancel',
            'timeout',
            'failed',
            'returned',
            'refunded',
            'no_rider',
            'payment_failed',
          ].contains(o.status) ||
          ((o.status == 'awaiting_acceptance' || o.status == 'pending') &&
              o.isExpired))
      .toList();
  ```

### Step 3: Reassigned / Dropped Rider Ghost GPS Cleanup on Seller Tracking Map
**File**: [`lib/pages/seller/seller_order_map_page.dart`](file:///Users/muhtaashimnazki/Downloads/Enything/lib/pages/seller/seller_order_map_page.dart)
- In `_subscribeToRider` callback:
  ```dart
  final partnerId = r['delivery_partner_id'] as String?;
  final lat = (r['rider_lat'] as num?)?.toDouble();
  final lng = (r['rider_lng'] as num?)?.toDouble();

  if (partnerId == null || lat == null || lng == null || lat == 0.0) {
    // Rider dropped or not yet assigned
    _riderLatLngNotifier.value = null;
    _pickupRoute = [];
    if (mounted) setState(() {});
  } else {
    // Active assigned rider GPS
    final newPos = LatLng(lat, lng);
    _riderLatLngNotifier.value = newPos;
    ...
  }
  ```

### Step 4: Multi-Shop Dropped Rider Notification to All Sibling Shops
**File**: [`lib/pages/delivery/dashboard_page.dart`](file:///Users/muhtaashimnazki/Downloads/Enything/lib/pages/delivery/dashboard_page.dart)
- In `_updateStatus` for `'reassign'` / `'reassign_disputed'`:
  - Fetch all distinct `shop_id`s for the affected cart group (not just `order.shopId`).
  - Send the `"🛵 Rider Dropped the Order"` push to every affected seller.

### Step 5: Paid Reassigned Order Push Suppression in Seller Accept
**File**: [`lib/pages/seller/seller_orders_page.dart`](file:///Users/muhtaashimnazki/Downloads/Enything/lib/pages/seller/seller_orders_page.dart)
- In `_sellerAccept`:
  - Query `select('status, payment_status')` for the group.
  - If `payment_status == 'captured'`, suppress `"Pay Now 💳"` push and send `"🏪 Shop Confirmed & Packing!"`.

### Step 6: User-Friendly Cancellation Handling During Preparation
**File**: [`lib/pages/seller/seller_orders_page.dart`](file:///Users/muhtaashimnazki/Downloads/Enything/lib/pages/seller/seller_orders_page.dart)
- In `_updateOrderStatus`:
  ```dart
  } on PostgrestException catch (pe) {
    if (pe.message.contains('Cannot mark ready_for_pickup from state: cancelled') ||
        pe.message.contains('from state: cancelled')) {
      _showSnack('⚠️ Customer cancelled this order. Do not pack.', isError: true);
      _loadOrders();
    } else {
      _showSnack(pe.message, isError: true);
    }
  }
  ```

### Step 7: Backend Wait-Time Penalty Dispute Immunity Migration
**File**: `supabase/migrations/20290000000131_100x_seller_multirider_and_wait_dispute_fortress.sql`
- Update `update_order_status` RPC:
  - Select `wait_time_disputed` in line 186.
  - Guard penalty calculation:
    ```sql
    IF v_arrived_at_shop_time IS NOT NULL AND COALESCE(v_wait_time_disputed, false) = false THEN
      -- Calculate wait time penalty
      ...
    ELSE
      v_calculated_wait_penalty := 0;
    END IF;
    ```

### Step 8: Automated Test Matrix Expansion
**File**: [`test/test_100x_dashboards_exhaustive_edge_cases.dart`](file:///Users/muhtaashimnazki/Downloads/Enything/test/test_100x_dashboards_exhaustive_edge_cases.dart)
Add unit tests for all seller edge cases:
- `S-EC-08`: `_doneOrders()` properly includes `shop_dispute_cancel, timeout, failed, returned, refunded, no_rider`.
- `S-EC-09`: Rider arrival timestamp calculates elapsed waiting minutes for card alert chip.
- `S-EC-10`: Reassigned/dropped rider clears GPS marker on seller tracking map.
- `S-EC-11`: Dropped rider in multi-shop cart group identifies all sibling shops for notification dispatch.
- `S-EC-12`: Seller accept on reassigned paid order suppresses "Pay Now" push.
- `S-EC-13`: `update_order_status` suppresses penalty calculation when `wait_time_disputed = true`.
- `S-EC-14`: Customer cancellation during preparation shows clear kitchen warning and halts packaging.

---

## 4. Verification Plan

### Automated Execution
```bash
flutter analyze lib/pages/seller/ lib/pages/delivery/ lib/models/ test/
flutter test test/test_100x_dashboards_exhaustive_edge_cases.dart
```

### Success Criteria
- 100% of existing tests (26/26) pass with 0 regressions.
- All 7 new seller tests (`S-EC-08` through `S-EC-14`) pass.
- 0 lint or static analysis warnings across all files.
- Zero test leftover entities in database.
