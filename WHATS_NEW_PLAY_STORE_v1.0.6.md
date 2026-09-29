# Google Play Console Release Notes — Version 1.0.6 (Build 17)

## 📱 Google Play Release Summary
- **App Name**: Enything
- **Package Name**: `com.muhtaashimnazki.enything`
- **Version Name**: `1.0.6`
- **Version Code**: `17` (Upgrades from Release 15 / `1.0.4`)
- **Target SDK**: Android 15 (API 35)
- **Min SDK**: API 21 (Android 5.0)

---

## 📋 What's New in this Release (Play Store Description — Max 500 chars)

```text
• Android 15 Edge-to-Edge Ready: Full-screen immersion with modern display insets.
• Real-Time Order & Rider Tracking: Live GPS navigation with instant auto-reconnect.
• Seamless Multi-Shop Orders: Enhanced multi-store cart grouping and live pickup milestones.
• Instant Prepaid Checkout: Fast UPI integration, itemized billing, and zero doorstep cash hassle.
• Referral Rewards: Instant bonus credits and referral tracking.
• Performance & Battery: R8 full-mode optimization with lighter memory usage.
```

---

## 🛡️ Resolution of Play Console 4 Recommended Actions

### 1. Edge-to-Edge Compatibility (Android 15 / SDK 35)
- **Action Taken**: Called `enableEdgeToEdge()` in `MainActivity.onCreate()` using `androidx.activity:activity-ktx` backwards compatibility layer.
- **Result**: App seamlessly adheres to Android 15 edge-to-edge window insets on API 35+.

### 2. Deprecated Display Cutout Parameters Removed
- **Action Taken**: Removed deprecated `LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES` from all four theme style configurations (`values/styles.xml`, `values-v31/styles.xml`, `values-night/styles.xml`, `values-night-v31/styles.xml`).
- **Result**: No deprecated cutout parameters used; Android 15 system insets handle display cutouts natively.

### 3. Large Screen & Foldable Resizability Restrictions Removed
- **Action Taken**: Added `android:resizeableActivity="true"` to both `<application>` and `<activity android:name=".MainActivity">` in `AndroidManifest.xml`.
- **Result**: Full support for foldables, tablets, multi-window mode, and Android 16 large-screen guidelines without orientation layout breakage.

### 4. R8 Full Mode & Optimized Resource Shrinking Enabled
- **Action Taken**: 
  - Added `android.enableR8.fullMode=true` and `android.enableResourceOptimizations=true` to `android/gradle.properties`.
  - Added explicit ProGuard keep rules for `io.flutter.embedding.**`, `androidx.activity.**`, and `androidx.core.view.**` in `android/app/proguard-rules.pro`.
- **Result**: Dramatic reduction in AAB bundle size, optimized DEX packaging, and lower runtime memory overhead.
