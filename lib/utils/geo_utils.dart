import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';

/// 100x Geographic & Map Utilities for Live Order & Rider Tracking
class GeoUtils {
  /// Calculates compass bearing (heading in degrees from 0 to 360) between two coordinates.
  /// Used for smoothly rotating the delivery rider's bike icon along the trajectory.
  static double calculateBearing(LatLng from, LatLng to) {
    final lat1 = _toRad(from.latitude);
    final lon1 = _toRad(from.longitude);
    final lat2 = _toRad(to.latitude);
    final lon2 = _toRad(to.longitude);

    final dLon = lon2 - lon1;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    final rad = math.atan2(y, x);
    final deg = _toDeg(rad);
    return (deg + 360.0) % 360.0;
  }

  /// Computes a geographic bounding box enclosing all provided coordinates with optional padding.
  /// Used to auto-fit the map camera viewport to show Shop, Customer, and Rider simultaneously.
  static LatLngBounds? computeBounds(List<LatLng> points, {double paddingFactor = 0.005}) {
    if (points.isEmpty) return null;
    if (points.length == 1) {
      final p = points.first;
      return LatLngBounds(
        LatLng(p.latitude - paddingFactor, p.longitude - paddingFactor),
        LatLng(p.latitude + paddingFactor, p.longitude + paddingFactor),
      );
    }

    double minLat = double.infinity;
    double maxLat = -double.infinity;
    double minLng = double.infinity;
    double maxLng = -double.infinity;

    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    return LatLngBounds(
      LatLng(minLat - paddingFactor, minLng - paddingFactor),
      LatLng(maxLat + paddingFactor, maxLng + paddingFactor),
    );
  }

  /// Formats distance in km to user-friendly string (e.g. "450 m" or "3.2 km").
  static String formatDistance(double distanceKm) {
    if (distanceKm <= 0) return '0 m';
    if (distanceKm < 1.0) {
      final meters = (distanceKm * 1000).round();
      return '$meters m';
    }
    return '${distanceKm.toStringAsFixed(1)} km';
  }

  static double _toRad(double deg) => deg * math.pi / 180.0;
  static double _toDeg(double rad) => rad * 180.0 / math.pi;
}
