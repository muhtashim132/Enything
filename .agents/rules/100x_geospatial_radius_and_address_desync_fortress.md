# 100x Geospatial Radius & Address Desync Fortress

## Context & Architecture
When users (including admins switching roles to customers) are outside the operational delivery radius (e.g. located in Bemina, Srinagar, ~60km away from Bandipora), the Customer Home feed must strictly enforce the platform delivery radius (`DeliveryCalculator.maxRadiusKm`, default 15km). The app must never display stores or products from distant hubs, must never desynchronize address text from GPS coordinates, and must never show conflicting badge counters (e.g. `(0)` when items exist).

## Inviolable Rules & Remediation Protocols

1. **Atomic Coordinate & Address Text Synchronization**:
   - In `LocationProvider`, `_currentAddress` text and `_currentLocation` (LatLng) must update atomically.
   - Never call `setLocalAddressDetails` with address text without updating `_currentLocation`.
   - In `profile_settings_dialogs.dart`, saving an address calls `locProv.selectSavedAddress(addr)` to activate both address and coordinates simultaneously.

2. **Apple Reviewer Demo Protection**:
   - The 50km auto-select bypass in `LocationProvider.loadSavedAddresses()` is strictly restricted to Apple Reviewer demo test credentials (`_isAppleReviewerAccount()` checking `999999999X` / `9876500000`).
   - Real customers, sellers, and admins located > 50km away in Srinagar or elsewhere must NEVER have their GPS location hijacked to Bandipora.

3. **Missing Coordinate Self-Healing Geocoder**:
   - In `LocationProvider.selectSavedAddress()`, `addSavedAddress()`, and `updateSavedAddress()`, if an address has `!hasValidCoordinates` (`lat == 0 || lng == 0`), the system triggers forward-geocoding via OpenStreetMap Nominatim, sets `_currentLocation`, and backfills coordinates to `saved_addresses`.

4. **Zero-Leak Geospatial Early Return & Cache Purging**:
   - In `CustomerHomeViewState._loadAllData()`, if `nearby.isEmpty` (no shops within delivery radius), immediately purge static memory caches (`_cachedShops`, `_cachedProducts`, `_cachedProductShops`, `_cachedDepartmentProductCounts`), clear state (`_shops = []`, `_products = []`), and exit immediately.
   - Never invoke `get_feed_products` or cosmetic backfills when `nearby.isEmpty`.

5. **Static Memory Cache Invalidation on Role Switch**:
   - Switching roles (Admin -> Customer, Rider -> Customer, Seller -> Customer) in `RoleSwitcherCard` must invoke `CustomerHomeView.invalidateStaticCache()` and `LocationProvider.checkLocationOnResume()`.
   - Never allow static in-memory shop/product caches from other sessions to survive across role changes.

6. **Multi-Department Product Counter Parity**:
   - In `_fetchDepartmentTotalCounts`, department products must be counted across all active nearby shops (`allNearbyShopIds`) matching `inFilter('category', categories)` to include omnibus stores (supermarkets, hypermarkets, departmental stores).
   - All department section headers must wrap the count badge with `math.max(_departmentProductCounts[dept] ?? 0, products.length)` to guarantee a section with products never displays `(0)`.

7. **Delivery Radius Distance Pill Suppression**:
   - In `ProductCard`, if `d < 0 || !DeliveryCalculator.isWithinRange(d)`, suppress the distance chip (`return const SizedBox.shrink()`). Never display distance chips for out-of-range items.

8. **Unserviceable Zone UI with One-Tap Relocation**:
   - When no shops are within radius (`_buildNoShopsNearby`), render a dedicated unserviceable zone screen showing the user's current address badge, explanation of the 15km hub radius, a prominent `"Change Location"` button opening `showAddressPickerSheet(context)`, and a `"Recheck GPS"` button.

