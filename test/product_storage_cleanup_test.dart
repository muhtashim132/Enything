import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/models/product_model.dart';
import 'package:enythingmobilenew/services/product_storage_service.dart';

void main() {
  group('ProductStorageService - extractStoragePath', () {
    test('extracts relative path from standard public Supabase Storage URL', () {
      const url =
          'https://hvtujaatwhyxielrlztr.supabase.co/storage/v1/object/public/products/shop_abc123/1726359000_0.jpg';
      final path = ProductStorageService.extractStoragePath(url, bucket: 'products');
      expect(path, equals('shop_abc123/1726359000_0.jpg'));
    });

    test('strips query parameters and cache busters', () {
      const url =
          'https://hvtujaatwhyxielrlztr.supabase.co/storage/v1/object/public/products/shop_abc123/variant_1726359000_0.jpg?t=2026-09-15T02:00:00Z&version=2';
      final path = ProductStorageService.extractStoragePath(url, bucket: 'products');
      expect(path, equals('shop_abc123/variant_1726359000_0.jpg'));
    });

    test('extracts path from signed Supabase Storage URL', () {
      const url =
          'https://hvtujaatwhyxielrlztr.supabase.co/storage/v1/object/sign/products/shop_xyz/secret_photo.png?token=mocktoken';
      final path = ProductStorageService.extractStoragePath(url, bucket: 'products');
      expect(path, equals('shop_xyz/secret_photo.png'));
    });

    test('extracts path from authenticated Supabase Storage URL', () {
      const url =
          'https://hvtujaatwhyxielrlztr.supabase.co/storage/v1/object/authenticated/products/shop_xyz/doc.jpg';
      final path = ProductStorageService.extractStoragePath(url, bucket: 'products');
      expect(path, equals('shop_xyz/doc.jpg'));
    });

    test('correctly URL decodes special characters in filename', () {
      const url =
          'https://hvtujaatwhyxielrlztr.supabase.co/storage/v1/object/public/products/shop_1/My%20Product%20Image.jpg';
      final path = ProductStorageService.extractStoragePath(url, bucket: 'products');
      expect(path, equals('shop_1/My Product Image.jpg'));
    });

    test('returns null for external third-party URLs (e.g. Unsplash)', () {
      const url =
          'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=500&q=80';
      final path = ProductStorageService.extractStoragePath(url, bucket: 'products');
      expect(path, isNull);
    });

    test('returns null when bucket does not match', () {
      const url =
          'https://hvtujaatwhyxielrlztr.supabase.co/storage/v1/object/public/shops/shop_1/banner.jpg';
      final path = ProductStorageService.extractStoragePath(url, bucket: 'products');
      expect(path, isNull);
    });

    test('returns null for empty or invalid string', () {
      expect(ProductStorageService.extractStoragePath(''), isNull);
      expect(ProductStorageService.extractStoragePath('   '), isNull);
    });
  });

  group('ProductStorageService - getStoragePathsForProduct', () {
    test('extracts both main images and variant images without duplicates', () {
      final product = ProductModel(
        id: 'p1',
        shopId: 'shop_1',
        name: 'Test Product',
        category: 'Food',
        price: 99.0,
        images: [
          'https://xyz.supabase.co/storage/v1/object/public/products/shop_1/main1.jpg',
          'https://xyz.supabase.co/storage/v1/object/public/products/shop_1/main2.jpg',
          // Re-used in main gallery:
          'https://xyz.supabase.co/storage/v1/object/public/products/shop_1/main1.jpg',
          // External URL that should be ignored:
          'https://images.unsplash.com/photo-12345',
        ],
        variants: [
          ProductVariant(
            id: 'v1',
            name: 'Small',
            price: 89.0,
            imageUrl:
                'https://xyz.supabase.co/storage/v1/object/public/products/shop_1/var_small.jpg',
          ),
          ProductVariant(
            id: 'v2',
            name: 'Medium',
            price: 99.0,
            // Reuses main1.jpg:
            imageUrl:
                'https://xyz.supabase.co/storage/v1/object/public/products/shop_1/main1.jpg',
          ),
          ProductVariant(
            id: 'v3',
            name: 'Large',
            price: 109.0,
            imageUrl: null,
          ),
        ],
      );

      final paths = ProductStorageService.getStoragePathsForProduct(product);

      expect(paths.length, equals(3));
      expect(
        paths,
        containsAll([
          'shop_1/main1.jpg',
          'shop_1/main2.jpg',
          'shop_1/var_small.jpg',
        ]),
      );
    });

    test('returns empty list when product has no storage images', () {
      final product = ProductModel(
        id: 'p2',
        shopId: 'shop_1',
        name: 'No Image Product',
        category: 'Food',
        price: 50.0,
        images: [],
        variants: [],
      );

      final paths = ProductStorageService.getStoragePathsForProduct(product);
      expect(paths, isEmpty);
    });
  });
}
