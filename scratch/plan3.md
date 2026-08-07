# Analysis of User's Bug Report
The user provided a screenshot of the "Partial Order Rejection" state where Shop 1 is cancelled and Shop 2 is active.
In this state, the UI shows:
- Delivery Fee: ₹40 (This is the TOTAL delivery fee of the original cart).
- Handling Fee: ₹33.90 (This is the TOTAL handling fee of BOTH shops).
- Multi-shop fee: NOT PRESENT (My previous fix successfully dropped this to 0!).

The bug is that `reallocate_cancelled_delivery_fees` is FORCING the active order to absorb ALL fees from the cancelled order, including `platform_fee`, `small_cart_fee`, and `heavy_order_fee`.
Since Handling Fee is strictly calculated PER SHOP (e.g., ₹16.95/shop), if one shop cancels, the Handling Fee MUST drop to ₹16.95. By forcing the active shop to absorb it, we are overcharging the customer by ₹16.95 for a shop they aren't even buying from.

# Plan
Update `reallocate_cancelled_delivery_fees` to ONLY absorb `delivery_charges` (to protect the rider's wages for the max distance travelled).
It should NOT absorb `platform_fee`, `small_cart_fee`, or `heavy_order_fee`. Those fees for the cancelled order should be fully refunded to the customer.
