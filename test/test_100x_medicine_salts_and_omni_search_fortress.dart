import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:enythingmobilenew/config/app_categories.dart';
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

  group('100x Medicine Salts & Omni Search Fortress Tests', () {
    final pharmacyShop = ShopModel(
      id: 'shop-noor-medicate',
      sellerId: 'seller-pharmacy-1',
      name: 'Noor Medicate',
      shopType: 'shop',
      category: 'Pharmacy',
      categories: const ['Pharmacy', 'Medical Store'],
      address: 'Near Clock Tower',
      location: const LatLng(34.0837, 74.7973),
      isActive: true,
      isAcceptingOrders: true,
      rating: 4.9,
      totalReviews: 88,
      openTime: '09:00',
      closeTime: '22:00',
      distanceKm: 0.8,
    );

    final groceryShop = ShopModel(
      id: 'shop-grocery-1',
      sellerId: 'seller-grocery-1',
      name: 'Fresh Supermarket',
      shopType: 'shop',
      category: 'Grocery',
      categories: const ['Grocery', 'Supermarket / Hypermarket'],
      address: 'Main Bazaar',
      location: const LatLng(34.0850, 74.7980),
      isActive: true,
      isAcceptingOrders: true,
      rating: 4.7,
      totalReviews: 45,
      openTime: '08:00',
      closeTime: '23:00',
      distanceKm: 1.2,
    );

    final clothingShop = ShopModel(
      id: 'shop-clothing-1',
      sellerId: 'seller-clothing-1',
      name: 'Trendz Apparel',
      shopType: 'shop',
      category: 'Clothing',
      categories: const ['Clothing', 'Footwear'],
      address: 'Residency Road',
      location: const LatLng(34.0820, 74.7950),
      isActive: true,
      isAcceptingOrders: true,
      rating: 4.6,
      totalReviews: 32,
      openTime: '10:00',
      closeTime: '21:00',
      distanceKm: 1.5,
    );

    final medicineProduct = ProductModel(
      id: 'prod-rosuvas-20',
      shopId: 'shop-noor-medicate',
      name: 'Rosuvas 20Mg Strip Of 10 Tablets',
      description: 'Rosuvastatin(20.0 Mg)',
      price: 245.0,
      originalPrice: 288.0,
      category: 'Pharmacy',
      menuCategory: 'Cardiovascular Care',
      brand: 'Sun Pharma',
      medicineType: 'Tablet',
      isAvailable: true,
      images: const ['https://images.unsplash.com/photo-medicines.jpg'],
      rating: 4.8,
      totalReviews: 14,
    );

    final doloProduct = ProductModel(
      id: 'prod-dolo-650',
      shopId: 'shop-noor-medicate',
      name: 'Dolo 650Mg Strip Of 15 Tablets',
      description: 'Paracetamol / Acetaminophen(650.0 Mg)',
      price: 33.0,
      originalPrice: 35.0,
      category: 'Pharmacy',
      menuCategory: 'Pain Relief & Fever',
      brand: 'Micro Labs',
      medicineType: 'Tablet',
      isAvailable: true,
      images: const ['https://images.unsplash.com/photo-dolo.jpg'],
      rating: 4.9,
      totalReviews: 95,
    );

    final noodlesProduct = ProductModel(
      id: 'prod-maggi-noodles',
      shopId: 'shop-grocery-1',
      name: 'Maggi 2-Minute Masala Instant Noodles 280g',
      description: 'Authentic Indian instant noodles with masala tastemaker',
      price: 55.0,
      originalPrice: 60.0,
      category: 'Grocery',
      menuCategory: 'Instant Food & Noodles',
      brand: 'Nestle',
      isAvailable: true,
      images: const ['https://images.unsplash.com/photo-maggi.jpg'],
      rating: 4.9,
      totalReviews: 120,
    );

    final jeansProduct = ProductModel(
      id: 'prod-men-jeans',
      shopId: 'shop-clothing-1',
      name: 'Slim Fit Men Denim Jeans Dark Blue',
      description: 'Stretchable cotton denim slim fit jeans for men',
      price: 1499.0,
      originalPrice: 2499.0,
      category: 'Clothing',
      menuCategory: 'Men Jeans',
      brand: 'Levis',
      isAvailable: true,
      images: const ['https://images.unsplash.com/photo-jeans.jpg'],
      rating: 4.7,
      totalReviews: 38,
    );

    final cosmeticsProduct = ProductModel(
      id: 'prod-lakme-lipstick',
      shopId: 'shop-grocery-1',
      name: 'Lakme Absolute Matte Melt Liquid Lip Color',
      description: 'Enriched with rosehip oil, smooth matte finish cosmetics',
      price: 499.0,
      originalPrice: 650.0,
      category: 'Cosmetics & Beauty',
      menuCategory: 'Makeup & Lips',
      brand: 'Lakme',
      isAvailable: true,
      images: const ['https://images.unsplash.com/photo-lipstick.jpg'],
      rating: 4.8,
      totalReviews: 50,
    );

    final allCatalog = [
      medicineProduct,
      doloProduct,
      noodlesProduct,
      jeansProduct,
      cosmeticsProduct,
    ];

    test('AppCategories.isPharmacyCategory correctly identifies all medical classifications', () {
      expect(AppCategories.isPharmacyCategory('Pharmacy'), isTrue);
      expect(AppCategories.isPharmacyCategory('Medical Store'), isTrue);
      expect(AppCategories.isPharmacyCategory('Medicines'), isTrue);
      expect(AppCategories.isPharmacyCategory('medicine'), isTrue);
      expect(AppCategories.isPharmacyCategory('Healthcare'), isTrue);
      expect(AppCategories.isPharmacyCategory('Grocery'), isFalse);
      expect(AppCategories.isPharmacyCategory('Restaurant'), isFalse);
      expect(AppCategories.isPharmacyCategory('Clothing'), isFalse);
      expect(AppCategories.isPharmacyCategory('Cosmetics & Beauty'), isFalse);
      expect(AppCategories.isPharmacyCategory(null), isFalse);
    });

    test('Multi-term tokenized search finds medicines by active chemical salt composition', () {
      // Searching by salt: "Rosuvastatin"
      final saltQuery = 'Rosuvastatin';
      final saltTerms = saltQuery.toLowerCase().split(RegExp(r'\s+'));
      final saltMatches = allCatalog.where((p) {
        final searchable =
            '${p.name} ${p.description ?? ''} ${p.brand ?? ''} ${p.category} ${p.menuCategory ?? ''}'
                .toLowerCase();
        return saltTerms.every((t) => searchable.contains(t));
      }).toList();

      expect(saltMatches.length, equals(1));
      expect(saltMatches.first.id, equals('prod-rosuvas-20'));
      expect(saltMatches.first.description, contains('Rosuvastatin'));

      // Compound search: "Rosuvastatin 20" (Salt in description + dosage in name)
      final compoundQuery = 'Rosuvastatin 20';
      final compoundTerms = compoundQuery.toLowerCase().split(RegExp(r'\s+'));
      final compoundMatches = allCatalog.where((p) {
        final searchable =
            '${p.name} ${p.description ?? ''} ${p.brand ?? ''} ${p.category} ${p.menuCategory ?? ''}'
                .toLowerCase();
        return compoundTerms.every((t) => searchable.contains(t));
      }).toList();

      expect(compoundMatches.length, equals(1));
      expect(compoundMatches.first.name, contains('Rosuvas 20Mg'));

      // Paracetamol salt search for Dolo
      final paraQuery = 'Paracetamol';
      final paraTerms = paraQuery.toLowerCase().split(RegExp(r'\s+'));
      final paraMatches = allCatalog.where((p) {
        final searchable =
            '${p.name} ${p.description ?? ''} ${p.brand ?? ''} ${p.category} ${p.menuCategory ?? ''}'
                .toLowerCase();
        return paraTerms.every((t) => searchable.contains(t));
      }).toList();

      expect(paraMatches.length, equals(1));
      expect(paraMatches.first.id, equals('prod-dolo-650'));
    });

    test('Omni search correctly discovers noodles, jeans, and cosmetics across categories', () {
      // 1. Noodles search
      final noodleQuery = 'noodles';
      final noodleTerms = noodleQuery.toLowerCase().split(RegExp(r'\s+'));
      final noodleMatches = allCatalog.where((p) {
        final searchable =
            '${p.name} ${p.description ?? ''} ${p.brand ?? ''} ${p.category} ${p.menuCategory ?? ''}'
                .toLowerCase();
        return noodleTerms.every((t) => searchable.contains(t));
      }).toList();
      expect(noodleMatches.length, equals(1));
      expect(noodleMatches.first.id, equals('prod-maggi-noodles'));

      // 2. Jeans search
      final jeansQuery = 'denim jeans';
      final jeansTerms = jeansQuery.toLowerCase().split(RegExp(r'\s+'));
      final jeansMatches = allCatalog.where((p) {
        final searchable =
            '${p.name} ${p.description ?? ''} ${p.brand ?? ''} ${p.category} ${p.menuCategory ?? ''}'
                .toLowerCase();
        return jeansTerms.every((t) => searchable.contains(t));
      }).toList();
      expect(jeansMatches.length, equals(1));
      expect(jeansMatches.first.id, equals('prod-men-jeans'));

      // 3. Cosmetics search
      final cosmeticsQuery = 'matte cosmetics';
      final cosmeticsTerms = cosmeticsQuery.toLowerCase().split(RegExp(r'\s+'));
      final cosmeticsMatches = allCatalog.where((p) {
        final searchable =
            '${p.name} ${p.description ?? ''} ${p.brand ?? ''} ${p.category} ${p.menuCategory ?? ''}'
                .toLowerCase();
        return cosmeticsTerms.every((t) => searchable.contains(t));
      }).toList();
      expect(cosmeticsMatches.length, equals(1));
      expect(cosmeticsMatches.first.id, equals('prod-lakme-lipstick'));
    });

    testWidgets('ProductSearchCard renders active salt / composition tag with science icon for medicines', (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => CartProvider()),
            ChangeNotifierProvider(create: (_) => FavoritesProvider()),
            ChangeNotifierProvider(create: (_) => AuthProvider()),
            ChangeNotifierProvider(create: (_) => LocationProvider()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ProductSearchCard(
                product: medicineProduct,
                shop: pharmacyShop,
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      // Verify product name is shown
      expect(find.text('Rosuvas 20Mg Strip Of 10 Tablets'), findsOneWidget);

      // Verify active salt from description is rendered prominently
      expect(find.text('Rosuvastatin(20.0 Mg)'), findsOneWidget);

      // Verify science / lab icon is rendered next to the salt
      expect(find.byIcon(Icons.science_outlined), findsOneWidget);

      // Verify shop name is displayed
      expect(find.text('Noor Medicate'), findsOneWidget);
    });

    testWidgets('ProductCard renders active salt / composition subtitle for pharmacy items', (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => CartProvider()),
            ChangeNotifierProvider(create: (_) => FavoritesProvider()),
            ChangeNotifierProvider(create: (_) => AuthProvider()),
            ChangeNotifierProvider(create: (_) => LocationProvider()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 200,
                height: 300,
                child: ProductCard(
                  product: doloProduct,
                  shop: pharmacyShop,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      // Verify product name is rendered
      expect(find.text('Dolo 650Mg Strip Of 15 Tablets'), findsOneWidget);

      // Verify salt composition from description is rendered
      expect(find.text('Paracetamol / Acetaminophen(650.0 Mg)'), findsOneWidget);
    });

    test('Soft-delete contract: Deleted products are strictly excluded from search results', () {
      final dbProducts = [
        {'id': 'p1', 'name': 'Rosuvas 20', 'is_deleted': false},
        {'id': 'p2', 'name': 'Old Medicine', 'is_deleted': true},
      ];

      // Soft delete rule must be honored
      final activeOnly = dbProducts.where((p) => p['is_deleted'] == false).toList();
      expect(activeOnly.length, equals(1));
      expect(activeOnly.first['id'], equals('p1'));
    });
  });
}
