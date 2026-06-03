import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import '../models/shop_model.dart';
import '../providers/platform_config_provider.dart';

class DeliveryCalculator {
  /// Max delivery radius — shops beyond this won't be shown.
  static double get maxRadiusKm =>
      PlatformConfigProvider.instance?.maxDeliveryRadiusKm ?? 15.0;

  /// Rate per km — used for both base delivery AND multi-shop surcharge.
  static double get _ratePerKm =>
      PlatformConfigProvider.instance?.deliveryRatePerKm ?? 10.0;

  // ---------------------------------------------------------------------------
  // Base delivery charge (customer ↔ nearest shop)
  // ---------------------------------------------------------------------------

  /// Delivery charge: ceil(distanceKm) × ratePerKm.
  /// Returns -1 if beyond maxRadiusKm.
  static double calculateDeliveryCharges(double distanceKm, double orderValue) {
    if (distanceKm > maxRadiusKm) return -1;
    final km = distanceKm.ceil().clamp(1, maxRadiusKm.ceil().toInt());
    return km * _ratePerKm;
  }

  /// Returns the label string for the delivery charge.
  static String deliveryChargeLabel(double distanceKm, double orderValue) {
    final charge = calculateDeliveryCharges(distanceKm, orderValue);
    if (charge < 0) return 'Out of range';
    return '₹${charge.toStringAsFixed(0)} delivery';
  }

  /// Whether a shop at [distanceKm] is within the delivery zone.
  static bool isWithinRange(double distanceKm) => distanceKm <= maxRadiusKm;

  // ---------------------------------------------------------------------------
  // Haversine distance between two LatLng points (in km)
  // ---------------------------------------------------------------------------
  static double haversineKm(LatLng a, LatLng b) {
    const r = 6371.0; // Earth radius in km
    final dLat = _toRad(b.latitude - a.latitude);
    final dLng = _toRad(b.longitude - a.longitude);
    final sinDLat = math.sin(dLat / 2);
    final sinDLng = math.sin(dLng / 2);
    final h = sinDLat * sinDLat +
        math.cos(_toRad(a.latitude)) *
            math.cos(_toRad(b.latitude)) *
            sinDLng *
            sinDLng;
    return 2 * r * math.asin(math.sqrt(h));
  }

  static double _toRad(double deg) => deg * math.pi / 180;

  // ---------------------------------------------------------------------------
  // Multi-shop surcharge
  // ---------------------------------------------------------------------------

  /// Calculates the extra inter-shop delivery surcharge when a customer orders
  /// from more than one shop.
  ///
  /// **Algorithm**
  /// • Shop 1 — no surcharge (it's the "anchor").
  /// • Shop 2 — distance from shop 1.
  ///   - ≤ 1 km  → ₹7 (minimum flat charge)
  ///   - > 1 km  → ₹7 × ceil(distanceKm)
  /// • Shop 3, 4, … — distance from the **nearest** already-visited shop
  ///   (greedy nearest-neighbour), same rate as above.
  ///
  /// [shops] must be in the order they were added to the cart (first shop first).
  /// Returns 0 if there is only one shop.
  static double calculateMultiShopSurcharge(List<ShopModel> shops) {
    if (shops.length <= 1) return 0;

    double total = 0;
    // "visited" starts with just the first shop
    final visited = <ShopModel>[shops.first];

    for (int i = 1; i < shops.length; i++) {
      final candidate = shops[i];

      // Find the minimum distance from this shop to any already-visited shop
      double minDist = double.infinity;
      for (final v in visited) {
        final d = haversineKm(candidate.location, v.location);
        if (d < minDist) minDist = d;
      }

      // Charge: minimum ₹7, then ₹7 per km (ceiling)
      final chargeForShop = _ratePerKm * math.max(1, minDist.ceil());
      total += chargeForShop;

      visited.add(candidate);
    }

    return total;
  }

  // ---------------------------------------------------------------------------
  // Legacy overload kept for backward compatibility
  // (pass raw distances if you already have them)
  // ---------------------------------------------------------------------------
  @Deprecated('Use calculateMultiShopSurcharge(List<ShopModel>) instead')
  static double calculateMultiShopSurchargeFromDistances(
      List<double> interShopDistances) {
    double total = 0;
    for (double d in interShopDistances) {
      total += _ratePerKm * math.max(1, d.ceil());
    }
    return total;
  }

  static int estimatedDeliveryTime(double distance, int prepTimeMinutes) {
    const deliverySpeed = 25.0;
    final travelMins = (distance / deliverySpeed * 60).ceil();
    return prepTimeMinutes + travelMins;
  }
}
