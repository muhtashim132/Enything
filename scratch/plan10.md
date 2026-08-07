# Investigate the UI values
The user sees:
- Multi-shop fee: +₹1
- Handling Fee: ₹0.91

If `Multi-shop fee` is 1, and `Handling Fee` is 0.91, this means `_computeGroupMultiShopSurcharge()` = `1.0` (or rounds to 1).
And `_computeGroupPlatformFee() - _computeGroupGstPlatform()` = `0.91`.

How can `platformFee` be `1.07` in the DB?
How can `multi_shop_surcharge` be `1` in the DB?
I need to query the `orders` table directly using dart to see EXACTLY what was inserted!
