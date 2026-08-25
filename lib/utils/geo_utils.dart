import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// 100x Geographic, Navigation & Routing Utilities for Live Order & Rider Tracking
class GeoUtils {
  // In-memory LRU route cache to prevent redundant HTTP requests for identical routes
  static final Map<String, List<LatLng>> _routeCache = {};
  static const int _kMaxCacheEntries = 60;

  /// Calculates compass bearing (heading in degrees from 0 to 360) between two coordinates.
  /// Used for smoothly rotating the delivery rider's icon along the trajectory.
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

  /// Smooth shortest-path angle interpolation between two angles in degrees [0, 360).
  static double lerpAngle(double from, double to, double t) {
    double diff = (to - from) % 360.0;
    if (diff > 180.0) diff -= 360.0;
    if (diff < -180.0) diff += 360.0;
    return (from + diff * t) % 360.0;
  }

  /// Linear interpolation between two coordinates.
  static LatLng lerpLatLng(LatLng from, LatLng to, double t) {
    return LatLng(
      from.latitude + (to.latitude - from.latitude) * t,
      from.longitude + (to.longitude - from.longitude) * t,
    );
  }

  /// Computes a geographic bounding box enclosing all provided coordinates with optional padding.
  /// Used to auto-fit the map camera viewport to show Shop, Customer, and Rider simultaneously.
  static LatLngBounds? computeBounds(List<LatLng> points,
      {double paddingFactor = 0.005}) {
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

  /// Calculates total route polyline distance in kilometers.
  static double calculateRouteDistanceKm(List<LatLng> points) {
    if (points.length < 2) return 0.0;
    double km = 0.0;
    for (int i = 1; i < points.length; i++) {
      km += Geolocator.distanceBetween(
            points[i - 1].latitude,
            points[i - 1].longitude,
            points[i].latitude,
            points[i].longitude,
          ) /
          1000.0;
    }
    return km;
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

  /// Estimates travel time given distance and average speed (default 22 km/h city delivery speed).
  static String estimateTravelTime(double distanceKm,
      {double avgSpeedKmh = 22.0}) {
    if (distanceKm <= 0.05) return '< 1 min';
    final mins = ((distanceKm / avgSpeedKmh) * 60).round();
    if (mins < 1) return '< 1 min';
    return '$mins min';
  }

  /// Multi-provider road routing engine with seamless fallback:
  /// 1. OSRM Public Routing (real turn-by-turn road curves, no API key needed)
  /// 2. Mapbox Directions API (if MAPBOX_TOKEN present in .env)
  /// 3. OpenRouteService API (if ORS_API_KEY present in .env)
  /// 4. Direct geodesic line fallback
  static Future<List<LatLng>> fetchRoadRoute(LatLng from, LatLng to) async {
    final cacheKey =
        '${from.latitude.toStringAsFixed(4)},${from.longitude.toStringAsFixed(4)}->'
        '${to.latitude.toStringAsFixed(4)},${to.longitude.toStringAsFixed(4)}';

    if (_routeCache.containsKey(cacheKey)) {
      return List<LatLng>.from(_routeCache[cacheKey]!);
    }

    // 1. Primary Engine: High-speed OSRM Public Driving Router
    try {
      final osrmUrl = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
        '?overview=full&geometries=geojson',
      );

      final resp = await http.get(osrmUrl).timeout(const Duration(seconds: 7));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final routes = data['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final geometry = routes.first['geometry'] as Map<String, dynamic>;
          final coords = geometry['coordinates'] as List;
          final polyline = coords
              .map((c) => LatLng(
                    (c[1] as num).toDouble(),
                    (c[0] as num).toDouble(),
                  ))
              .toList();

          if (polyline.isNotEmpty) {
            _cacheRoute(cacheKey, polyline);
            return polyline;
          }
        }
      }
    } catch (e) {
      debugPrint('OSRM routing fallback: $e');
    }

    // 2. Secondary Engine: Mapbox Directions API (if configured)
    try {
      final mapboxToken = dotenv.maybeGet('MAPBOX_TOKEN') ?? '';
      if (mapboxToken.isNotEmpty && mapboxToken.startsWith('pk.')) {
        final mapboxUrl = Uri.parse(
          'https://api.mapbox.com/directions/v5/mapbox/driving/'
          '${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
          '?geometries=geojson&access_token=$mapboxToken',
        );

        final resp =
            await http.get(mapboxUrl).timeout(const Duration(seconds: 7));
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          final routes = data['routes'] as List?;
          if (routes != null && routes.isNotEmpty) {
            final geometry = routes.first['geometry'] as Map<String, dynamic>;
            final coords = geometry['coordinates'] as List;
            final polyline = coords
                .map((c) => LatLng(
                      (c[1] as num).toDouble(),
                      (c[0] as num).toDouble(),
                    ))
                .toList();

            if (polyline.isNotEmpty) {
              _cacheRoute(cacheKey, polyline);
              return polyline;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Mapbox routing fallback: $e');
    }

    // 3. Tertiary Engine: OpenRouteService API (if configured)
    try {
      final orsKey = dotenv.maybeGet('ORS_API_KEY') ?? '';
      if (orsKey.isNotEmpty) {
        final orsUrl = Uri.parse(
          'https://api.openrouteservice.org/v2/directions/driving-car'
          '?api_key=$orsKey'
          '&start=${from.longitude},${from.latitude}'
          '&end=${to.longitude},${to.latitude}',
        );

        final resp = await http.get(orsUrl).timeout(const Duration(seconds: 7));
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          final features = data['features'] as List?;
          if (features != null && features.isNotEmpty) {
            final geometry = features.first['geometry'] as Map<String, dynamic>;
            final coords = geometry['coordinates'] as List;
            final polyline = coords
                .map((c) => LatLng(
                      (c[1] as num).toDouble(),
                      (c[0] as num).toDouble(),
                    ))
                .toList();

            if (polyline.isNotEmpty) {
              _cacheRoute(cacheKey, polyline);
              return polyline;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('ORS routing fallback: $e');
    }

    // 4. Fallback: Direct straight-line connection
    final fallbackLine = [from, to];
    return fallbackLine;
  }

  /// Connects multiple waypoints sequentially along the road network.
  /// Used for multi-stop delivery journeys (Rider -> Shop 1 -> Shop 2 -> Customer).
  static Future<List<LatLng>> fetchMultiStopRoute(
      List<LatLng> waypoints) async {
    if (waypoints.length < 2) return waypoints;

    // Try multi-point OSRM first for unified geometry
    try {
      final coordString =
          waypoints.map((p) => '${p.longitude},${p.latitude}').join(';');
      final osrmUrl = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/$coordString?overview=full&geometries=geojson',
      );

      final resp = await http.get(osrmUrl).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final routes = data['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final geometry = routes.first['geometry'] as Map<String, dynamic>;
          final coords = geometry['coordinates'] as List;
          return coords
              .map((c) => LatLng(
                    (c[1] as num).toDouble(),
                    (c[0] as num).toDouble(),
                  ))
              .toList();
        }
      }
    } catch (_) {}

    // Segment by segment fallback
    final fullPolyline = <LatLng>[];
    for (int i = 0; i < waypoints.length - 1; i++) {
      final seg = await fetchRoadRoute(waypoints[i], waypoints[i + 1]);
      if (fullPolyline.isNotEmpty && seg.isNotEmpty) {
        fullPolyline.addAll(seg.skip(1));
      } else {
        fullPolyline.addAll(seg);
      }
    }
    return fullPolyline;
  }

  static void _cacheRoute(String key, List<LatLng> route) {
    if (_routeCache.length >= _kMaxCacheEntries) {
      _routeCache.remove(_routeCache.keys.first);
    }
    _routeCache[key] = route;
  }

  static double _toRad(double deg) => deg * math.pi / 180.0;
  static double _toDeg(double rad) => rad * 180.0 / math.pi;
}
