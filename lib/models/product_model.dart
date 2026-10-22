import '../config/app_categories.dart';

enum VegFilterMode { all, vegOnly, nonVegOnly }

class ProductVariant {
  final String id;
  final String name;
  final double price;
  final double? originalPrice;
  final bool isAvailable;
  final String? imageUrl;

  ProductVariant({
    required this.id,
    required this.name,
    required this.price,
    this.originalPrice,
    this.isAvailable = true,
    this.imageUrl,
  });

  factory ProductVariant.fromMap(Map<String, dynamic> map) {
    return ProductVariant(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      price: ProductModel._parseDouble(map['price']),
      originalPrice: ProductModel._parseDoubleNullable(map['original_price']),
      isAvailable: map['is_available'] ?? true,
      imageUrl: map['image_url'],
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'price': price,
        'original_price': originalPrice,
        'is_available': isAvailable,
        if (imageUrl != null) 'image_url': imageUrl,
      };

  double? get discountPercent {
    if (originalPrice != null && originalPrice! > price) {
      return ((originalPrice! - price) / originalPrice! * 100);
    }
    return null;
  }

  ProductVariant copyWith({
    String? id,
    String? name,
    double? price,
    double? originalPrice,
    bool? isAvailable,
    String? imageUrl,
  }) {
    return ProductVariant(
      id: id ?? this.id,
      name: name ?? this.name,
      price: price ?? this.price,
      originalPrice: originalPrice ?? this.originalPrice,
      isAvailable: isAvailable ?? this.isAvailable,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }
}

class ProductModel {
  final String id;
  final String shopId;
  final String name;
  final String category;
  final String? subCategory;
  final String? brand;
  final double price;
  final double? originalPrice;
  final int? totalQuantity;
  final double? weightPerUnit;
  final String unitType;
  final String? description;
  final List<String> images;
  final bool? isVeg;
  final String? menuCategory;
  final int? prepTimeMinutes;
  final List<String> specialTags;
  final bool isAvailable;
  final double rating;
  final int totalReviews;
  final bool requiresPrescription;
  final String medicineType;
  final List<ProductVariant> variants;

  /// Product-level GST override rate (e.g. 0.05 = 5%).
  /// If null, the checkout falls back to the category-level rate from tax_config.
  final double? gstRateOverride;

  /// Bulk / Event catering configuration
  final bool bulkEligible;
  final int? minBulkQuantity;
  final List<Map<String, dynamic>> bulkPriceTiers;

  ProductModel({
    required this.id,
    required this.shopId,
    required this.name,
    required this.category,
    this.subCategory,
    this.brand,
    required this.price,
    this.originalPrice,
    this.totalQuantity,
    this.weightPerUnit,
    this.unitType = 'pieces',
    this.description,
    this.images = const [],
    this.isVeg,
    this.menuCategory,
    this.prepTimeMinutes,
    this.specialTags = const [],
    this.isAvailable = true,
    this.rating = 0.0,
    this.totalReviews = 0,
    this.requiresPrescription = false,
    this.medicineType = 'General',
    this.variants = const [],
    this.gstRateOverride,
    this.bulkEligible = false,
    this.minBulkQuantity,
    this.bulkPriceTiers = const [],
  });

  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  static double? _parseDoubleNullable(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static int? _parseIntNullable(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  factory ProductModel.fromMap(Map<String, dynamic> map) {
    List<String> imageList = [];
    if (map['images'] != null) {
      if (map['images'] is List) {
        imageList = List<String>.from(map['images']);
      } else if (map['images'] is Map) {
        imageList = List<String>.from(map['images']['urls'] ?? []);
      }
    }

    return ProductModel(
      id: map['id'] ?? '',
      shopId: map['shop_id'] ?? '',
      name: map['name'] ?? '',
      category: map['category'] ?? '',
      subCategory: map['sub_category'],
      brand: map['brand'],
      price: _parseDouble(map['price']),
      originalPrice: _parseDoubleNullable(map['original_price']),
      totalQuantity: _parseIntNullable(map['total_quantity']),
      weightPerUnit: _parseDoubleNullable(map['weight_per_unit']),
      unitType: map['unit_type'] ?? 'pieces',
      description: map['description'],
      images: imageList,
      isVeg: AppCategories.isFoodCategory(map['category']?.toString())
          ? map['is_veg']
          : null,
      menuCategory: map['menu_category'],
      prepTimeMinutes: _parseIntNullable(map['prep_time_minutes']),
      specialTags: map['special_tags'] is List
          ? (map['special_tags'] as List).map((e) => e.toString()).toList()
          : [],
      isAvailable: map['is_available'] ?? true,
      rating: _parseDouble(map['rating']),
      totalReviews: _parseIntNullable(map['total_reviews']) ?? 0,
      requiresPrescription: map['requires_prescription'] ?? false,
      medicineType: map['medicine_type'] ?? 'General',
      variants: (map['variants'] as List<dynamic>?)
              ?.map((v) => ProductVariant.fromMap(v as Map<String, dynamic>))
              .toList() ??
          [],
      gstRateOverride: _parseDoubleNullable(map['gst_rate_override']),
      bulkEligible: map['bulk_eligible'] == true || map['bulk_eligible'] == 'true',
      minBulkQuantity: _parseIntNullable(map['min_bulk_quantity']),
      bulkPriceTiers: (map['bulk_price_tiers'] as List?)
              ?.map((t) => Map<String, dynamic>.from(t as Map))
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toMap() => {
        if (id.isNotEmpty) 'id': id,
        'shop_id': shopId,
        'name': name,
        'category': category,
        'sub_category': subCategory,
        'brand': brand,
        'price': price,
        'original_price': originalPrice,
        'total_quantity': totalQuantity,
        'weight_per_unit': weightPerUnit,
        'unit_type': unitType,
        'description': description,
        'images': images,
        'is_veg': isFood ? isVeg : null,
        'menu_category': menuCategory,
        'prep_time_minutes': prepTimeMinutes,
        'special_tags': specialTags,
        'is_available': isAvailable,
        'requires_prescription': requiresPrescription,
        'medicine_type': medicineType,
        'variants': variants.map((v) => v.toMap()).toList(),
        'gst_rate_override': gstRateOverride,
        'bulk_eligible': bulkEligible,
        'min_bulk_quantity': minBulkQuantity,
        'bulk_price_tiers': bulkPriceTiers,
      };

  String get firstImage => images.isNotEmpty ? images.first : '';

  /// Returns the primary product image
  String get displayImage {
    return firstImage;
  }

  double? get discountPercent {
    if (originalPrice != null && originalPrice! > price) {
      return ((originalPrice! - price) / originalPrice! * 100);
    }
    return null;
  }

  ProductModel copyWith({
    String? id,
    String? shopId,
    String? name,
    String? category,
    String? subCategory,
    String? brand,
    double? price,
    double? originalPrice,
    int? totalQuantity,
    double? weightPerUnit,
    String? unitType,
    String? description,
    List<String>? images,
    bool? isVeg,
    String? menuCategory,
    int? prepTimeMinutes,
    List<String>? specialTags,
    bool? isAvailable,
    double? rating,
    int? totalReviews,
    bool? requiresPrescription,
    String? medicineType,
    List<ProductVariant>? variants,
    double? gstRateOverride,
    bool? bulkEligible,
    int? minBulkQuantity,
    List<Map<String, dynamic>>? bulkPriceTiers,
  }) {
    return ProductModel(
      id: id ?? this.id,
      shopId: shopId ?? this.shopId,
      name: name ?? this.name,
      category: category ?? this.category,
      subCategory: subCategory ?? this.subCategory,
      brand: brand ?? this.brand,
      price: price ?? this.price,
      originalPrice: originalPrice ?? this.originalPrice,
      totalQuantity: totalQuantity ?? this.totalQuantity,
      weightPerUnit: weightPerUnit ?? this.weightPerUnit,
      unitType: unitType ?? this.unitType,
      description: description ?? this.description,
      images: images ?? this.images,
      isVeg: isVeg ?? this.isVeg,
      menuCategory: menuCategory ?? this.menuCategory,
      prepTimeMinutes: prepTimeMinutes ?? this.prepTimeMinutes,
      specialTags: specialTags ?? this.specialTags,
      isAvailable: isAvailable ?? this.isAvailable,
      rating: rating ?? this.rating,
      totalReviews: totalReviews ?? this.totalReviews,
      requiresPrescription: requiresPrescription ?? this.requiresPrescription,
      medicineType: medicineType ?? this.medicineType,
      variants: variants ?? this.variants,
      gstRateOverride: gstRateOverride ?? this.gstRateOverride,
      bulkEligible: bulkEligible ?? this.bulkEligible,
      minBulkQuantity: minBulkQuantity ?? this.minBulkQuantity,
      bulkPriceTiers: bulkPriceTiers ?? this.bulkPriceTiers,
    );
  }

  /// Calculates the unit price for a given quantity based on tiered pricing
  double getPriceForQuantity(int quantity) {
    if (!bulkEligible || bulkPriceTiers.isEmpty) {
      return price;
    }
    // Sort tiers descending by min_qty
    final sortedTiers = List<Map<String, dynamic>>.from(bulkPriceTiers)
      ..sort((a, b) => (_parseIntNullable(b['min_qty']) ?? 0)
          .compareTo(_parseIntNullable(a['min_qty']) ?? 0));

    for (final tier in sortedTiers) {
      final minQty = _parseIntNullable(tier['min_qty']) ?? 0;
      if (quantity >= minQty) {
        final tierPrice = _parseDoubleNullable(tier['price']);
        if (tierPrice != null && tierPrice > 0) {
          return tierPrice;
        }
      }
    }
    return price;
  }

  /// Returns whether this product belongs to an edible food, dining, grocery, or perishable category.
  bool get isFood => AppCategories.isFoodCategory(category);

  /// Returns whether this product should display a dietary preference marker (Veg/Non-Veg emblem).
  /// Strictly requires both:
  /// 1. isVeg must not be null.
  /// 2. category must be a recognized food or grocery category. Non-food items (Stationery, Clothing, Electronics, etc.) never show dietary emblems.
  bool get showsDietEmblem => isVeg != null && isFood;
}
