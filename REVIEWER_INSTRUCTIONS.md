# 📱 Enything App — Reviewer Instructions

> **Platform**: Android / iOS  
> **Environment**: Test mode (Razorpay test payments)  
> **Location**: All accounts are hardcoded to **Bandipora, Jammu & Kashmir**

---

## 🔑 Magic Login Credentials

All three accounts log in **directly without OTP verification**. Just enter the phone number and tap Continue — you'll be taken straight to the dashboard.

| Role | Name | Phone Number | OTP |
|------|------|-------------|-----|
| 👤 Customer | **Rajesh Kumar** | `9999999996` | Any 6 digits (e.g. `123456`) |
| 🏪 Seller | **Amit Bandana** | `9999999997` | Any 6 digits (e.g. `123456`) |
| 🛵 Delivery Partner | **Kishan Nadda** | `9999999998` | Any 6 digits (e.g. `123456`) |

> **Tip:** You can also just type the phone number and the app will auto-login without needing OTP at all.

---

## 🛒 Customer Flow — Rajesh Kumar (`9999999996`)

1. **Open app** → Enter `9999999996` → Tap **Continue** → Auto-logged in as Rajesh Kumar
2. App location is hardcoded to **Main Market, Bandipora, J&K**
3. **Browse** the home page → Find **"Amit Medical Store"** (Medical Store category)
4. Tap on a product → Add to Cart
5. Go to **Cart** → Tap **Proceed to Checkout**
6. Review the order summary → Tap **Place Order**
7. You land on the **Track Order** page showing **"Awaiting Acceptance"**
8. **Wait ~2 seconds** → The order is automatically accepted (simulated shop + rider acceptance)
9. Status changes to **"Ready — Pay Now!"**
10. **Razorpay payment sheet opens automatically** within 1 second
11. Use any Razorpay **test card** to complete payment:
    - Card: `4111 1111 1111 1111` | Expiry: Any future date | CVV: Any 3 digits
    - UPI: `success@razorpay`

---

## 🏪 Seller Flow — Amit Bandana (`9999999997`)

1. **Open app** → Enter `9999999997` → Tap **Continue** → Auto-logged in as Amit Bandana
2. You land on the **Seller Dashboard**
3. The shop **"Amit Medical Store"** is pre-created, verified, and active in Bandipora
4. To add products: tap **Manage Products** → **Add Product** → fill in name, price, quantity → **Save**
5. When the customer places an order, it appears in **Orders** tab (auto-accepted for reviewer flow)
6. You can view order details, mark as preparing, ready for pickup, etc.

---

## 🛵 Delivery Partner Flow — Kishan Nadda (`9999999998`)

1. **Open app** → Enter `9999999998` → Tap **Continue** → Auto-logged in as Kishan Nadda
2. You land on the **Delivery Dashboard**
3. Account is pre-verified (`verification_status: verified`) and active
4. Location is hardcoded to Bandipora — orders nearby will appear automatically
5. Toggle **Online** to go active
6. Incoming orders appear in the dashboard — you can accept/reject them

---

## ⚙️ Technical Notes for Reviewers

### Razorpay Test Mode
- The app uses **Razorpay test keys** (`rzp_test_*`)
- No real money is charged
- Use [Razorpay test credentials](https://razorpay.com/docs/payments/payments/test-card-details/)

### Test Cards
| Card Number | Expiry | CVV | Result |
|-------------|--------|-----|--------|
| `4111 1111 1111 1111` | Any future | Any | ✅ Success |
| `4000 0000 0000 0002` | Any future | Any | ❌ Failure |
| UPI: `success@razorpay` | — | — | ✅ Success |

### Location
- All magic accounts are hardcoded to **Bandipora, J&K (34.4225°N, 74.6366°E)**
- No GPS permission required for reviewer accounts

### Order Auto-Accept
- When Rajesh Kumar (Customer) places an order, the Track Order page shows "Awaiting Acceptance" for **2 seconds** — this simulates the shop and rider accepting
- After 2 seconds, status automatically changes to "Awaiting Payment" and Razorpay opens
- This is intentional for reviewer flow only

### No Real Logic Changed
- All magic number behavior is **isolated** to these 3 phone numbers
- Real user accounts are completely unaffected
- The reviewer accounts can be reset at any time by re-running the migration

---

## 🚫 Important Notes

- Do **NOT** use these phone numbers for real accounts
- The auto-accept only works for the customer account (`9999999996`) — the seller and delivery partner accounts have real dashboards
- If the Razorpay sheet shows an error, ensure `RAZORPAY_KEY_SECRET` is set in Supabase Dashboard → Project Settings → Secrets matching the key `rzp_test_T5cdZftV7kj5jV`
