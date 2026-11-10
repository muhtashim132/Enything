import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:enythingmobilenew/models/cart_item_model.dart';
import 'package:enythingmobilenew/models/product_model.dart';
import 'package:enythingmobilenew/models/shop_model.dart';
import 'package:enythingmobilenew/providers/cart_provider.dart';
import 'package:enythingmobilenew/utils/weight_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mockShop = ShopModel(
    id: 'shop-001',
    sellerId: 'seller-001',
    name: 'SuperMart',
    shopType: 'retail',
    category: 'Grocery',
    categories: const ['Grocery'],
    address: '123 Main Street',
    location: const LatLng(12.9716, 77.5946),
    isActive: true,
    isAcceptingOrders: true,
  );

  group('100x WeightEngine Resolution Fortress', () {
    test('Converts explicit units (kg, g, mg, L, ml) correctly with liquid density', () {
      // 500 grams -> 0.50 kg
      final pGrams = ProductModel(
        id: 'p-1',
        shopId: 'shop-1',
        name: 'Haldiram Bhujia',
        price: 120,
        weightPerUnit: 500,
        unitType: 'g',
        category: 'Grocery',
      );
      expect(WeightEngine.resolveUnit(product: pGrams), closeTo(0.50, 0.001));

      // 1.5 Kilograms -> 1.50 kg
      final pKg = ProductModel(
        id: 'p-2',
        shopId: 'shop-1',
        name: 'Aashirvaad Atta',
        price: 90,
        weightPerUnit: 1.5,
        unitType: 'kg',
        category: 'Grocery',
      );
      expect(WeightEngine.resolveUnit(product: pKg), closeTo(1.50, 0.001));

      // 250 Milligrams -> 0.00025 kg
      final pMg = ProductModel(
        id: 'p-3',
        shopId: 'shop-1',
        name: 'Paracetamol Tablets',
        price: 30,
        weightPerUnit: 250,
        unitType: 'mg',
        category: 'Pharmacy',
      );
      expect(WeightEngine.resolveUnit(product: pMg), closeTo(0.00025, 0.00001));

      // 1 Litre of liquid (Density 1.02) -> 1.02 kg
      final pLiter = ProductModel(
        id: 'p-4',
        shopId: 'shop-1',
        name: 'Fortune Sunflower Oil',
        price: 150,
        weightPerUnit: 1,
        unitType: 'L',
        category: 'Grocery',
      );
      expect(WeightEngine.resolveUnit(product: pLiter), closeTo(1.02, 0.001));

      // 500 Millilitres -> 0.51 kg
      final pMl = ProductModel(
        id: 'p-5',
        shopId: 'shop-1',
        name: 'Amul Milk',
        price: 35,
        weightPerUnit: 500,
        unitType: 'ml',
        category: 'Dairy',
      );
      expect(WeightEngine.resolveUnit(product: pMl), closeTo(0.51, 0.001));
    });

    test('Protects 5G/4G tech cellular designations from matching as grams', () {
      final p5g = ProductModel(
        id: 'p-tech-1',
        shopId: 'shop-1',
        name: 'Realme 12 Pro 5G (8GB RAM, 256GB)',
        price: 24999,
        category: 'Electronics',
      );
      // Must not match "5G" as 5 grams (0.005 kg). Must fall back to electronics default 0.40 kg.
      expect(WeightEngine.resolveUnit(product: p5g), closeTo(0.40, 0.01));

      final p4g = ProductModel(
        id: 'p-tech-2',
        shopId: 'shop-1',
        name: 'Samsung Galaxy A15 4G Smartphone',
        price: 12999,
        category: 'Electronics',
      );
      expect(WeightEngine.resolveUnit(product: p4g), closeTo(0.40, 0.01));
    });

    test('Parses multi-packs, BOGO, and prefix multiplier titles correctly', () {
      final pPack = ProductModel(
        id: 'p-pack-1',
        shopId: 'shop-1',
        name: 'Pack of 3 Trident Sugar Free Gum (14 Sticks)',
        price: 450,
        category: 'Hypermarket',
      );
      // Trident base 0.035 kg * 3 = 0.105 kg
      expect(WeightEngine.resolveUnit(product: pPack), closeTo(0.105, 0.005));

      final pBogo = ProductModel(
        id: 'p-bogo-1',
        shopId: 'shop-1',
        name: 'Ariel Liquid Detergent 1L (Buy 1 Get 1 Free)',
        price: 399,
        category: 'Supermarket',
      );
      // 1L = 1.02 kg * 2 = 2.04 kg
      expect(WeightEngine.resolveUnit(product: pBogo), closeTo(2.04, 0.01));
    });

    test('Correctly calculates unweighted items across categories including Grocerylm', () {
      // Grocerylm category must inherit the complete supermarket heuristics
      final pGrocerylm = ProductModel(
        id: 'p-glm-1',
        shopId: 'shop-1',
        name: 'Potato Fresh 1kg',
        price: 40,
        category: 'Grocerylm',
      );
      expect(WeightEngine.resolveUnit(product: pGrocerylm), closeTo(1.0, 0.001));

      // Chewing gum & rolls
      final pGum = ProductModel(
        id: 'p-gum-1',
        shopId: 'shop-1',
        name: "Wrigley's Doublemint Peppermint Gum (5 Sticks)",
        price: 10,
        category: 'Hypermarket',
      );
      expect(WeightEngine.resolveUnit(product: pGum), closeTo(0.035, 0.005));

      final pMentos = ProductModel(
        id: 'p-gum-2',
        shopId: 'shop-1',
        name: 'Mentos Mint Chewy Dragees Roll (29.7g)',
        price: 30,
        category: 'Supermarket',
      );
      expect(WeightEngine.resolveUnit(product: pMentos), closeTo(0.0297, 0.005));

      // Micro produce: Lemon, Garlic, Chilli
      final pLemon = ProductModel(
        id: 'p-veg-1',
        shopId: 'shop-1',
        name: 'Fresh Lemon (1 pc)',
        price: 5,
        category: 'Fruits & Vegs',
      );
      expect(WeightEngine.resolveUnit(product: pLemon), closeTo(0.05, 0.001));

      // Heavy produce: Watermelon
      final pMelon = ProductModel(
        id: 'p-veg-2',
        shopId: 'shop-1',
        name: 'Sweet Watermelon (1 piece)',
        price: 120,
        category: 'Fruits & Vegs',
      );
      expect(WeightEngine.resolveUnit(product: pMelon), closeTo(2.5, 0.1));

      // Glass perfume bottle: Envy 100ml
      final pPerfume = ProductModel(
        id: 'p-beauty-1',
        shopId: 'shop-1',
        name: 'Envy Aura Eau De Parfum (100ml)',
        price: 649,
        category: 'Cosmetics',
      );
      expect(WeightEngine.resolveUnit(product: pPerfume), closeTo(0.28, 0.02));
    });

    test('Allows selected variant weight to directly override base product weight', () {
      final pBase = ProductModel(
        id: 'p-var-1',
        shopId: 'shop-1',
        name: 'Organic Honey',
        price: 150,
        weightPerUnit: 200,
        unitType: 'g',
        category: 'Grocery',
      );
      // Base product is 200g (0.20 kg)
      expect(WeightEngine.resolveUnit(product: pBase), closeTo(0.20, 0.001));

      // Variant specifies 1 kg
      final v1kg = ProductVariant(id: 'v1', name: '1 kg Jar', price: 650);
      expect(WeightEngine.resolveUnit(product: pBase, selectedVariant: v1kg), closeTo(1.0, 0.001));

      // Variant specifies 500g
      final v500g = ProductVariant(id: 'v2', name: '500g Pack', price: 350);
      expect(WeightEngine.resolveUnit(product: pBase, selectedVariant: v500g), closeTo(0.50, 0.001));
    });
  });

  group('100x CartItemModel Unit Weight Disentanglement', () {
    test('Stores unitWeightKg and computes totalWeightKg accurately', () {
      final prod = ProductModel(
        id: 'p-dis-1',
        shopId: 'shop-1',
        name: 'Basmati Rice 1kg',
        price: 100,
        weightPerUnit: 1,
        unitType: 'kg',
        category: 'Grocery',
      );

      final item = CartItem(
        product: prod,
        shop: mockShop,
        quantity: 4,
      );

      expect(item.unitWeightKg, closeTo(1.0, 0.001));
      expect(item.totalWeightKg, closeTo(4.0, 0.001));
      expect(item.weightKg, closeTo(4.0, 0.001)); // Backward compatible alias
    });
  });

  group('100x CartProvider 15.0 kg Hard Stop Fortress', () {
    late CartProvider cart;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      cart = CartProvider();
      cart.clear();
    });

    test('Prevents single item exceeding 15 kg from being added', () {
      final giantItem = ProductModel(
        id: 'p-heavy-1',
        shopId: 'shop-1',
        name: 'Commercial Flour Sack 25kg',
        price: 1200,
        weightPerUnit: 25,
        unitType: 'kg',
        category: 'Grocery',
      );

      expect(cart.canAddItem(giantItem), isFalse);
      final err = cart.addItem(giantItem, mockShop);
      expect(err, isNotNull);
      expect(err, contains('15 kg'));
      expect(cart.totalItemCount, 0);
    });

    test('Allows additions up to 15 kg and strictly blocks at or above 15 kg ceiling', () {
      final bag5kg = ProductModel(
        id: 'p-bag-5',
        shopId: 'shop-1',
        name: 'Aashirvaad Atta 5kg',
        price: 250,
        weightPerUnit: 5,
        unitType: 'kg',
        category: 'Grocery',
      );

      // Add 1 bag (5 kg total)
      expect(cart.canAddItem(bag5kg), isTrue);
      cart.addItem(bag5kg, mockShop, quantity: 1);
      expect(cart.totalWeight, closeTo(5.0, 0.001));
      expect(cart.isMaxWeightReached, isFalse);
      expect(cart.isHeavyOrder, isFalse); // < 10 kg
      expect(cart.remainingWeightCapacityKg, closeTo(10.0, 0.001));

      // Add second bag (10 kg total)
      cart.addItem(bag5kg, mockShop, quantity: 1);
      expect(cart.totalWeight, closeTo(10.0, 0.001));
      expect(cart.isMaxWeightReached, isFalse);
      expect(cart.isHeavyOrder, isFalse); // Exactly at 10.0 kg
      expect(cart.remainingWeightCapacityKg, closeTo(5.0, 0.001));

      // Add third bag (15 kg total) -> Hits the exact 15 kg cap
      cart.addItem(bag5kg, mockShop, quantity: 1);
      expect(cart.totalWeight, closeTo(15.0, 0.001));
      expect(cart.isMaxWeightReached, isTrue);
      expect(cart.isHeavyOrder, isTrue); // > 10 kg
      expect(cart.remainingWeightCapacityKg, closeTo(0.0, 0.001));

      // Attempt to add 1 more unit of any product -> Must be rejected
      final smallGum = ProductModel(
        id: 'p-gum-extra',
        shopId: 'shop-1',
        name: 'Trident Sugar Free Gum',
        price: 150,
        category: 'Hypermarket',
      );

      expect(cart.canAddItem(smallGum), isFalse);
      expect(cart.canIncrementProduct(bag5kg.id), isFalse);

      final err = cart.addItem(smallGum, mockShop);
      expect(err, isNotNull);
      expect(err, contains('15 kg'));
      expect(cart.items.length, 1);
      expect(cart.items.first.quantity, 3); // Untouched
    });

    test('updateQuantity enforces 15 kg limit and prevents capacity violation', () {
      final bag2kg = ProductModel(
        id: 'p-bag-2',
        shopId: 'shop-1',
        name: 'Basmati Rice 2kg',
        price: 200,
        weightPerUnit: 2,
        unitType: 'kg',
        category: 'Grocery',
      );

      cart.addItem(bag2kg, mockShop, quantity: 5); // 10 kg
      expect(cart.totalWeight, closeTo(10.0, 0.001));

      // Increment to 7 bags (14 kg) -> Allowed
      final errAllowed = cart.updateQuantity(bag2kg.id, 7);
      expect(errAllowed, isNull);
      expect(cart.totalWeight, closeTo(14.0, 0.001));

      // Attempt to jump to 8 bags (16 kg) -> Blocked
      final errBlocked = cart.updateQuantity(bag2kg.id, 8);
      expect(errBlocked, isNotNull);
      expect(errBlocked, contains('15 kg'));
      expect(cart.items.first.quantity, 7); // Clamped at 7
      expect(cart.totalWeight, closeTo(14.0, 0.001));
    });

    test('Integer gram summation eliminates IEEE 754 floating point drift', () {
      final pDrift = ProductModel(
        id: 'p-drift',
        shopId: 'shop-1',
        name: 'Canned Drink 330ml',
        price: 40,
        weightPerUnit: 330,
        unitType: 'ml',
        category: 'Beverages',
      );

      // 330ml * 1.02 density = 0.3366 kg = 337 grams
      for (int i = 0; i < 10; i++) {
        cart.addItem(pDrift, mockShop, quantity: 1);
      }

      // Total must be an exact rounded multiple without 0.00000000000004 noise
      expect(cart.totalWeight.toString().split('.').last.length, lessThanOrEqualTo(3));
    });
  });
}
