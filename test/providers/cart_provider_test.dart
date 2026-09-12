import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:enythingmobilenew/providers/cart_provider.dart';
import 'package:enythingmobilenew/models/product_model.dart';
import 'package:enythingmobilenew/models/shop_model.dart';
import 'package:latlong2/latlong.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CartProvider cartProvider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    cartProvider = CartProvider();
  });

  group('CartProvider Core Tests', () {
    final testProduct = ProductModel(
      id: 'p1',
      shopId: 's1',
      name: 'Test Product',
      category: 'Food',
      subCategory: 'Snacks',
      brand: 'TestBrand',
      price: 100.0,
      originalPrice: 120.0,
      totalQuantity: 50,
      weightPerUnit: 0.5,
      unitType: 'kg',
      description: 'A test product',
      images: ['image1.jpg'],
      isVeg: true,
      menuCategory: 'Snacks',
      prepTimeMinutes: 10,
      specialTags: [],
      isAvailable: true,
      rating: 4.5,
      requiresPrescription: false,
      medicineType: '',
      gstRateOverride: null,
    );

    final testProductVariant = ProductModel(
      id: 'p1_variant',
      shopId: 's1',
      name: 'Test Product Variant',
      category: 'Food',
      subCategory: 'Snacks',
      brand: 'TestBrand',
      price: 100.0,
      originalPrice: 120.0,
      totalQuantity: 50,
      weightPerUnit: 0.5,
      unitType: 'kg',
      description: 'A test product',
      images: ['image1.jpg'],
      isVeg: true,
      menuCategory: 'Snacks',
      prepTimeMinutes: 10,
      specialTags: [],
      isAvailable: true,
      rating: 4.5,
      requiresPrescription: false,
      medicineType: '',
      gstRateOverride: null,
    );

    final testShop = ShopModel(
      id: 's1',
      sellerId: 'sel1',
      name: 'Test Shop',
      shopType: 'restaurant',
      cuisineType: 'Indian',
      fssaiNumber: '12345678901234',
      prepTimeMinutes: 20,
      isVegOnly: false,
      openingHours: '{}',
      address: '123 Test St',
      location: const LatLng(10.0, 20.0),
      category: 'Food',
      categories: ['Food'],
      isActive: true,
      rating: 4.5,
      totalReviews: 100,
      totalOrders: 500,
      bannerImage: null,
    );

    final testShop2 = ShopModel(
      id: 's2',
      sellerId: 'sel2',
      name: 'Test Shop 2',
      shopType: 'grocery',
      cuisineType: 'None',
      fssaiNumber: '12345678901234',
      prepTimeMinutes: 5,
      isVegOnly: true,
      openingHours: '{}',
      address: '456 Test St',
      location: const LatLng(10.1, 20.1),
      category: 'Grocery',
      categories: ['Grocery'],
      isActive: true,
      rating: 4.0,
      totalReviews: 10,
      totalOrders: 50,
      bannerImage: null,
    );

    test('Initial cart is empty', () {
      expect(cartProvider.isEmpty, true);
      expect(cartProvider.totalItemCount, 0);
      expect(cartProvider.subtotal, 0.0);
    });

    test('Adding an item updates cart totals', () {
      final error = cartProvider.addItem(testProduct, testShop, quantity: 2);
      expect(error, isNull);
      expect(cartProvider.isEmpty, false);
      expect(cartProvider.totalItemCount, 2);
      expect(cartProvider.subtotal, 200.0);
      expect(cartProvider.totalWeight, 1.0); // 0.5 * 2
    });

    test('Updating quantity works correctly', () {
      cartProvider.addItem(testProduct, testShop, quantity: 1);
      cartProvider.updateQuantity(testProduct.id, 3);
      expect(cartProvider.totalItemCount, 3);
      expect(cartProvider.subtotal, 300.0);
    });

    test('Setting quantity to 0 removes the item', () {
      cartProvider.addItem(testProduct, testShop, quantity: 2);
      cartProvider.updateQuantity(testProduct.id, 0);
      expect(cartProvider.isEmpty, true);
    });

    test('Removing an item directly', () {
      cartProvider.addItem(testProduct, testShop, quantity: 1);
      cartProvider.removeItem(testProduct.id);
      expect(cartProvider.isEmpty, true);
    });

    test('Clearing cart', () {
      cartProvider.addItem(testProduct, testShop, quantity: 5);
      cartProvider.clear();
      expect(cartProvider.isEmpty, true);
      expect(cartProvider.totalItemCount, 0);
    });

    test('Cannot add more than max items (limit handled inside addItem)', () {
      final error = cartProvider.addItem(testProduct, testShop, quantity: 1000);
      expect(error, isNotNull);
    });

    test('Adding items from multiple shops', () {
      cartProvider.addItem(testProduct, testShop, quantity: 1);
      cartProvider.addItem(testProductVariant, testShop2, quantity: 1);
      expect(cartProvider.isMultiShopOrder, true);
      expect(cartProvider.shops.length, 2);
    });

    test('Product variant tracking, getProductTotalQuantity and getItemsForProduct', () {
      final variantProduct = ProductModel(
        id: 'p_var',
        shopId: 's1',
        name: 'Chicken Malai Makhni',
        category: 'Food',
        subCategory: 'Curry',
        price: 500.0,
        variants: [
          ProductVariant(id: 'v1', name: 'Half', price: 500.0),
          ProductVariant(id: 'v2', name: 'Full', price: 900.0),
        ],
      );

      // Initially empty
      expect(cartProvider.hasProduct('p_var'), false);
      expect(cartProvider.getProductTotalQuantity('p_var'), 0);
      expect(cartProvider.getItemsForProduct('p_var'), isEmpty);

      // Add 'Half' variant (qty: 1)
      cartProvider.addItem(variantProduct, testShop,
          quantity: 1, selectedVariant: variantProduct.variants[0]);
      expect(cartProvider.hasProduct('p_var'), true);
      expect(cartProvider.getProductTotalQuantity('p_var'), 1);
      expect(cartProvider.getItemQuantity('p_var', variantName: 'Half'), 1);
      expect(cartProvider.getItemQuantity('p_var', variantName: 'Full'), 0);
      expect(cartProvider.getItemsForProduct('p_var').length, 1);

      // Add 'Full' variant (qty: 2)
      cartProvider.addItem(variantProduct, testShop,
          quantity: 2, selectedVariant: variantProduct.variants[1]);
      expect(cartProvider.getProductTotalQuantity('p_var'), 3);
      expect(cartProvider.getItemQuantity('p_var', variantName: 'Half'), 1);
      expect(cartProvider.getItemQuantity('p_var', variantName: 'Full'), 2);
      expect(cartProvider.getItemsForProduct('p_var').length, 2);

      // Decrement 'Half' variant to 0
      cartProvider.updateQuantity('p_var', 0, variantName: 'Half');
      expect(cartProvider.getProductTotalQuantity('p_var'), 2);
      expect(cartProvider.getItemQuantity('p_var', variantName: 'Half'), 0);
      expect(cartProvider.getItemQuantity('p_var', variantName: 'Full'), 2);
      expect(cartProvider.getItemsForProduct('p_var').length, 1);

      // Remove 'Full' variant
      cartProvider.removeItem('p_var', variantName: 'Full');
      expect(cartProvider.hasProduct('p_var'), false);
      expect(cartProvider.getProductTotalQuantity('p_var'), 0);
    });

    test('Can load cart from shared preferences', () async {
      SharedPreferences.setMockInitialValues({
        'enything_cart_v2':
            '[{"product":{"id":"p1","shop_id":"s1","name":"Test Product","category":"Food","sub_category":"Snacks","brand":"TestBrand","price":100.0,"original_price":120.0,"total_quantity":50,"weight_per_unit":0.5,"unit_type":"kg","description":"A test product","images":["image1.jpg"],"is_veg":true,"menu_category":"Snacks","prep_time_minutes":10,"special_tags":[],"is_available":true,"rating":4.5,"requires_prescription":false,"medicine_type":"","gst_rate_override":null},"shop":{"id":"s1","seller_id":"sel1","name":"Test Shop","shop_type":"restaurant","cuisine_type":"Indian","fssai_number":"12345678901234","prep_time_minutes":20,"is_veg_only":false,"opening_hours":"{}","address":"123 Test St","_lat":10.0,"_lng":20.0,"category":"Food","categories":["Food"],"is_active":true,"rating":4.5,"total_reviews":100,"total_orders":500,"banner_image":null},"quantity":2}]'
      });
      await cartProvider.loadCart();
      expect(cartProvider.isEmpty, false);
      expect(cartProvider.totalItemCount, 2);
      expect(cartProvider.items.first.product.id, 'p1');
    });

    test('Enforces 3-shop cap across active pending shops and cart shops', () {
      final shop1 = ShopModel(
        id: 's1', sellerId: 'sel1', name: 'Shop 1', shopType: 'restaurant',
        cuisineType: 'Indian', fssaiNumber: '1', prepTimeMinutes: 20, isVegOnly: false,
        openingHours: '{}', address: '123 St', location: const LatLng(10.0, 20.0),
        category: 'Food', categories: ['Food'], isActive: true, rating: 4.5,
        totalReviews: 10, totalOrders: 50, bannerImage: null,
      );
      final shop2 = ShopModel(
        id: 's2', sellerId: 'sel2', name: 'Shop 2', shopType: 'grocery',
        cuisineType: 'General', fssaiNumber: '2', prepTimeMinutes: 15, isVegOnly: false,
        openingHours: '{}', address: '456 St', location: const LatLng(10.1, 20.1),
        category: 'Grocery', categories: ['Grocery'], isActive: true, rating: 4.0,
        totalReviews: 5, totalOrders: 25, bannerImage: null,
      );
      final shop3 = ShopModel(
        id: 's3', sellerId: 'sel3', name: 'Shop 3', shopType: 'bakery',
        cuisineType: 'Bakery', fssaiNumber: '3', prepTimeMinutes: 10, isVegOnly: false,
        openingHours: '{}', address: '789 St', location: const LatLng(10.2, 20.2),
        category: 'Bakery', categories: ['Bakery'], isActive: true, rating: 4.8,
        totalReviews: 20, totalOrders: 100, bannerImage: null,
      );
      final shop4 = ShopModel(
        id: 's4', sellerId: 'sel4', name: 'Shop 4', shopType: 'pharmacy',
        cuisineType: 'Medicine', fssaiNumber: '4', prepTimeMinutes: 5, isVegOnly: false,
        openingHours: '{}', address: '101 St', location: const LatLng(10.3, 20.3),
        category: 'Pharmacy', categories: ['Pharmacy'], isActive: true, rating: 4.9,
        totalReviews: 30, totalOrders: 150, bannerImage: null,
      );

      final p2 = ProductModel(
        id: 'p2', shopId: 's2', name: 'Item 2', category: 'Grocery', subCategory: 'Staples',
        brand: 'Brand2', price: 50.0, originalPrice: 60.0, totalQuantity: 10,
        weightPerUnit: 1.0, unitType: 'kg', description: 'Desc 2', images: [],
        isVeg: true, menuCategory: 'Staples', prepTimeMinutes: 15, specialTags: [],
        isAvailable: true, rating: 4.0, requiresPrescription: false, medicineType: '',
        gstRateOverride: null,
      );
      final p3 = ProductModel(
        id: 'p3', shopId: 's3', name: 'Item 3', category: 'Bakery', subCategory: 'Bread',
        brand: 'Brand3', price: 40.0, originalPrice: 45.0, totalQuantity: 10,
        weightPerUnit: 0.4, unitType: 'piece', description: 'Desc 3', images: [],
        isVeg: true, menuCategory: 'Bread', prepTimeMinutes: 10, specialTags: [],
        isAvailable: true, rating: 4.8, requiresPrescription: false, medicineType: '',
        gstRateOverride: null,
      );
      final p4 = ProductModel(
        id: 'p4', shopId: 's4', name: 'Item 4', category: 'Pharmacy', subCategory: 'FirstAid',
        brand: 'Brand4', price: 20.0, originalPrice: 25.0, totalQuantity: 10,
        weightPerUnit: 0.1, unitType: 'piece', description: 'Desc 4', images: [],
        isVeg: true, menuCategory: 'FirstAid', prepTimeMinutes: 5, specialTags: [],
        isAvailable: true, rating: 4.9, requiresPrescription: false, medicineType: '',
        gstRateOverride: null,
      );

      // Pre-set surviving active shop from pending order
      cartProvider.setActivePendingShops([shop1]);
      expect(cartProvider.activePendingShops.length, 1);
      expect(cartProvider.activePendingShops.first.id, 's1');

      // Add item from shop 2 -> total effective shops: 2 (allowed)
      final err2 = cartProvider.addItem(p2, shop2);
      expect(err2, isNull);
      expect(cartProvider.shops.length, 1);

      // Add item from shop 3 -> total effective shops: 3 (allowed)
      final err3 = cartProvider.addItem(p3, shop3);
      expect(err3, isNull);
      expect(cartProvider.shops.length, 2);

      // Add item from shop 4 -> total effective shops would be 4 (rejected!)
      final err4 = cartProvider.addItem(p4, shop4);
      expect(err4, isNotNull);
      expect(err4, contains('Maximum 3 shops allowed'));
      expect(cartProvider.shops.length, 2);

      // Clear pending replacement -> activePendingShops becomes 0
      cartProvider.clearPendingReplacement();
      expect(cartProvider.activePendingShops.isEmpty, true);

      // Now shop 4 can be added because effective shops is now only 2 (shop2 + shop3)
      final err4AfterClear = cartProvider.addItem(p4, shop4);
      expect(err4AfterClear, isNull);
      expect(cartProvider.shops.length, 3);
    });
  });
}
