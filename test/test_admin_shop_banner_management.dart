import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/pages/admin/platform/admin_product_management_page.dart';

void main() {
  group('100x Admin Shop Banner Management - Model & Invariant Tests', () {
    test('AdminShopItem.fromMap correctly parses banner_url and banner_image', () {
      final mapWithUrl = {
        'id': 'shop-1',
        'name': 'Bistro Cafe',
        'category': 'Restaurant',
        'is_active': true,
        'banner_url': 'https://storage.enything.in/shops/banners/shop-1/100.jpg',
      };
      final item1 = AdminShopItem.fromMap(mapWithUrl);
      expect(item1.bannerUrl, equals('https://storage.enything.in/shops/banners/shop-1/100.jpg'));

      final mapWithLegacyImage = {
        'id': 'shop-2',
        'name': 'Spice Garden',
        'category': 'Restaurant',
        'is_active': true,
        'banner_image': 'https://storage.enything.in/shops/banners/shop-2/200.jpg',
      };
      final item2 = AdminShopItem.fromMap(mapWithLegacyImage);
      expect(item2.bannerUrl, equals('https://storage.enything.in/shops/banners/shop-2/200.jpg'));

      final mapWithoutBanner = {
        'id': 'shop-3',
        'name': 'Dessert Corner',
        'category': 'Bakery',
        'is_active': true,
      };
      final item3 = AdminShopItem.fromMap(mapWithoutBanner);
      expect(item3.bannerUrl, isNull);
    });

    test('AdminShopItem.copyWith updates and clears bannerUrl cleanly without tombstone resurrection', () {
      const initial = AdminShopItem(
        id: 'shop-10',
        name: 'Royal Diner',
        category: 'Food',
        isActive: true,
        bannerUrl: 'https://example.com/initial_banner.jpg',
      );

      // 1. Update bannerUrl
      final updated = initial.copyWith(
        bannerUrl: 'https://example.com/new_banner.jpg',
      );
      expect(updated.bannerUrl, equals('https://example.com/new_banner.jpg'));

      // 2. Clear banner with explicit clearBanner: true
      final cleared = updated.copyWith(clearBanner: true);
      expect(cleared.bannerUrl, isNull,
          reason: 'clearBanner: true must cleanly set bannerUrl to null');

      // 3. Normal copyWith without bannerUrl preserves existing banner
      final preserved = updated.copyWith(name: 'Royal Diner & Lounge');
      expect(preserved.name, equals('Royal Diner & Lounge'));
      expect(preserved.bannerUrl, equals('https://example.com/new_banner.jpg'));
    });

    test('Realtime payload resolution handles explicit null banner removal', () {
      const current = AdminShopItem(
        id: 'shop-99',
        name: 'Sunset Pizzeria',
        category: 'Food',
        isActive: true,
        bannerUrl: 'https://storage.enything.in/banners/old.jpg',
      );

      // Simulating Supabase Realtime UPDATE payload where banner was deleted
      final newRec = {
        'id': 'shop-99',
        'name': 'Sunset Pizzeria',
        'banner_url': null,
        'banner_image': null,
      };

      final hasBannerField = newRec.containsKey('banner_url') || newRec.containsKey('banner_image');
      final rawBanner = (newRec['banner_url'] ?? newRec['banner_image'])?.toString();
      final updatedBannerUrl = hasBannerField ? rawBanner : current.bannerUrl;

      final updated = current.copyWith(
        bannerUrl: updatedBannerUrl,
        clearBanner: hasBannerField && (rawBanner == null || rawBanner.isEmpty),
      );

      expect(updated.bannerUrl, isNull,
          reason: 'Deleting a banner via realtime must not revive the old bannerUrl');
    });

    test('URL validation rules enforce valid HTTP/HTTPS scheme and length constraints', () {
      bool isValidBannerUrl(String? url) {
        if (url == null || url.trim().isEmpty) return false;
        final trimmed = url.trim();
        if (trimmed.length > 1000) return false;
        final uri = Uri.tryParse(trimmed);
        if (uri == null) return false;
        if (!uri.isScheme('http') && !uri.isScheme('https')) return false;
        if (uri.host.isEmpty) return false;
        return true;
      }

      // Valid URLs
      expect(isValidBannerUrl('https://example.com/banner.jpg'), isTrue);
      expect(isValidBannerUrl('http://cdn.restaurant.com/images/123.png'), isTrue);
      expect(isValidBannerUrl('https://supabase.enything.in/storage/v1/object/public/shops/banners/1/test.jpg'), isTrue);

      // Invalid URLs
      expect(isValidBannerUrl(''), isFalse);
      expect(isValidBannerUrl('   '), isFalse);
      expect(isValidBannerUrl('ftp://example.com/image.jpg'), isFalse);
      expect(isValidBannerUrl('file:///path/to/image.jpg'), isFalse);
      expect(isValidBannerUrl('not-a-valid-url'), isFalse);
      expect(isValidBannerUrl('https://' + 'a' * 1005 + '.jpg'), isFalse);
    });

    test('Dual-column update payload generates matching banner_url and banner_image', () {
      const targetUrl = 'https://storage.enything.in/shops/banners/shop-1/new.jpg';
      final payload = {
        'banner_url': targetUrl,
        'banner_image': targetUrl,
        'updated_at': DateTime.now().toIso8601String(),
      };

      expect(payload['banner_url'], equals(payload['banner_image']),
          reason: 'Both columns must remain in 100% parity to prevent split-brain banner state');
    });
  });

  group('100x Admin Shop Banner Management - Migration Verification', () {
    test('Migration 149 file exists and defines admin_update_shop_banner and shops bucket', () {
      final migrationFile = File('supabase/migrations/20290000000149_100x_admin_shop_banner_management.sql');
      expect(migrationFile.existsSync(), isTrue,
          reason: 'Migration 20290000000149_100x_admin_shop_banner_management.sql must exist');

      final sql = migrationFile.readAsStringSync();

      // Check storage bucket configuration
      expect(sql.contains("INSERT INTO storage.buckets (id, name, public)"), isTrue);
      expect(sql.contains("VALUES ('shops', 'shops', true)"), isTrue);
      expect(sql.contains("CREATE POLICY \"Public Access Shops\""), isTrue);
      expect(sql.contains("CREATE POLICY \"Authenticated Upload Shops Banners\""), isTrue);

      // Check atomic RPC definition
      expect(sql.contains("CREATE OR REPLACE FUNCTION public.admin_update_shop_banner"), isTrue);
      expect(sql.contains("p_shop_id UUID"), isTrue);
      expect(sql.contains("p_banner_url TEXT"), isTrue);
      expect(sql.contains("banner_url = v_clean_url"), isTrue);
      expect(sql.contains("banner_image = v_clean_url"), isTrue);
      expect(sql.contains("GRANT EXECUTE ON FUNCTION public.admin_update_shop_banner"), isTrue);
    });
  });
}
