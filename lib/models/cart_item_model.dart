import '../utils/weight_engine.dart';
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

  double get weightKg => WeightEngine.resolve(
        product: product,
        selectedVariant: selectedVariant,
        quantity: quantity,
      );

  CartItem copyWith({
    ProductModel? product,
    ShopModel? shop,
    int? quantity,
    String? specialInstructions,
    ProductVariant? selectedVariant,
  }) {
    return CartItem(
      product: product ?? this.product,
      shop: shop ?? this.shop,
      quantity: quantity ?? this.quantity,
      specialInstructions: specialInstructions ?? this.specialInstructions,
      selectedVariant: selectedVariant ?? this.selectedVariant,
    );
  }

  Map<String, dynamic> toMap() => {
        'product': product.toMap(),
        'shop': shop.toMap(),
        'quantity': quantity,
        'special_instructions': specialInstructions,
        'selected_variant': selectedVariant?.toMap(),
      };

  factory CartItem.fromMap(Map<String, dynamic> map) {
    return CartItem(
      product: ProductModel.fromMap(map['product'] != null
          ? Map<String, dynamic>.from(map['product'] as Map)
          : <String, dynamic>{}),
      shop: ShopModel.fromMap(map['shop'] != null
          ? Map<String, dynamic>.from(map['shop'] as Map)
          : <String, dynamic>{}),
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
      specialInstructions: map['special_instructions'] as String?,
      selectedVariant: map['selected_variant'] != null
          ? ProductVariant.fromMap(
              Map<String, dynamic>.from(map['selected_variant'] as Map))
          : null,
    );
  }
}
