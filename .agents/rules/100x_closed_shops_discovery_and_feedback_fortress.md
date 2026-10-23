# 100x Forensic Edge-Case Audit & Remediation (Closed Shops & Products Discovery and Non-Clickable Message Fortress)

All AI models and developers working on this project MUST adhere to the architecture, edge cases, and remediation protocols for closed store discovery, product reflection, searchability, and tap interception:

1. **Separation of Platform Status vs Order Acceptance in ShopModel**:
   In `lib/models/shop_model.dart`, `isActive` reflects whether the platform has approved and not suspended the shop (`is_active`). `isAcceptingOrders` reflects whether the merchant or operating schedule currently accepts orders (`is_accepting_orders`). Never merge them as `isActive: (map['is_active'] ?? true) && (map['is_accepting_orders'] ?? true)`. Merging causes closed shops to vanish from customer feeds (`where((s) => s.isActive)`), incorrectly triggering empty states or "Coming Soon". `isOpenRightNow` evaluates: `if (!isActive || !isAcceptingOrders) return false;` along with operating hours.

2. **Geospatial & Search SQL Discovery of Closed Shops**:
   In `supabase/migrations/20290000000150_100x_closed_shops_discovery_and_search_fortress.sql`:
   - `get_nearby_shops`: Removes `s.is_accepting_orders = true` filter. Orders shops by `(s.is_active AND s.is_accepting_orders) DESC, ST_Distance(...) ASC` so open shops are discovered first, followed by closed shops within the radius.
   - `search_shops_geospatial`: Includes closed shops (`is_active = true`), ranked by open status first, allowing customers to search closed merchants normally.
   - `search_products_geospatial`: Soft-deleted products excluded (`p.is_deleted = false`), but includes products from closed shops, ranked by open shop products first.

3. **Open Shop Ranking Priority in Feeds & Listings**:
   In `HomePage` (`lib/pages/customer/home_page.dart`), `CategoryProductsPage` (`lib/pages/customer/category_products_page.dart`), and `AllListingsPage` (`lib/pages/customer/all_listings_page.dart`):
   - Open shops (`s.isOpenRightNow == true`) strictly rank ahead of closed shops in feeds and search results.
   - Products from open shops strictly rank ahead of products from closed shops.
   - A category never renders "Coming Soon" if closed shops exist in the delivery area; closed shops and their products must be visible to reassure customers the store is in their region.

4. **Closed Store Visual Indicator & Tap Interception**:
   - `ShopCard` (`lib/widgets/shop_card.dart`) and `RestaurantShopCard` (`lib/widgets/restaurant_shop_card.dart`): If `!shop.isOpenRightNow`, the card renders a prominent `"CLOSED"` badge and when tapped, intercepts navigation to display `ClosedStoreFeedback.showClosedStoreNotice(context, shopName: ..., openTime: ...)` informing the customer when the store opens.
   - `ProductCard` (`lib/widgets/product_card.dart`) and `ProductSearchCard` (`lib/widgets/product_search_card.dart`): If the parent store is closed, the button displays `"STORE CLOSED"` with a lock icon. Tapping the button or trying to add to cart displays `ClosedStoreFeedback.showClosedStoreNotice`.
   - `ProductDetailSheet` (`lib/widgets/product_detail_sheet.dart`): If the store is closed, the bottom bar renders a disabled `"Shop Currently Closed"` banner with a lock icon, which displays the notice if clicked.

5. **Universal Closed Store Feedback Utility**:
   In `lib/utils/closed_store_feedback.dart`, `ClosedStoreFeedback.showClosedStoreNotice` and `ClosedStoreFeedback.showProductUnavailableNotice` provide standard, debounced floating SnackBars alerting users with clear copy, operating hours, and haptic feedback.
