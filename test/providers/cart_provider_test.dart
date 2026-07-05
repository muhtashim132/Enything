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
    
    test('Can load cart from shared preferences', () async {
      SharedPreferences.setMockInitialValues({
        'enything_cart_v2': '[{"product":{"id":"p1","shop_id":"s1","name":"Test Product","category":"Food","sub_category":"Snacks","brand":"TestBrand","price":100.0,"original_price":120.0,"total_quantity":50,"weight_per_unit":0.5,"unit_type":"kg","description":"A test product","images":["image1.jpg"],"is_veg":true,"menu_category":"Snacks","prep_time_minutes":10,"special_tags":[],"is_available":true,"rating":4.5,"requires_prescription":false,"medicine_type":"","gst_rate_override":null},"shop":{"id":"s1","seller_id":"sel1","name":"Test Shop","shop_type":"restaurant","cuisine_type":"Indian","fssai_number":"12345678901234","prep_time_minutes":20,"is_veg_only":false,"opening_hours":"{}","address":"123 Test St","_lat":10.0,"_lng":20.0,"category":"Food","categories":["Food"],"is_active":true,"rating":4.5,"total_reviews":100,"total_orders":500,"banner_image":null},"quantity":2}]'
      });
      await cartProvider.loadCart();
      expect(cartProvider.isEmpty, false);
      expect(cartProvider.totalItemCount, 2);
      expect(cartProvider.items.first.product.id, 'p1');
    });
  });
}
