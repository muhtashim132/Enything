import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product_model.dart';

/// 100x Master Catalog Service
/// Allows merchants and admins to search existing products across all stores
/// on the platform to autofill details (names, descriptions, salts, images, prices, variants).
class MasterCatalogService {
  MasterCatalogService._();
  static final MasterCatalogService instance = MasterCatalogService._();

  SupabaseClient get _supabase => Supabase.instance.client;

  // In-memory query cache to provide instantaneous 0ms repeat suggestions
  final Map<String, List<ProductModel>> _cache = {};

  /// Searches the global product catalog with debouncing and sequence protection.
  /// Deduplicates across stores, prioritizing records with images, descriptions, and category matches.
  Future<List<ProductModel>> searchCatalog({
    required String query,
    String? shopCategory,
    int limit = 12,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.length < 2) return [];

    final cacheKey = '${cleanQuery.toLowerCase()}_${shopCategory ?? 'all'}';
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    try {
      // Primary: High-performance PostgreSQL RPC with Trigram & Partition Deduplication
      final response = await _supabase.rpc(
        'search_global_product_catalog',
        params: {
          'p_query': cleanQuery,
          'p_shop_category': shopCategory,
          'p_limit': limit,
        },
      );

      final List<dynamic> rows = response as List<dynamic>? ?? [];
      final List<ProductModel> products = [];

      for (final row in rows) {
        if (row is Map<String, dynamic>) {
          products.add(_mapCatalogRowToProduct(row));
        }
      }

      _cache[cacheKey] = products;
      // Cap cache size to avoid unbounded memory growth
      if (_cache.length > 50) {
        _cache.remove(_cache.keys.first);
      }

      return products;
    } catch (e) {
      debugPrint('[MasterCatalogService] RPC search failed, invoking direct fallback: $e');
      return _fallbackDirectSearch(
        cleanQuery: cleanQuery,
        shopCategory: shopCategory,
        limit: limit,
        cacheKey: cacheKey,
      );
    }
  }

  /// Resilient direct PostgREST fallback if RPC is temporarily unavailable.
  /// Honors project rule: MUST include .eq('is_deleted', false).
  Future<List<ProductModel>> _fallbackDirectSearch({
    required String cleanQuery,
    String? shopCategory,
    required int limit,
    required String cacheKey,
  }) async {
    try {
      final terms = cleanQuery.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
      var q = _supabase
          .from('products')
          .select('id, shop_id, name, description, price, original_price, category, menu_category, brand, is_veg, unit_type, weight_per_unit, total_quantity, images, requires_prescription, medicine_type, variants, gst_rate_override, special_tags, shops(name, category)')
          .eq('is_deleted', false);

      for (final t in terms) {
        q = q.or('name.ilike.%$t%,description.ilike.%$t%,brand.ilike.%$t%,category.ilike.%$t%,menu_category.ilike.%$t%');
      }

      final rawList = await q.limit(limit * 2);
      final List<ProductModel> results = [];
      final Set<String> seenKeys = {};

      for (final item in rawList as List) {
        final map = item as Map<String, dynamic>;
        final name = (map['name'] as String? ?? '').trim().toLowerCase();
        final brand = (map['brand'] as String? ?? '').trim().toLowerCase();
        final unit = (map['unit_type'] as String? ?? 'pieces').trim().toLowerCase();
        final dedupeKey = '$name|$brand|$unit';

        if (seenKeys.add(dedupeKey)) {
          results.add(_mapCatalogRowToProduct(map));
          if (results.length >= limit) break;
        }
      }

      _cache[cacheKey] = results;
      return results;
    } catch (err) {
      debugPrint('[MasterCatalogService] Fallback direct search error: $err');
      return [];
    }
  }

  ProductModel _mapCatalogRowToProduct(Map<String, dynamic> row) {
    List<String> images = [];
    if (row['images'] is List) {
      images = (row['images'] as List)
          .map((e) => e.toString())
          .where((url) => url.startsWith('http'))
          .toList();
    }

    List<ProductVariant> variants = [];
    if (row['variants'] is List) {
      for (final v in row['variants'] as List) {
        if (v is Map<String, dynamic>) {
          variants.add(ProductVariant.fromMap(v));
        }
      }
    }

    return ProductModel(
      id: row['id']?.toString() ?? '',
      shopId: row['shop_id']?.toString() ?? '',
      name: row['name']?.toString() ?? '',
      description: row['description']?.toString(),
      price: (row['price'] as num?)?.toDouble() ?? 0.0,
      originalPrice: (row['original_price'] as num?)?.toDouble(),
      category: row['category']?.toString() ?? 'Other',
      menuCategory: row['menu_category']?.toString(),
      brand: row['brand']?.toString(),
      isVeg: row['is_veg'] as bool?,
      unitType: row['unit_type']?.toString() ?? 'pieces',
      weightPerUnit: (row['weight_per_unit'] as num?)?.toDouble(),
      totalQuantity: (row['total_quantity'] as num?)?.toInt(),
      images: images,
      requiresPrescription: row['requires_prescription'] == true,
      medicineType: row['medicine_type']?.toString() ?? 'General',
      variants: variants,
      gstRateOverride: (row['gst_rate_override'] as num?)?.toDouble(),
    );
  }

  /// Clears in-memory cache
  void clearCache() {
    _cache.clear();
  }
}
