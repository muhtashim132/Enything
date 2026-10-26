# 🍏 Enything iOS Release Notes — Version 1.0.7 (Build 18)

**Release Date:** October 27, 2026  
**Bundle Identifier:** `com.muhtaashimnazki.enything`  
**Version:** `1.0.7`  
**Build Number:** `18`  
**Minimum iOS Target:** iOS 14.0+  
**Live Activity Minimum:** iOS 16.1+  
**Target Architecture:** `arm64`  
**Developer Team ID:** `548PL673KC`  

---

## 📱 App Store Connect: "What's New in This Version" (Paste-Ready)

```text
Welcome to Enything 1.0.7! This update introduces exciting new capabilities, live tracking widgets, and performance enhancements:

• Live Activities & Dynamic Island: Glance at live order progress, merchant packing status, and rider arrival right from your Lock Screen and Dynamic Island in real time.
• Supermart & Multi-Department Shopping: Shop seamlessly across groceries, cosmetics, fresh produce, and gadgets with clear aisle pricing and itemized settlement.
• One-Tap Dietary Filters: Easily discover Pure Veg and Non-Veg restaurants, bakeries, and grocery essentials with isolated dietary tags.
• Closed Store Discovery & Hours: View scheduled opening times and browse complete catalogs from local merchants even outside operating hours.
• Modernized Ergonomic Navigation: Adaptive bottom navigation bar, fluid iOS transitions, and reduced battery consumption during live GPS tracking.
• 100% Prepaid Model: Zero doorstep cash hassle with secure online payments powered by Razorpay.

Thank you for choosing Enything — Everything. Everywhere. Instantly.
```

---

## 🛠️ Detailed Technical Changelog for Version 1.0.7 (Build 18)

### 1. iOS Live Activities & Dynamic Island Integration
- **WidgetKit Extension**: Implemented `EnythingLiveActivity` with ActivityKit framework support (`Activity<OrderLiveActivityAttributes>`).
- **Dynamic Island Presentations**:
  - **Compact Leading**: Animated delivery scooter icon with real-time state badge.
  - **Compact Trailing**: Elapsed / ETA countdown timer (`Text(timerInterval: ...)`).
  - **Minimal**: High-contrast animated scooter indicator for stacked system activities.
  - **Expanded Region**: Multi-stop progress bar showing Order Placed ➔ Shop Preparing ➔ Out for Delivery ➔ Delivered with store name, item summary, and prepaid verification chip.
- **In-App Mirroring**: Created `InAppLiveActivityPill` floating pill for seamless in-app order monitoring.

### 2. Supermart & Multi-Department Store Catalog Architecture
- **Multi-Department Sizing**: Omnibus stores (*Supermarkets*, *Hypermarts*, *Department Stores*) carry diverse aisles without being forced into a single flat commission rate.
- **Itemized Settlement**: Groceries apply 6%, cosmetics 10%, electronics 10%, and fresh produce 5% at checkout time.
- **Transparent Sign-Up Deductibles**: Complete profile and sign-up cards present clear dynamic tier ranges (`7.96% – 12.96%`) and aisle quick-pills.

### 3. Dietary Preferences & Search Isolation
- **Pure Veg Filtering**: Customer search and category listings allow instant toggling between Pure Veg and All Items.
- **Dietary Guard Fortress**: Category-isolated filters prevent vegetarian flags from erroneously hiding non-food categories (fashion, electronics, pharmacy).

### 4. Merchant Operating Hours & Closed Store Discoverability
- **Scheduled Opening Times**: Customer app renders clear opening hour indicators (e.g. *"Opens at 09:00 AM"*) for closed stores.
- **Catalog Browsing**: Full product catalogs remain discoverable to encourage cart pre-filling and planned ordering.

### 5. Platform Hardening & iOS Ergonomics
- **Adaptive Layout**: Device-responsive bottom navigation bar adapts seamlessly across home indicators on iPhone 14/15/16 Pro, mini, Plus, and Max models.
- **Soft Deletes Discipline**: Strict enforcement of `is_deleted = false` across all product discovery queries.
- **100% Prepaid Model Invariant**: Absolute enforcement of digital prepaid payments (UPI, Cards, NetBanking); zero COD cash collection.
