import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:enythingmobilenew/models/product_model.dart';
import 'package:enythingmobilenew/models/shop_model.dart';
import 'package:enythingmobilenew/providers/cart_provider.dart';
import 'package:enythingmobilenew/providers/favorites_provider.dart';
import 'package:enythingmobilenew/providers/auth_provider.dart';
import 'package:enythingmobilenew/providers/location_provider.dart';
import 'package:enythingmobilenew/providers/platform_config_provider.dart';
import 'package:enythingmobilenew/widgets/shop_card.dart';
import 'package:enythingmobilenew/widgets/restaurant_shop_card.dart';
import 'package:enythingmobilenew/widgets/product_card.dart';
import 'package:enythingmobilenew/widgets/product_search_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    PlatformConfigProvider();
    try {
      await Supabase.initialize(
        url: 'https://mock-test.supabase.co',
        anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.e30.mock_key',
      );
    } catch (_) {}
  });

  group('100x Closed Shops and Products Discovery Fortress Tests', () {
    final openShop = ShopModel(
      id: 'shop-open-1',
      sellerId: 'seller-1',
      name: 'Open Fresh Mart',
      shopType: 'shop',
      category: 'Grocery',
      categories: const ['Grocery'],
      address: '123 Market St',
      location: const LatLng(12.9716, 77.5946),
      isActive: true,
      isAcceptingOrders: true,
      rating: 4.8,
      totalReviews: 25,
      openTime: '00:00',
      closeTime: '23:59',
      distanceKm: 1.5,
    );

    final closedShop = ShopModel(
      id: 'shop-closed-1',
      sellerId: 'seller-2',
      name: 'Night Owl Cafe (Closed)',
      shopType: 'restaurant',
      category: 'Cafes & Bakeries',
      categories: const ['Cafes & Bakeries'],
      address: '456 Sleepy Lane',
      location: const LatLng(12.9720, 77.5950),
      isActive: true, // Platform active
      isAcceptingOrders: false, // Closed right now
      rating: 4.9, // Higher rating than open shop
      totalReviews: 80,
      openTime: '10:00',
      closeTime: '22:00',
      distanceKm: 0.8, // Closer than open shop
    );

    final productFromOpenShop = ProductModel(
      id: 'prod-open-1',
      shopId: openShop.id,
      name: 'Fresh Apples',
      price: 120.0,
      category: 'Grocery',
      isAvailable: true,
      rating: 4.5,
      totalReviews: 12,
    );

    final productFromClosedShop = ProductModel(
      id: 'prod-closed-1',
      shopId: closedShop.id,
      name: 'Signature Latte',
      price: 180.0,
      category: 'Cafes & Bakeries',
      isAvailable: true, // Product is catalog active, but shop is closed
      rating: 5.0, // Higher rating
      totalReviews: 40,
    );

    test('ShopModel separates platform isActive from isAcceptingOrders', () {
      expect(closedShop.isActive, isTrue);
      expect(closedShop.isAcceptingOrders, isFalse);
      expect(closedShop.isOpenRightNow, isFalse);

      expect(openShop.isActive, isTrue);
      expect(openShop.isAcceptingOrders, isTrue);
    });

    test('Open shops strictly rank ahead of closed shops regardless of distance/rating', () {
      final shops = [closedShop, openShop];

      // Sorter algorithm from home_page.dart & all_listings_page.dart
      shops.sort((a, b) {
        final openA = a.isOpenRightNow ? 1 : 0;
        final openB = b.isOpenRightNow ? 1 : 0;
        if (openA != openB) return openB.compareTo(openA);
        return b.rating.compareTo(a.rating);
      });

      expect(shops.first.id, equals(openShop.id));
      expect(shops.last.id, equals(closedShop.id));
    });

    test('Products from open shops strictly rank ahead of products from closed shops', () {
      final products = [productFromClosedShop, productFromOpenShop];
      final prodShops = {
        productFromOpenShop.id: openShop,
        productFromClosedShop.id: closedShop,
      };

      // Sorter algorithm from home_page.dart
      products.sort((a, b) {
        final sA = prodShops[a.id];
        final sB = prodShops[b.id];
        final availA = a.isAvailable && (sA?.isOpenRightNow ?? false);
        final availB = b.isAvailable && (sB?.isOpenRightNow ?? false);
        if (availA && !availB) return -1;
        if (!availA && availB) return 1;
        return b.rating.compareTo(a.rating);
      });

      expect(products.first.id, equals(productFromOpenShop.id));
      expect(products.last.id, equals(productFromClosedShop.id));
    });

    testWidgets('Closed ShopCard renders CLOSED badge and intercepts click with SnackBar',
        (tester) async {
      bool tapped = false;
      final favsProvider = FavoritesProvider();
      final authProvider = AuthProvider();
      final locationProvider = LocationProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: favsProvider),
            ChangeNotifierProvider.value(value: authProvider),
            ChangeNotifierProvider.value(value: locationProvider),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 300,
                width: 300,
                child: ShopCard(
                  shop: closedShop,
                  onTap: () {
                    tapped = true;
                  },
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));

      // Verify CLOSED overlay is displayed
      expect(find.text('CLOSED'), findsOneWidget);
      expect(find.text('Opens at 10:00'), findsOneWidget);

      // Tap on closed card
      await tester.tap(find.byType(ShopCard));
      await tester.pump(const Duration(milliseconds: 300));

      // Verify onTap callback was NOT executed
      expect(tapped, isFalse);

      // Verify SnackBar notice appears
      expect(find.textContaining('Night Owl Cafe (Closed) is currently closed'),
          findsOneWidget);
      expect(find.text('Orders cannot be placed right now.'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      favsProvider.dispose();
      authProvider.dispose();
      locationProvider.dispose();
    });

    testWidgets('Closed RestaurantShopCard renders CLOSED badge and intercepts click with SnackBar',
        (tester) async {
      bool tapped = false;
      final favsProvider = FavoritesProvider();
      final authProvider = AuthProvider();
      final locationProvider = LocationProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: favsProvider),
            ChangeNotifierProvider.value(value: authProvider),
            ChangeNotifierProvider.value(value: locationProvider),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 350,
                width: 350,
                child: RestaurantShopCard(
                  shop: closedShop,
                  onTap: () {
                    tapped = true;
                  },
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));

      // Verify CLOSED text is rendered
      expect(find.text('CLOSED'), findsOneWidget);

      // Tap on closed restaurant card
      await tester.tap(find.byType(RestaurantShopCard));
      await tester.pump(const Duration(milliseconds: 300));

      // Verify original onTap was blocked
      expect(tapped, isFalse);

      // Verify closed SnackBar is displayed
      expect(find.textContaining('Night Owl Cafe (Closed) is currently closed'),
          findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      favsProvider.dispose();
      authProvider.dispose();
      locationProvider.dispose();
    });

    testWidgets('ProductCard for product of closed shop renders STORE CLOSED and blocks ordering',
        (tester) async {
      final cartProvider = CartProvider();
      final favsProvider = FavoritesProvider();
      final authProvider = AuthProvider();
      final locationProvider = LocationProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: cartProvider),
            ChangeNotifierProvider.value(value: favsProvider),
            ChangeNotifierProvider.value(value: authProvider),
            ChangeNotifierProvider.value(value: locationProvider),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 350,
                width: 200,
                child: ProductCard(
                  product: productFromClosedShop,
                  shop: closedShop,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));

      // Verify STORE CLOSED button text is rendered
      expect(find.text('STORE CLOSED'), findsOneWidget);

      // Tap on the STORE CLOSED button
      await tester.tap(find.text('STORE CLOSED'));
      await tester.pump(const Duration(milliseconds: 300));

      // Verify closed store notice is displayed
      expect(find.textContaining('Night Owl Cafe (Closed) is currently closed'),
          findsOneWidget);
      expect(find.text('Orders cannot be placed right now.'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      cartProvider.dispose();
      favsProvider.dispose();
      authProvider.dispose();
      locationProvider.dispose();
    });

    testWidgets('ProductSearchCard for closed shop renders STORE CLOSED and alerts user on tap',
        (tester) async {
      final cartProvider = CartProvider();
      final favsProvider = FavoritesProvider();
      final authProvider = AuthProvider();
      final locationProvider = LocationProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: cartProvider),
            ChangeNotifierProvider.value(value: favsProvider),
            ChangeNotifierProvider.value(value: authProvider),
            ChangeNotifierProvider.value(value: locationProvider),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 200,
                width: 400,
                child: ProductSearchCard(
                  product: productFromClosedShop,
                  shop: closedShop,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));

      // Verify STORE CLOSED button is rendered
      expect(find.text('STORE CLOSED'), findsOneWidget);

      // Tap on card
      await tester.tap(find.byType(ProductSearchCard));
      await tester.pump(const Duration(milliseconds: 300));

      // Verify SnackBar notice appears
      expect(find.textContaining('Night Owl Cafe (Closed) is currently closed'),
          findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      cartProvider.dispose();
      favsProvider.dispose();
      authProvider.dispose();
      locationProvider.dispose();
    });
  });
}
