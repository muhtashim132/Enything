# Enything — API Subscriptions, Cloud Infrastructure & Cost Roadmap for First 1,000 Active Users

> **Executive Summary**: Running the Enything platform for its first 1,000 active users (Customers, Sellers, Riders) is remarkably lean and cost-efficient. The total estimated recurring operating expenditure (**OPEX**) is only **~₹2,500 to ₹3,000 / month (\$30 – \$35 / month)**. 
> 
> However, **choosing the correct tier for each API is critical**: relying on the wrong free tiers (such as Supabase Free which auto-pauses after inactivity) will cause fatal crashes and order drop-offs in production. Below is the 100x forensic analysis of every service, exact tiers required, volume calculations, and setup instructions.

---

## 1. Quick Budget Summary at a Glance

| Service / Provider | Capability in App | Free Tier Limits | Recommended Tier for 1,000 Users | Monthly Cost (INR / USD) | Mandatory Before Launch? |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Supabase** | DB (PostGIS), Auth, Storage, Edge Functions, Realtime | 500 MB DB, 1 GB Storage, 200 Realtime conns (Auto-pauses) | **Pro Plan** (Dedicated compute, no auto-pause, PITR backups) | **\$25 / mo** (~₹2,100) | **YES (Crucial)** |
| **Fast2SMS / DLT** | SMS OTP Phone Login & Verification | ₹50 trial credits | **Pay-As-You-Go** (~₹0.20 per SMS) | **~₹400 – ₹500 / mo** (~2,000 OTPs) | **YES** |
| **Razorpay** | Online Prepaid Payments (UPI, Cards, Netbanking) | Standard Plan (0 fixed fee) | **Standard Merchant Account** | **₹0 fixed** (2% + GST per txn, 0% UPI) | **YES** |
| **RazorpayX / Payouts** | Automated Seller & Rider Weekly Payouts | Standard Dashboard | **Standard Payouts** (Pay-per-transfer) | **~₹200 – ₹400 / mo** (₹2–₹4 per payout) | Optional (Can do manual NEFT initially) |
| **Mapbox** | Vector Map Tiles & Directions Routing | 50,000 MAU Maps, 100,000 Directions requests | **Free Tier (Pay-As-You-Go)** | **\$0 / mo** (Usage < 5% of free limit) | **YES (Account + Card)** |
| **OpenRouteService (ORS)**| Multi-Stop Routing Fallback | 2,000 req/day (60,000/mo) | **Standard Free API Key** | **\$0 / mo** | **YES** |
| **Firebase (GCP)** | Push Notifications (FCM HTTP v1) | Unlimited Push Messages | **Spark Plan (100% Free)** | **\$0 / mo** | **YES** |
| **Google Cloud (GCP)** | Reverse Geocoding & Places Fallback | \$200 free credit every month | **Free Tier / Credits** | **\$0 / mo** | **YES** |
| **Apple Developer** | iOS App Store & APNs Push Certificates | N/A | **Apple Developer Program** | **\$99 / year** (~₹8,300/yr) | **YES (for iOS)** |
| **Google Play Console** | Android Play Store Publishing | N/A | **Google Play Developer Account** | **\$25 One-Time** (~₹2,100) | **YES (for Android)** |
| **Domain & Custom Email** | Webhooks, Invoicing & Brand Identity | N/A | **Domain (.in / .com) + Brevo / Resend** | **~₹800 / year** (Email is free) | **YES** |

---

## 2. Forensic Breakdown of Every Service & API

### 1. Supabase (Core Backend, Database & Microservices)
- **Role in Enything**:
  - PostgreSQL database with PostGIS geospatial queries (`search_products_geospatial`, `search_shops_geospatial`).
  - Supabase Storage for product images, KYC IDs, and store banners.
  - Supabase Realtime (WebSockets) for real-time rider GPS tracking, order status state machine, and seller kitchen display.
  - 10 Supabase Edge Functions (`send-otp`, `send-push`, `verify-razorpay-payment`, `create-razorpay-order`, etc.).
- **Why Free Tier is DANGEROUS**:
  - Supabase Free projects **automatically pause** after 7 days of inactivity.
  - No automated daily backups or Point-in-Time Recovery (PITR).
  - Restricted to 200 concurrent Realtime connections (riders sending GPS pings every 5s will exhaust this rapidly).
- **Recommended Tier**: **Supabase Pro Tier (\$25/month)**.
  - 8 GB database included (1,000 users + 10,000 products will take < 300 MB).
  - 100 GB storage included.
  - 2,000,000 Edge Function invocations included.
  - 500 concurrent Realtime connections.
  - No auto-pausing (24/7 uptime guarantee).
  - 7 days of daily automated backups.

---

### 2. Fast2SMS & Telecom DLT (SMS & OTP Login)
- **Role in Enything**:
  - Invoked by the `send-otp` Supabase Edge Function to deliver 6-digit OTPs during customer, seller, and rider onboarding.
- **Telecom Regulatory Mandate (India DLT)**:
  - In India, TRAI mandates Distributed Ledger Technology (DLT) registration for sending transactional SMS to Indian (+91) phone numbers.
  - You must register on any telecom DLT portal (e.g. **Jio DLT**, **Airtel DLT**, or **Vilpower/Vodafone DLT**).
  - Register Header/Sender ID: e.g. `ENYTHG` or `ENYAPP`.
  - Register Content Template: e.g. `Your Enything login verification code is {#var#}. Valid for 5 minutes. Please do not share this OTP with anyone.`
- **Costs & Volume for 1,000 Users**:
  - ~1,000 initial signups + ~1,000 repeat logins/month = **~2,000 SMS / month**.
  - Fast2SMS DLT SMS cost: **~₹0.18 to ₹0.22 per SMS**.
  - Monthly wallet recharge: **₹400 – ₹500 / month**.
  - Fast2SMS account: **Pay-as-you-go** (No monthly fixed subscription fee).

---

### 3. Razorpay (Payment Gateway & Settlement)
- **Role in Enything**:
  - Handles the **100% Prepaid Model (Zero COD)** via UPI (Google Pay, PhonePe, Paytm), Credit/Debit Cards, and Netbanking.
  - Edge Functions: `create-razorpay-order`, `verify-razorpay-payment`, and `process-refund`.
- **Pricing & Tier**:
  - **Standard Gateway Account**: **₹0 Setup Fee, ₹0 Annual Maintenance**.
  - **Transaction Fee**:
    - Standard UPI: **0% fee**.
    - Domestic Debit/Credit Cards & Netbanking: **2% + 18% GST**.
- **Payouts (RazorpayX)**:
  - If you disburse earnings to sellers and riders automatically:
    - ₹2 to ₹4 per payout transfer (IMPS/UPI).
    - Can be operated on pay-per-payout without upgrading to RazorpayX Pro.

---

### 4. Mapbox & OpenRouteService (Mapping, Routing & ETA)
- **Role in Enything**:
  - Mapbox vector map tiles for `flutter_map` in Customer Home, Restaurant pages, and Rider Route Map.
  - Mapbox Directions API for calculating driving distances, navigation polyline paths, and delivery fees.
  - OpenRouteService (ORS) as the fallback routing provider.
- **Volume & Free Tier Coverage for 1,000 Users**:
  - **Mapbox Mobile Maps SDK**: **50,000 Monthly Active Users (MAU) FREE**.
    - With 1,000 users, you use only 2% of the free quota!
  - **Mapbox Directions API**: **100,000 requests / month FREE**.
    - For 1,000 users placing ~3,000 orders, total routing API calls will be ~15,000 requests.
    - 100% covered within the 100,000 free request quota!
  - **OpenRouteService**: **2,000 requests / day (60,000 / month) FREE**.
- **Recommended Tier**: **Free Tier on Pay-As-You-Go** (\$0/month). Add a debit/credit card to prevent service cutoff.

---

### 5. Firebase & FCM (Push Notifications)
- **Role in Enything**:
  - Pushes order confirmations, rider arrival alerts, kitchen packing updates, and payment alerts to Customer, Rider, and Seller apps via `send-push` Edge Function.
- **Pricing & Tier**:
  - Firebase Cloud Messaging (FCM HTTP v1) is **100% FREE with UNLIMITED notifications**.
  - Google does not charge for FCM push notifications.
  - **Recommended Tier**: **Firebase Spark Plan (Free forever)**.

---

### 6. App Store & Play Store Submissions (CapEx)
- **Google Play Console**:
  - **\$25 one-time registration fee** (lifetime access).
- **Apple Developer Program**:
  - **\$99 / year** (~₹8,300 / year).
  - Required for publishing iOS apps, provisioning profiles, and generating APNs (Apple Push Notification service) keys.

---

## 3. The 5 Production Traps to Avoid (100x Architecture Protection)

```
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                              THE 5 CRITICAL PRODUCTION TRAPS                                │
├─────────────────────────────────────────────────────────────────────────────────────────────┤
│ 1. The Supabase Free Tier Auto-Pause Trap:                                                   │
│    Free projects sleep after 7 days of inactivity. If a customer opens the app during off-  │
│    peak hours, the API will fail or hang for 30s. Always launch with Supabase Pro ($25/mo). │
│                                                                                             │
│ 2. The Unregistered DLT SMS Block:                                                          │
│    Sending SMS in India without DLT entity & template registration results in 100% message   │
│    drops by telecom firewalls (Airtel/Jio). Register your DLT template 2 weeks before launch.│
│                                                                                             │
│ 3. Client Secret Leaks:                                                                     │
│    Ensure `RAZORPAY_KEY_SECRET` and `SUPABASE_SERVICE_ROLE_KEY` are NEVER packaged in       │
│    Flutter's `.env` asset. They must strictly remain in Supabase Edge Function secrets.     │
│                                                                                             │
│ 4. Mapbox Tile Quota Burn:                                                                  │
│    Ensure `flutter_map` uses caching via `cached_network_image`. Never re-download tiles on  │
│    every frame or panning motion.                                                           │
│                                                                                             │
│ 5. Rider GPS Realtime Flood:                                                                │
│    Throttled GPS updates: Riders should emit GPS coordinates every 5 seconds (not 500ms).    │
│    This keeps WebSocket bandwidth within limits and preserves rider phone battery.          │
└─────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Month 1 Launch Checklist & Action Plan

### Day 1 – 3: Developer & Cloud Setup
- [ ] **Supabase**: Upgrade project from Free to **Pro Plan (\$25/mo)** in Supabase Dashboard $\to$ Settings $\to$ Billing.
- [ ] **Google Play Console**: Register account (\$25 one-time).
- [ ] **Apple Developer**: Register account (\$99/year).

### Day 4 – 7: SMS & Telecom Compliance
- [ ] **DLT Registration**: Sign up on [Jio DLT](https://trueconnect.jio.com) or [Airtel DLT](https://www.airtel.in/business/commercial-communication).
- [ ] **Fast2SMS**: Create account on [Fast2SMS](https://www.fast2sms.com), recharge ₹500, link DLT Header (`ENYTHG`) & Template ID.
- [ ] Add `FAST2SMS_API_KEY` to Supabase Edge Function secrets.

### Day 8 – 10: Payments & Push Notifications
- [ ] **Razorpay**: Complete Business KYC on [Razorpay Dashboard](https://dashboard.razorpay.com). Generate Live API Keys (`Key ID` & `Key Secret`).
- [ ] Set `RAZORPAY_KEY_ID` and `RAZORPAY_KEY_SECRET` in Supabase Secrets.
- [ ] **Firebase**: Download `google-services.json` (Android) and `GoogleService-Info.plist` (iOS). Generate Firebase Service Account JSON key and set `FIREBASE_SERVICE_ACCOUNT` in Supabase.

### Day 11 – 12: Maps & Routing
- [ ] **Mapbox**: Create an account on [Mapbox](https://account.mapbox.com). Generate a Default Public Token with URL/Bundle restriction.
- [ ] Add `MAPBOX_TOKEN` and `ORS_API_KEY` to the app `.env`.

---

## 5. Conclusion & Verdict

For your first **1,000 active users**:
- **Monthly Fixed Operating Cost**: **\$25 / month (~₹2,100)** (Supabase Pro).
- **Variable Usage Cost**: **~₹500 / month** (Fast2SMS OTPs) + transaction fee on payments.
- **Maps, Routing, and Push Notifications**: **₹0 / month** (Fully covered by free quotas).

You can comfortably launch and scale Enything to 1,000+ active customers with less than **₹3,000 / month in total API and cloud spend**!

