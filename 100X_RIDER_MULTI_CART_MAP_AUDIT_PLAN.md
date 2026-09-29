# 100X RIDER MULTI-CART & CROSS-CUSTOMER MAP LIFECYCLE AUDIT & REMEDIATION PLAN

## Document Metadata
- **Author**: 100x Principal Systems Architect (Antigravity Senior Engine)
- **Target Platform**: Delivery Partner App — Master Navigation & Route Map (`OrderRouteMapPage`)
- **Scope**: Multi-Cart Groups (up to 3 concurrent customer checkouts), Multi-Shop Carts (1 to 3 shops per cart), Cross-Customer Drop-off Sequencing, Dynamic TSP Waypoint Routing, Bottom Sheet State Synchronization, and External Google/Apple Maps Launchers.
- **Strict Policy**: 100% Non-destructive / Additive Only. Zero breaking changes to existing order status RPCs or database schemas.

---

## 1. Executive Summary & The Mathematical VRPPD Challenge

When a delivery partner on the Enything platform accepts multiple orders, the system transitions from a simple single-cart model into a **Composite Vehicle Routing Problem with Pickups and Deliveries (VRPPD) with Precedence Constraints**:

```
                                  [ Rider Current Location ]
                                              │
                      ┌───────────────────────┴───────────────────────┐
                      ▼                                               ▼
         [ Physical Shop A ]                             [ Physical Shop B ]
     (Sub-order 1: Cust Alice)                       (Sub-order 2: Cust Alice)
                                                     (Sub-order 3: Cust Bob)  <-- CO-LOCATED!
                      │                                               │
                      └───────────────────────┬───────────────────────┘
                                              │
                      ┌───────────────────────┴───────────────────────┐
                      ▼                                               ▼
         [ Customer Alice Drop-off ]                     [ Customer Bob Drop-off ]
           (Requires: Shop A + B)                          (Requires: Shop B + C)
```

### The 3 Core Architectural Invariants
1. **Invariant 1 (Shop Co-Location & Single-Stop Aggregation)**:
   If two distinct customers order from the same physical shop, the rider MUST NOT visit the shop twice. The map must cluster sub-orders into a single physical stop, display all items to be picked up across both customers, and prevent duplicate identical coordinates from entering route calculation engines.
2. **Invariant 2 (Precedence-Constrained Greedy TSP Sequencing)**:
   - **Pickups First**: The rider must first visit all unpicked shops along an optimal nearest-neighbor path starting from their live GPS coordinates.
   - **Drop-offs Sequence**: Once shops are picked up, customer drop-offs must be sequenced by minimum road distance from the last pickup point, rather than arbitrary array index order.
   - **Dynamic Leg Transition**: When all items for Customer Alice are picked up, Customer Alice's drop-off becomes eligible, dynamically updating the polyline.
3. **Invariant 3 (Multi-Customer UI Parity & Bound Safety)**:
   The bottom sheet carousel MUST provide dedicated tabs for every individual customer drop-off (`Drop 1 (Alice)`, `Drop 2 (Bob)`, `Drop 3 (Charlie)`), complete with customer address, delivery notes, and direct call buttons. Active stop pointers (`_selectedStopIndex`) must be strictly bounds-checked against realtime cancellations to prevent `RangeError` crashes.

---

## 2. Forensic Code Audit & Identified Vulnerabilities

A line-by-line inspection of [`lib/pages/delivery/order_route_map_page.dart`](file:///Users/muhtaashimnazki/Downloads/Enything/lib/pages/delivery/order_route_map_page.dart) and [`lib/pages/delivery/dashboard_page.dart`](file:///Users/muhtaashimnazki/Downloads/Enything/lib/pages/delivery/dashboard_page.dart) reveals 10 critical flaws:

| ID | Location | Critical Flaw | Impact |
|---|---|---|---|
| **F-01** | `order_route_map_page.dart:237-271` | `_effectiveShopStops` maps every active order to a shop stop without deduplicating by shop location. | If Cust 1 and Cust 2 order from Shop B, Shop B appears twice as two distinct stops with jittered overlapping markers. |
| **F-02** | `order_route_map_page.dart:344-345` | `GeoUtils.fetchMultiStopRoute([...shopPts, ...customerPts])` passes duplicate consecutive coordinates when shops overlap. | OSRM routing engine returns HTTP 400 (`InvalidQuery`) or zero-distance loops; polyline fails to render. |
| **F-03** | `order_route_map_page.dart:315-328` | Customer drop-off points (`customerPts`) are appended in arbitrary `widget.groups` array order with zero TSP optimization. | Rider is routed in severe zigzag patterns across town (e.g. 18km detour) instead of nearest-customer-first. |
| **F-04** | `order_route_map_page.dart:1018-1095` | The bottom sheet stop selector only generates tabs for `shops` and ONE single `Customer` tab (`_selectedStopIndex == shops.length`). | Customer 2 and Customer 3 are 100% invisible! Rider cannot see their address, delivery notes, or call them. |
| **F-05** | `order_route_map_page.dart:1100-1270` | Customer details card hardcodes `widget.group` (Customer 1) instead of inspecting the selected customer group. | Rider delivering to Bob is shown Alice's phone number and address. Calling reaches the wrong customer. |
| **F-06** | `order_route_map_page.dart:168-175, 1121` | When an order is cancelled/disputed via Realtime, `_orders` shrinks, but `_selectedStopIndex` is not bounds-clamped. | Throws `RangeError (index): Invalid value: Not in inclusive range` -> Red Screen crash while riding. |
| **F-07** | `order_route_map_page.dart:222-235` | `_isGroupDelivered` returns `true` when `active.isEmpty` (which occurs when all sub-orders are cancelled/disputed). | Cancelled customer orders are mislabeled as "Delivered" on map markers with grey pins. |
| **F-08** | `order_route_map_page.dart:453-463` | `_openInExternalMap` appends duplicate shops to Google Maps `waypoints` and does not TSP-order customer drop-offs. | Google Maps instructs rider to navigate to the same shop twice and navigate drop-offs in sub-optimal order. |
| **F-09** | `order_route_map_page.dart:453-465` | Google Maps URL encodes all unpicked shops + all customer drop-offs without capping. | With 3 carts and up to 3 shops each (9 shops + 3 drops = 12 waypoints), Google Maps rejects URL with error 400. |
| **F-10** | `dashboard_page.dart:2144` | Master Route launcher passes `shops: const []`. | When opening Master Route, `order_route_map_page.dart:260` falls back to `o.items.first.productName` as the shop name. |

---

## 3. Detailed Forensic Breakdown of Each Flaw

### 3.1 Flaw F-01 & F-02: Duplicate Physical Shop Co-Location
In `_effectiveShopStops`:
```dart
// CURRENT VULNERABLE IMPLEMENTATION
List<({double lat, double lng, String name, String status, String? phone})>
    get _effectiveShopStops {
  ...
  return targetOrders.map((o) {
    final matchingShop = widget.shops.firstWhere(...);
    return (
      lat: matchingShop.lat,
      lng: matchingShop.lng,
      name: matchingShop.name,
      status: o.status,
      phone: o.shopPhone,
    );
  }).where((s) => s.lat != 0.0 && s.lng != 0.0).toList();
}
```
**Forensic Trace**:
If Alice has Order 1 from Bakery (`lat: 28.500, lng: 77.200`), and Bob has Order 2 from the same Bakery (`lat: 28.500, lng: 77.200`):
1. `_effectiveShopStops` returns two elements with identical coordinates.
2. In `build()`, markers loop over `shops`: `applyJitter` adds `0.00015` jitter, drawing two separate pins for the same building.
3. In `_fetchRoutes()`:
   ```dart
   final allWaypoints = [...shopPts, ...customerPts];
   final r = await GeoUtils.fetchMultiStopRoute(allWaypoints);
   ```
   `allWaypoints` has `[LatLng(28.500, 77.200), LatLng(28.500, 77.200)]`.
4. `GeoUtils.fetchMultiStopRoute` constructs the OSRM URL:
   `https://router.project-osrm.org/route/v1/driving/77.2,28.5;77.2,28.5;...`
   OSRM fails or generates a 0-meter circular stutter leg.

---

### 3.2 Flaw F-03: Customer Drop-off Sequencing (VRP Precedence Failure)
```dart
// CURRENT VULNERABLE IMPLEMENTATION
final customerPts = (widget.groups != null && widget.groups!.isNotEmpty)
    ? widget.groups!
        .where((g) =>
            !_isGroupDelivered(g) &&
            g.deliveryLat != null &&
            g.deliveryLat != 0.0)
        .map((g) => LatLng(g.deliveryLat!, g.deliveryLng!))
        .toList()
    : ...;
```
**Forensic Trace**:
Suppose the rider has picked up all items at Shop 2.
- Rider current location: Sector 14.
- Customer 1 (Alice): Sector 62 (18 km east).
- Customer 2 (Bob): Sector 15 (1.2 km south of Sector 14).
- Customer 3 (Charlie): Sector 16 (2.5 km south of Sector 14).

Because `widget.groups` holds `[Alice, Bob, Charlie]`, `customerPts` routes:
`Sector 14 -> Alice (18 km) -> Bob (19 km back) -> Charlie (1.5 km)` = **38.5 km total**.
Optimal TSP ordering starting from Sector 14:
`Sector 14 -> Bob (1.2 km) -> Charlie (1.3 km) -> Alice (17 km)` = **19.5 km total**.
**Dead mileage imposed on rider: 19.0 km!**

---

### 3.3 Flaw F-04 & F-05: Missing Multi-Customer Bottom Sheet Tabs & Detail Cards
```dart
// CURRENT VULNERABLE IMPLEMENTATION
// Stop Selector Tabs:
for (int i = 0; i < shops.length; i++) ...[ ... ],
Expanded(
  child: GestureDetector(
    onTap: () => setState(() => _selectedStopIndex = shops.length),
    child: Text('Customer'), // ONLY ONE CUSTOMER TAB!
  ),
),
```
```dart
// Customer Details Card:
Text(widget.group.customerAddress),       // HARDCODED TO CUSTOMER 1!
Text('Note: ${primaryOrder.deliveryNotes}'), // HARDCODED TO CUSTOMER 1!
_call(widget.group.customerPhone),         // CALLS CUSTOMER 1!
```
**Forensic Trace**:
The rider accepts a master route with 3 customers.
They deliver to Customer 1, then proceed to Customer 2.
The rider wants to check Customer 2's apartment number or call Customer 2:
- There is only a single "Customer" tab.
- Tapping "Customer" displays Customer 1's address and phone number!
- The rider has NO way to see Customer 2 or Customer 3's information inside the map! They are forced to exit the map, return to the dashboard, and search through order cards.

---

### 3.4 Flaw F-06: Out-of-Bounds Crash on Realtime Mutation
```dart
// In _subscribeToOrderChanges:
callback: (payload) {
  final updatedOrder = OrderModel.fromMap(payload.newRecord);
  ...
  setState(() { _orders[idx] = updatedOrder; });
  _fetchRoutes(silent: true);
}
```
**Forensic Trace**:
1. Rider is viewing Stop 3 (`_selectedStopIndex = 2`).
2. Shop 2 cancels or customer cancels Order 2.
3. Order 2 status becomes `seller_rejected` or `cancelled`.
4. `_effectiveShopStops` filters out cancelled orders; total shop stops shrinks from 3 to 2.
5. In `build()`:
   ```dart
   if (_selectedStopIndex < shops.length) {
     shops[_selectedStopIndex].name // ACCESSES shops[2] when shops.length == 2!
   }
   ```
6. **Crash**: `RangeError (index): Invalid value: Not in inclusive range 0..1: 2`. The Flutter map crashes and unmounts.

---

### 3.5 Flaw F-07: Cancelled Groups Marked as "Delivered"
```dart
// CURRENT VULNERABLE IMPLEMENTATION
bool _isGroupDelivered(OrderGroup g) {
  final groupOrders = _orders.where(...);
  if (groupOrders.isEmpty) return false;
  final active = groupOrders.where((o) =>
      o.status != 'rejected' &&
      o.status != 'cancelled' &&
      o.status != 'seller_rejected' &&
      o.status != 'partner_rejected' &&
      o.status != 'shop_dispute_cancel');
  if (active.isEmpty) return true; // <-- BUG!
  return active.every((o) => o.status == 'delivered');
}
```
**Forensic Trace**:
If Customer 1's orders are all cancelled by the shops:
`active.isEmpty` is `true`.
The method returns `true`!
In `build()`, marker rendering checks:
`_isGroupDelivered(widget.groups![i]) ? 'Delivered' : 'Drop ${i + 1}'`
Customer 1's marker displays **"Delivered"** in grey instead of being recognized as cancelled!

---

### 3.6 Flaw F-08 & F-09: External Map Waypoint Duplication & Overflow
```dart
// CURRENT VULNERABLE IMPLEMENTATION
final waypoints = <String>[
  ...unpickedShops.map((s) => '${s.lat},${s.lng}'),
  if (allCustomerPts.length > 1)
    ...allCustomerPts.sublist(0, allCustomerPts.length - 1),
];
```
**Forensic Trace**:
1. Unpicked shops from multiple orders at the same shop appear twice in `waypoints`. Google Maps guides the rider to the same location twice in a row.
2. If 3 carts have 3 shops each (9 shops + 2 intermediate drops = 11 waypoints), Google Maps directory URL standard caps at 8–9 waypoints. The URL exceeds character/parameter limits, causing Google Maps to fail with "Directions not found" or HTTP 400.

---

### 3.7 Flaw F-10: Shop Name Discarded in Master Route
```dart
// In dashboard_page.dart:2144
OrderRouteMapPage(
  group: _myGroups.first,
  groups: _myGroups,
  riderLat: _riderLat,
  riderLng: _riderLng,
  shops: const [], // <-- EMPTY LIST!
  isViewOnly: true,
)
```
In `order_route_map_page.dart:260`:
Because `widget.shops` is empty, `matchingShop` falls back to:
`name: o.items.isNotEmpty ? o.items.first.productName : 'Shop'`
The rider sees "Spicy Chicken Burger" as the name of the shop instead of "Burger King"!

---

## 4. 100x Remediation Specifications

### Remediation Architecture Diagram
```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       OrderRouteMapPage State Fortress                      │
├─────────────────────────────────────────────────────────────────────────────┤
│ 1. Unified Shop Stops:                                                      │
│    Cluster target orders by physical location (threshold <= 15m).           │
│    Aggregate sub-orders & items under a single physical shop entity.        │
│                                                                             │
│ 2. Precedence TSP Pathing:                                                  │
│    Rider GPS ──(Greedy Nearest-Neighbor)──> Unpicked Shops Deduplicated     │
│        └──(Greedy Nearest-Neighbor from Last Shop)──> Undelivered Customers │
│                                                                             │
│ 3. Multi-Customer Tabs & Cards:                                             │
│    Tabs: [Shop 1] [Shop 2] ... [Drop 1: Alice] [Drop 2: Bob] [Drop 3: ...] │
│    Details: Dynamic resolution of customer phone, notes, address, & items.  │
│                                                                             │
│ 4. Realtime Mutation Clamping:                                              │
│    _selectedStopIndex = _selectedStopIndex.clamp(0, max(0, totalStops - 1)) │
│                                                                             │
│ 5. Safe External Map Launch:                                                │
│    Deduplicate coordinates; cap waypoints to max 8 immediate upcoming stops.│
└─────────────────────────────────────────────────────────────────────────────┘
```

### Spec 1: Unified Physical Shop Stop Model
Replace the raw flat order-to-shop mapping with a structured, deduplicated model:

```dart
class UnifiedShopStop {
  final double lat;
  final double lng;
  final String name;
  final String? phone;
  final List<OrderModel> orders;

  UnifiedShopStop({
    required this.lat,
    required this.lng,
    required this.name,
    this.phone,
    required this.orders,
  });

  /// Aggregate status:
  /// - 'ready_for_pickup' if any order is ready
  /// - 'preparing' if any order is preparing
  /// - 'confirmed' if any order is confirmed
  /// - 'picked_up' if ALL active orders are picked up
  /// - 'cancelled' if all orders are cancelled
  String get aggregateStatus {
    final active = orders.where((o) => !_isTerminal(o.status)).toList();
    if (active.isEmpty) return 'cancelled';
    if (active.every((o) => o.status == 'picked_up' || o.status == 'out_for_delivery' || o.status == 'delivered')) {
      return 'picked_up';
    }
    if (active.any((o) => o.status == 'ready_for_pickup')) return 'ready_for_pickup';
    if (active.any((o) => o.status == 'preparing')) return 'preparing';
    return active.first.status;
  }

  bool get isPickedUp => aggregateStatus == 'picked_up';
  bool get isCancelled => aggregateStatus == 'cancelled';
}
```

### Spec 2: Precedence-Constrained Greedy TSP Router
1. **Deduplicate Shop Coordinates**:
   Group active orders where `Geolocator.distanceBetween(lat1, lng1, lat2, lng2) < 20.0` or `shopId1 == shopId2`.
2. **Greedy Shop Pickup Order**:
   Start at `riderPos`. Repeatedly find nearest unvisited unpicked shop until all unpicked shops are visited.
3. **Greedy Customer Drop-off Order**:
   Start at the coordinate of the last visited shop (or `riderPos` if all shops were already picked up).
   Filter out customers whose orders are already delivered or entirely cancelled.
   Repeatedly select the nearest unvisited customer drop-off.
4. **Sanitize Coordinates for Routing Engine**:
   Before calling `GeoUtils.fetchMultiStopRoute`, strip any consecutive identical coordinates (`dist < 5m`) to guarantee OSRM/Mapbox never receives zero-distance segments.

### Spec 3: Full Multi-Customer Bottom Sheet Carousel
Generate tabs dynamically:
- For each `UnifiedShopStop i`: Tab label = `shops.length > 1 ? 'Shop ${i + 1}' : 'Shop'`.
- For each active `OrderGroup j`: Tab label = `widget.groups != null && widget.groups!.length > 1 ? 'Drop ${j + 1}' : 'Customer'`.
- Total stops = `unifiedShops.length + activeCustomerGroups.length`.
- Selection handling:
  - If `index < unifiedShops.length`: Render `ShopDetailsCard` listing all items to collect at that shop (grouped by customer name / sub-order ID).
  - If `index >= unifiedShops.length`: Render `CustomerDetailsCard` for `activeCustomerGroups[index - unifiedShops.length]` showing that customer's address, phone, notes, and items from all shops.

### Spec 4: Realtime Cancellation & Status Guard
1. Add `_isGroupCancelled(OrderGroup g)`:
   ```dart
   bool _isGroupCancelled(OrderGroup g) {
     final groupOrders = _ordersForGroup(g);
     if (groupOrders.isEmpty) return true;
     return groupOrders.every((o) => _isTerminal(o.status));
   }
   ```
2. In `_isGroupDelivered(OrderGroup g)`:
   ```dart
   bool _isGroupDelivered(OrderGroup g) {
     final active = _ordersForGroup(g).where((o) => !_isTerminal(o.status)).toList();
     if (active.isEmpty) return false; // NOT delivered if cancelled!
     return active.every((o) => o.status == 'delivered');
   }
   ```
3. In `_subscribeToOrderChanges`:
   When `_orders` is mutated, safely re-clamp `_selectedStopIndex`:
   ```dart
   final totalStops = _unifiedShopStops.length + _activeCustomerGroups.length;
   if (_selectedStopIndex >= totalStops) {
     _selectedStopIndex = math.max(0, totalStops - 1);
   }
   ```

### Spec 5: Safe External Map Launch URL Builder
1. Waypoints = Deduplicated unpicked shop coordinates in TSP order + intermediate undelivered customer drop-offs in TSP order.
2. If total waypoints > 8:
   Cap waypoints to the next 8 immediate stops:
   `safeWaypoints = waypoints.take(8).toList();`
   Google Maps Navigation will successfully launch without HTTP 400 errors.

### Spec 6: Shop Name Propagation in Master Route
In `lib/pages/delivery/dashboard_page.dart:2139`:
Instead of passing `shops: const []`, collect all shops across all active `_myGroups`:
```dart
final allShops = _myGroups.expand((g) {
  final targetOrders = g.activeOrders.isNotEmpty ? g.activeOrders : g.orders;
  return targetOrders.map((o) {
    final info = _shopInfoCache[o.shopId];
    return (
      lat: info?.lat ?? o.shopLat ?? 0.0,
      lng: info?.lng ?? o.shopLng ?? 0.0,
      name: info?.name ?? 'Shop',
    );
  });
}).where((s) => s.lat != 0.0 && s.lng != 0.0).toList();
```
Pass `shops: allShops` to `OrderRouteMapPage`.

---

## 5. Exhaustive Edge-Case Matrix (R-MC-01 to R-MC-10)

| Test ID | Edge Case Scenario | Vulnerability in Legacy Code | 100x Fortified Behavior |
|---|---|---|---|
| **R-MC-01** | **Shared Shop Co-Location**: Customer A and Customer B both order from Shop 1. | 2 identical shop stops generated; consecutive identical coordinates sent to OSRM -> 400 error; jittered overlapping markers. | Orders clustered into 1 `UnifiedShopStop`. 1 marker drawn. Coords deduplicated before routing. Items from both customers shown on single shop card. |
| **R-MC-02** | **Customer Drop-off TSP Reordering**: Customer 1 is 15km away; Customer 2 is 1km away from last shop. | Drop-offs sequenced in raw group list order (`Last Shop -> Cust 1 -> Cust 2`), wasting 14km. | Drop-offs sequenced nearest-neighbor from last shop: `Last Shop -> Cust 2 (1km) -> Cust 1 (15km)`. |
| **R-MC-03** | **Realtime Shop Cancellation Bounds Safety**: Rider views Stop 3 (`_selectedStopIndex = 2`). Shop 2 or 3 cancelled. Total stops shrinks to 2. | `shops[_selectedStopIndex]` throws `RangeError: Index out of range: 2`. Red screen crash while driving. | `_selectedStopIndex` clamped to `math.max(0, totalStops - 1)`. Carousel safely slides to surviving active stop. |
| **R-MC-04** | **Multi-Customer Phone & Address Isolation**: Rider has 3 customer drops. Rider taps "Drop 2" tab. | Legacy map only had 1 "Customer" tab pointing to Customer 1. Rider cannot view Customer 2's notes or call Customer 2. | Dedicated tab `Drop 2` created. Tapping displays Customer 2's address, notes, and calls Customer 2's phone number directly. |
| **R-MC-05** | **Cancelled Customer Marker Mislabeled**: All sub-orders of Customer 1 cancelled by shops. | `_isGroupDelivered` returned `true` because `active.isEmpty`, labeling cancelled order as "Delivered" in grey. | `_isGroupCancelled` returns `true`. Marker is removed from active route or rendered with distinct `Cancelled` badge. |
| **R-MC-06** | **External Map Waypoint Cap Safeguard**: Rider has 3 carts with 3 shops each (9 shops + 3 drops = 12 waypoints). | Google Maps directory URL fails with HTTP 400 Bad Request or "Cannot calculate route". | Waypoints deduplicated and capped to max 8 immediate upcoming stops. External navigation opens reliably. |
| **R-MC-07** | **Master Route Shop Name Preservation**: Rider opens Master Route with `shops: const []`. | Shop names fallback to product names (e.g. "Pepperoni Pizza" instead of "Pizza Hut"). | `dashboard_page.dart` resolves all shops from `_shopInfoCache` across all active groups. Real shop names displayed. |
| **R-MC-08** | **Zero-Distance Coordinate Stripping**: Two consecutive waypoints within 5 meters of each other. | OSRM routing engine returns zero-distance loop or fails routing. | `GeoUtils.fetchMultiStopRoute` sanitizes waypoints, filtering out points within 5m of previous point. |
| **R-MC-09** | **All Orders Cancelled Clean Exit**: Every customer in master route cancels while rider is driving. | Map remains open in zombie state or crashes on null bounds. | Displays clear snackbar "All orders were cancelled", safely pops navigation back to dashboard. |
| **R-MC-10** | **Partial Customer Delivery Leg Advancement**: Customer 1 delivered while Customer 2 still in transit. | Polyline recalculation keeps completed customer in route or breaks sequence. | Delivered customer excluded from remaining delivery polyline; route smoothly connects `Rider -> Customer 2`. |

---

## 6. Implementation & Verification Plan

### Phase 1: Engine Hardening (`lib/pages/delivery/order_route_map_page.dart`)
1. Implement `UnifiedShopStop` clustering logic.
2. Implement Precedence-Constrained Greedy TSP sequencing for pickups and drop-offs.
3. Build the full multi-customer carousel and detail sheet with customer-specific address, notes, items, and phone call actions.
4. Add realtime clamping on `_selectedStopIndex` to prevent `RangeError`.
5. Fix `_isGroupDelivered` and introduce `_isGroupCancelled`.
6. Harden `_openInExternalMap` with deduplication and waypoint capping.

### Phase 2: Dashboard Launcher Enhancement (`lib/pages/delivery/dashboard_page.dart`)
1. In `_openMasterRoute` / Master Route launcher (line 2139), aggregate all shops across all active `_myGroups` using `_shopInfoCache`.

### Phase 3: GeoUtils Sanitization (`lib/utils/geo_utils.dart`)
1. Add duplicate/near-identical coordinate filtering in `fetchMultiStopRoute`.

### Phase 4: Automated Testing (`test/test_100x_dashboards_exhaustive_edge_cases.dart`)
1. Add dedicated test suite `4. 100x Rider Multi-Cart & Multi-Customer Map Lifecycle (R-MC-01 to R-MC-10)`.
2. Run full regression test suite ensuring 100% pass rate.
3. Run `flutter analyze` ensuring 0 warnings and 0 errors.
