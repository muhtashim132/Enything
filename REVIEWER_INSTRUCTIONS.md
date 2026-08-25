# 📱 Enything App — Production Testing Guidelines

> **Platform**: Android / iOS  
> **Environment**: Production Authentication (Fast2SMS OTP Verification)  
> **Location**: Hyperlocal delivery in Bandipora, Jammu & Kashmir

---

## 🔑 Authentication & Login Flow

All user logins now go through live Fast2SMS OTP verification:
1. Enter any valid 10-digit mobile number.
2. An SMS OTP will be dispatched via Fast2SMS to the phone number.
3. Enter the received 6-digit OTP to verify and log in.
4. If it's a first-time login, select your profile role (Customer, Seller, or Delivery Partner) and complete profile setup.
5. If you already have registered roles, you are automatically routed to your active role dashboard.

---

## 🛒 Customer Flow
1. **Open app** → Enter mobile number → Verify OTP.
2. Grant device location permissions to discover nearby verified stores in Bandipora.
3. Browse products from active stores (e.g., *Kamrans Restaurant*, *Mubashir Medical Shop*, *Haji Super Mart*).
4. Add items to cart and proceed to checkout.
5. Review order summary with transparent GST breakdown and place order.
6. Track order in real time on the Track Order page as shop and delivery partner accept and fulfill the order.
