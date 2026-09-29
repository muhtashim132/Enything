# 🍏 Enything iOS Release Notes — Version 1.0.6 (Build 17)

**Release Date:** September 30, 2026  
**Target Launch:** October 2, 2026 (T-2 Days)  
**Bundle Identifier:** `com.muhtaashimnazki.enything`  
**Minimum iOS Target:** iOS 14.0+  
**Target Architecture:** `arm64`  

---

## 📱 App Store Connect: "What's New in This Version" (Paste-Ready)

```text
Welcome to Enything 1.0.6! We've refined and hardened every aspect of your shopping, delivery, and merchant experience ahead of our public launch:

• 100% Prepaid Model: Enjoy zero-friction online payments via UPI, Google Pay, PhonePe, and Cards with complete security powered by Razorpay. Zero cash collection hassle at your doorstep.
• Smart Multi-Stop GPS Routing: Advanced nearest-neighbor route optimization for riders delivering from multiple shops and to stacked customer stops.
• Live Merchant Arrival Alerts: Store owners get real-time rider arrival indicators and preparation countdowns.
• Fortress-Grade Checkout Reliability: Enhanced stock validation, empty-cart race condition protections, dynamic store availability checks, and accurate GST invoice calculations.
• Lightning Fast & Battery Efficient: Optimized realtime GPS streams and butter-smooth iOS navigation animations.

Thank you for choosing Enything — Everything. Everywhere. Instantly.
```

---

## 🛠️ Detailed Technical Changelog for Version 1.0.6 (Build 17)

### 1. Checkout & Customer Experience
- **Pre-Flight Integrity Guards:** Added strict client-side validation against empty carts, missing delivery coordinates, and minimum payable order thresholds (₹1.00 gateway compliance).
- **Coupon Usage Fairness:** Excluded orders terminated due to shop declines, rider shortage, or verification failures from consuming customer per-user coupon limits.
- **Dynamic Geolocation Resolution:** Replaced static coordinate fallbacks with dynamic store/drop-off centroids, preventing camera jumping to Null Island during momentary GPS packet loss.
- **Stacked Delivery Customer Reassurance:** Added transparent multi-order status indicators assuring customers when their assigned rider is completing a prioritized en-route delivery.

### 2. Delivery Partner & Multi-Shop Route Fortress
- **Capacity Ceiling UI Lockout:** Proactively capped active rider groups at 3 concurrent orders across both the dashboard and the interactive route preview map.
- **Multi-Shop Sibling Drop Dispatch:** When a rider drops a cart group order, all affected sibling merchants receive immediate cancellation notices without stranded kitchen states.
- **Safe Out-For-Delivery Transitions:** Constrained batch status advancements strictly to orders verified in `picked_up` state, preventing state machine transition crashes.
- **Unified Shop Stop Clustering:** Clustered co-located merchant pickups into a unified waypoint to eliminate redundant map pins and duplicate routing calculations.
- **Precedence-Constrained Greedy TSP:** Sequenced customer drop-offs via nearest-neighbor distance algorithm after all store pickups are complete.

### 3. Merchant & Kitchen Workflow
- **Live Rider Arrival Badging:** Prominently highlights rider arrival with amber/red urgency alerts if kitchen preparation approaches the scheduled dispatch deadline.
- **Terminal Status Preservation:** Ensured all non-active orders (`delivered`, `cancelled`, `seller_rejected`, `disputed`, `timed_out`) remain fully visible in the Done tab for complete bookkeeping.
- **Soft-Delete Query Fortification:** Sealed product lookup queries across mobile and web interfaces to strictly enforce `is_deleted = false`.

### 4. Admin & Team Security (RBAC)
- **Super Admin Self-Action Guards:** Added client-side and database-level protections preventing accidental self-deletion or self-suspension of administrator accounts.
- **Session Revocation Sync:** Ensured that revoking team access immediately deletes active admin sessions and revokes staff privileges across all client endpoints.

---

## 📦 Build & Release Checklist

- [x] **`pubspec.yaml`**: Version set to `1.0.6+17`
- [x] **`ios/Flutter/Generated.xcconfig`**: Regenerated with `FLUTTER_BUILD_NAME=1.0.6` and `FLUTTER_BUILD_NUMBER=17`
- [x] **`lib/config/app_version.dart`**: Created centralized version metadata source
- [x] **In-App Display**: Updated `AboutEnythingPage` and `ProfileSettingsPage` with dynamic version strings and "What's New in v1.0.6" bottom sheet
- [x] **Static Analysis**: `flutter analyze lib/` passing with 0 errors and 0 warnings
- [x] **Unit & Integration Test Matrix**: 70/70 edge-case tests passing cleanly
