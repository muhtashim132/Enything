import 'package:flutter_test/flutter_test.dart';
import 'package:enythingmobilenew/models/product_model.dart';
import 'package:enythingmobilenew/utils/weight_engine.dart';

void main() {
  group('100x WeightEngine Verification Suite', () {
    test('1 Piece Jeans Pants baseline calculation', () {
      final jeans = ProductModel(
        id: 'p-jeans-1',
        shopId: 's-1',
        name: 'Calvin Klein Slim Fit Jeans',
        category: 'Clothing',
        price: 5999,
        unitType: 'pieces',
      );

      final weight = WeightEngine.resolve(product: jeans, quantity: 1);
      expect(weight, equals(0.65)); // 650g for standard jeans
    });

    test('Pack of 3 Jeans calculation via Regex Multiplier', () {
      final packJeans = ProductModel(
        id: 'p-jeans-3',
        shopId: 's-1',
        name: 'Denim Jeans (Pack of 3)',
        category: 'Clothing',
        price: 3499,
        unitType: 'pieces',
      );

      final weight = WeightEngine.resolve(product: packJeans, quantity: 1);
      expect(weight, closeTo(1.95, 0.01)); // 0.65 * 3 = 1.95 kg
    });

    test('Sanity Guard auto-corrects seller 650 kg typo to 0.65 kg', () {
      final typoJeans = ProductModel(
        id: 'p-jeans-typo',
        shopId: 's-1',
        name: 'Designer Jeans Pant',
        category: 'Clothing',
        price: 2999,
        weightPerUnit: 650, // Seller typed 650
        unitType: 'kg', // but selected kg instead of grams
      );

      final weight = WeightEngine.resolve(product: typoJeans, quantity: 1);
      expect(weight, equals(0.65)); // Auto-corrected to 0.65 kg
    });

    test('Variant size scaling on jeans (XS vs XXL)', () {
      final jeans = ProductModel(
        id: 'p-jeans-var',
        shopId: 's-1',
        name: 'Levi 501 Original Fit Jeans',
        category: 'Clothing',
        price: 4999,
        unitType: 'pieces',
      );

      final xsVariant = ProductVariant(id: 'v-xs', name: 'Size 28 / XS', price: 4999);
      final xxlVariant = ProductVariant(id: 'v-xxl', name: 'Size 38 / XXL', price: 4999);

      final xsWeight = WeightEngine.resolve(product: jeans, selectedVariant: xsVariant, quantity: 1);
      final xxlWeight = WeightEngine.resolve(product: jeans, selectedVariant: xxlVariant, quantity: 1);

      expect(xsWeight, closeTo(0.65 * 0.88, 0.01)); // ~0.572 kg
      expect(xxlWeight, closeTo(0.65 * 1.18, 0.01)); // ~0.767 kg
      expect(xxlWeight > xsWeight, isTrue);
    });

    test('Pharmacy strip of tablets vs syrup bottle', () {
      final dolo = ProductModel(
        id: 'p-dolo',
        shopId: 's-pharma',
        name: 'Dolo 650 tablets (Strip of 15)',
        category: 'Pharmacy',
        price: 33,
        unitType: 'pieces',
      );

      final syrup = ProductModel(
        id: 'p-syrup',
        shopId: 's-pharma',
        name: 'Benadryl Cough Syrup 100ml',
        category: 'Pharmacy',
        price: 125,
        unitType: 'pieces',
      );

      final doloWeight = WeightEngine.resolve(product: dolo, quantity: 1);
      final syrupWeight = WeightEngine.resolve(product: syrup, quantity: 1);

      expect(doloWeight, equals(0.02)); // 20g strip
      expect(syrupWeight, closeTo(0.102, 0.02)); // 100ml liquid ~102g
    });

    test('Food items (Pizza vs Burger vs Biryani)', () {
      final pizza = ProductModel(
        id: 'p-pizza',
        shopId: 's-rest',
        name: 'Farmhouse Medium Pizza',
        category: 'Fast Food',
        price: 399,
      );

      final burger = ProductModel(
        id: 'p-burger',
        shopId: 's-rest',
        name: 'Veg Whopper Burger',
        category: 'Fast Food',
        price: 179,
      );

      expect(WeightEngine.resolve(product: pizza, quantity: 1), equals(0.55));
      expect(WeightEngine.resolve(product: burger, quantity: 1), equals(0.25));
    });

    test('Dairy liquid density (Milk 1L vs Milk 500ml)', () {
      final milk1L = ProductModel(
        id: 'p-milk-1',
        shopId: 's-dairy',
        name: 'Amul Taaza Milk 1L',
        category: 'Dairy & Eggs',
        price: 68,
      );

      final milk500ml = ProductModel(
        id: 'p-milk-2',
        shopId: 's-dairy',
        name: 'Amul Taaza Milk 500ml',
        category: 'Dairy & Eggs',
        price: 34,
      );

      expect(WeightEngine.resolve(product: milk1L, quantity: 1), closeTo(1.02, 0.02));
      expect(WeightEngine.resolve(product: milk500ml, quantity: 1), closeTo(0.51, 0.02));
    });

    test('Electronics (Laptop vs Phone vs Earbuds)', () {
      final laptop = ProductModel(
        id: 'p-lap',
        shopId: 's-elec',
        name: 'MacBook Air M2 13 inch',
        category: 'Electronics',
        price: 99990,
      );

      final phone = ProductModel(
        id: 'p-phone',
        shopId: 's-elec',
        name: 'iPhone 15 128GB',
        category: 'Electronics',
        price: 72999,
      );

      final earbuds = ProductModel(
        id: 'p-ear',
        shopId: 's-elec',
        name: 'AirPods Pro 2 TWS',
        category: 'Electronics',
        price: 24900,
      );

      expect(WeightEngine.resolve(product: laptop, quantity: 1), equals(2.40));
      expect(WeightEngine.resolve(product: phone, quantity: 1), equals(0.45));
      expect(WeightEngine.resolve(product: earbuds, quantity: 1), equals(0.12));
    });
  });
}
