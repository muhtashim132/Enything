# Delivery Fee Overcharging Bug Analysis
The user pointed out that the Delivery Fee should be ₹20 (for 500m), but the UI showed ₹40.
I discovered that the `delivery_charges` column in the database is actually a **bundled** field containing:
`baseDelivery + multi_shop_surcharge + small_cart_fee + heavy_order_fee`.

When `reallocate_cancelled_delivery_fees` calculates `v_total_cart_delivery`, it gets the sum of this bundled field (e.g., ₹20 base + ₹20 surcharge = ₹40).
Then it does `v_new_del = v_total_cart_delivery * v_prop`, which forces the new active order's `delivery_charges` to be ₹40.
It also correctly sets `multi_shop_surcharge = 0`.
Because the UI subtracts `multi_shop_surcharge` from `delivery_charges` to display the "Delivery Fee", it does: `₹40 - ₹0 = ₹40`!
The ₹20 surcharge was mathematically "trapped" inside the `delivery_charges` field, causing the customer to still pay it, completely hidden as a delivery fee!

# Plan to Fix
Update `reallocate_cancelled_delivery_fees` to:
1. Extract the `pure_base_delivery` by subtracting the sum of all surcharges, small cart fees, and heavy order fees from the total `delivery_charges`.
2. Construct the `v_new_del` by taking the `pure_base_delivery * v_prop`, and ADDING BACK the `v_new_surcharge`, `rec.small_cart_fee`, and `rec.heavy_order_fee`.
3. This ensures the bundled `delivery_charges` column perfectly reflects the newly reduced surcharge without trapping the cancelled fee.
