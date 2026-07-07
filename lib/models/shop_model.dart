import 'dart:typed_data';
import 'package:latlong2/latlong.dart';

class ShopModel {
  final String id;
  final String sellerId;
  final String name;
  final String shopType;
  final String? cuisineType;
  final String? fssaiNumber;
  final int prepTimeMinutes;
  final bool isVegOnly;
  final String? openingHours;
  final String? openTime;
  final String? closeTime;
  final String address;
  final LatLng location;
  final String category;
  final List<String> categories;
  final bool isActive;
  final double rating;
  final int totalReviews;
  final int totalOrders;
  final String? bannerImage;
  double? distanceKm;

  ShopModel({
    required this.id,
    required this.sellerId,
    required this.name,
    required this.shopType,
    this.cuisineType,
    this.fssaiNumber,
    this.prepTimeMinutes = 30,
    this.isVegOnly = false,
    this.openingHours,
    this.openTime,
    this.closeTime,
    required this.address,
    required this.location,
    required this.category,
    required this.categories,
    required this.isActive,
    this.rating = 4.0,
    this.totalReviews = 0,
    this.totalOrders = 0,
    this.bannerImage,
    this.distanceKm,
  });

  factory ShopModel.fromMap(Map<String, dynamic> map) {
    double lat = 0.0, lng = 0.0;
    if (map['location'] != null) {
      try {
        final loc = map['location'];
        if (loc is Map) {
          // Supabase REST API returns geography as GeoJSON:
          // {"type":"Point","coordinates":[longitude, latitude]}
          final coords = loc['coordinates'] as List?;
          if (coords != null && coords.length >= 2) {
            lng = (coords[0] as num).toDouble();
            lat = (coords[1] as num).toDouble();
          }
        } else {
          final str = loc.toString().trim();
          if (str.startsWith('0101000020E6100000')) {
            // Parse EWKB Hex for SRID 4326 Point
            final hex = str.substring(18);
            if (hex.length >= 32) {
              final xHex = hex.substring(0, 16);
              final yHex = hex.substring(16, 32);
              
              double decodeHexDouble(String h) {
                final bytes = <int>[];
                for (int i = 0; i < 16; i += 2) {
                  bytes.add(int.parse(h.substring(i, i + 2), radix: 16));
                }
                final bd = ByteData.view(Uint8List.fromList(bytes).buffer);
                return bd.getFloat64(0, Endian.little);
              }
              
              lng = decodeHexDouble(xHex);
              lat = decodeHexDouble(yHex);
            }
          } else {
            // Fallback: WKT string format "POINT(lng lat)"
            final inner = str.replaceAll('POINT(', '').replaceAll(')', '').trim();
            final parts = inner.split(' ');
            if (parts.length >= 2) {
              lng = double.tryParse(parts[0]) ?? 0.0;
              lat = double.tryParse(parts[1]) ?? 0.0;
            }
          }
        }
      } catch (_) {}
    }

    return ShopModel(
      id: map['id'] ?? '',
      sellerId: map['seller_id'] ?? '',
      name: map['name'] ?? '',
      shopType: map['shop_type'] ?? 'shop',
      cuisineType: map['cuisine_type'],
      fssaiNumber: map['fssai_number'],
      prepTimeMinutes: map['prep_time_minutes'] ?? 30,
      isVegOnly: map['is_veg_only'] ?? false,
      openingHours: map['opening_hours'],
      openTime: map['open_time']?.toString().substring(0, 5), // e.g., '09:00' from '09:00:00'
      closeTime: map['close_time']?.toString().substring(0, 5),
      address: map['address'] ?? '',
      location: LatLng(lat, lng),
      category: map['category'] ??
          (map['categories'] != null && (map['categories'] as List).isNotEmpty
              ? map['categories'][0]
              : 'Other'),
      categories: List<String>.from(map['categories'] ?? []),
      isActive: (map['is_active'] ?? true) && (map['is_accepting_orders'] ?? true),
      rating: (map['average_rating'] ?? map['rating'] ?? 0.0).toDouble(),
      totalReviews: map['total_reviews'] ?? 0,
      totalOrders: map['total_orders'] ?? 0,
      bannerImage: map['banner_url'] ?? map['banner_image'],
    );
  }

  bool get isOpenRightNow {
    if (!isActive) return false;
    if (openTime == null || closeTime == null) return isActive;
    
    try {
      final now = DateTime.now();
      final openParts = openTime!.split(':');
      final closeParts = closeTime!.split(':');
      if (openParts.length < 2 || closeParts.length < 2) return isActive;
      
      final openH = int.parse(openParts[0]);
      final openM = int.parse(openParts[1]);
      final closeH = int.parse(closeParts[0]);
      final closeM = int.parse(closeParts[1]);
      
      final nowMinutes = now.hour * 60 + now.minute;
      final openMinutes = openH * 60 + openM;
      final closeMinutes = closeH * 60 + closeM;
      
      if (closeMinutes < openMinutes) {
        // Night shift
        return (nowMinutes >= openMinutes || nowMinutes <= closeMinutes);
      } else {
        // Normal shift
        return (nowMinutes >= openMinutes && nowMinutes <= closeMinutes);
      }
    } catch (_) {
      return isActive;
    }
  }
}
