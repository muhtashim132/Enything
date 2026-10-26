# 100x Forensic Edge-Case Audit & Remediation (Live Activities & Dynamic Island Tracking Fortress)

All AI models and developers working on this project MUST adhere to the architecture, edge cases, and remediation protocols for iOS Live Activities, Dynamic Island, and Android Ongoing Notifications:

1. **Pixel-Perfect Swiggy Visual Parity**:
   - Preparing: *"Your order is being prepared"* with orange bold ETA (`Arriving in X mins`) and ~35% progress bar.
   - Confirmed & Rider Assigned: *"Rider is on the way to pick up"* with ~40% progress bar.
   - Picked Up: *"Order picked up · On the way to you"* with ~75% progress bar.
   - Out For Delivery: *"Almost there! Rider is arriving 🛵"* with ~90% progress bar.
   - Multi-Shop Sub-Order Pickups: *"🛍️ X of Y stores collected · Next stop"* with ~65% progress bar.
2. **Tri-State Active Lifecycle**:
   - **Terminated/Closed**: Native iOS ActivityKit widget (`OrderLiveActivityWidget`) and Android ongoing notification (`NotificationService.showOrderProgressNotification`) persist on the Lock Screen.
   - **Backgrounded/Minimized**: Realtime state synchronization via APNs, FCM, and background handlers.
   - **Foregrounded/Active**: `InAppLiveActivityPill` floats at the top of customer pages (`HomePage`, `FavoritesPage`, `OrderHistoryPage`, etc.) and automatically hides when `TrackOrderPage` is opened.
3. **100% Prepaid Model (Zero COD Doorstep Collection)**:
   - Live activities and widgets never display or request cash collection. Financial stop info strictly renders `💳 Prepaid · ₹0 To Collect`.
4. **Clean Terminal Dismissal**:
   - When an order reaches a terminal state (`delivered`, `cancelled`, `seller_rejected`), the widget briefly presents the terminal status and calls `activity.end(nil, dismissalPolicy: .immediate)`. Android notifications are cancelled immediately via `NotificationService.cancelOrderProgressNotification()`.
5. **Route Awareness & Suppression**:
   - `LiveActivityService.isTrackOrderPageOpenNotifier` tracks whether the user is on `TrackOrderPage`. When open, the in-app floating pill is suppressed to prevent UI obstruction.
6. **Native Countdown Without Battery Drain**:
   - iOS widgets utilize `Text(timerInterval: ..., countsDown: true)` for client-side animated minute/second decrementing at 0% battery overhead.
7. **Delivery OTP on Lock Screen & Dynamic Island**:
   - During `out_for_delivery`, `order.deliveryOtp` is rendered directly on the iOS Lock Screen Live Activity card, in the Dynamic Island Expanded bottom view (`[ 🔑 OTP: XXXX ]`), and in the Android Ongoing Notification body and summary, allowing customers to provide the handover OTP without unlocking their device.
8. **Geographic Sanity & India Bounding Box**:
   - Coordinates from rider GPS must pass `LiveActivityService.isValidCoordinate` (rejecting null, NaN, `(0.0, 0.0)`, and coordinates outside India bounds: 6.0°N–38.0°N, 68.0°E–98.0°E). Corrupted or uninitialized coordinates must never trigger 10,000-minute ETA calculation bugs; fallback to `order.estimatedDistanceKm`.
9. **ETA Anti-Flapping / Smoothing Damper**:
   - When a rider stops at traffic signals, speed drops to 0; `_lastSmoothedEtaMinutes` dampens momentary upward spikes to at most +1 minute unless rerouted by > 1.5 km, preventing erratic ETA flapping on lock screens.
10. **Deterministic Per-Order Notification IDs**:
    - In `NotificationService`, notification IDs are calculated deterministically as `(orderId.hashCode.abs() % 100000) + 10000` to prevent concurrent multi-orders from overwriting each other's ongoing progress cards.
11. **Background FCM Handler Sync for Terminated State**:
    - In `_fcmBackgroundHandler` (`lib/main.dart`), customer order updates (`confirmed`, `preparing`, `ready_for_pickup`, `picked_up`, `out_for_delivery`) update the Android Ongoing Progress Notification on the Lock Screen even when the Flutter app is dead, and purge notifications on `delivered` or `cancelled`.
12. **Cold-Boot & Lifecycle State Restoration**:
    - On app launch or resume, `CustomerMainPage._checkActiveInFlightOrders` checks active in-flight orders and re-attaches the Live Activity and floating pill, ending any zombie activities if the order was delivered while the app was closed.
