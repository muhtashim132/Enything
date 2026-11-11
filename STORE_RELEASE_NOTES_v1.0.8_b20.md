# ENYTHING STORE RELEASE SPECIFICATION & SUBMISSION DOSSIER
**Release Version**: `1.0.8`  
**Internal Build Number**: `20`  
**Target Release Date**: November 12, 2026  
**Platform Scope**: Google Play Console (Android) & Apple App Store Connect (iOS)  
**Security & Model**: 100% Prepaid Model (Zero Cash-on-Delivery) · Statutory GST Compliance

---

## 1. GOOGLE PLAY CONSOLE SUBMISSION DETAILS

### 1.1 Binary Artifact Details
- **Artifact Type**: Android App Bundle (`.aab`)
- **Generated File Location**: `build/app/outputs/bundle/release/app-release.aab`
- **Application ID / Package Name**: `com.muhtaashimnazki.enything`
- **Version Name**: `1.0.8`
- **Version Code**: `20`
- **Min SDK**: `21` (Android 5.0 Lollipop)
- **Target SDK**: `34` / `35` (Android 14 / 15 Compliant)
- **Code Shrinking & Obfuscation**: Enabled (`isMinifyEnabled = true`, `isShrinkResources = true`, R8 ProGuard)
- **Signing Scheme**: v2 + v3 Keystore Signed (`upload-keystore.jks`, alias `upload`)

---

### 1.2 Play Store Track & Release Name
- **Target Track**: Production (or Open Testing / Closed Internal Track first)
- **Release Name**: `1.0.8 (20) - 100x Forensic Stability & Statutory GST Engine`

### 1.3 Release Notes / What's New (`en-IN` & `en-US`)

```text
What's New in Version 1.0.8:

🛡️ 100x Forensic Reliability & Performance
• Fully fortified order lifecycle state machine with atomic concurrency locks.
• Zero-leak memory management for all map controllers and dynamic bottom sheets.

🧾 Statutory GST & Transparent Tax Breakdown
• Complete statutory compliance under Section 9(5) for food and restaurant orders.
• Itemized tax slab transparency and guaranteed ₹20 delivery fee floor.

📍 Intelligent Multi-Merchant Routing & Co-Location
• Smart clustering for multi-order pickups from shared shop locations.
• Sub-5m route caching and precision compass tracking with zero GPS drift.

💳 100% Prepaid Online Security
• Seamless, secure prepaid online checkout via UPI, cards, and net banking with zero doorstep cash collection risk.

🔍 Pharmaceutical Active Salt Search
• Instant search discovery for medicines by active salt composition and generic formulation.
```

---

### 1.4 Play Store Metadata & Listing
- **App Name**: Enything: Hyperlocal Delivery
- **Short Description** (Max 80 chars):
  `Food, groceries, medicines & essentials delivered to your doorstep in minutes.`
- **Full Description**:
```text
Enything brings your entire neighborhood to your fingertips. Experience instant hyperlocal delivery from your favorite local restaurants, grocery supermarkets, pharmacies, bakeries, and specialty stores—all in a single unified order.

WHY CHOOSE ENYTHING?
• Multi-Shop In One Order: Shop from up to 3 local merchants in a single checkout. Your assigned delivery partner picks up all items and delivers them together in one consolidated trip.
• 100% Prepaid & Secure: Enjoy frictionless online payments via UPI, Google Pay, PhonePe, Paytm, credit/debit cards, and net banking. No cash handling, no doorstep change hassles.
• Real-Time Order & Live Route Tracking: Follow your delivery partner on dynamic turn-by-turn road maps with precision ETAs and instant milestone notifications.
• Statutory Tax Transparency: Complete visibility into itemized GST slabs, delivery fee breakdowns, and restaurant food tax under Section 9(5).
• Certified Local Merchants: Verified restaurants, licensed pharmacies with secure prescription verification, and quality-checked neighborhood stores.

EVERYTHING YOU NEED, INSTANTLY:
• Hot Food & Bakery: Fresh meals, snacks, and cakes delivered hot and fresh.
• Groceries & Daily Essentials: Fresh produce, dairy, household staples, and personal care.
• Pharmacy & Health: Prescribed medicines and wellness products from verified local medical stores.
• Electronics & Accessories: Daily cables, tech essentials, and office stationery.

Download Enything today and get anything from anywhere in your city delivered directly to your door!
```

---

### 1.5 Data Safety & Security Declarations (Play Console)
- **Location**:
  - *Approximate location & Precise location*: Collected and shared for active order delivery routing, nearby shop discovery, and real-time courier tracking.
- **Personal Info**:
  - *Name & Phone Number*: Collected for user authentication, OTP verification, order coordination, and customer support.
- **Financial Info**:
  - *Purchase History & Payment Info*: Processed securely through RBI-compliant Razorpay payment gateway for 100% prepaid order fulfillment. No raw card numbers or CVVs stored on platform servers.
- **Photos and Videos**:
  - *User-uploaded Images*: Optional prescription uploads for pharmaceutical items and identity documents for merchant/courier onboarding.
- **Security Practices**:
  - Data is encrypted in transit over HTTPS / TLS 1.3.
  - Users can request account and data deletion at any time via Profile Settings.

---

## 2. APPLE APP STORE CONNECT SUBMISSION DETAILS

### 2.1 Bundle & Target Specification
- **App Name**: Enything: Instant Local Delivery
- **Bundle Identifier**: `com.muhtaashimnazki.enything`
- **Apple Team ID**: `548PL673KC`
- **Version String**: `1.0.8`
- **Build Number**: `20`
- **Primary Category**: `Food & Drink`
- **Secondary Category**: `Shopping`
- **Content Rights**: Enything owns and licenses all displayed brand trademarks.

---

### 2.2 App Store Metadata & Copywriting

#### Subtitle (Max 30 chars):
`Food, Groceries & Essentials`

#### Promotional Text (Max 170 chars):
`Order from multiple local restaurants, supermarkets, and pharmacies in a single checkout with 100% secure prepaid delivery and real-time live map tracking.`

#### Description:
```text
Enything delivers anything from your city straight to your doorstep. Experience ultra-fast delivery from neighborhood restaurants, grocery supermarkets, licensed pharmacies, bakeries, and retail stores in one seamless platform.

Key Features:
• Multi-Merchant Shopping: Order from up to 3 distinct neighborhood stores in one unified cart with consolidated route delivery.
• 100% Prepaid Convenience: Fast, secure online payments via Apple Pay, UPI, and major cards. Zero doorstep cash collection.
• Live Activities & Route Tracking: Glanceable real-time delivery status on your iOS Lock Screen and Dynamic Island with sub-second milestone updates.
• Statutory Tax Compliance: Clear, transparent GST breakdowns under Indian tax statutes with statutory Section 9(5) restaurant tax remittance.
• Prescription Pharmacy Verification: Safe, encrypted prescription uploads for medical essentials handled by licensed pharmacists.
• Dietary & Category Filters: Instant one-tap Vegetarian / Non-Vegetarian toggle, cuisine filters, and operating hour discovery.

Support & Privacy:
We value your privacy. All location data is strictly used for active order delivery and merchant discovery.
```

#### Keywords (Max 100 chars, comma-separated):
`enything,food delivery,grocery,hyperlocal,pharmacy,medicine,instant delivery,multi shop,prepaid,order`

#### Support & Privacy URLs:
- **Support URL**: `https://enything.app/support`
- **Marketing URL**: `https://enything.app`
- **Privacy Policy URL**: `https://enything.app/privacy-policy`

---

### 2.3 App Review Information (For Apple Review Team)
- **Demo Account Phone**: `+91 9999999999`
- **Demo Account OTP**: `123456` (or platform demo credentials configured in `verify-otp`)
- **Review Notes**:
```text
Enything is a hyperlocal multi-merchant delivery platform operating strictly on a 100% online prepaid model (no cash-on-delivery). 
To test customer ordering:
1. Log in with the demo phone credentials provided above.
2. The customer dashboard will display nearby partner stores.
3. Add items to cart and proceed to checkout using the test payment gateway.
4. Active order route tracking displays real-time milestone transitions from store preparation to delivery.
```
- **Export Compliance**:
  - Does the app use encryption? Yes.
  - Does it qualify for an exemption? Yes, uses standard HTTPS / TLS 1.3 and Apple standard cryptographic libraries for WebCrypto (Exempt under Category 5, Part 2).

---

## 3. CHECKLIST FOR PRODUCTION ROLLOUT

1. [x] Bump `pubspec.yaml` version to `1.0.8+20`.
2. [x] Update `lib/config/app_version.dart` to version `1.0.8` (Build `20`).
3. [x] Synchronize `android/local.properties` to `versionName=1.0.8` and `versionCode=20`.
4. [x] Run `flutter build appbundle --release` to generate `app-release.aab`.
5. [x] Verify keystore signature with `keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab`.
6. [ ] Upload `app-release.aab` to Google Play Console Production Track.
7. [ ] Archive and upload iOS IPA build to App Store Connect via Xcode / `flutter build ipa`.
8. [ ] Paste What's New notes and submit for App Store review.
