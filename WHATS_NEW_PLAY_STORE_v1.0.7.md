# Google Play Console Release Notes — Version 1.0.7 (Build 18)

## 📱 Google Play Release Summary
- **App Name**: Enything
- **Package Name**: `com.muhtaashimnazki.enything`
- **Version Name**: `1.0.7`
- **Version Code**: `18` (Upgrades from Release 17 / `1.0.6`)
- **Target SDK**: Android 15 (API 35)
- **Min SDK**: API 21 (Android 5.0)
- **Architecture**: Universal (arm64-v8a, armeabi-v7a, x86_64)
- **Bundle Format**: Android App Bundle (`.aab`) with R8 full mode & ProGuard shrinking

---

## 📋 What's New in this Release (Play Store Console Description — Max 500 chars)

```text
• Supermart Multi-Department Aisle Engine: Transparent item-level settlement across grocery, cosmetics, electronics, and fresh produce.
• Smart Closed Store Discovery: View scheduled operating hours, pre-order from favorite local shops, and browse full menus anytime.
• One-Tap Dietary Filters: Instant Pure Veg / Non-Veg food and grocery discovery.
• Modernized Ergonomics: Adaptive bottom navigation bar and ultra-responsive browsing.
• 100% Prepaid Reliability: Fast UPI, cards, and zero doorstep cash hassle.
```

*(Character count: 494 / 500 max characters — paste-ready for Google Play Console)*

---

## 🚀 Key Highlights & New Features in Version 1.0.7 (Build 18)

### 1. 🏬 Supermart & Multi-Department Store Catalog Architecture
- **Aisle-Based Settlement**: Supermarkets, Hypermarts, and Department Stores now display transparent aisle commission schedules (Grocery 6%, Cosmetics 10%, Electronics 10%, Fresh Produce 5%).
- **Itemized Merchant Payout**: When customers purchase items across multiple store departments in a single cart, each product applies its respective department rate upon settlement. Groceries are never charged at the higher retail rate, and non-grocery items are fully supported.
- **Dynamic Platform Configuration**: Sign-up cards and earning modals automatically synchronize with admin-configured platform rates in real time.

### 2. 🕐 Closed Store Discovery & Operating Hours Intelligence
- **Scheduled Opening Times**: Customers can now browse nearby stores even when temporarily closed outside operating hours, viewing the exact scheduled opening time (e.g. *"Opens at 09:00 AM"*).
- **Cart Pre-ordering & Scheduling**: Full menus and catalogs remain discoverable with clear status badges, preventing customer confusion and boosting merchant pre-order volume.

### 3. 🥗 Pure Veg & Dietary Preference Discovery
- **One-Tap Dietary Switching**: Added intuitive Pure Veg and Non-Veg filters for restaurants and grocery aisles.
- **Dietary Isolation Guards**: Dietary preferences strictly filter relevant food and grocery categories without interfering with non-food retail, fashion, electronics, or pharmacy catalogs.
- **Prescription Safeguards**: Prescription medicine upload cards and healthcare ordering remain strictly isolated and protected.

### 4. 📱 Modernized Ergonomic UI & Performance
- **Adaptive Bottom Navigation Bar**: Redesigned navigation bar with enhanced responsive padding, device-safe insets, and fluid active tab animations.
- **Android 15 Edge-to-Edge Immersion**: Fully compliant with Android 15 edge-to-edge window insets, transparent status bars, and modern system navigation bars.
- **R8 Full Mode Optimization**: Compact bytecode, reduced runtime heap footprint, and lightning-fast cold app launches.

### 5. 💳 100% Prepaid Model & Zero COD Invariant
- **Guaranteed Digital Payments**: All orders are 100% prepaid online via UPI, Google Pay, PhonePe, Paytm, and Credit/Debit Cards powered by Razorpay.
- **Zero Doorstep Cash Collection**: Riders never handle or collect cash at customer doorsteps, eliminating cash leakage, disputed change, and driver theft.
- **Transparent Statutory Deductions**: Automated Income Tax TDS (§194-O at 0.10%), GST TCS (§52 at 0.50% on taxable goods / 0.00% exempt on fresh produce), and 2.36% online gateway processing.

---

## 📦 AAB File Verification & Artifact Details
- **File Path**: `build/app/outputs/bundle/release/app-release.aab`
- **Signing Keystore**: `android/upload-keystore.jks`
- **Key Alias**: `upload`
- **Keystore Type**: PKCS12 (2048-bit RSA)
- **Signature Algorithm**: SHA384withRSA
- **SHA-256 Fingerprint**: `77:13:D3:3E:8F:94:B2:00:85:0C:5B:E8:0C:CF:13:F8:36:3B:D6:10:52:E3:2F:8B:93:6E:7F:D1:C8:BD:9A:43`
