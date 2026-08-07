# Plan

1. Update `lib/pages/customer/checkout_page.dart` to include `multi_shop_surcharge`, `small_cart_fee`, and `heavy_order_fee` in `grand_total_collected`.
2. Create migration `20290000000027_100x_ultimate_dynamic_reallocation_fix.sql`:
   - Update `place_orders_transaction` to correctly calculate `v_expected_grand_total` including those 3 fees.
   - Update `reallocate_cancelled_delivery_fees` to dynamically recalculate and re-distribute ALL fees (`platform_fee`, `delivery_charges`, `small_cart_fee`, `heavy_order_fee`, `multi_shop_surcharge`) proportionally among active orders.
   - Set the cancelled order's `grand_total_collected` to EXACTLY `v_available_pool - SUM(new_active_grand_totals)` to guarantee a mathematically perfect refund via Razorpay without any Enything wage theft or revenue leakage.
