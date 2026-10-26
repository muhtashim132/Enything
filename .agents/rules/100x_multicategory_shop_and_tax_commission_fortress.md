# 100x Multi-Category Store, Tax & Commission Fortress

All AI models and developers working on this project MUST adhere to the architecture, edge cases, and remediation protocols for omnibus multi-department stores, cross-category commission, and statutory tax splits:

1. **Omnibus Multi-Department Recognition**: Any store with category containing `Supermarket`, `Hypermarket`, `Supermart`, `Departmental Store`, `General Store`, `Provision Store`, or `Kirana` is detected via `AppCategories.isOmnibusStoreCategory(cat)`. They are permitted to carry and sell items across all departments (Food, Grocery, Perishables, Retail, Cosmetics, Stationery, Electronics, Clothing, etc.).
2. **Item-Level Commission Fallback Hierarchy**: In `place_orders_transaction` (Migration 161 & 163) and `OrderTaxBreakdown.calculate`:
   - Commission is evaluated dynamically per item using the fallback chain: `Product Category Commission` -> `Shop Base Commission` -> `Platform Default Commission (5.0%)`.
   - Shop base category (`v_shop_category`) and commission (`v_shop_comm`) are strictly preserved before the item loop to prevent product loop state overwriting.
   - All category lookups in SQL and Dart MUST execute `TRIM()` to prevent whitespace mismatches against `platform_config` keys.
3. **Statutory GST Slabs & Section 9(5) Remittance Split**:
   - Items carry applicable GST rates: 0% for fresh produce, 5% for grocery/dairy/packaged food, 18% for cosmetics/electronics/services, price-tiered for clothing/footwear (≤₹2500 @ 5%, >₹2500 @ 18%).
   - Section 9(5) deemed-supplier food GST is collected and directly remitted by Enything.
   - Non-food retail GST is passed through to the seller's bank account (`order.nonFoodGstAmount`) for the seller to remit in GSTR-3B.
4. **Statutory Withholdings Precision**:
   - GST TCS (§52 CGST Act): 0.5% applied exclusively to taxable goods. Exempt supplies (0% fresh produce) and Section 9(5) food have 0.0% TCS.
   - IT TDS (§194-O): 0.1% applied uniformly across all categories on gross item base subtotal.
5. **Seller Payout Transparency**:
   - Seller order cards in `seller_orders_page.dart` display both the order total and the exact Net Bank Payout (`order.sellerPayout`), calculated as `Base Price + Non-Food GST Passthrough - Platform & Gateway Commission - TCS - TDS`.
   - Expanding the order card presents an itemized breakdown of base subtotal, GST passthrough, deductions, and net bank deposit.
6. **Category-Agnostic Store Presentation**:
   - In `restaurant_dashboard_page.dart`, placeholder icons dynamically resolve using `AppCategories.getCategoryEmoji(category)` (`🏬` for Supermarkets, `💊` for Pharmacy, `💄` for Cosmetics) instead of hardcoded food emojis.
   - Store section title dynamically adapts: `"Aisles & Departments"` for omnibus stores, `"Products & Catalog"` for retail, and `"Menu"` for restaurants.
7. **Omnibus Store Category Exploration & Discovery**:
   - In `category_products_page.dart` and `all_listings_page.dart`, omnibus stores browsing specialty categories (e.g. Cosmetics) display only products matching that specialty category, preventing grocery leakage into specialty aisles.
8. **Auto Product Upload Multi-Department Classification Guard**:
   - In `scripts/auto_upload/engine.py`, `build_product_payload` never sets `category = "Supermarket / Hypermarket"`. For omnibus stores, `classify_department_category` automatically classifies items into their true AppCategories department (`Dairy & Eggs`, `Fruits & Vegs`, `Cosmetics & Beauty`, `Beverages`, `Bakery`, `Electronics`, `Pharmacy`, `Grocery`) ensuring item-level GST slabs and commissions compute accurately.
9. **Remote Live Search Category Isolation Guard**:
   - In `CategoryProductsPage._performLiveProductSearch`, products returned from omnibus supermarket stores are strictly filtered against the current category subcategories, preventing cross-category products from leaking into live search results.
10. **Customer Interactive Statutory Tax Breakdown Sheet**:
   - In `checkout_page.dart` and `track_order_page.dart`, tapping `Taxes & GST` opens an itemized modal sheet displaying:
     - Exact product tax slabs (`taxableByRate` and `gstByRate`: 0% exempt produce, 5% food/grocery, 18% cosmetics/electronics).
     - Delivery service GST (18%) and Handling fee GST (18%).
     - Statutory remittance split: Section 9(5) food GST remitted by Enything vs. merchant GST passed through to seller for GSTR-3B compliance.
