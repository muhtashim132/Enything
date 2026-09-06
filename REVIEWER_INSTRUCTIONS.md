# 🍎 Apple App Store Reviewer Instructions & Notes

> **App Name**: Enything — On-Demand Hyperlocal Delivery  
> **Bundle Identifier**: `com.muhtaashimnazki.enything`  
> **Target Audience / Service Region**: Hyperlocal physical goods delivery operating in Jammu & Kashmir, India.  

---

## 📋 Copy-Paste Text for App Store Connect "Review Notes"

```text
Dear Apple Review Team,

Thank you for reviewing Enything! 

Enything is an on-demand hyperlocal physical goods marketplace connecting local customers, neighbourhood merchant stores, and delivery riders in India.

Below are full demo credentials and instructions to test all three primary user roles (Customer, Merchant/Seller, and Delivery Rider).

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. DEMO CREDENTIALS (BYPASS SMS OTP)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Our SMS OTP provider requires Indian mobile numbers (+91). For the App Review team, we have pre-provisioned dedicated test numbers with a static OTP:

A. CUSTOMER DEMO ACCOUNT:
   - Phone Number: 9999999991 (or +919999999991)
   - Verification OTP: 123456
   - Behavior: Logs directly into the Customer Home experience with a pre-configured delivery address in our active operating zone. Browse live merchant catalogs, add items to cart, and experience the full checkout & tracking interface.

B. MERCHANT / SELLER DEMO ACCOUNT:
   - Phone Number: 9999999992 (or +919999999992)
   - Verification OTP: 123456
   - Behavior: Automatically routes to the Merchant Dashboard ("Apple Demo Store"). Reviewers can manage product listings, toggle store opening hours, review real-time orders, and manage catalog inventory.

C. DELIVERY PARTNER (RIDER) DEMO ACCOUNT:
   - Phone Number: 9999999993 (or +919999999993)
   - Verification OTP: 123456
   - Behavior: Automatically routes to the Delivery Partner Dashboard with an approved and verified vehicle profile. Reviewers can test order dispatch radar, accept delivery requests, and view delivery earnings.

D. UNIVERSAL / ALL-IN-ONE DEMO ACCOUNT:
   - Phone Number: 9999999999 (or +919999999999)
   - Verification OTP: 123456
   - Behavior: Pre-linked to all three roles (Customer, Seller, Rider). The in-app Role Switcher Card under Profile Settings allows seamlessly toggling between Customer, Seller, and Rider roles without re-authenticating.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
2. GEOGRAPHIC LOCATION & SERVICE AREA NOTES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Enything currently provides physical delivery operations in Bandipora, Jammu & Kashmir (India). 

To ensure Apple reviewers testing outside India (e.g. Cupertino, California) have a seamless review experience without being blocked by geographic geofences:
- The app automatically links the demo accounts to our central operating zone (Bandipora).
- When logging in with any of the demo accounts above, nearby verified merchant stores (e.g. Kamrans Restaurant, Apple Demo Store) and products will load immediately on the Home screen.
- You can freely test cart checkout, order placement, and tracking.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
3. APP STORE GUIDELINE COMPLIANCE CLARIFICATIONS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
- Guideline 3.1.5 (Physical Goods & Services Exemption):
  All transactions within Enything are exclusively for physical food, grocery, and pharmacy items delivered to physical doorsteps. Therefore, in accordance with Guideline 3.1.5, in-app purchases (IAP) are not used; digital payment gateways (Razorpay) and Cash on Delivery (COD) are utilized.

- Guideline 5.1.1(v) (Account Deletion):
  Users can permanently delete their account and all personal data self-service directly in-app at:
  Profile Settings → Scroll down → Tap "Delete Account" → Confirm "Delete Forever".
  Account deletion immediately removes all personal data, profile records, and saved addresses from the database.

- Guideline 2.5.4 (Background Location Usage):
  Background location is exclusively requested and used for active Delivery Partners during an ongoing delivery mission to broadcast real-time delivery coordinates to the waiting customer. Customers and Merchants are NEVER tracked in the background.

- Guideline 4.8 (Sign in with Apple):
  Enything exclusively uses direct mobile phone number authentication. We do not support third-party social logins (Google, Facebook, etc.); therefore, Sign in with Apple is not applicable.

- Privacy Manifest:
  An Apple-compliant `PrivacyInfo.xcprivacy` manifest is embedded in the application bundle declaring all data collection types, non-tracking status, and official reason codes for standard system APIs.

Should you require any additional information, please contact our Lead Developer at muhtashimnazki@gmail.com or support@enything.in.
```

---

## 🛠 Feature Verification Summary Table

| Role | Demo Phone | Static OTP | Pre-Configured State | Landing Page |
|---|---|---|---|---|
| **Customer** | `9999999991` | `123456` | Pre-configured saved address in Bandipora | Customer Home |
| **Seller** | `9999999992` | `123456` | Verified shop "Apple Demo Store" | Seller Dashboard |
| **Rider** | `9999999993` | `123456` | Verified rider & approved bike vehicle | Delivery Partner Dashboard |
| **Universal** | `9999999999` | `123456` | All 3 roles enabled with Role Switcher | Customer Home / Role Switcher |

---

## 🔍 Verification Steps for Apple Reviewers

1. **Test In-App Account Deletion**:
   - Log in with Customer demo `9999999991`, OTP `123456`.
   - Tap profile icon in the bottom navigation bar to open Profile Settings.
   - Scroll to the bottom and tap **"Delete Account"**.
   - Confirmation dialog warns of irreversible data loss. Tapping **"Delete Forever"** executes account purge and navigates to role selection.

2. **Test Merchant / Seller Experience**:
   - Log in with Seller demo `9999999992`, OTP `123456`.
   - The app opens directly to the **Seller Dashboard**.
   - Reviewer can view sales insights, manage catalog products, and toggle store operating hours.

3. **Test Delivery Partner (Rider) Experience**:
   - Log in with Rider demo `9999999993`, OTP `123456`.
   - The app opens directly to the **Delivery Partner Dashboard**.
   - Reviewer can view pending orders radar, toggle online/offline availability, and view completed delivery earnings.
