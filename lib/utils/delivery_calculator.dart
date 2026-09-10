import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import '../models/shop_model.dart';
import '../config/payment_config.dart';
import '../providers/platform_config_provider.dart';

class DeliveryCalculator {
  /// Max delivery radius — shops beyond this won't be shown.
  static double get maxRadiusKm =>
      PlatformConfigProvider.instance?.maxDeliveryRadiusKm ?? 15.0;

  /// Rate per km — used for both base delivery AND multi-shop surcharge.
  static double get _ratePerKm =>
      PlatformConfigProvider.instance?.deliveryRatePerKm ??
      PaymentConfig.deliveryRatePerKm;

  /// Flat base delivery fee per cart/order (covers 1-3 shops in cart)
  static double get flatDeliveryFee =>
      PlatformConfigProvider.instance?.deliveryBaseFee ??
      PaymentConfig.deliveryFee;

  // ---------------------------------------------------------------------------
  // Base delivery charge (customer ↔ nearest shop)
  // ---------------------------------------------------------------------------

  /// Dynamic per-km delivery charge: ceil(distanceKm) * ratePerKm, with flatDeliveryFee as floor.
  /// Returns -1 if beyond maxRadiusKm.
  static double calculateDeliveryCharges(double distanceKm, double orderValue) {
    if (distanceKm > maxRadiusKm) return -1;
    final km = math.max(1, distanceKm.ceil());
    return math.max(flatDeliveryFee, km * _ratePerKm);
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

  /// Distance-based Multi-Shop Surcharge:
  /// • 1 shop: ₹0
  /// • 2 shops: Leg 0->1 surcharge = max(1, ceil(dist(Shop 1, Shop 2))) * ratePerKm
  /// • 3 shops: Leg 1->2 surcharge = max(1, ceil(dist(Shop 2, Shop 3))) * ratePerKm
  /// Returns the sum of all inter-shop leg surcharges.
  static double calculateMultiShopSurcharge(List<ShopModel> shops) {
    if (shops.length <= 1) return 0.0;
    double total = 0.0;
    for (int i = 0; i < shops.length - 1; i++) {
      final d = haversineKm(shops[i].location, shops[i + 1].location);
      final km = math.max(1, d.ceil());
      total += km * _ratePerKm;
    }
    return total;
  }

  /// Returns individual leg surcharges per shop index in cart order:
  /// Index 0 (Shop 1): 0.0
  /// Index 1 (Shop 2): max(1, ceil(dist(Shop 1, Shop 2))) * ratePerKm
  /// Index 2 (Shop 3): max(1, ceil(dist(Shop 2, Shop 3))) * ratePerKm
  static List<double> calculateLegSurcharges(List<ShopModel> shops) {
    if (shops.isEmpty) return [];
    final surcharges = <double>[0.0];
    for (int i = 0; i < shops.length - 1; i++) {
      final d = haversineKm(shops[i].location, shops[i + 1].location);
      final km = math.max(1, d.ceil());
      surcharges.add(km * _ratePerKm);
    }
    return surcharges;
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

  // ---------------------------------------------------------------------------
  // ETA helpers — Swiggy/Zomato-style formatted delivery time
  // ---------------------------------------------------------------------------

  /// Returns the raw ETA in minutes:
  ///   prepTimeMinutes + ceil(distanceKm / 25 km/h * 60)
  static int etaMinutes(double distanceKm, int prepTimeMinutes) {
    const deliverySpeed = 25.0; // km/h average urban rider speed
    final travelMins = (distanceKm / deliverySpeed * 60).ceil();
    return prepTimeMinutes + travelMins;
  }

  /// Returns a display-ready ETA string like Swiggy/Zomato:
  ///   < 20 min  → "15–20 mins"
  ///   20–60 min → "25–35 mins"
  ///   > 60 min  → "1 hr 10 mins"
  static String etaLabel(double distanceKm, int prepTimeMinutes) {
    final mins = etaMinutes(distanceKm, prepTimeMinutes);
    if (mins <= 0) return '< 5 mins';
    if (mins <= 5) return 'Under 5 mins';

    // Show a ±5 min range, same as Zomato
    final lo = (mins ~/ 5) * 5;
    final hi = lo + 10;

    if (hi > 90) return '90+ mins';

    if (hi >= 60) {
      final h = hi ~/ 60;
      final m = hi % 60;
      return m == 0 ? '$h hr' : '$h hr $m mins';
    }
    return '$lo–$hi mins';
  }

  /// Returns the estimated arrival clock time as a string, e.g. "4:35 PM".
  /// [fromNow] defaults to [DateTime.now()].
  static String etaArrivalTime(double distanceKm, int prepTimeMinutes,
      {DateTime? fromNow}) {
    final mins = etaMinutes(distanceKm, prepTimeMinutes);
    final arrival = (fromNow ?? DateTime.now()).add(Duration(minutes: mins));
    final h = arrival.hour > 12
        ? arrival.hour - 12
        : (arrival.hour == 0 ? 12 : arrival.hour);
    final m = arrival.minute.toString().padLeft(2, '0');
    final ampm = arrival.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }
}
