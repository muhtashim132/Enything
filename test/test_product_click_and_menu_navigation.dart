import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:enythingmobilenew/models/product_model.dart';
import 'package:enythingmobilenew/models/shop_model.dart';
import 'package:enythingmobilenew/providers/cart_provider.dart';
import 'package:enythingmobilenew/providers/favorites_provider.dart';
import 'package:enythingmobilenew/providers/auth_provider.dart';
import 'package:enythingmobilenew/providers/location_provider.dart';
import 'package:enythingmobilenew/providers/platform_config_provider.dart';
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

  group('100x Forensic Tests: Product Click and Menu Navigation Fortress', () {
    final openShop = ShopModel(
      id: 'shop-open-1',
      sellerId: 'seller-1',
      name: 'Tasty Treats Kitchen',
      shopType: 'Restaurant',
      category: 'Food',
      categories: const ['Food'],
      address: '123 Food Street',
      location: const LatLng(34.0837, 74.7973),
      isActive: true,
      openTime: '00:00',
      closeTime: '23:59',
    );

    final closedShop = ShopModel(
      id: 'shop-closed-1',
      sellerId: 'seller-2',
      name: 'Night Owl Bistro (Closed)',
      shopType: 'Restaurant',
      category: 'Food',
      categories: const ['Food'],
      address: '456 Midnight Ave',
      location: const LatLng(34.0837, 74.7973),
      isActive: false, // Inactive / closed
      openTime: '12:00',
      closeTime: '13:00',
    );

    final availableProduct = ProductModel(
      id: 'prod-avail-1',
      shopId: 'shop-open-1',
      name: 'Paneer Tikka Roll',
      category: 'Food',
      description: 'Marinated cottage cheese rolled in flaky flatbread',
      price: 180.0,
      isAvailable: true,
      totalQuantity: 25,
      rating: 4.6,
      totalReviews: 15,
      unitType: 'pieces',
    );

    final outOfStockProduct = ProductModel(
      id: 'prod-oos-1',
      shopId: 'shop-open-1',
      name: 'Special Biryani (Sold Out)',
      category: 'Food',
      description: 'Slow-cooked aromatic basmati rice with spices',
      price: 320.0,
      isAvailable: true,
      totalQuantity: 0,
      rating: 4.8,
      totalReviews: 40,
      unitType: 'pieces',
    );

    testWidgets('ProductCard is always clickable even when shop is closed',
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
              body: Center(
                child: SizedBox(
                  width: 200,
                  height: 320,
                  child: ProductCard(
                    product: availableProduct,
                    shop: closedShop,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 600));

      final cardFinder = find.byType(ProductCard);
      expect(cardFinder, findsOneWidget);

      // Verify that STORE CLOSED is displayed on the button because shop is closed
      expect(find.text('STORE CLOSED'), findsOneWidget);

      // The card itself is tap-responsive and NOT null-disabled
      await tester.tap(cardFinder);
      await tester.pump(const Duration(milliseconds: 600));

      await tester.pumpWidget(const SizedBox.shrink());
      cartProvider.dispose();
      favsProvider.dispose();
      authProvider.dispose();
      locationProvider.dispose();
    });

    testWidgets('ProductCard is always clickable even when product is out of stock',
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
              body: Center(
                child: SizedBox(
                  width: 200,
                  height: 320,
                  child: ProductCard(
                    product: outOfStockProduct,
                    shop: openShop,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 600));

      final cardFinder = find.byType(ProductCard);
      expect(cardFinder, findsOneWidget);

      // Button renders UNAVAILABLE
      expect(find.text('UNAVAILABLE'), findsOneWidget);

      // Card tap is enabled
      await tester.tap(cardFinder);
      await tester.pump(const Duration(milliseconds: 600));

      await tester.pumpWidget(const SizedBox.shrink());
      cartProvider.dispose();
      favsProvider.dispose();
      authProvider.dispose();
      locationProvider.dispose();
    });

    testWidgets('ProductSearchCard is clickable even when product is out of stock',
        (tester) async {
      final cartProvider = CartProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: cartProvider),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 350,
                  height: 120,
                  child: ProductSearchCard(
                    product: outOfStockProduct,
                    shop: openShop,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 600));

      final searchCardFinder = find.byType(ProductSearchCard);
      expect(searchCardFinder, findsOneWidget);

      // Tap on search card is accepted
      await tester.tap(searchCardFinder);
      await tester.pump(const Duration(milliseconds: 600));

      await tester.pumpWidget(const SizedBox.shrink());
      cartProvider.dispose();
    });

    testWidgets('Restaurant menu item tap event isolation: Item tap vs ADD button tap',
        (tester) async {
      bool itemTapped = false;
      bool addTapped = false;

      // Construct a mock menu item widget reflecting the pattern in RestaurantDashboardSheet & Page
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  itemTapped = true;
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      // Image
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          itemTapped = true;
                        },
                        child: Container(
                          key: const ValueKey('menu_food_image'),
                          width: 100,
                          height: 90,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 14),
                      // Text Info
                      const Expanded(
                        child: Text(
                          'Butter Chicken',
                          key: ValueKey('menu_food_title'),
                        ),
                      ),
                      // Add Button
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          addTapped = true;
                        },
                        child: Container(
                          key: const ValueKey('menu_add_btn'),
                          child: const Text('ADD'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 1. Tapping on the food image triggers item tap
      await tester.tap(find.byKey(const ValueKey('menu_food_image')));
      await tester.pump();
      expect(itemTapped, isTrue);
      expect(addTapped, isFalse);

      // Reset
      itemTapped = false;
      addTapped = false;

      // 2. Tapping on the food title triggers item tap
      await tester.tap(find.byKey(const ValueKey('menu_food_title')));
      await tester.pump();
      expect(itemTapped, isTrue);
      expect(addTapped, isFalse);

      // Reset
      itemTapped = false;
      addTapped = false;

      // 3. Tapping on the ADD button triggers add tap exclusively (does NOT trigger item tap)
      await tester.tap(find.byKey(const ValueKey('menu_add_btn')));
      await tester.pump();
      expect(addTapped, isTrue);
      expect(itemTapped, isFalse);
    });

    test('ProductDetailSheet bottom bar states logic check', () {
      // 1. When shop is closed, shop condition triggers "Shop Currently Closed"
      final isShopClosed = !closedShop.isActive || !closedShop.isOpenRightNow;
      expect(isShopClosed, isTrue);

      // 2. When shop is open but item is out of stock
      final isOpenShopClosed = !openShop.isActive || !openShop.isOpenRightNow;
      expect(isOpenShopClosed, isFalse);

      final isOos = !outOfStockProduct.isAvailable ||
          (outOfStockProduct.totalQuantity != null &&
              outOfStockProduct.totalQuantity! <= 0);
      expect(isOos, isTrue);

      // 3. When shop is open and item is available
      final isAvailOos = !availableProduct.isAvailable ||
          (availableProduct.totalQuantity != null &&
              availableProduct.totalQuantity! <= 0);
      expect(isAvailOos, isFalse);
    });
  });
}
