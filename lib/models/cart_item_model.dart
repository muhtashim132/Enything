import 'product_model.dart';
import 'shop_model.dart';

class CartItem {
  final ProductModel product;
  final ShopModel shop;
  int quantity;
  String? specialInstructions;
  ProductVariant? selectedVariant;

  CartItem({
    required this.product,
    required this.shop,
    this.quantity = 1,
    this.specialInstructions,
    this.selectedVariant,
  });

  double get totalPrice => (selectedVariant?.price ?? product.price) * quantity;

  double get weightKg {
    final w = product.weightPerUnit ?? 0.5;
    switch (product.unitType) {
      case 'kg': return w * quantity;
      case 'grams': return (w / 1000) * quantity;
      case 'liter': return w * quantity;
      case 'ml': return (w / 1000) * quantity;
      case 'pieces': return w * quantity;
      default: return 0.5 * quantity;
    }
  }
}
