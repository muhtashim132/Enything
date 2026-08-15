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
      PlatformConfigProvider.instance?.deliveryRatePerKm ?? 10.0;

  /// Flat base delivery fee per cart/order (covers 1-3 shops in cart)
  static double get flatDeliveryFee =>
      PlatformConfigProvider.instance?.deliveryBaseFee ??
      PaymentConfig.deliveryFee;

  // ---------------------------------------------------------------------------
  // Base delivery charge (customer ↔ nearest shop)
  // ---------------------------------------------------------------------------

  /// Flat delivery charge per order/cart: flatDeliveryFee (₹20 default).
  /// Returns -1 if beyond maxRadiusKm.
  static double calculateDeliveryCharges(double distanceKm, double orderValue) {
    if (distanceKm > maxRadiusKm) return -1;
    return flatDeliveryFee;
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

  /// Multi-shop surcharge:
  /// • 1 shop: ₹0
  /// • 2+ shops: multiShopSurcharge (default ₹20.0 from Admin) per additional shop.
  static double calculateMultiShopSurcharge(List<ShopModel> shops) {
    if (shops.length <= 1) return 0.0;
    final ratePerExtraShop =
        PlatformConfigProvider.instance?.multiShopSurcharge ?? 20.0;
    return ratePerExtraShop * (shops.length - 1);
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
