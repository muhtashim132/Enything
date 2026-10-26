# 🚀 Enything v1.0.7 Release & Forced In-App Update Guide

This guide provides step-by-step instructions for:
1. **Verifying the automated Apple App Store Connect upload** (v1.0.7).
2. **Releasing the Android App Bundle (`.aab`) on Google Play Console**.
3. **Triggering the in-app update prompt for customers on older versions** (v1.0.6) on both **Google Play** and the **Apple App Store**.

---

## 🍎 Part 1: Apple App Store Connect Release

The iOS build has been **automatically packaged, archived, and uploaded directly to Apple App Store Connect without manual intervention**:
- **Status:** `Upload succeeded` (`** EXPORT SUCCEEDED **`)
- **Bundle ID:** `com.muhtaashimnazki.enything`
- **Version:** `1.0.7`
- **Build:** `18` (and `19`)
- **Developer Team ID:** `548PL673KC`

### Steps to Finalize & Submit the Release on App Store Connect:
1. Go to [App Store Connect](https://appstoreconnect.apple.com/) and sign in with your Apple Developer account.
2. Click **Apps** ➔ Select **Enything**.
3. In the left sidebar under **iOS App**:
   - If version **1.0.7** is not listed, click the **"+" (Add Version or Platform)** button next to iOS App. Enter `1.0.7` and click **Create**.
4. In the **What's New in This Version** box, paste the following release notes:

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

5. Scroll down to the **Build** section:
   - Click **"+" (Add Build)**.
   - Select the newly uploaded build (**1.0.7, Build 18 or 19**).
   - *(Note: If Apple shows "Processing", wait 5-10 minutes for Apple to complete automatic compliance scanning, then refresh the page and select it).*
6. **Export Compliance Information**:
   - When prompted: *"Does your app use encryption?"* ➔ Select **No** (standard HTTPS/SSL is exempt).
7. Click **Save** in the top-right corner.
8. Click **Add for Review** (or **Submit to App Review**).
9. Once approved by Apple, the app will either automatically release or be ready for manual release depending on your account settings.

---

## 🤖 Part 2: Google Play Console Release

The Android App Bundle (`.aab`) is compiled, shrunk with R8 full mode, and cryptographically signed with the production release keystore:
- **File Location:** `build/app/outputs/bundle/release/app-release.aab`
- **Target SDK:** Android 15 (API 35)
- **Min SDK:** API 21 (Android 5.0)
- **Version Name:** `1.0.7`
- **Version Code:** `19`

### Steps to Upload & Release on Google Play Console:
1. Open the [Google Play Console](https://play.google.com/console/) and select **Enything**.
2. In the left navigation menu, go to **Release** ➔ **Production** (or your internal/closed testing track if desired).
3. Click **Create new release** (top right).
4. Under **App bundles**, drag and drop:
   `build/app/outputs/bundle/release/app-release.aab`
5. In **Release name**, verify it displays `1.0.7 (19)`.
6. In the **Release notes** field (under language `en-IN` or `en-US`), paste:

```text
• Supermart Multi-Department Aisle Engine: Transparent item-level settlement across grocery, cosmetics, electronics, and fresh produce.
• Smart Closed Store Discovery: View scheduled operating hours, pre-order from favorite local shops, and browse full menus anytime.
• One-Tap Dietary Filters: Instant Pure Veg / Non-Veg food and grocery discovery.
• Modernized Ergonomics: Adaptive bottom navigation bar and ultra-responsive browsing.
• 100% Prepaid Reliability: Fast UPI, cards, and zero doorstep cash hassle.
```

7. Click **Next** at the bottom right.
8. Review any warnings (e.g., standard deobfuscation/mapping file notes).
9. Click **Save and publish** / **Send for review**.

---

## 🔄 Part 3: How to Enforce the Update Prompt for Customers on Older Versions

The user requested that customers opening the older update (e.g. v1.0.6) must receive a message requiring them to update from the App Store / Play Store first.

Here is how to enforce this for both platforms:

### 1. For Google Play Store (Android): Play Recovery Tools
Google Play provides a native, OS-level feature specifically engineered to force users on older builds to update immediately upon opening the app, without requiring any custom code in the old build:

1. In the **Google Play Console**, go to **Release** ➔ **App bundle explorer**.
2. In the version dropdown, select the older release: **Version Code 17 (v1.0.6)**.
3. Click on the **Recovery** tab (or **Prompt users to update**).
4. Click **Create prompt**.
5. Configure the prompt:
   - **Target version:** Select **Version Code 19 (v1.0.7)**.
   - **Update type:** Select **Immediate update** (this presents a full-screen, non-dismissible prompt from Google Play Services requiring the user to update before they can use the app).
6. Click **Save** and **Activate prompt**.
7. **Result:** Any customer opening v1.0.6 on their Android device is instantly greeted by Google Play's native system dialog: *"Update available. To continue using Enything, download the latest version."* with an **Update** button that updates the app right on their screen!

---

### 2. For Apple App Store (iOS): Supabase Remote Platform Config
Apple App Store does not have an OS-level prompt tool like Google Play Recovery. Instead, iOS apps rely on remote configuration.

Enything includes two layers of defense:

#### Layer A: Instant Enforcement for Older Clients (v1.0.6)
All versions of Enything fetch `platform_config` from Supabase on startup. When `maintenance_mode = true`, v1.0.6:
- Displays a prominent alert banner across the top of the Home page.
- Disables the checkout button in the Cart.
- Blocks order placement in Checkout with the maintenance message.

To notify existing v1.0.6 iOS users to update:
1. Open the [Supabase Dashboard](https://supabase.com/dashboard) ➔ Select your Enything project.
2. Go to **Table Editor** ➔ `platform_config`.
3. Locate the row with `key = 'maintenance_message'`.
4. Update `value` to:
   ```json
   "⚠️ App Update Required: Version 1.0.7 is now available! Please update Enything from the App Store to enjoy live Dynamic Island tracking, Supermarts, and faster checkout."
   ```
5. Ensure `key = 'maintenance_mode'` is `true`.

#### Layer B: Hard Forced Update Guard (Built into v1.0.7+)
In version 1.0.7, we implemented a dedicated **`_showForceUpdateDialog`** in `SplashPage` and `PlatformConfigProvider`:
- It compares the installed build against `min_supported_build_number` in `platform_config`.
- If `installed_build < min_supported_build_number`, the splash screen stops and displays a non-dismissible modal:
  - **Title:** "App Update Required 🚀"
  - **Message:** Explains the update and provides a 1-tap **"Update on App Store"** or **"Update on Play Store"** button.
  - **Link:** Opens `https://apps.apple.com/in/app/enything/id6809016496` or `https://play.google.com/store/apps/details?id=com.muhtaashimnazki.enything`.

To activate Layer B after v1.0.7 is approved and live in stores:
In Supabase `platform_config`, add or update:
- `key = 'min_supported_build_number'`, `value = 18` (or `19`).

> [!CAUTION]
> **Timing is Critical:** Only activate `min_supported_build_number` or the Play Store update prompt **AFTER** Apple and Google have approved version 1.0.7 and made it downloadable in the stores. If activated beforehand, users who tap "Update" will land on the store page where only the old version is available, creating a loop.

---

## 📋 Summary of Deliverables & Files

| Component | Target / Value | Location |
|---|---|---|
| **iOS Archive** | Uploaded to App Store Connect | `build/ios/archive/Runner.xcarchive` |
| **Android Bundle** | Ready for Google Play Console | `build/app/outputs/bundle/release/app-release.aab` |
| **Play Store Notes** | 494 chars (Paste-ready) | `WHATS_NEW_PLAY_STORE_v1.0.7.md` |
| **iOS Notes** | Formatted (Paste-ready) | `WHATS_NEW_IOS_v1.0.7.md` |
| **Version Code** | `19` (`1.0.7+19`) | `pubspec.yaml` & `lib/config/app_version.dart` |
| **App Store ID** | `6809016496` | Production link verified |
| **Play Store ID** | `com.muhtaashimnazki.enything` | Production link verified |
