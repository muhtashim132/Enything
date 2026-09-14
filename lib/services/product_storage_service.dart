import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product_model.dart';

/// Service responsible for managing Supabase Storage assets for products,
/// including extracting bucket paths from public URLs and cleaning up orphaned images.
class ProductStorageService {
  /// Extracts the relative storage path inside a Supabase Storage bucket.
  ///
  /// Examples:
  /// - `https://xyz.supabase.co/storage/v1/object/public/products/shop_1/photo.jpg` -> `shop_1/photo.jpg`
  /// - `https://xyz.supabase.co/storage/v1/object/public/products/shop_1/photo.jpg?t=123` -> `shop_1/photo.jpg`
  /// - `https://images.unsplash.com/...` -> `null` (third-party external host)
  static String? extractStoragePath(String url, {String bucket = 'products'}) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;

    try {
      final uri = Uri.parse(trimmed);
      final segments = uri.pathSegments;

      // Check if it follows Supabase storage URL format:
      // .../storage/v1/object/(public|sign|authenticated)/<bucket>/<pathSegments...>
      final bucketIdx = segments.indexOf(bucket);
      if (bucketIdx != -1 && bucketIdx < segments.length - 1) {
        if (segments.contains('object') && bucketIdx > 0) {
          final rawPath = segments.sublist(bucketIdx + 1).join('/');
          return Uri.decodeComponent(rawPath);
        }
      }

      // If it is already a direct relative path (e.g. shop_id/filename.jpg)
      if (!trimmed.startsWith('http://') &&
          !trimmed.startsWith('https://') &&
          trimmed.contains('/')) {
        return trimmed;
      }

      return null;
    } catch (e) {
      debugPrint('ProductStorageService: Error parsing storage URL ($url): $e');
      return null;
    }
  }

  /// Gathers all unique storage paths belonging to the given bucket from a product's
  /// main image gallery and variant images.
  static List<String> getStoragePathsForProduct(
    ProductModel product, {
    String bucket = 'products',
  }) {
    final Set<String> paths = {};

    // 1. Main product images
    for (final imgUrl in product.images) {
      final path = extractStoragePath(imgUrl, bucket: bucket);
      if (path != null && path.isNotEmpty) {
        paths.add(path);
      }
    }

    // 2. Variant images
    for (final variant in product.variants) {
      if (variant.imageUrl != null && variant.imageUrl!.isNotEmpty) {
        final path = extractStoragePath(variant.imageUrl!, bucket: bucket);
        if (path != null && path.isNotEmpty) {
          paths.add(path);
        }
      }
    }

    return paths.toList();
  }

  /// Deletes all storage objects associated with the product from Supabase Storage.
  ///
  /// Returns the number of paths attempted/removed. Does NOT throw if deletion fails
  /// (logs error and returns 0 to allow the soft-delete transaction to proceed gracefully).
  static Future<int> deleteProductImages(
    ProductModel product, {
    SupabaseClient? client,
    String bucket = 'products',
  }) async {
    final paths = getStoragePathsForProduct(product, bucket: bucket);
    if (paths.isEmpty) return 0;

    return deleteStoragePaths(paths, client: client, bucket: bucket);
  }

  /// Deletes arbitrary storage paths from the specified bucket in batches.
  static Future<int> deleteStoragePaths(
    List<String> paths, {
    SupabaseClient? client,
    String bucket = 'products',
  }) async {
    if (paths.isEmpty) return 0;

    final targetClient = client ?? Supabase.instance.client;
    try {
      // Supabase Storage remove supports a list of paths
      await targetClient.storage.from(bucket).remove(paths);
      debugPrint('ProductStorageService: Successfully removed ${paths.length} file(s) from $bucket');
      return paths.length;
    } catch (e) {
      debugPrint('ProductStorageService: Error removing storage files from $bucket: $e');
      return 0;
    }
  }
}
