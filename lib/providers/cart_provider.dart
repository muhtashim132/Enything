import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';
import '../models/cart_item_model.dart';
import '../models/product_model.dart';
import '../models/shop_model.dart';
import '../config/payment_config.dart';
import '../config/tax_config.dart';
import '../providers/platform_config_provider.dart';
import '../utils/delivery_calculator.dart';

// ---------------------------------------------------------------------------
// Serialization helpers (Bug #20)
// ---------------------------------------------------------------------------

Map<String, dynamic> _productToJson(ProductModel p) => {
  'id': p.id,
  'shop_id': p.shopId,
  'name': p.name,
  'category': p.category,
  'sub_category': p.subCategory,
  'brand': p.brand,
  'price': p.price,
  'original_price': p.originalPrice,
  'total_quantity': p.totalQuantity,
  'weight_per_unit': p.weightPerUnit,
  'unit_type': p.unitType,
  'description': p.description,
  'images': p.images,
  'is_veg': p.isVeg,
  'menu_category': p.menuCategory,
  'prep_time_minutes': p.prepTimeMinutes,
  'special_tags': p.specialTags,
  'is_available': p.isAvailable,
  'rating': p.rating,
  'requires_prescription': p.requiresPrescription,
  'medicine_type': p.medicineType,
  'gst_rate_override': p.gstRateOverride,
  'variants': p.variants.map((v) => v.toMap()).toList(),
};

ProductModel _productFromJson(Map<String, dynamic> m) => ProductModel.fromMap({
  ...m,
  'id': m['id'] ?? '',
});

Map<String, dynamic> _shopToJson(ShopModel s) => {
  'id': s.id,
  'seller_id': s.sellerId,
  'name': s.name,
  'shop_type': s.shopType,
  'cuisine_type': s.cuisineType,
  'fssai_number': s.fssaiNumber,
  'prep_time_minutes': s.prepTimeMinutes,
  'is_veg_only': s.isVegOnly,
  'opening_hours': s.openingHours,
  'address': s.address,
  // Store lat/lng manually since ShopModel uses POINT format in DB
  '_lat': s.location.latitude,
  '_lng': s.location.longitude,
  'category': s.category,
  'categories': s.categories,
  'is_active': s.isActive,
  'rating': s.rating,
  'total_reviews': s.totalReviews,
  'total_orders': s.totalOrders,
  'banner_image': s.bannerImage,
};

ShopModel _shopFromJson(Map<String, dynamic> m) {
  final lat = (m['_lat'] as num?)?.toDouble() ?? 0.0;
  final lng = (m['_lng'] as num?)?.toDouble() ?? 0.0;
  return ShopModel(
    id: m['id'] ?? '',
    sellerId: m['seller_id'] ?? '',
    name: m['name'] ?? '',
    shopType: m['shop_type'] ?? 'shop',
    cuisineType: m['cuisine_type'],
    fssaiNumber: m['fssai_number'],
    prepTimeMinutes: m['prep_time_minutes'] ?? 30,
    isVegOnly: m['is_veg_only'] ?? false,
    openingHours: m['opening_hours'],
    address: m['address'] ?? '',
    location: LatLng(lat, lng),
    category: m['category'] ?? 'Other',
    categories: List<String>.from(m['categories'] ?? []),
    isActive: m['is_active'] ?? true,
    rating: (m['rating'] ?? 4.0).toDouble(),
    totalReviews: m['total_reviews'] ?? 0,
    totalOrders: m['total_orders'] ?? 0,
    bannerImage: m['banner_image'],
  );
}

class CartProvider extends ChangeNotifier {
  static const String _cartKey = 'enything_cart_v2'; // Bumped for variant support
  static const String _legacyCartKey = 'enything_cart_v1';
  final List<CartItem> _items = [];

  CartProvider() {
    _safeAddPlatformListener();
  }

  void _safeAddPlatformListener([int retries = 0]) {
    if (PlatformConfigProvider.instance != null) {
      PlatformConfigProvider.instance!.addListener(notifyListeners);
    } else if (retries < 10) {
      Future.delayed(const Duration(milliseconds: 500), () => _safeAddPlatformListener(retries + 1));
    }
  }

  @override
  void dispose() {
    PlatformConfigProvider.instance?.removeListener(notifyListeners);
    _saveDebounce?.cancel();
    super.dispose();
  }

  List<CartItem> get items => List.unmodifiable(_items);
  bool get isEmpty => _items.isEmpty;

  int get totalItemCount => _items.fold(0, (sum, item) => sum + item.quantity);

  double get totalWeight =>
      _items.fold(0.0, (sum, item) => sum + item.weightKg);

  double get subtotal =>
      _items.fold(0.0, (sum, item) => sum + item.totalPrice);

  /// Unique shops in the order they were first added to the cart.
  List<ShopModel> get shops {
    final seen = <String>{};
    return _items
        .where((item) => seen.add(item.shop.id))
        .map((item) => item.shop)
        .toList();
  }

  bool get meetsMinimumOrder => subtotal >= PaymentConfig.minimumOrderValue;

  // PlatformConfigProvider.instance now safely attaches its listener even if it's delayed.
  // This ensures UI rebuilds instantly when admin updates platform fee or rates.
  double get platformFee => PlatformConfigProvider.instance?.platformFee ?? PaymentConfig.platformFee;

  bool get requiresPrescription => _items.any((item) => item.product.requiresPrescription);

  // ---------------------------------------------------------------------------
  // Add-On GST helpers (tax_config.dart — ADD-ON MODEL)
  // ---------------------------------------------------------------------------

  /// GST added ON TOP of the base item subtotal.
  /// This is a REAL charge to the customer — not extracted from MRP.
  double get itemGstTotal {
    double gst = 0;
    for (final item in _items) {
      final category = item.product.category;
      final price = item.product.price;
      // Use product-level override if set; otherwise use category rate (unchanged)
      final rate = TaxConfig.gstRateForProduct(
        category,
        item.product.gstRateOverride,
        itemPrice: price,
      );
      // Apply PlatformConfigProvider slab overrides only when no product override
      final effectiveRate = item.product.gstRateOverride != null
          ? rate
          : (PlatformConfigProvider.instance?.getGstRate(
                category,
                itemPrice: price,
              ) ??
              rate);
      gst += item.totalPrice * effectiveRate;
    }
    return gst;
  }

  /// Gross item total the customer pays = base subtotal + GST on items.
  double get itemGrossTotal => subtotal + itemGstTotal;

  /// Builds the [items] list required by [OrderTaxBreakdown.calculate].
  /// prices are BASE prices (pre-GST) — GST is added on top in the breakdown.
  List<Map<String, dynamic>> get taxBreakdownItems => _items
      .map((i) => {
            'category': i.product.category,
            'price': i.product.price, // BASE price, pre-GST
            'quantity': i.quantity,
            'gst_rate_override': i.product.gstRateOverride, // null = use category
          })
      .toList();

  double get smallCartFee {
    final threshold = PlatformConfigProvider.instance?.smallCartThreshold ?? PaymentConfig.smallCartThreshold;
    final fee = PlatformConfigProvider.instance?.smallCartFee ?? PaymentConfig.smallCartFee;
    return subtotal < threshold && subtotal > 0 ? fee : 0.0;
  }

  double get heavyOrderFee {
    final threshold = PlatformConfigProvider.instance?.heavyOrderThresholdKg ?? PaymentConfig.heavyOrderThreshold;
    final fee = PlatformConfigProvider.instance?.heavyOrderFee ?? PaymentConfig.heavyOrderFee;
    return totalWeight > threshold ? fee : 0.0;
  }

  /// True when items come from more than one shop.
  bool get isMultiShopOrder => shops.length > 1;

  String? addItem(ProductModel product, ShopModel shop,
      {int quantity = 1, ProductVariant? selectedVariant}) {
    if (totalItemCount + quantity > PaymentConfig.maxItemsPerOrder) {
      return 'Maximum ${PaymentConfig.maxItemsPerOrder} items allowed per order';
    }

    final unitWeightKg = CartItem(product: product, shop: shop, quantity: 1, selectedVariant: selectedVariant).weightKg;
    if (totalWeight + (unitWeightKg * quantity) > PaymentConfig.maxWeightKg) {
      return 'Maximum weight of ${PaymentConfig.maxWeightKg} kg allowed per order';
    }

    // Enforce max 3 unique shops
    final currentShops = shops.map((s) => s.id).toSet();
    if (!currentShops.contains(shop.id) && currentShops.length >= 3) {
      return 'Maximum 3 shops allowed per order. Please complete your current order first.';
    }

    final existingIdx = _items.indexWhere(
        (item) => item.product.id == product.id && item.selectedVariant?.name == selectedVariant?.name);

    if (existingIdx == -1) {
      _items.add(CartItem(
        product: product,
        shop: shop,
        quantity: quantity,
        selectedVariant: selectedVariant,
      ));
    } else {
      _items[existingIdx].quantity += quantity;
    }

    _saveCart(); // Bug #20
    notifyListeners();
    return null;
  }

  void addItemWithFeedback(BuildContext context, ProductModel product, ShopModel shop,
      {int quantity = 1, ProductVariant? selectedVariant}) {
    final err = addItem(product, shop, quantity: quantity, selectedVariant: selectedVariant);
    ScaffoldMessenger.of(context).clearSnackBars();
    
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err),
          backgroundColor: const Color(0xFFEF4444), // AppColors.danger fallback
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      final remaining = 3 - shops.length;
      final msg = remaining > 0
          ? '${shops.length} shop${shops.length > 1 ? 's' : ''} selected, $remaining remaining if needed'
          : 'Max 3 shops selected';
          
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${product.name} added to cart! 🛒', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(msg, style: const TextStyle(fontSize: 12)),
            ],
          ),
          backgroundColor: const Color(0xFF10B981), // AppColors.success fallback
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void removeItem(String productId, {String? variantName}) {
    _items.removeWhere((item) => item.product.id == productId && item.selectedVariant?.name == variantName);
    _saveCart(); // Bug #20
    notifyListeners();
  }

  void updateQuantity(String productId, int quantity, {String? variantName}) {
    final idx = _items.indexWhere((item) => item.product.id == productId && item.selectedVariant?.name == variantName);
    if (idx != -1) {
      if (quantity <= 0) {
        _items.removeAt(idx);
      } else {
        _items[idx].quantity = quantity;
      }
      _saveCart(); // Bug #20
      notifyListeners();
    }
  }

  void clear() {
    _items.clear();
    _saveCart(); // Bug #20
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Bug #20: Persistence — save & load cart via shared_preferences
  // ---------------------------------------------------------------------------

  Timer? _saveDebounce;

  /// Serialises the current cart to shared_preferences with debounce.
  Future<void> _saveCart() async {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final encoded = jsonEncode(_items.map((item) => {
          'product': _productToJson(item.product),
          'shop': _shopToJson(item.shop),
          'quantity': item.quantity,
          'special_instructions': item.specialInstructions,
          'selected_variant': item.selectedVariant?.toMap(),
        }).toList());
        await prefs.setString(_cartKey, encoded);
      } catch (e) {
        debugPrint('CartProvider: failed to save cart: $e');
      }
    });
  }

  /// Restores the cart from shared_preferences.
  /// Call this once during app startup (e.g., after MultiProvider is set up).
  Future<void> loadCart() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? raw = prefs.getString(_cartKey);
      
      // Fallback to legacy cart if new one doesn't exist
      if (raw == null || raw.isEmpty) {
        raw = prefs.getString(_legacyCartKey);
      }
      
      if (raw == null || raw.isEmpty) return;

      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      _items.clear();
      for (final entry in list) {
        final map = entry as Map<String, dynamic>;
        final product = _productFromJson(map['product'] as Map<String, dynamic>);
        final shop = _shopFromJson(map['shop'] as Map<String, dynamic>);
        final qty = (map['quantity'] as num?)?.toInt() ?? 1;
        final instructions = map['special_instructions'] as String?;
        final variantMap = map['selected_variant'] as Map<String, dynamic>?;
        
        _items.add(CartItem(
          product: product,
          shop: shop,
          quantity: qty,
          specialInstructions: instructions,
          selectedVariant: variantMap != null ? ProductVariant.fromMap(variantMap) : null,
        ));
      }
      notifyListeners();
    } catch (e) {
      debugPrint('CartProvider: failed to load cart: $e');
      // Corrupted data — wipe it
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_cartKey);
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------------------
  // Delivery charge helpers
  // ---------------------------------------------------------------------------

  /// Base delivery charge based on customer-to-shop distance and order value.
  double calculateDeliveryCharges(double distanceKm) {
    return DeliveryCalculator.calculateDeliveryCharges(distanceKm, subtotal);
  }

  /// Extra surcharge for ordering from multiple shops.
  ///
  /// Rules:
  ///   • 1 shop  → ₹0 surcharge
  ///   • 2nd shop → ₹10 × max(1, ceil(distance from 1st shop))
  ///   • 3rd+ shops → ₹10 × max(1, ceil(distance from nearest already-visited shop))
  double get multiShopSurcharge =>
      DeliveryCalculator.calculateMultiShopSurcharge(shops);

  /// Combined total including base delivery + inter-shop surcharge + small cart fee - discount.
  /// Option 1: GST is added ON TOP of the delivery charge so the customer pays it.
  double totalDeliveryCharges(double baseDistanceKm) {
    final base = calculateDeliveryCharges(baseDistanceKm);
    final effectiveBase = base >= 0 ? base : 25.0;
    double totalWithoutGst = effectiveBase + multiShopSurcharge + heavyOrderFee + smallCartFee;
    if (totalWithoutGst < 0) totalWithoutGst = 0.0;
    return totalWithoutGst * (1 + TaxConfig.deliveryGstRate);
  }

  int getItemQuantity(String productId, {String? variantName}) {
    try {
      return _items
          .where((item) => item.product.id == productId && item.selectedVariant?.name == variantName)
          .fold(0, (sum, item) => sum + item.quantity);
    } catch (_) {
      return 0;
    }
  }
}
