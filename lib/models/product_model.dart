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
  final bool requiresPrescription;
  final String medicineType;
  final String? cutoutUrl; // AI-processed transparent PNG (background removed)

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
    this.requiresPrescription = false,
    this.medicineType = 'General',
    this.cutoutUrl,
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
      requiresPrescription: map['requires_prescription'] ?? false,
      medicineType: map['medicine_type'] ?? 'General',
      cutoutUrl: map['cutout_url'],
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
  };

  String get firstImage => images.isNotEmpty ? images.first : '';

  /// Returns the cutout (transparent PNG) if available, otherwise the first raw image.
  /// Use this everywhere in the UI to automatically show the best quality image.
  String get displayImage {
    if (cutoutUrl != null && cutoutUrl!.isNotEmpty) return cutoutUrl!;
    return firstImage;
  }

  /// True when the AI has processed this product's image
  bool get hasCutout => cutoutUrl != null && cutoutUrl!.isNotEmpty;

  double? get discountPercent {
    if (originalPrice != null && originalPrice! > price) {
      return ((originalPrice! - price) / originalPrice! * 100);
    }
    return null;
  }
}
