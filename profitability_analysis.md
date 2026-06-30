# Enything Profitability Blueprint
## Commission Strategy, Loophole Analysis & Category-Wise Rates

---

## 1. Current Model — What You Collect Per Order

Your revenue streams per order (current setup):

| Revenue Stream | Amount | Who Pays |
|---|---|---|
| Platform commission | 5% of item base | Seller |
| Platform/Handling fee | ₹15 (incl. 18% GST) | Customer |
| Delivery charge | ₹25–₹60 | Customer |
| Rider margin (you keep 20%) | 20% of delivery | Customer |
| Small cart fee | ₹15 (<₹99 orders) | Customer |
| Heavy order fee | ₹20 (>10kg) | Customer |
| Multi-shop surcharge | ₹7/km between shops | Customer |
| Enything Pass subscription | ₹49–₹199/month | Customer |

Your **costs** per order:

| Cost | Amount |
|---|---|
| Rider payout | 80% of delivery fee |
| Payment gateway (Razorpay) | 2.36% of grand total |
| S9(5) GST remittance (food) | 5% of food base |
| Delivery GST remittance | 18% inside delivery |
| Platform fee GST remittance | 18% inside ₹15 |

---

## 2. Profitability Calculation — Real Numbers

### Scenario A: ₹300 Grocery Order, 3km, UPI (Typical)

| Item | Value |
|---|---|
| Item subtotal (base) | ₹300 |
| GST on items (5%) | ₹15 |
| Delivery (3km slab) | ₹30 |
| Platform fee | ₹15 |
| **Customer pays** | **₹360** |
| Razorpay takes (2.36%) | -₹8.50 |
| Rider payout (80% × ₹30) | -₹24.00 |
| Commission (5%) | +₹15.00 |
| Platform net of GST (₹15/1.18 = ₹12.71) | +₹12.71 |
| Delivery net (₹30 - ₹5.08 GST - ₹24 rider) | +₹0.92 |
| Enything gateway share | -₹3.00 |
| **Enything Net Profit** | **~₹21.63** |
| **Margin %** | **~6.0%** |

### Scenario B: ₹150 Small Order, UPI (BAD CASE)

| Item | Value |
|---|---|
| Item subtotal | ₹150 |
| GST (5%) | ₹7.50 |
| Small cart fee | ₹15 (order < ₹99? No, skip) |
| Delivery (2km) | ₹25 |
| Platform fee | ₹15 |
| **Customer pays** | **₹197.50** |
| Razorpay (2.36%) | -₹4.66 |
| Rider payout (80% × ₹25) | -₹20.00 |
| Commission (5%) | +₹7.50 |
| Platform net | +₹12.71 |
| Delivery net (₹25 - ₹3.81 GST - ₹20 rider) | +₹1.19 |
| Enything gateway share | -₹2.05 |
| **Enything Net Profit** | **~₹19.35** |
| **Margin %** | **~9.8%** |

### Scenario C: ₹500 Restaurant Order, 5km UPI (FOOD — HIGH RISK)

| Item | Value |
|---|---|
| Food base | ₹500 |
| S9(5) GST (5%, Enything deposits) | ₹25 |
| Delivery (5km) | ₹35 |
| Platform fee | ₹15 |
| **Customer pays** | **₹575** |
| Razorpay (2.36%) | -₹13.57 |
| **You REMIT to govt** (S9(5) GST) | -₹25.00 |
| Rider payout (80% × ₹35) | -₹28.00 |
| Commission (5%) | +₹25.00 |
| Platform net | +₹12.71 |
| Delivery net (₹35 - ₹5.34 GST - ₹28 rider) | +₹1.66 |
| Enything gateway share | -₹4.00 |
| **Enything Net Profit** | **~₹10.37** |
| **Effective Margin %** | **~1.8% of order value** |

> [!CAUTION]
> Restaurant orders are your **worst-case category** — you collect 5% commission but must also deposit 5% GST yourself. Your REAL net margin on food is only ~2%. This is the biggest loophole.

### Scenario D: ₹100 Pharmacy Order, 1km (WORST CASE — Low AOV)

| Item | Value |
|---|---|
| Item base | ₹100 |
| GST (5%) | ₹5 |
| Delivery (1km slab) | ₹20 |
| Platform fee | ₹15 |
| **Customer pays** | **₹140** |
| Razorpay (2.36%) | -₹3.30 |
| Rider payout (80% × ₹20) | -₹16.00 |
| Commission (5%) | +₹5.00 |
| Platform net | +₹12.71 |
| Delivery net | +₹0.41 |
| Enything gateway share | -₹1.40 |
| **Enything Net Profit** | **~₹13.72** |
| **Margin %** | **~9.8%** |

> [!NOTE]
> Even tiny orders are profitable because the ₹15 platform fee acts as a high-margin fixed cushion. ₹13.72 from a ₹100 order is excellent.

---

## 3. Worst-Case Scenarios (The Loopholes)

### ❌ Loophole 1: Restaurant Orders Kill Margin
**Problem:** You earn 5% commission = ₹25 on ₹500 food order. But you ALSO deposit the S9(5) GST = ₹25 to the government. These cancel each other out. Your real money comes ONLY from delivery margin (₹1.66) + platform fee (₹12.71) = ₹14.37 total on a ₹575 customer payment.

**Solution:** Raise food commission to **15%** (still 50% below Zomato's 30%). Even after GST obligation, you retain ₹75 - ₹25 = ₹50 real margin.

### ❌ Loophole 2: Free Delivery (Enything Pass) + Restaurant = Zero Profit
**Problem:** Pass subscriber orders ₹500 restaurant food → delivery = ₹0 → You absorb ₹35 rider cost but collect no delivery fee. Platform fee = ₹12.71 net. Commission = ₹25. GST deposit = ₹25. **Net: -₹35 + ₹12.71 + ₹0 = LOSS.**

**Solution:**
1. Higher commission on food orders compensates.
2. Cap free delivery at 5km for Lite/Pro. Ultra gets 8km cap.
3. Make delivery "subsidized not free" — rider gets ₹20 from subscription pool.

### ❌ Loophole 3: Cancellations After Seller Acceptance
**Problem:** Customer cancels after seller accepts but before rider picks up. Seller has prepped the food. You've already started the flow. No revenue collected. But you've sent notifications (Supabase cost), rider was dispatched (fuel). 

**Solution:** 2-minute free cancel window (already implemented). After that: ₹15 cancellation fee (keep ₹10, send ₹5 to seller as prep compensation).

### ❌ Loophole 4: Multi-Shop Orders with Small Cart Each
**Problem:** Customer orders ₹80 from Shop A + ₹80 from Shop B = 2 separate orders, both qualify for small cart fee. But their platform fee is charged once. You have to do 2 rider pickups.

**Solution:** Multi-shop orders → platform fee per sub-order (already charged per shop in DB). Ensure small-cart fee also fires per-shop-subtotal, not total cart.

### ❌ Loophole 5: Pharmacy Low Margin Prescription Items
**Problem:** Generic medicines have razor-thin margins for pharmacies. You charge 5% commission on ₹50 Paracetamol. You earn ₹2.50. Not worth the tech/support overhead.

**Solution:** Pharmacy commission floor = **8%** but add a **₹5 prescription handling surcharge** on verified prescription items. OR pharmacy gets flat 6% (vs. 5%) and you provide free prescription verification service as value-add.

### ❌ Loophole 6: Rider Incentive Spend Not Modeled
**Problem:** During rainy season / night slots, you need surge pay to attract riders. Your code doesn't model this as a cost. During peak hours, you may need to pay riders ₹50–₹80/ride to meet demand, but you collected only ₹25 delivery fee (rider gets ₹20 of it).

**Solution:** Build a **rider surge fund** from 10% of subscription revenue. At ₹99/mo × 1000 subscribers = ₹9,900/mo for surge. Alternatively: add a "surge delivery fee" (₹10–₹20) during peak/rain hours, transparent to customer.

### ❌ Loophole 7: Jewellery 3% GST = High Base, Very Low Commission
**Problem:** A ₹10,000 jewellery order earns you ₹500 (5%) commission. Gateway eats ₹236. You're left with ₹264. But jewellery delivery = HIGH risk (theft/damage), HIGH rider effort. You need insurance.

**Solution:** Jewellery commission = **10–12%**. Add mandatory **item insurance clause** above ₹5,000 (pass-through ₹50–₹100 insurance fee to customer).

### ❌ Loophole 8: Grocery Items with 0% GST = No Tax Revenue
**Problem:** Fresh produce, meat, fish = 0% GST. No tax to leverage. Your 5% commission on a ₹200 veggie order = ₹10. That's fine, but the rider cost (₹20 minimum) wipes out the delivery margin.

**Solution:** These categories **need higher AOV to be profitable**. Set minimum order value = ₹149 for fresh categories. Bundle-suggested checkout ("Add ₹50 more for free delivery") to boost AOV.

### ❌ Loophole 9: Returns/Refunds Not Tracked as Cost
**Problem:** Customer says "food was wrong/cold" → you refund ₹100. You've already paid rider + seller. This is a 100% loss.

**Solution:** 
- Cap refund liability at ₹500/month per customer without proof.
- Require photo evidence for refunds > ₹200.
- Implement seller-funded refund pool (2% of their monthly payout held in escrow).

### ❌ Loophole 10: Subscription Revenue Not Accounting for Rider Cost
**Problem:** Pass Lite (₹49) gives free delivery ≥₹199. If a user places 4 orders/month ≥₹199 with avg ₹25 delivery, you absorb ₹100 in delivery costs for ₹49 revenue.

**Solution:** Raise Lite to ₹79. Free delivery only ≥₹249. Add data: if a user does >6 orders/month under Lite, auto-prompt upgrade to Pro.

---

## 4. Category-Wise Optimal Commission Rates

### Competitor Benchmark:
| Category | Zomato | Swiggy | Blinkit | **Enything (Current)** | **Enything (Recommended)** |
|---|---|---|---|---|---|
| Restaurant/Food | 18–30% | 15–30% | N/A | 5% | **15%** |
| Fast Food | 18–25% | 18–25% | N/A | 5% | **15%** |
| Grocery/Staples | N/A | 12–18% | 5–10% | 5% | **8%** |
| Organic | N/A | 12–18% | 5–10% | 5% | **8%** |
| Pharmacy | N/A | 15–22% | N/A | 5% | **6%** |
| Electronics | N/A | N/A | N/A | 5% | **10%** |
| Clothing/Fashion | N/A | N/A | N/A | 5% | **10%** |
| Jewellery | N/A | N/A | N/A | 5% | **12%** |
| Fruits & Vegs | N/A | 10–15% | 2–8% | 5% | **7%** |
| Dairy/Eggs | N/A | 8–14% | 2–8% | 5% | **6%** |
| Beverages | N/A | 15–20% | 8–12% | 5% | **10%** |
| Salon/Beauty | N/A | 20–28% | 10–15% | 5% | **12%** |
| Pet Supplies | N/A | 15–22% | 15–22% | 5% | **10%** |
| Home Decor | N/A | N/A | N/A | 5% | **8%** |
| Hardware | N/A | N/A | N/A | 5% | **7%** |
| Bakery/Sweets | 18–25% | 15–25% | N/A | 5% | **12%** |

> [!IMPORTANT]
> Even at these HIGHER rates, Enything is still 30–50% cheaper than Zomato/Swiggy for every single category. This IS the core marketing message to sellers: "Same reach, half the cost."

### Why This Works (Revenue Impact):

Assume 100 orders/day across all categories at avg ₹350 AOV:

| Scenario | Avg commission | Daily commission rev | Monthly |
|---|---|---|---|
| All 5% | 5% | ₹1,750 | ₹52,500 |
| Category-wise | ~8.5% avg | ₹2,975 | ₹89,250 |
| **Delta** | +3.5% | **+₹1,225/day** | **+₹36,750/mo** |

At 1,000 orders/day (achievable in a city): **+₹3,67,500 extra per month** just from correcting commission rates.

---

## 5. Full Profitability Model (Corrected Rates)

### With recommended category commissions + ₹15 platform fee + subscriptions:

| Revenue stream | Per 1000 orders/day | Monthly |
|---|---|---|
| Category commissions (avg 8.5%) | ₹2,975/day | ₹89,250 |
| Platform fee net of GST (₹12.71) | ₹12,710/day | ₹3,81,300 |
| Delivery margin (20% of ₹28 avg) | ₹5,600/day | ₹1,68,000 |
| Subscription revenue (5% of users) | — | ₹50,000 |
| **Total Revenue** | | **₹6,88,550/mo** |

| Cost stream | Monthly |
|---|---|
| Rider payouts (80% of delivery) | -₹67,200 |
| Payment gateway (2.36% of GMV) | -₹35,040 |
| GST remittances (S9(5) food) | -₹12,500 |
| Customer support + infra | -₹20,000 |
| Refunds/cancellations (~2%) | -₹10,500 |
| **Total Costs** | **-₹1,45,240** |

| **Net Profit** | **₹5,43,310/mo** | **~23% net margin** |
|---|---|---|

---

## 6. The 7 Profit Maximization Rules

1. **Food = 15% minimum** — you bear their GST burden, so your commission must compensate.
2. **High-value retail (Electronics, Jewellery, Clothing) = 10–12%** — higher basket size, lower frequency → premium commission justified.
3. **Grocery = 8%** — high frequency, low AOV. Volume compensates margin.
4. **Platform fee must be ₹15+ forever** — it's your single most profitable line (near-100% margin).
5. **Delivery minimum = ₹20** even after Pass. Never ₹0 real cost to you — always model rider payout.
6. **No free delivery on restaurant orders via Pass** — food margin too thin. Or charge restaurant 15% to compensate.
7. **Monthly subscription revenue is your moat** — even 500 subscribers × ₹99 = ₹49,500/mo of nearly pure profit (delivery cost already in model).

---

## 7. What to Implement in Code

The `platform_config` table already supports `commission_percent_{Category}` keys. The migration below seeds the recommended rates. **Zero code changes needed** — `PlatformConfigProvider.getCommissionRateForCategory(category)` already reads these.

See the migration: `20260705000001_category_commission_rates.sql`
