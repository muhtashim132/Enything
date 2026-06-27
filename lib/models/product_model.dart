class ProductVariant {
  final String id;
  final String name;
  final double price;
  final double? originalPrice;
  final bool isAvailable;

  ProductVariant({
    required this.id,
    required this.name,
    required this.price,
    this.originalPrice,
    this.isAvailable = true,
  });

  factory ProductVariant.fromMap(Map<String, dynamic> map) {
    return ProductVariant(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      price: (map['price'] ?? 0.0).toDouble(),
      originalPrice: map['original_price']?.toDouble(),
      isAvailable: map['is_available'] ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'price': price,
    'original_price': originalPrice,
    'is_available': isAvailable,
  };

  double? get discountPercent {
    if (originalPrice != null && originalPrice! > price) {
      return ((originalPrice! - price) / originalPrice! * 100);
    }
    return null;
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
  });

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
      price: (map['price'] ?? 0.0).toDouble(),
      originalPrice: map['original_price']?.toDouble(),
      totalQuantity: map['total_quantity'],
      weightPerUnit: map['weight_per_unit']?.toDouble(),
      unitType: map['unit_type'] ?? 'pieces',
      description: map['description'],
      images: imageList,
      isVeg: map['is_veg'],
      menuCategory: map['menu_category'],
      prepTimeMinutes: map['prep_time_minutes'],
      specialTags: List<String>.from(map['special_tags'] ?? []),
      isAvailable: map['is_available'] ?? true,
      rating: (map['rating'] ?? 0.0).toDouble(),
      totalReviews: map['total_reviews'] ?? 0,
      requiresPrescription: map['requires_prescription'] ?? false,
      medicineType: map['medicine_type'] ?? 'General',
      variants: (map['variants'] as List<dynamic>?)
              ?.map((v) => ProductVariant.fromMap(v as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toMap() => {
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
    'is_veg': isVeg,
    'menu_category': menuCategory,
    'prep_time_minutes': prepTimeMinutes,
    'special_tags': specialTags,
    'is_available': isAvailable,
    'requires_prescription': requiresPrescription,
    'medicine_type': medicineType,
    'variants': variants.map((v) => v.toMap()).toList(),
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
}
