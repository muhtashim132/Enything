import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../providers/theme_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/platform_config_provider.dart';

import '../../providers/recently_viewed_provider.dart';
import '../../providers/referral_provider.dart';
import '../../providers/cart_provider.dart';

import '../../theme/app_colors.dart';
import '../../config/routes.dart';
import '../../models/product_model.dart';
import '../../models/shop_model.dart';
import '../../config/app_categories.dart';
import '../../utils/delivery_calculator.dart';
import '../../utils/demographic_utils.dart';
import '../../utils/responsive_layout.dart';
import '../../utils/search_relevance_engine.dart';
import '../../widgets/product_card.dart';
import '../../widgets/shop_card.dart';
import '../../widgets/restaurant_shop_card.dart';
import '../../widgets/product_search_card.dart';
import '../../widgets/shop_detail_sheet.dart';
import '../../widgets/restaurant_dashboard_sheet.dart';
import '../../widgets/common/notification_bell.dart';
import '../../widgets/common/animated_search_ticker.dart';
import '../../widgets/3d/perspective_card.dart';
import '../../theme/sensory_haptics.dart';
import '../../widgets/address_picker_sheet.dart';
import '../../providers/quote_request_provider.dart';
import 'all_listings_page.dart';

class CustomerHomeView extends StatefulWidget {
  const CustomerHomeView({super.key});

  /// 100x Cache Eviction: Clears in-memory static caches on role switches or location resets.
  static void invalidateStaticCache() {
    CustomerHomeViewState._cachedShops = null;
    CustomerHomeViewState._cachedProducts = null;
    CustomerHomeViewState._cachedProductShops = null;
    CustomerHomeViewState._cachedDepartmentProductCounts = null;
    CustomerHomeViewState._cachedLocation = null;
    CustomerHomeViewState._cacheTimestamp = null;
  }

  @override
  State<CustomerHomeView> createState() => CustomerHomeViewState();
}

enum _SortMode { relevant, bestRating, priceLow, priceHigh, discount, nearest }

class CustomerHomeViewState extends State<CustomerHomeView>
    with SingleTickerProviderStateMixin {
  static final ValueNotifier<bool> globalIsFiltering = ValueNotifier(false);

  // ── Homepage Feed In-Memory Cache ─────────────────────────────────────────
  // Avoids redundant RPC round-trips on GPS micro-updates (< 100 m movements).
  // Cache is static so it persists across widget rebuilds within the same session.
  static List<ShopModel>? _cachedShops;
  static List<ProductModel>? _cachedProducts;
  static Map<String, ShopModel>? _cachedProductShops;
  static Map<String, int>? _cachedDepartmentProductCounts;
  static LatLng? _cachedLocation;
  static DateTime? _cacheTimestamp;
  static const _cacheTtl = Duration(minutes: 5);

  void resetToHome() {
    if (!mounted) return;
    setState(() {
      _selectedTabIndex = -1;
      _comingSoonMessage = null;
      _comingSoonSubMessage = null;
      _selectedFilterCategories.clear();
      _selectedSizes.clear();
      _selectedFeedDemographic = 'All';
      _searchQuery = '';
      _searchController.clear();
    });
    _loadAllData();
  }

  SupabaseClient get _supabase => Supabase.instance.client;
  int _selectedTabIndex = -1; // -1 = no tab selected (show ALL)
  String? _comingSoonMessage;
  String? _comingSoonSubMessage;
  bool _isLoading = true;
  bool _isSearching = false;
  bool _searchError = false;
  String _searchErrorMessage = '';
  int _shopsDisplayLimit = 3;
  int _productsDisplayLimit = 6;
  int _searchShopsDisplayLimit = 12;
  List<ShopModel> _shops = [];
  List<ShopModel> _searchResults = [];
  List<ProductModel> _searchProductResults = [];
  Map<String, ShopModel> _searchProductShops = {};
  List<ProductModel> _products = [];
  Map<String, ShopModel> _productShops = {};
  Map<String, int> _departmentProductCounts = {};
  String _searchQuery = '';
  String _selectedSearchDemographic = 'All';
  String _selectedFeedDemographic = 'All'; // 'All', 'Men/Boys', 'Women/Girls'
  _SortMode _sortMode = _SortMode.relevant;
  VegFilterMode _vegFilterMode = VegFilterMode.all;
  final _searchController = TextEditingController();
  final Set<String> _selectedFilterCategories = {};
  final Set<String> _selectedSizes = {};
  final Set<String> _cachedAvailableSizes = {};

  static const Map<String, List<String>> _searchKeywords = {
    'Food': [
      'food',
      'eat',
      'hungry',
      'pizza',
      'burger',
      'meal',
      'restaurant',
      'fast food',
      'biryani',
      'chicken',
      'mutton',
      'kebab',
      'fries',
      'noodles',
      'noodle',
      'maggi',
      'pasta',
      'chowmein',
      'roll',
      'sandwich',
      'momos',
      'shawarma',
      'tea',
      'coffee',
      'dessert',
      'ice cream',
      'bakery',
      'cake',
      'pastry',
      'roti',
      'naan',
      'curry',
    ],
    'Grocery': [
      'grocery',
      'grocerylm',
      'milk',
      'bread',
      'eggs',
      'supermarket',
      'hypermarket',
      'ration',
      'vegetables',
      'fruits',
      'apple',
      'banana',
      'meat',
      'beef',
      'dal',
      'rice',
      'noodle',
      'noodles',
      'maggi',
      'pasta',
      'macaroni',
      'ramen',
      'spaghetti',
      'vermicelli',
      'snack',
      'snacks',
      'biscuit',
      'biscuits',
      'oil',
      'ghee',
      'atta',
      'flour',
      'sugar',
      'salt',
      'spices',
      'masala',
      'soap',
      'detergent',
      'toothpaste',
    ],
    'Pharmacy': [
      'pharmacy',
      'medicine',
      'medicines',
      'med',
      'meds',
      'pill',
      'pills',
      'tablet',
      'tablets',
      'tabs',
      'syrup',
      'suspension',
      'drops',
      'ointment',
      'cream',
      'gel',
      'capsule',
      'capsules',
      'injection',
      'inhaler',
      'medical',
      'health',
      'healthcare',
      'drug',
      'drugs',
      'panadol',
      'paracetamol',
      'dolo',
      'calpol',
      'rosuvastatin',
      'atorvastatin',
      'fenofibrate',
      'salts',
      'salt',
      'composition',
      'active ingredient',
      'clinic',
      'doctor',
      'chemist',
      'prescription',
      'rx',
      'antibiotic',
      'antacid',
      'painkiller',
      'analgesic',
      'vitamin',
      'vitamins',
      'multivitamin',
      'calcium',
      'iron',
      'fever',
      'cough',
      'cold',
      'headache',
      'flu',
      'infection',
      'allergy',
      'asthma',
      'bp',
      'blood pressure',
      'hypertension',
      'diabetes',
      'insulin',
      'thyroid',
      'cholesterol',
      'cardiac',
      'heart',
      'acidity',
      'gas',
      'digestion',
      'ayurvedic',
      'homeopathy',
      'first aid',
      'bandage',
      'dettol',
      'savlon',
      'antiseptic',
      'cotton',
      'thermometer',
      'oximeter',
      'bp monitor',
      'strip',
      'strips',
    ],
    'Clothing': [
      'clothing',
      'clothes',
      'shirt',
      'shirts',
      'tshirt',
      't-shirt',
      't-shirts',
      'pant',
      'pants',
      'trousers',
      'jeans',
      'denim',
      'shoes',
      'sneakers',
      'sandals',
      'slippers',
      'footwear',
      'fashion',
      'apparel',
      'wear',
      'dress',
      'dresses',
      'kurta',
      'salwar',
      'shawl',
      'pashmina',
      'pheran',
      'jacket',
      'jackets',
      'coat',
      'hoodie',
      'sweater',
      'sweatshirt',
      'socks',
      'suit',
      'top',
      'garments',
      'outfit',
      'jewellery',
    ],
    'Cosmetics': [
      'cosmetics',
      'cosmetic',
      'makeup',
      'beauty',
      'skincare',
      'skin care',
      'lipstick',
      'lipsticks',
      'lip balm',
      'eyeliner',
      'kajal',
      'mascara',
      'foundation',
      'compact',
      'face wash',
      'facewash',
      'lotion',
      'moisturizer',
      'sunscreen',
      'serum',
      'serums',
      'shampoo',
      'conditioner',
      'perfume',
      'perfumes',
      'deodorant',
      'deodorants',
      'body spray',
      'nail polish',
      'hair oil',
      'cleanser',
      'toner',
      'body wash',
      'face cream',
      'cream',
      'garnier',
      'mamaearth',
      'nivea',
      'loreal',
      'biotique',
      'cetaphil',
      'minimalist',
      'plum',
      'lakme',
      'maybelline',
    ],
    'Stationery': [
      'stationery',
      'notebook',
      'notebooks',
      'pen',
      'pens',
      'pencil',
      'pencils',
      'eraser',
      'sharpener',
      'scale',
      'ruler',
      'calculator',
      'file',
      'folder',
      'stapler',
      'scissors',
      'glue',
      'tape',
      'marker',
      'highlighter',
      'chart',
      'book',
      'books',
      'diary',
      'register',
    ],
    'More': [
      'toys',
      'games',
      'sports',
      'pet supplies',
      'flowers',
      'hardware',
      'home decor',
    ],
    'Electronics': [
      'electronics',
      'mobile',
      'phone',
      'laptop',
      'charger',
      'gadget',
      'device',
      'computer',
      'earbuds',
      'earphones',
      'headphones',
      'headset',
      'cable',
      'smartwatch',
      'watch',
      'powerbank',
      'speaker',
      'bluetooth',
      'cover',
      'tempered glass',
      'screen guard',
      'mouse',
      'keyboard',
    ],
  };
  // Debounce timer for GPS listener to prevent race conditions
  Timer? _locationDebounceTimer;

  int _compareAvailability(
      ProductModel a, ProductModel b, Map<String, ShopModel> shops) {
    final sA = shops[a.id];
    final sB = shops[b.id];
    final availA = a.isAvailable && (sA?.isOpenRightNow ?? true);
    final availB = b.isAvailable && (sB?.isOpenRightNow ?? true);
    if (availA && !availB) return -1;
    if (!availA && availB) return 1;
    return 0;
  }

  // ── Frame-Memoized Sorted Getters ──────────────────────────────────────────
  List<ProductModel>? _memoizedSortedProductResults;
  List<ProductModel>? _memoizedSortedNormalProducts;
  List<ProductModel>? _memoizedSortedPharmacyProducts;
  List<ProductModel>? _memoizedSortedClothingProducts;
  List<ProductModel>? _memoizedSortedFoodProducts;
  List<ProductModel>? _memoizedSortedCosmeticsProducts;
  List<ProductModel>? _memoizedSortedSupermarketProducts;
  List<ProductModel>? _memoizedSortedStationeryProducts;
  List<ProductModel>? _memoizedSortedMeatAndFishProducts;
  List<ProductModel>? _memoizedSortedDairyProducts;
  List<ProductModel>? _memoizedSortedBakeryProducts;
  List<ProductModel>? _memoizedSortedFruitsVegsProducts;
  List<ProductModel>? _memoizedSortedElectronicsProducts;
  List<ProductModel>? _memoizedSortedHardwareProducts;
  List<ProductModel>? _memoizedSortedSalonProducts;
  List<ShopModel>? _memoizedSortedShopResults;
  List<ShopModel>? _memoizedSortedNormalShops;

  void _invalidateSortMemo() {
    _memoizedSortedProductResults = null;
    _memoizedSortedNormalProducts = null;
    _memoizedSortedPharmacyProducts = null;
    _memoizedSortedClothingProducts = null;
    _memoizedSortedFoodProducts = null;
    _memoizedSortedCosmeticsProducts = null;
    _memoizedSortedSupermarketProducts = null;
    _memoizedSortedStationeryProducts = null;
    _memoizedSortedMeatAndFishProducts = null;
    _memoizedSortedDairyProducts = null;
    _memoizedSortedBakeryProducts = null;
    _memoizedSortedFruitsVegsProducts = null;
    _memoizedSortedElectronicsProducts = null;
    _memoizedSortedHardwareProducts = null;
    _memoizedSortedSalonProducts = null;
    _memoizedSortedShopResults = null;
    _memoizedSortedNormalShops = null;
  }

  /// Returns search product results sorted by the current _sortMode and filtered by _vegFilterMode.
  List<ProductModel> get _sortedProductResults {
    if (_memoizedSortedProductResults != null) {
      return _memoizedSortedProductResults!;
    }
    _memoizedSortedProductResults = _computeSortedProductResults();
    return _memoizedSortedProductResults!;
  }

  List<ProductModel> _computeSortedProductResults() {
    var list = List<ProductModel>.from(_searchProductResults);

    // 100x Dietary Filter: Veg / Non-Veg
    if (_vegFilterMode == VegFilterMode.vegOnly) {
      list = list.where((p) => p.isVeg == true).toList();
    } else if (_vegFilterMode == VegFilterMode.nonVegOnly) {
      list = list.where((p) => p.isVeg == false).toList();
    }

    list.sort((a, b) {
      final availCmp = _compareAvailability(a, b, _searchProductShops);
      if (availCmp != 0) return availCmp;

      switch (_sortMode) {
        case _SortMode.bestRating:
          return b.rating.compareTo(a.rating);
        case _SortMode.priceLow:
          return a.price.compareTo(b.price);
        case _SortMode.priceHigh:
          return b.price.compareTo(a.price);
        case _SortMode.discount:
          return (b.discountPercent ?? 0).compareTo(a.discountPercent ?? 0);
        case _SortMode.nearest:
          final sA = _searchProductShops[a.id];
          final sB = _searchProductShops[b.id];
          return (sA?.distanceKm ?? double.infinity)
              .compareTo(sB?.distanceKm ?? double.infinity);
        case _SortMode.relevant:
          if (_searchQuery.trim().isNotEmpty) {
            final scoreA = SearchRelevanceEngine.computeScore(
              product: a,
              query: _searchQuery,
              shop: _searchProductShops[a.id],
            );
            final scoreB = SearchRelevanceEngine.computeScore(
              product: b,
              query: _searchQuery,
              shop: _searchProductShops[b.id],
            );
            if (scoreA != scoreB) {
              return scoreB.compareTo(scoreA); // Highest relevance first!
            }
          }
          return b.rating.compareTo(a.rating);
      }
    });
    return list;
  }

  /// 100x Demographic matcher for feed items (Men, Women, Boys, Girls, Kids, Unisex)
  bool _matchesDemographic(ProductModel product, String demographic) {
    return DemographicUtils.matchesDemographic(product, demographic);
  }

  /// Returns normal product results sorted by the current _sortMode.
  List<ProductModel> get _sortedNormalProducts {
    if (_memoizedSortedNormalProducts != null) {
      return _memoizedSortedNormalProducts!;
    }
    _memoizedSortedNormalProducts = _computeSortedNormalProducts();
    return _memoizedSortedNormalProducts!;
  }

  List<ProductModel> _computeSortedNormalProducts() {
    var list = List<ProductModel>.from(_products);
    if (_selectedFeedDemographic != 'All') {
      list = list
          .where((p) => _matchesDemographic(p, _selectedFeedDemographic))
          .toList();
    }
    list.sort((a, b) {
      final availCmp = _compareAvailability(a, b, _productShops);
      if (availCmp != 0) return availCmp;

      switch (_sortMode) {
        case _SortMode.bestRating:
          return b.rating.compareTo(a.rating);
        case _SortMode.priceLow:
          return a.price.compareTo(b.price);
        case _SortMode.priceHigh:
          return b.price.compareTo(a.price);
        case _SortMode.discount:
          return (b.discountPercent ?? 0).compareTo(a.discountPercent ?? 0);
        case _SortMode.nearest:
          final sA = _productShops[a.id];
          final sB = _productShops[b.id];
          return (sA?.distanceKm ?? double.infinity)
              .compareTo(sB?.distanceKm ?? double.infinity);
        case _SortMode.relevant:
          return b.rating
              .compareTo(a.rating); // Default rating sort for relevant
      }
    });
    return list;
  }

  List<ProductModel> _computeSortedCategoryProducts(
    List<String> targetCategories, {
    bool applyDemographic = false,
  }) {
    var list = _products.where((p) {
      final shop = _productShops[p.id];
      return AppCategories.matchesBrowsingCategory(
        productCategory: p.category,
        shopCategory: shop?.category,
        targetCategories: targetCategories,
        shopCategories: shop?.categories,
      );
    }).toList();

    if (applyDemographic && _selectedFeedDemographic != 'All') {
      list = list
          .where((p) => _matchesDemographic(p, _selectedFeedDemographic))
          .toList();
    }

    list.sort((a, b) {
      final availCmp = _compareAvailability(a, b, _productShops);
      if (availCmp != 0) return availCmp;

      switch (_sortMode) {
        case _SortMode.bestRating:
          return b.rating.compareTo(a.rating);
        case _SortMode.priceLow:
          return a.price.compareTo(b.price);
        case _SortMode.priceHigh:
          return b.price.compareTo(a.price);
        case _SortMode.discount:
          return (b.discountPercent ?? 0).compareTo(a.discountPercent ?? 0);
        case _SortMode.nearest:
          final sA = _productShops[a.id];
          final sB = _productShops[b.id];
          return (sA?.distanceKm ?? double.infinity)
              .compareTo(sB?.distanceKm ?? double.infinity);
        case _SortMode.relevant:
          return b.rating.compareTo(a.rating);
      }
    });

    return list;
  }

  /// Returns normal products filtered for Medicines & Healthcare (immune to clothing demographic filter)
  List<ProductModel> get _sortedPharmacyProducts {
    if (_memoizedSortedPharmacyProducts != null) {
      return _memoizedSortedPharmacyProducts!;
    }
    _memoizedSortedPharmacyProducts = _computeSortedCategoryProducts(
      _tabCategories['Pharmacy'] ?? [],
      applyDemographic: false,
    );
    return _memoizedSortedPharmacyProducts!;
  }

  /// Returns normal products filtered for Clothing & Fashion (respects demographic filter if active)
  List<ProductModel> get _sortedClothingProducts {
    if (_memoizedSortedClothingProducts != null) {
      return _memoizedSortedClothingProducts!;
    }
    _memoizedSortedClothingProducts = _computeSortedCategoryProducts(
      _tabCategories['Clothing'] ?? [],
      applyDemographic: true,
    );
    return _memoizedSortedClothingProducts!;
  }

  /// Returns normal products filtered for Food & Restaurants (immune to clothing demographic filter)
  List<ProductModel> get _sortedFoodProducts {
    if (_memoizedSortedFoodProducts != null) {
      return _memoizedSortedFoodProducts!;
    }
    _memoizedSortedFoodProducts = _computeSortedCategoryProducts(
      _tabCategories['Food'] ?? [],
      applyDemographic: false,
    );
    return _memoizedSortedFoodProducts!;
  }

  /// Returns normal products filtered for Cosmetics & Beauty (immune to clothing demographic filter)
  List<ProductModel> get _sortedCosmeticsProducts {
    if (_memoizedSortedCosmeticsProducts != null) {
      return _memoizedSortedCosmeticsProducts!;
    }
    _memoizedSortedCosmeticsProducts = _computeSortedCategoryProducts(
      _tabCategories['Cosmetics'] ?? [],
      applyDemographic: false,
    );
    return _memoizedSortedCosmeticsProducts!;
  }

  /// Returns normal products filtered for Supermarket/Hypermarket & Grocery combined (immune to clothing demographic filter)
  List<ProductModel> get _sortedSupermarketProducts {
    if (_memoizedSortedSupermarketProducts != null) {
      return _memoizedSortedSupermarketProducts!;
    }
    _memoizedSortedSupermarketProducts = _computeSortedCategoryProducts(
      _tabCategories['Supermarket'] ?? _tabCategories['Grocery'] ?? [],
      applyDemographic: false,
    );
    return _memoizedSortedSupermarketProducts!;
  }

  /// Returns normal products filtered for Stationery & Office Supplies (immune to clothing demographic filter)
  List<ProductModel> get _sortedStationeryProducts {
    if (_memoizedSortedStationeryProducts != null) {
      return _memoizedSortedStationeryProducts!;
    }
    _memoizedSortedStationeryProducts = _computeSortedCategoryProducts(
      _tabCategories['Stationery'] ?? [],
      applyDemographic: false,
    );
    return _memoizedSortedStationeryProducts!;
  }

  /// Returns normal products filtered for Fish, Mutton & Meat (immune to clothing demographic filter)
  List<ProductModel> get _sortedMeatAndFishProducts {
    if (_memoizedSortedMeatAndFishProducts != null) {
      return _memoizedSortedMeatAndFishProducts!;
    }
    _memoizedSortedMeatAndFishProducts = _computeSortedCategoryProducts(
      _tabCategories['MeatAndFish'] ?? [],
      applyDemographic: false,
    );
    return _memoizedSortedMeatAndFishProducts!;
  }

  /// Returns normal products filtered for Fresh Milk, Butter, Cheese & Eggs (immune to clothing demographic filter)
  List<ProductModel> get _sortedDairyProducts {
    if (_memoizedSortedDairyProducts != null) {
      return _memoizedSortedDairyProducts!;
    }
    _memoizedSortedDairyProducts = _computeSortedCategoryProducts(
      _tabCategories['DairyAndEggs'] ?? [],
      applyDemographic: false,
    );
    return _memoizedSortedDairyProducts!;
  }

  /// Returns normal products filtered for Bakery, Sweets & Mithai (immune to clothing demographic filter)
  List<ProductModel> get _sortedBakeryProducts {
    if (_memoizedSortedBakeryProducts != null) {
      return _memoizedSortedBakeryProducts!;
    }
    _memoizedSortedBakeryProducts = _computeSortedCategoryProducts(
      _tabCategories['BakeryAndSweets'] ?? [],
      applyDemographic: false,
    );
    return _memoizedSortedBakeryProducts!;
  }

  /// Returns normal products filtered for Fruits, Vegs & Organic (immune to clothing demographic filter)
  List<ProductModel> get _sortedFruitsVegsProducts {
    if (_memoizedSortedFruitsVegsProducts != null) {
      return _memoizedSortedFruitsVegsProducts!;
    }
    _memoizedSortedFruitsVegsProducts = _computeSortedCategoryProducts(
      _tabCategories['FruitsVegsOrganic'] ?? [],
      applyDemographic: false,
    );
    return _memoizedSortedFruitsVegsProducts!;
  }

  /// Returns normal products filtered for Electronics (immune to clothing demographic filter)
  List<ProductModel> get _sortedElectronicsProducts {
    if (_memoizedSortedElectronicsProducts != null) {
      return _memoizedSortedElectronicsProducts!;
    }
    _memoizedSortedElectronicsProducts = _computeSortedCategoryProducts(
      _tabCategories['Electronics'] ?? [],
      applyDemographic: false,
    );
    return _memoizedSortedElectronicsProducts!;
  }

  /// Returns normal products filtered for Hardware (immune to clothing demographic filter)
  List<ProductModel> get _sortedHardwareProducts {
    if (_memoizedSortedHardwareProducts != null) {
      return _memoizedSortedHardwareProducts!;
    }
    _memoizedSortedHardwareProducts = _computeSortedCategoryProducts(
      _tabCategories['Hardware'] ?? [],
      applyDemographic: false,
    );
    return _memoizedSortedHardwareProducts!;
  }

  /// Returns normal products filtered for Salon & Beauty (immune to clothing demographic filter)
  List<ProductModel> get _sortedSalonProducts {
    if (_memoizedSortedSalonProducts != null) {
      return _memoizedSortedSalonProducts!;
    }
    _memoizedSortedSalonProducts = _computeSortedCategoryProducts(
      _tabCategories['SalonAndBeauty'] ?? [],
      applyDemographic: false,
    );
    return _memoizedSortedSalonProducts!;
  }

  /// Returns search shop results sorted by the current _sortMode and filtered by dietary preference.
  List<ShopModel> get _sortedShopResults {
    if (_memoizedSortedShopResults != null) {
      return _memoizedSortedShopResults!;
    }
    _memoizedSortedShopResults = _computeSortedShopResults();
    return _memoizedSortedShopResults!;
  }

  List<ShopModel> _computeSortedShopResults() {
    var list = List<ShopModel>.from(_searchResults);

    // 100x Dietary Filter: Coherence for food shops & restaurants
    if (_vegFilterMode == VegFilterMode.vegOnly) {
      list = list.where((s) {
        if (s.isVegOnly) return true;
        if (s.category == 'Butcher' || s.category == 'Fish & Seafood') {
          return false;
        }
        final hasVegProduct = _searchProductResults
            .any((p) => p.shopId == s.id && p.isVeg == true);
        if (hasVegProduct) return true;
        if (_searchProductResults.isNotEmpty) {
          return false;
        }
        return true;
      }).toList();
    } else if (_vegFilterMode == VegFilterMode.nonVegOnly) {
      list = list.where((s) {
        if (s.isVegOnly) return false;
        final hasNonVegProduct = _searchProductResults
            .any((p) => p.shopId == s.id && p.isVeg == false);
        if (hasNonVegProduct) return true;
        if (_searchProductResults.isNotEmpty) {
          return s.category == 'Butcher' || s.category == 'Fish & Seafood';
        }
        return true;
      }).toList();
    }

    final cleanQ = _searchQuery.toLowerCase().trim();
    final qTerms = cleanQ
        .replaceAll(RegExp(r'[,()"\x27]'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();

    list.sort((a, b) {
      // Priority 0: Exact / primary restaurant or shop name match outranks unrelated stores
      if (cleanQ.isNotEmpty) {
        final aName = a.name.toLowerCase();
        final bName = b.name.toLowerCase();
        final aExact = aName == cleanQ || aName.contains(cleanQ);
        final bExact = bName == cleanQ || bName.contains(cleanQ);
        if (aExact != bExact) return aExact ? -1 : 1;

        final aMatches =
            qTerms.isNotEmpty && qTerms.every((t) => aName.contains(t));
        final bMatches =
            qTerms.isNotEmpty && qTerms.every((t) => bName.contains(t));
        if (aMatches != bMatches) return aMatches ? -1 : 1;
      }

      final openA = a.isOpenRightNow ? 1 : 0;
      final openB = b.isOpenRightNow ? 1 : 0;
      if (openA != openB) return openB.compareTo(openA);

      switch (_sortMode) {
        case _SortMode.bestRating:
          return b.rating.compareTo(a.rating);
        default:
          return (a.distanceKm ?? double.infinity)
              .compareTo(b.distanceKm ?? double.infinity);
      }
    });
    return list;
  }

  /// Returns whether the active search results contain food items or food/dining establishments.
  bool get _hasFoodItemsInSearch {
    final hasFoodProduct =
        _searchProductResults.any((p) => p.isFood || p.isVeg != null);
    if (hasFoodProduct) return true;

    final hasFoodShop =
        _searchResults.any((s) => AppCategories.isFoodCategory(s.category));
    if (hasFoodShop) return true;

    if (_vegFilterMode != VegFilterMode.all) return true;

    return false;
  }

  /// Returns normal shop results sorted by the current _sortMode.
  List<ShopModel> get _sortedNormalShops {
    if (_memoizedSortedNormalShops != null) {
      return _memoizedSortedNormalShops!;
    }
    _memoizedSortedNormalShops = _computeSortedNormalShops();
    return _memoizedSortedNormalShops!;
  }

  List<ShopModel> _computeSortedNormalShops() {
    final list = List<ShopModel>.from(_shops);
    final matchingShopIds = (_selectedFeedDemographic != 'All')
        ? _products
            .where((p) => _matchesDemographic(p, _selectedFeedDemographic))
            .map((p) => p.shopId)
            .toSet()
        : const <String>{};

    list.sort((a, b) {
      final openA = a.isOpenRightNow ? 1 : 0;
      final openB = b.isOpenRightNow ? 1 : 0;
      if (openA != openB) return openB.compareTo(openA);

      if (_selectedFeedDemographic != 'All' && matchingShopIds.isNotEmpty) {
        final hasProdsA = matchingShopIds.contains(a.id) ? 1 : 0;
        final hasProdsB = matchingShopIds.contains(b.id) ? 1 : 0;
        if (hasProdsA != hasProdsB) return hasProdsB.compareTo(hasProdsA);
      }

      switch (_sortMode) {
        case _SortMode.bestRating:
          return b.rating.compareTo(a.rating);
        case _SortMode.nearest:
        case _SortMode.priceLow:
        case _SortMode.priceHigh:
        case _SortMode.discount:
        case _SortMode.relevant:
          return (a.distanceKm ?? double.infinity)
              .compareTo(b.distanceKm ?? double.infinity);
      }
    });
    return list;
  }

  // Track if the very first load has completed (shimmer only on first load)
  bool _hasLoadedOnce = false;
  // Phase 25 Fix: Atomic State Tracking to prevent Tab Desync and Overload
  int _fetchId = 0;
  bool _isFetching = false;

  // ── Industrial-standard retry state (Issue 2 fix) ────────────────────────
  // Tracks consecutive transient failures so we can backoff exponentially.
  // Resets to 0 on any successful data load.
  int _loadRetryCount = 0;
  static const int _maxLoadRetries = 3;
  Timer? _retryTimer;

  // Banner carousel
  static const int _featuredSlidesCount = 6;
  final PageController _bannerController = PageController();
  final ValueNotifier<int> _bannerIndex = ValueNotifier<int>(0);
  Timer? _bannerTimer;
  bool _isBannerHovered = false;
  Timer? _searchDebounce;

  // Location Required block
  final GlobalKey _locationRequiredKey = GlobalKey();
  late AnimationController _locationGlowCtrl;
  late Animation<double> _locationGlowAnim;

  // ── Trending Strip auto-scroll ──────────────────────────────────────────
  final ScrollController _mainScrollController = ScrollController();
  final ScrollController _trendingScrollController = ScrollController();
  Timer? _trendingScrollTimer;

  // Dynamic trending keywords fetched from DB (real order data).
  // Falls back to _staticFallbackKeywords if DB returns nothing or on error.
  List<Map<String, dynamic>> _dynamicTrendingKeywords = [];

  // Static fallback shown until/if DB data arrives or when DB is empty.
  static const List<Map<String, dynamic>> _staticFallbackKeywords = [
    {'label': 'Pizza', 'emoji': '🍕'},
    {'label': 'Milk', 'emoji': '🥛'},
    {'label': 'Burger', 'emoji': '🍔'},
    {'label': 'Chicken', 'emoji': '🍗'},
    {'label': 'Paracetamol', 'emoji': '💊'},
    {'label': 'Eggs', 'emoji': '🥚'},
    {'label': 'Bread', 'emoji': '🍞'},
    {'label': 'Biryani', 'emoji': '🍛'},
    {'label': 'Shoes', 'emoji': '👟'},
    {'label': 'Mobile', 'emoji': '📱'},
    {'label': 'Dal', 'emoji': '🫘'},
    {'label': 'Kebab', 'emoji': '🥙'},
  ];

  // Helper: pick a relevant emoji for a product name based on keywords.
  // Purely cosmetic — no logic impact.
  static String _emojiForKeyword(String label) {
    final l = label.toLowerCase();
    if (l.contains('pizza')) {
      return '🍕';
    }
    if (l.contains('burger')) {
      return '🍔';
    }
    if (l.contains('chicken')) {
      return '🍗';
    }
    if (l.contains('milk')) {
      return '🥛';
    }
    if (l.contains('egg')) {
      return '🥚';
    }
    if (l.contains('bread')) {
      return '🍞';
    }
    if (l.contains('biryani') || l.contains('rice')) {
      return '🍛';
    }
    if (l.contains('dal') || l.contains('daal')) {
      return '🫘';
    }
    if (l.contains('kebab') || l.contains('kabab')) {
      return '🥙';
    }
    if (l.contains('tea') || l.contains('chai')) {
      return '🍵';
    }
    if (l.contains('coffee')) {
      return '☕';
    }
    if (l.contains('juice')) {
      return '🍹';
    }
    if (l.contains('water')) {
      return '💧';
    }
    if (l.contains('fish')) {
      return '🐟';
    }
    if (l.contains('mutton') || l.contains('lamb')) {
      return '🥩';
    }
    if (l.contains('paneer')) {
      return '🧀';
    }
    if (l.contains('roti') || l.contains('naan') || l.contains('paratha')) {
      return '🫓';
    }
    if (l.contains('cake') || l.contains('sweet') || l.contains('mithai')) {
      return '🎂';
    }
    if (l.contains('medicine') ||
        l.contains('tablet') ||
        l.contains('capsule') ||
        l.contains('syrup') ||
        l.contains('paracetamol')) {
      return '💊';
    }
    if (l.contains('shoe') || l.contains('sandal')) {
      return '👟';
    }
    if (l.contains('mobile') || l.contains('phone')) {
      return '📱';
    }
    if (l.contains('shirt') || l.contains('cloth') || l.contains('dress')) {
      return '👕';
    }
    if (l.contains('soap') || l.contains('shampoo') || l.contains('cream')) {
      return '🧴';
    }
    if (l.contains('fruit') || l.contains('apple') || l.contains('mango')) {
      return '🍎';
    }
    if (l.contains('veg') || l.contains('sabzi')) {
      return '🥬';
    }
    if (l.contains('ice cream') || l.contains('icecream')) {
      return '🍨';
    }
    return '🛒'; // default: shopping bag
  }

  bool _pendingLocationUpdate = false;

  /// True when a food-type tab is currently selected.
  bool get _isFoodTab {
    if (_selectedTabIndex < 0) return false;
    final cats = _categories;
    if (_selectedTabIndex >= cats.length) return false;
    final name = cats[_selectedTabIndex]['name'] as String;
    return name == 'Food';
  }

  // ── Category tabs: filtered by admin-disabled categories (Additive) ──────
  // This is a getter so it reacts to PlatformConfigProvider changes.
  List<Map<String, dynamic>> get _categories {
    final config = context.read<PlatformConfigProvider>();
    const allTabs = [
      {
        'name': 'Food',
        'emoji': '🍔',
        'grad': [Color(0xFFFF6B6B), Color(0xFFEE5A24)]
      },
      {
        'name': 'Supermarket / Hypermarket',
        'emoji': '🏬',
        'grad': [Color(0xFF51CF66), Color(0xFF2F9E44)]
      },
      {
        'name': 'Pharmacy',
        'emoji': '💊',
        'grad': [Color(0xFF4C6EF5), Color(0xFF364FC7)]
      },
      {
        'name': 'Cosmetics & Beauty',
        'emoji': '💄',
        'grad': [Color(0xFFE91E8C), Color(0xFFFF6FB5)]
      },
      {
        'name': 'Clothing',
        'emoji': '👕',
        'grad': [Color(0xFFFF8C42), Color(0xFFE8590C)]
      },
      {
        'name': 'Electronics',
        'emoji': '📱',
        'grad': [Color(0xFFCC5DE8), Color(0xFF9C36B5)]
      },
      {
        'name': 'More',
        'emoji': '🛍️',
        'grad': [Color(0xFF20C997), Color(0xFF0CA678)]
      },
    ];
    // Keep a tab only if at least one of its subcategories is active
    return allTabs.where((tab) {
      final name = tab['name'] as String;
      final subcategories = _tabCategories[name] ?? [name];
      return subcategories.any((c) => config.isActiveCategory(c));
    }).toList();
  }

  /// 100x Contextual Metadata for the Products Section & See All Action
  ({String sectionTitle, String buttonLabel, List<String>? categoryFilter})
      _getProductSectionMeta() {
    final config = context.read<PlatformConfigProvider>();

    // 1. If an Explore Category tab is selected
    if (_selectedTabIndex >= 0 && _selectedTabIndex < _categories.length) {
      final tabName = _categories[_selectedTabIndex]['name'] as String;
      final rawSubcategories = _tabCategories[tabName] ?? [tabName];
      final finalCategories =
          rawSubcategories.where((c) => config.isActiveCategory(c)).toList();

      if (tabName == 'Supermarket / Hypermarket') {
        return (
          sectionTitle: 'Popular in Supermarket & Hypermarket',
          buttonLabel: 'See all Supermarket & Hypermarket products',
          categoryFilter: finalCategories,
        );
      } else if (tabName == 'Food') {
        return (
          sectionTitle: 'Popular in Food & Restaurants',
          buttonLabel: 'See all Food & Restaurant items',
          categoryFilter: finalCategories,
        );
      } else if (tabName == 'Pharmacy') {
        return (
          sectionTitle: 'Popular in Pharmacy & Healthcare',
          buttonLabel: 'See all Pharmacy & Healthcare products',
          categoryFilter: finalCategories,
        );
      } else if (tabName == 'Cosmetics & Beauty' || tabName == 'Cosmetics') {
        return (
          sectionTitle: 'Popular in Cosmetics & Beauty',
          buttonLabel: 'See all Cosmetics & Beauty products',
          categoryFilter: finalCategories,
        );
      } else if (tabName == 'Clothing') {
        final demoTitle = _selectedFeedDemographic == 'Men/Boys'
            ? 'Popular for Men & Boys'
            : (_selectedFeedDemographic == 'Women/Girls'
                ? 'Popular for Women & Girls'
                : (_selectedFeedDemographic == 'Kids'
                    ? 'Popular for Kids'
                    : (_selectedFeedDemographic == 'Unisex'
                        ? 'Popular Unisex Fashion'
                        : 'Popular in Clothing & Fashion')));
        final demoBtn = _selectedFeedDemographic != 'All'
            ? 'See all $_selectedFeedDemographic fashion'
            : 'See all Clothing & Fashion products';
        return (
          sectionTitle: demoTitle,
          buttonLabel: demoBtn,
          categoryFilter: finalCategories,
        );
      } else if (tabName == 'Electronics') {
        return (
          sectionTitle: 'Popular in Electronics & Gadgets',
          buttonLabel: 'See all Electronics & Gadgets',
          categoryFilter: finalCategories,
        );
      } else if (tabName == 'More') {
        return (
          sectionTitle: 'Popular in More Categories',
          buttonLabel: 'See all products in this category',
          categoryFilter: finalCategories,
        );
      } else {
        return (
          sectionTitle: 'Popular in $tabName',
          buttonLabel: 'See all $tabName products',
          categoryFilter: finalCategories,
        );
      }
    }

    // 2. If filtering via custom filter categories without tab selection
    if (_selectedFilterCategories.isNotEmpty) {
      final firstFilter = _selectedFilterCategories.first;
      final effectiveCategories = <String>[];
      for (final cat in _selectedFilterCategories) {
        final subs = _tabCategories[cat] ?? [cat];
        effectiveCategories
            .addAll(subs.where((c) => config.isActiveCategory(c)));
      }
      return (
        sectionTitle: _selectedFilterCategories.length == 1
            ? 'Popular in $firstFilter'
            : 'Filtered Popular Products',
        buttonLabel: 'See all filtered products',
        categoryFilter: effectiveCategories,
      );
    }

    // 3. Default "All" dashboard view
    final defaultTitle = _selectedFeedDemographic == 'Men/Boys'
        ? 'Popular for Men & Boys'
        : (_selectedFeedDemographic == 'Women/Girls'
            ? 'Popular for Women & Girls'
            : (_selectedFeedDemographic == 'Kids'
                ? 'Popular for Kids'
                : (_selectedFeedDemographic == 'Unisex'
                    ? 'Popular Unisex Fashion'
                    : 'Popular in your area')));
    final defaultBtn = _selectedFeedDemographic != 'All'
        ? 'See all $_selectedFeedDemographic products'
        : 'See all popular products';

    return (
      sectionTitle: defaultTitle,
      buttonLabel: defaultBtn,
      categoryFilter: null,
    );
  }

  /// 100x Contextual Metadata for the Stores Section & See All Action
  ({String sectionTitle, String buttonLabel, List<String>? categoryFilter})
      _getStoreSectionMeta() {
    final config = context.read<PlatformConfigProvider>();

    if (_selectedTabIndex >= 0 && _selectedTabIndex < _categories.length) {
      final tabName = _categories[_selectedTabIndex]['name'] as String;
      final rawSubcategories = _tabCategories[tabName] ?? [tabName];
      final finalCategories =
          rawSubcategories.where((c) => config.isActiveCategory(c)).toList();

      if (tabName == 'Food') {
        return (
          sectionTitle: 'Restaurants near you',
          buttonLabel: 'See all restaurants',
          categoryFilter: finalCategories,
        );
      } else if (tabName == 'Supermarket / Hypermarket') {
        return (
          sectionTitle: 'Supermarkets & Hypermarkets near you',
          buttonLabel: 'See all supermarkets & hypermarkets',
          categoryFilter: finalCategories,
        );
      } else if (tabName == 'Pharmacy') {
        return (
          sectionTitle: 'Pharmacies & Medical Stores near you',
          buttonLabel: 'See all pharmacies & medical stores',
          categoryFilter: finalCategories,
        );
      } else if (tabName == 'Cosmetics & Beauty' || tabName == 'Cosmetics') {
        return (
          sectionTitle: 'Cosmetics & Beauty Stores near you',
          buttonLabel: 'See all cosmetics & beauty stores',
          categoryFilter: finalCategories,
        );
      } else if (tabName == 'Clothing') {
        return (
          sectionTitle: _selectedFeedDemographic == 'Men/Boys'
              ? 'Men & Boys Stores'
              : (_selectedFeedDemographic == 'Women/Girls'
                  ? 'Women & Girls Stores'
                  : 'Clothing & Fashion Stores near you'),
          buttonLabel: 'See all clothing stores',
          categoryFilter: finalCategories,
        );
      } else if (tabName == 'Electronics') {
        return (
          sectionTitle: 'Electronics Stores near you',
          buttonLabel: 'See all electronics stores',
          categoryFilter: finalCategories,
        );
      } else {
        return (
          sectionTitle: 'Stores in $tabName near you',
          buttonLabel: 'See all $tabName stores',
          categoryFilter: finalCategories,
        );
      }
    }

    return (
      sectionTitle: 'Stores near you',
      buttonLabel: 'See all stores',
      categoryFilter: null,
    );
  }

  @override
  void initState() {
    super.initState();
    _locationGlowCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _locationGlowAnim = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _locationGlowCtrl, curve: Curves.easeInOut));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLocationAndLoad();
    });
    _startNotifications();
    _checkActiveOrders();
    // Subscribe to live GPS updates so distance filter stays accurate
    _startLiveLocationUpdates();
    // Auto-scroll banner every 4 seconds (pauses on hover/touch)
    _bannerTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_bannerController.hasClients || _isBannerHovered) return;
      final next = (_bannerIndex.value + 1) % _featuredSlidesCount;
      _bannerController.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    });
    // Auto-scroll trending strip + fetch real trending keywords
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startTrendingScroll();
      _loadTrendingKeywords(); // fetch real trending from DB (additive, no SQL change)
    });
    // Fetch favorites, saved address, and subscription state
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      if (auth.currentUserId != null) {
        context.read<FavoritesProvider>().fetchFavorites(auth.currentUserId!);
        context.read<LocationProvider>().loadAddressFromDb(auth.currentUserId!);
        context.read<ReferralProvider>().init(auth.currentUserId!);
      }
    });
  }

  void _startTrendingScroll() {
    _trendingScrollTimer?.cancel();
    // Slowly auto-scroll the trending strip, wrap around when reaching end
    _trendingScrollTimer =
        Timer.periodic(const Duration(milliseconds: 60), (_) {
      if (!mounted || !_trendingScrollController.hasClients) return;
      final max = _trendingScrollController.position.maxScrollExtent;
      if (max <= 0) return;
      final current = _trendingScrollController.offset;
      if (current >= max) {
        // Jump silently back to start for infinite loop effect
        _trendingScrollController.jumpTo(0);
      } else {
        _trendingScrollController.jumpTo(current + 0.6);
      }
    });
  }

  /// Fetches real trending product names from DB (last 30 days, delivered orders).
  /// Purely additive — new read-only RPC, zero changes to existing SQL logic.
  /// On error or empty result, falls back to the static curated list.
  Future<void> _loadTrendingKeywords() async {
    try {
      final locationProvider = context.read<LocationProvider>();
      final lat = locationProvider.currentLocation?.latitude;
      final lng = locationProvider.currentLocation?.longitude;

      dynamic response;
      if (locationProvider.hasLocation && lat != null && lng != null) {
        final disabledCats =
            context.read<PlatformConfigProvider>().disabledCategories.toList();
        response =
            await _supabase.rpc('get_trending_keywords_geospatial', params: {
          'p_lat': lat,
          'p_lng': lng,
          'p_radius_km': DeliveryCalculator.maxRadiusKm,
          'p_limit': 15,
          'p_disabled_categories': disabledCats.isEmpty ? null : disabledCats,
        });
      } else {
        // When location is not yet locked, rely on clean curated static fallback
        response = [];
      }

      if (!mounted) return;

      final rows = response as List?;
      if (rows == null || rows.isEmpty) {
        if (mounted && _dynamicTrendingKeywords.isNotEmpty) {
          setState(() => _dynamicTrendingKeywords = []);
        }
        return;
      }

      final fetched = rows
          .map((row) {
            final keyword = (row['keyword'] as String? ?? '').trim();
            if (keyword.isEmpty) return null;
            return {
              'label': keyword,
              'emoji': _emojiForKeyword(keyword),
            };
          })
          .whereType<Map<String, dynamic>>()
          .toList();

      if (fetched.isEmpty) {
        if (mounted && _dynamicTrendingKeywords.isNotEmpty) {
          setState(() => _dynamicTrendingKeywords = []);
        }
        return;
      }

      // Re-start the scroll from position 0 so it doesn't jump mid-way
      if (mounted) {
        setState(() => _dynamicTrendingKeywords = fetched);
        // Reset scroll position so the new list starts from the beginning
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_trendingScrollController.hasClients) {
            _trendingScrollController.jumpTo(0);
          }
        });
      }
    } catch (e) {
      debugPrint('[Trending] Failed to load trending keywords: $e');
    }
  }

  bool _isActiveOrderNavigating = false;
  bool _isSettingsNavigating = false;
  Future<void> _checkActiveOrders() async {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = context.read<AuthProvider>();
      if (auth.currentUserId == null) return;
      try {
        final activeOrder = await _supabase
            .from('orders')
            .select('id, status, payment_deadline, created_at')
            .eq('customer_id', auth.currentUserId!)
            .inFilter('status', [
              'awaiting_acceptance',
              'awaiting_payment',
              'pending',
              'confirmed',
              'preparing',
              'ready_for_pickup',
              'picked_up',
              'out_for_delivery',
            ])
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();

        if (activeOrder != null && mounted) {
          final status = activeOrder['status'];
          bool isExpired = false;

          if (status == 'awaiting_payment' &&
              activeOrder['payment_deadline'] != null) {
            final deadline =
                DateTime.parse(activeOrder['payment_deadline']).toLocal();
            if (DateTime.now().isAfter(deadline)) {
              isExpired = true;
            }
          } else if (status == 'pending' && activeOrder['created_at'] != null) {
            final createdAt =
                DateTime.parse(activeOrder['created_at']).toLocal();
            // If stuck in payment processing for more than 30 mins, treat as expired
            if (DateTime.now().difference(createdAt).inMinutes > 30) {
              isExpired = true;
            }
          }

          if (isExpired) {
            // Silently cancel it in the background so it stops polluting queries
            _supabase.rpc('cancel_order', params: {
              'p_order_id': activeOrder['id'],
              'p_reason': 'timeout'
            }).catchError((e) {
              debugPrint('Failed to auto-cancel expired active order: $e');
            });
            return; // DO NOT NAVIGATE
          }

          if (status == 'awaiting_payment') {
            // FIX (Issue 3): Do not auto-redirect if the customer is actively
            // searching for replacement items after a partial order rejection.
            final cartProvider = context.read<CartProvider>();
            if (cartProvider.pendingCartGroupId != null) {
              return;
            }

            if (_isActiveOrderNavigating) return;
            _isActiveOrderNavigating = true;
            Navigator.pushNamed(context, AppRoutes.trackOrder,
                    arguments: {'orderId': activeOrder['id']})
                .then((_) => _isActiveOrderNavigating = false);
          } else {
            final controller =
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: const Text('You have an active order in progress.'),
              action: SnackBarAction(
                label: 'Track',
                textColor: Colors.white,
                onPressed: () {
                  if (_isActiveOrderNavigating) return;
                  _isActiveOrderNavigating = true;
                  Navigator.pushNamed(context, AppRoutes.trackOrder,
                          arguments: {'orderId': activeOrder['id']})
                      .then((_) => _isActiveOrderNavigating = false);
                },
              ),
              backgroundColor: AppColors.primary,
              duration: const Duration(seconds: 10),
            ));

            // Additive fix: Force close after duration to bypass sticky SnackBar bug
            Future.delayed(const Duration(seconds: 10), () {
              try {
                controller.close();
              } catch (_) {}
            });
          }
        }
      } catch (e) {
        debugPrint('Failed to check active orders: $e');
      }
    });
  }

  LocationProvider? _locationProvider;

  bool _argsProcessed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _locationProvider ??= context.read<LocationProvider>();

    if (!_argsProcessed) {
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args != null && args['searchQuery'] != null) {
        final query = args['searchQuery'] as String;
        if (query.isNotEmpty) {
          _searchController.text = query;
          _searchShops(query);
        }
      }
      _argsProcessed = true;
    }
  }

  void _startLiveLocationUpdates() {
    // Re-fetch data whenever GPS location changes significantly
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _locationProvider?.addListener(_onLocationChanged);
    });
  }

  void _onLocationChanged() {
    if (!mounted || _searchQuery.isNotEmpty) return;

    if (_isFetching) {
      // Guard against actual network activity, not UI shimmer
      _pendingLocationUpdate = true;
      return;
    }

    _locationDebounceTimer?.cancel();
    _locationDebounceTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || _isFetching) {
        if (_isFetching) _pendingLocationUpdate = true;
        return;
      }
      _loadTrendingKeywords();
      if (_selectedTabIndex < 0) {
        _loadAllData();
      } else {
        _loadData(_categories[_selectedTabIndex]['name']! as String);
      }
    });
  }

  void _startNotifications() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userId = _supabase.auth.currentUser?.id;
      if (userId != null) {
        final notifProvider = context.read<NotificationProvider>();
        notifProvider.listenAsCustomer(userId);
        notifProvider.registerFcmToken(
            userId, 'customer'); // Register push token
        // Subscribe to customer's catering quotes in realtime
        final quoteProv = context.read<QuoteRequestProvider>();
        quoteProv.subscribeToCustomerQuotes();
        quoteProv.loadCustomerQuotes();
      }
    });
  }

  @override
  void dispose() {
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    _locationGlowCtrl.dispose();
    _bannerTimer?.cancel();
    _locationDebounceTimer?.cancel();
    _searchDebounce?.cancel();
    _trendingScrollTimer?.cancel();
    _retryTimer?.cancel(); // Issue 2: Cancel any pending retry on dispose
    _mainScrollController.dispose();
    _trendingScrollController.dispose();
    // Remove live location listener to avoid memory leaks
    _locationProvider?.removeListener(_onLocationChanged);
    _searchController.dispose();
    _bannerController.dispose();
    _bannerIndex.dispose();
    globalIsFiltering.value = false; // Reset state leakage
    super.dispose();
  }

  /// Scrolls the main view to the top if it's currently scrolled down.
  /// Returns true if a scroll action was triggered, false otherwise.
  bool scrollToTopIfNeeded() {
    if (_mainScrollController.hasClients && _mainScrollController.offset > 0) {
      _mainScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
      return true;
    }
    return false;
  }

  /// Runs a Supabase text search for shops by name across all categories.
  Future<void> _searchShops(String query, {bool skipNLP = false}) async {
    final locationProvider = context.read<LocationProvider>();
    if (!locationProvider.hasLocation) {
      _promptEnableLocation();
      return;
    }
    if (query.trim().isEmpty) {
      setState(() {
        _searchQuery = '';
        _searchResults = [];
        _searchProductResults = [];
        _searchProductShops = {};
        _isSearching = false;
        _searchError = false;
        _searchErrorMessage = '';
        _comingSoonMessage = null;
        _comingSoonSubMessage = null;
        _sortMode = _SortMode.relevant; // reset sort on clear
        _selectedSearchDemographic = 'All'; // reset demographic on clear
        _selectedSizes.clear(); // reset sizes on clear
        _vegFilterMode = VegFilterMode.all; // reset dietary filter on clear
        _invalidateSortMemo();
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _searchError = false;
      _searchErrorMessage = '';
      _comingSoonMessage = null;
      _comingSoonSubMessage = null;
      _searchQuery = query;
      _searchShopsDisplayLimit = 2;
      if (!skipNLP) {
        _selectedSearchDemographic = 'All';
        _selectedSizes.clear();
      }
      _invalidateSortMemo();
    });

    try {
      final locationProvider = context.read<LocationProvider>();
      final config = context.read<PlatformConfigProvider>();
      final String lowerQuery = query.toLowerCase().trim();
      final String cleanQuery =
          query.replaceAll(RegExp(r'[,()"\x27]'), ' ').trim();
      final List<String> rawTerms = cleanQuery
          .toLowerCase()
          .split(RegExp(r'\s+'))
          .where((t) => t.isNotEmpty)
          .toList();

      // 100x Noise & Stop-Word Stripping for multi-word queries:
      // (e.g. "serum for face" -> ['serum', 'face'], "milk and bread" -> ['milk', 'bread'])
      const stopWords = {
        'for',
        'in',
        'of',
        'with',
        'and',
        'the',
        'a',
        'an',
        'at',
        'by',
        'to',
        '&'
      };
      final List<String> filteredTerms = rawTerms.length > 1
          ? rawTerms.where((t) => !stopWords.contains(t)).toList()
          : rawTerms;
      final List<String> terms =
          filteredTerms.isNotEmpty ? filteredTerms : rawTerms;

      List<String> matchedSubcategories = [];

      if (!skipNLP) {
        _searchKeywords.forEach((catName, keywords) {
          bool match = keywords.any((k) {
            return lowerQuery.contains(k) ||
                k.contains(lowerQuery) ||
                terms.contains(k);
          });
          if (match) {
            final subs = _tabCategories[catName] ?? [catName];
            matchedSubcategories
                .addAll(subs.where((c) => config.isActiveCategory(c)));
          }
        });
      }

      List<String>? effectiveCategories;
      if (_selectedFilterCategories.isNotEmpty) {
        effectiveCategories = [];
        for (final cat in _selectedFilterCategories) {
          final subs = _tabCategories[cat] ?? [cat];
          effectiveCategories
              .addAll(subs.where((c) => config.isActiveCategory(c)));
        }
      } else {
        // 100x Omni-Search: When no filter category chip is selected, search across ALL categories platform-wide!
        effectiveCategories = null;
      }
      List<dynamic> shopsByName = [];
      List<dynamic> productsByName = [];
      List<dynamic> shopsByCat = [];
      List<dynamic> productsByCat = [];

      final lat = locationProvider.currentLocation?.latitude;
      final lng = locationProvider.currentLocation?.longitude;

      if (locationProvider.hasLocation && lat != null && lng != null) {
        // Phase 24: Mathematically pure ST_DWithin geospatial search via Additive RPC
        final maxRadius = DeliveryCalculator.maxRadiusKm;

        debugPrint(
            '[Search] Step 1/4: search_shops_geospatial (byName) q="$query" lat=$lat lng=$lng radius=$maxRadius');
        try {
          shopsByName = await _supabase.rpc('search_shops_geospatial', params: {
            'p_lat': lat,
            'p_lng': lng,
            'p_query': query,
            'p_categories': effectiveCategories,
            'p_radius_km': maxRadius,
            'p_limit': 50
          });
          debugPrint('[Search] Step 1/4 OK: ${shopsByName.length} shops found');
        } catch (e) {
          debugPrint(
              '[Search] Step 1/4 FAILED (search_shops_geospatial byName): $e');
        }

        // ── 100x Forensic Geospatial Product Omni-Search ───────────────────
        // Calls the high-performance search_products_geospatial RPC directly.
        // It tokenizes query, matches product name, brand, description, category,
        // sub_category, menu_category, special tags, and parent shop name with
        // PostGIS geospatial ST_DWithin and partitions by shop.
        final demoIntent = DemographicUtils.detectDemographicIntent(cleanQuery);
        debugPrint(
            '[Search] Step 2/4: search_products_geospatial q="$query" (demo: ${demoIntent.hasDemographicIntent ? demoIntent.canonicalDemographic : "none"})');
        List<dynamic> rawProductsByName = [];
        try {
          final rpcProducts =
              await _supabase.rpc('search_products_geospatial', params: {
            'p_lat': lat,
            'p_lng': lng,
            'p_query':
                demoIntent.hasDemographicIntent && !demoIntent.isPureDemographic
                    ? demoIntent.strippedProductQuery
                    : query,
            'p_categories': effectiveCategories,
            'p_radius_km': maxRadius,
            'p_limit': 150,
            'p_limit_per_shop': 100,
            'p_special_tag': _selectedSearchDemographic != 'All'
                ? _selectedSearchDemographic
                : null,
          });
          if (rpcProducts is List && rpcProducts.isNotEmpty) {
            rawProductsByName.addAll(rpcProducts);
            debugPrint(
                '[Search] Step 2/4 OK via search_products_geospatial RPC: ${rawProductsByName.length} products');
          }
        } catch (e) {
          debugPrint(
              '[Search] Step 2/4 search_products_geospatial RPC failed: $e');
        }

        // ── 100x Semantic Demographic Catalog Expansion ────────────────────
        // When searching a demographic persona ("women", "men", "girls", "boys", "kids"),
        // never starve the customer with just literal substring matches!
        // Proactively retrieve available lifestyle, beauty, and apparel products from nearby stores.
        if (demoIntent.hasDemographicIntent && shopsByName.isNotEmpty) {
          try {
            final nearbyShopIds =
                shopsByName.map((s) => s['id'] as String).toList();
            final existingIds = rawProductsByName.map((p) => p['id']).toSet();

            for (int i = 0; i < nearbyShopIds.length; i += 25) {
              final chunk = nearbyShopIds.sublist(
                  i, math.min(i + 25, nearbyShopIds.length));
              var q = _supabase
                  .from('products')
                  .select()
                  .eq('is_deleted', false)
                  .eq('is_available', true)
                  .inFilter('shop_id', chunk);

              if (demoIntent.isPureDemographic) {
                q = q.not('category', 'in',
                    '("Food","Restaurant","Fast Food","Bakery","Sweets & Mithai","Butcher","Fish & Seafood","Dairy & Eggs","Fruits & Vegs","Grocery","Grocerylm","Grocery (Low Margin)","Ice Cream","Paan Shop","Beverages")');
              } else if (demoIntent.strippedProductQuery.isNotEmpty) {
                final sq = demoIntent.strippedProductQuery;
                q = q.or(
                    'name.ilike.%$sq%,description.ilike.%$sq%,brand.ilike.%$sq%,category.ilike.%$sq%');
              }

              final extraProds =
                  await q.order('rating', ascending: false).limit(150);
              for (final ep in extraProds) {
                if (!existingIds.contains(ep['id'])) {
                  rawProductsByName.add(ep);
                  existingIds.add(ep['id']);
                }
              }
            }
            debugPrint(
                '[Search] Demographic expansion added products, total: ${rawProductsByName.length}');
          } catch (e) {
            debugPrint('[Search] Demographic catalog expansion error: $e');
          }
        }

        // Store-Name Match Supplementation:
        // If the query matched a restaurant or shop by name or cuisine (e.g. "Maxx Retail" or "Biryani Hut"),
        // fetch that store's top available products and prepend them to results.
        final matchingShops = shopsByName.where((s) {
          final sName = (s['name'] as String? ?? '').toLowerCase();
          final sCuisine = (s['cuisine_type'] as String? ?? '').toLowerCase();
          final sCat = (s['category'] as String? ?? '').toLowerCase();
          if (lowerQuery.isNotEmpty &&
              (sName.contains(lowerQuery) || lowerQuery.contains(sName))) {
            return true;
          }
          if (terms.isNotEmpty && terms.every((t) => sName.contains(t))) {
            return true;
          }
          if (terms.isNotEmpty &&
              terms.every((t) => sCuisine.contains(t) || sCat.contains(t))) {
            return true;
          }
          return false;
        }).toList();

        final matchingShopIds =
            matchingShops.map((s) => s['id'] as String).toSet();
        if (matchingShopIds.isNotEmpty) {
          try {
            final storeProdsRaw = await _supabase
                .from('products')
                .select()
                .eq('is_deleted', false)
                .eq('is_available', true)
                .inFilter('shop_id', matchingShopIds.take(10).toList())
                .order('rating', ascending: false)
                .limit(50);
            final existingIds = rawProductsByName.map((p) => p['id']).toSet();
            for (final sp in storeProdsRaw) {
              if (!existingIds.contains(sp['id'])) {
                rawProductsByName.insert(0, sp);
                existingIds.add(sp['id']);
              }
            }
          } catch (e) {
            debugPrint('[Search] Store products fetch failed: $e');
          }
        }

        // Direct-Query Resilient Fallback:
        // If search_products_geospatial was unavailable or returned 0 products,
        // perform chunked direct search on products table (max 25 shop IDs per chunk
        // to strictly prevent HTTP 414 URL length overflow!).
        if (rawProductsByName.isEmpty && terms.isNotEmpty) {
          try {
            final nearbyShops =
                await _supabase.rpc('search_shops_geospatial', params: {
              'p_lat': lat,
              'p_lng': lng,
              'p_query': null,
              'p_categories': effectiveCategories,
              'p_radius_km': maxRadius,
              'p_limit': 100
            });
            final allShopIds =
                (nearbyShops as List).map((s) => s['id'] as String).toList();

            for (int i = 0; i < allShopIds.length; i += 25) {
              final chunk =
                  allShopIds.sublist(i, math.min(i + 25, allShopIds.length));
              var q = _supabase
                  .from('products')
                  .select()
                  .eq('is_deleted', false)
                  .eq('is_available', true)
                  .inFilter('shop_id', chunk);

              final demoIntent =
                  DemographicUtils.detectDemographicIntent(cleanQuery);
              if (demoIntent.hasDemographicIntent &&
                  demoIntent.isPureDemographic) {
                q = q.not('category', 'in',
                    '("Food","Restaurant","Fast Food","Bakery","Sweets & Mithai","Butcher","Fish & Seafood","Dairy & Eggs","Fruits & Vegs","Grocery","Grocerylm","Grocery (Low Margin)","Ice Cream","Paan Shop","Beverages")');
              } else {
                for (final term in terms) {
                  if (!DemographicUtils.isDemographicKeyword(term)) {
                    q = q.or(
                      'name.ilike.%$term%,description.ilike.%$term%,brand.ilike.%$term%,category.ilike.%$term%,menu_category.ilike.%$term%,sub_category.ilike.%$term%,medicine_type.ilike.%$term%',
                    );
                  }
                }
              }

              final chunkProds =
                  await q.order('rating', ascending: false).limit(50);
              rawProductsByName.addAll(chunkProds);
              if (rawProductsByName.length >= 60) break;
            }
          } catch (e) {
            debugPrint('[Search] Direct query fallback failed: $e');
          }
        }

        // Local Filter for Size, Demographic, and Dietary preferences
        final filteredByName = rawProductsByName.where((p) {
          if (terms.isNotEmpty) {
            final searchable =
                '${p['name']} ${p['description'] ?? ''} ${p['brand'] ?? ''} ${p['category'] ?? ''} ${p['sub_category'] ?? ''} ${p['menu_category'] ?? ''} ${p['medicine_type'] ?? ''}'
                    .toLowerCase();
            final cleanSearchable =
                searchable.replaceAll(RegExp(r'[,()"\x27\-]'), '');
            final spacedSearchable =
                searchable.replaceAll(RegExp(r'[,()"\x27\-]'), ' ');
            final matchesAllTerms = terms.every((t) {
              if (DemographicUtils.isDemographicKeyword(t)) {
                return DemographicUtils.rawProductMatchesTerm(
                  product: p,
                  term: t,
                  searchableText: searchable,
                );
              }
              final cleanT = t.replaceAll(RegExp(r'[,()"\x27\-]'), '');
              // Direct or punctuation-agnostic match (e.g. loreal matches l'oreal)
              if (searchable.contains(t) ||
                  cleanSearchable.contains(cleanT) ||
                  spacedSearchable.contains(t)) {
                return true;
              }
              if (t.endsWith('s') && t.length > 3) {
                final stem = t.substring(0, t.length - 1);
                if (searchable.contains(stem) ||
                    cleanSearchable.contains(stem)) {
                  return true;
                }
              }
              return false;
            });
            if (!matchesAllTerms) return false;
          }
          if (_selectedSizes.isNotEmpty) {
            final variants = p['variants'] as List<dynamic>? ?? [];
            final matchesSize = variants.any((v) {
              final name = (v['name'] as String?)?.trim() ?? '';
              return _selectedSizes.contains(name);
            });
            if (!matchesSize) return false;
          }
          if (_selectedSearchDemographic != 'All') {
            final allowedTags =
                DemographicUtils.getAllowedTags(_selectedSearchDemographic);
            if (allowedTags != null) {
              final tagsRaw = p['special_tags'];
              final List<String> tags = (tagsRaw is List)
                  ? tagsRaw.map((t) => t.toString().trim()).toList()
                  : [];
              if (!tags.any((t) => allowedTags.contains(t))) return false;
            }
          }
          return true;
        }).toList();
        rawProductsByName = filteredByName;

        List<dynamic> rawProductsByCat = [];
        if (matchedSubcategories.isNotEmpty && !skipNLP) {
          debugPrint(
              '[Search] Step 3/4: search_shops_geospatial (byCat) cats=$matchedSubcategories');
          try {
            shopsByCat =
                await _supabase.rpc('search_shops_geospatial', params: {
              'p_lat': lat,
              'p_lng': lng,
              'p_categories': matchedSubcategories,
              'p_radius_km': maxRadius,
              'p_limit': 30
            });
            debugPrint(
                '[Search] Step 3/4 OK: ${shopsByCat.length} shops found');

            final catShopIds =
                shopsByCat.map((s) => s['id'] as String).toList();

            if (catShopIds.isNotEmpty && terms.isNotEmpty) {
              // 100x Safe Chunked Query with SQL text filter (Never do unfiltered download of whole shops!)
              for (int i = 0; i < catShopIds.length; i += 25) {
                final chunk =
                    catShopIds.sublist(i, math.min(i + 25, catShopIds.length));
                var q = _supabase
                    .from('products')
                    .select()
                    .eq('is_deleted', false)
                    .eq('is_available', true)
                    .inFilter('shop_id', chunk);

                final demoIntent =
                    DemographicUtils.detectDemographicIntent(cleanQuery);
                if (demoIntent.hasDemographicIntent &&
                    demoIntent.isPureDemographic) {
                  q = q.not('category', 'in',
                      '("Food","Restaurant","Fast Food","Bakery","Sweets & Mithai","Butcher","Fish & Seafood","Dairy & Eggs","Fruits & Vegs","Grocery","Grocerylm","Grocery (Low Margin)","Ice Cream","Paan Shop","Beverages")');
                } else {
                  for (final term in terms) {
                    if (!DemographicUtils.isDemographicKeyword(term)) {
                      q = q.or(
                        'name.ilike.%$term%,description.ilike.%$term%,brand.ilike.%$term%,category.ilike.%$term%,menu_category.ilike.%$term%,sub_category.ilike.%$term%,medicine_type.ilike.%$term%',
                      );
                    }
                  }
                }

                final catProds =
                    await q.order('rating', ascending: false).limit(30);
                rawProductsByCat.addAll(catProds);
                if (rawProductsByCat.length >= 60) break;
              }
            }
          } catch (e) {
            debugPrint('[Search] Step 3/4 warning (non-fatal): $e');
            // Do NOT rethrow! Preserve all products discovered in Step 2!
          }
        } else {
          debugPrint(
              '[Search] Steps 3-4 skipped: no NLP-matched subcategories for "$query"');
        }

        // Collect all unique shop_ids from both product lists so we can
        // batch-fetch shop rows in a single query — no per-product round trips.
        final Set<String> productShopIds = {};
        for (final p in rawProductsByName) {
          final sid = (p as Map<String, dynamic>)['shop_id'] as String?;
          if (sid != null && sid.isNotEmpty) productShopIds.add(sid);
        }
        for (final p in rawProductsByCat) {
          final sid = (p as Map<String, dynamic>)['shop_id'] as String?;
          if (sid != null && sid.isNotEmpty) productShopIds.add(sid);
        }

        // Batch query for all shops referenced by the product results in safe chunks of 30.
        final Map<String, Map<String, dynamic>> shopById = {};
        if (productShopIds.isNotEmpty) {
          debugPrint(
              '[Search] Batch-fetching ${productShopIds.length} shop(s) for product results');
          final idList = productShopIds.toList();
          for (int i = 0; i < idList.length; i += 30) {
            final chunk = idList.sublist(i, math.min(i + 30, idList.length));
            final shopRows =
                await _supabase.from('shops').select('*').inFilter('id', chunk);
            for (final s in shopRows as List) {
              final sm = s as Map<String, dynamic>;
              shopById[sm['id'] as String] = sm;
            }
          }
        }

        // Reconstruct the product maps with the 'shops' key so that the
        // existing addProducts() closure (which reads p['shops']) works
        // without any modification — all downstream logic is preserved exactly.
        productsByName = rawProductsByName.map((p) {
          final m = Map<String, dynamic>.from(p as Map<String, dynamic>);
          m['shops'] = shopById[m['shop_id'] as String?];
          return m;
        }).toList();

        productsByCat = rawProductsByCat.map((p) {
          final m = Map<String, dynamic>.from(p as Map<String, dynamic>);
          m['shops'] = shopById[m['shop_id'] as String?];
          return m;
        }).toList();
      } else {
        // Fallback removed to prevent out-of-bounds checkouts
        shopsByName = [];
        productsByName = [];
        shopsByCat = [];
        productsByCat = [];
      }

      final allShopsSet = <String, ShopModel>{};

      void addShops(List<dynamic> response, bool requireNameMatch) {
        for (final s in response) {
          final shop = ShopModel.fromMap(s);
          if (!config.isActiveCategory(shop.category)) continue;
          if (!locationProvider.hasLocation &&
              requireNameMatch &&
              !shop.name.toLowerCase().contains(lowerQuery)) {
            continue;
          }
          if (!locationProvider.hasLocation &&
              effectiveCategories != null &&
              !effectiveCategories.contains(shop.category)) {
            continue;
          }
          allShopsSet[shop.id] = shop;
        }
      }

      addShops(shopsByName, true);
      addShops(shopsByCat, false);

      final allShops = allShopsSet.values.toList();

      List<ShopModel> shopResults;
      if (locationProvider.hasLocation) {
        for (final shop in allShops) {
          if (shop.location.latitude != 0 && shop.location.longitude != 0) {
            shop.distanceKm = locationProvider.distanceTo(shop.location);
          } else {
            shop.distanceKm = null;
          }
        }
        shopResults = allShops
            .where((s) =>
                s.distanceKm != null &&
                DeliveryCalculator.isWithinRange(s.distanceKm!))
            .toList();
      } else {
        shopResults = allShops;
      }

      final List<ProductModel> prodResults = [];
      final Map<String, ShopModel> prodShops = {};
      final addedProductIds = <String>{};

      void addProducts(List<dynamic> response) {
        for (final p in response) {
          final product = ProductModel.fromMap(p);
          if (!config.isActiveCategory(product.category)) continue;
          if (addedProductIds.contains(product.id)) continue;

          if (!locationProvider.hasLocation &&
              effectiveCategories != null &&
              !effectiveCategories.contains(product.category)) {
            continue;
          }
          if (p['shops'] == null) continue;

          final shop = ShopModel.fromMap(p['shops']);
          if (!shop.isActive || !config.isActiveCategory(shop.category)) {
            continue;
          }
          if (!locationProvider.hasLocation &&
              effectiveCategories != null &&
              !effectiveCategories.contains(shop.category)) {
            continue;
          }

          if (locationProvider.hasLocation) {
            if (shop.location.latitude == 0 || shop.location.longitude == 0) {
              continue;
            }
            final d = locationProvider.distanceTo(shop.location);
            if (!DeliveryCalculator.isWithinRange(d)) continue;
            shop.distanceKm = d;
          }

          prodResults.add(product);
          prodShops[product.id] = shop;
          addedProductIds.add(product.id);

          // Phase 25 Fix: Additive logic to ensure shops that sell the searched product
          // also appear in the "Shops & Restaurants" section within delivery radius.
          if (!allShopsSet.containsKey(shop.id)) {
            allShopsSet[shop.id] = shop;
            if (!locationProvider.hasLocation ||
                (shop.distanceKm != null &&
                    DeliveryCalculator.isWithinRange(shop.distanceKm!))) {
              shopResults.add(shop);
            }
          }
        }
      }

      addProducts(productsByName);
      addProducts(productsByCat);

      if (_searchQuery.trim().isNotEmpty) {
        SearchRelevanceEngine.sortProducts(
          products: prodResults,
          query: _searchQuery,
          shops: prodShops,
        );
      }

      if (mounted) {
        if (_searchQuery != query) return;

        setState(() {
          _searchResults = shopResults;
          _searchProductResults = prodResults;
          _searchProductShops = prodShops;
          _isSearching = false;
        });
      }
    } catch (e, st) {
      debugPrint('_searchShops ERROR: $e\n$st');

      // Classify the error for user-facing messaging
      String userMessage;
      final errStr = e.toString();
      if (errStr.contains('SocketException') ||
          errStr.contains('TimeoutException') ||
          errStr.contains('HandshakeException') ||
          errStr.contains('Connection closed') ||
          errStr.contains('Network is unreachable')) {
        userMessage = 'Please check your internet connection.';
      } else if (errStr.contains('42883') ||
          errStr.contains('function') && errStr.contains('does not exist')) {
        userMessage =
            'Search service unavailable. DB function missing — contact support.';
        debugPrint(
            '[Search] ⚠ PostgREST 42883: search function not found. Migrations may not be applied.');
      } else if (errStr.contains('42725') || errStr.contains('is not unique')) {
        userMessage =
            'Search service error. DB function ambiguity — contact support.';
        debugPrint('[Search] ⚠ PostgREST 42725: ambiguous function overload.');
      } else if (errStr.contains('PGRST')) {
        userMessage = 'Search service error: $errStr';
      } else {
        userMessage =
            'Search failed: ${errStr.length > 120 ? '${errStr.substring(0, 120)}...' : errStr}';
      }

      if (mounted && _searchQuery == query) {
        setState(() {
          _isSearching = false;
          _searchError = true;
          _searchErrorMessage = userMessage;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userMessage),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _checkLocationAndLoad() async {
    final locationProvider = context.read<LocationProvider>();

    setState(() {
      _isSearching = false;
      _searchError = false;
      _searchQuery = '';
      _comingSoonMessage = null;
      _comingSoonSubMessage = null;
    });

    if (!locationProvider.hasLocation) {
      await locationProvider.requestLocation();
    } else if (locationProvider.selectedAddress == null) {
      // 100x Background Verification: Ensure live physical GPS fix hasn't shifted away from cold cache
      locationProvider.requestLocation(isUserAction: false);
    }

    // _selectedTabIndex == -1 means "All" — fetch every active shop
    _loadTrendingKeywords();
    final cats = _categories;
    if (_selectedTabIndex < 0 || _selectedTabIndex >= cats.length) {
      _loadAllData();
    } else {
      _loadData(cats[_selectedTabIndex]['name']! as String);
    }
  }

  /// Maps broad tab name → actual DB category values
  static const Map<String, List<String>> _tabCategories = {
    'Food': [
      'Restaurant',
      'Fast Food',
      'Tea & Coffee',
      'Ice Cream',
      'Paan Shop',
      'Beverages'
    ],
    'MeatAndFish': [
      'Butcher',
      'Fish & Seafood',
      'Meat',
      'Raw Meat',
    ],
    'DairyAndEggs': [
      'Dairy & Eggs',
      'Dairy',
      'Fresh Milk',
      'Milk & Eggs',
    ],
    'BakeryAndSweets': [
      'Bakery',
      'Sweets & Mithai',
      'Sweets and Mithai',
      'Cake & Pastry',
    ],
    'FruitsVegsOrganic': [
      'Fruits & Vegs',
      'Fruits and Vegs',
      'Fruits & Vegetables',
      'Organic',
    ],
    'Grocery': [
      'Grocery',
      'Grocerylm',
      'Supermarket / Hypermarket',
      'Fruits & Vegs',
      'Dairy & Eggs',
      'Butcher',
      'Fish & Seafood',
      'Organic'
    ],
    'Pharmacy': [
      'Pharmacy',
      'Medical Store',
      'Medicines',
      'Medicine',
      'Pharma',
      'Chemist',
      'Healthcare'
    ],
    'GroceryAndMed': [
      'Grocery',
      'Grocerylm',
      'Supermarket / Hypermarket',
      'Fruits & Vegs',
      'Dairy & Eggs',
      'Butcher',
      'Fish & Seafood',
      'Organic',
      'Pharmacy',
      'Medical Store',
      'Medicines',
      'Medicine',
      'Pharma',
      'Chemist',
      'Healthcare'
    ],
    'Clothing': ['Clothing', 'Footwear', 'Jewellery'],
    'Electronics': ['Electronics', 'Mobile & Repair'],
    'Hardware': ['Hardware Store', 'Hardware', 'Tools & Hardware'],
    'Cosmetics': ['Cosmetics & Beauty'],
    'Cosmetics & Beauty': ['Cosmetics & Beauty'],
    'SalonAndBeauty': [
      'Salon & Beauty',
      'Salon and Beauty',
      'Beauty & Personal Care'
    ],
    'Supermarket': [
      'Supermarket / Hypermarket',
      'Grocery',
      'Grocerylm',
      'Fruits & Vegs',
      'Dairy & Eggs',
      'Butcher',
      'Fish & Seafood',
      'Organic'
    ],
    'Supermarket / Hypermarket': [
      'Supermarket / Hypermarket',
      'Grocery',
      'Grocerylm',
      'Fruits & Vegs',
      'Dairy & Eggs',
      'Butcher',
      'Fish & Seafood',
      'Organic'
    ],
    'Stationery': ['Stationery'],
    'More': [
      'Hardware Store',
      'Stationery',
      'Toys & Games',
      'Sports',
      'Pet Supplies',
      'Cosmetics & Beauty',
      'Salon & Beauty',
      'Flowers',
      'Home Decor',
      'Furniture',
      'Auto Parts',
      'Other'
    ],
  };

  /// 100x Department Catalog Inventory Parity Counter
  /// Queries exact total active products in database for nearby shops by department,
  /// perfectly mirroring the query pattern and shop matching of AllListingsPage and
  /// CategoryProductsPage so that dashboard badges match opened catalog views 100%.
  Future<Map<String, int>> _fetchDepartmentTotalCounts(
      List<ShopModel> nearbyShops) async {
    final Map<String, int> counts = {};
    if (nearbyShops.isEmpty) return counts;

    final departments = <String, List<String>>{
      'Food': _tabCategories['Food'] ?? ['Food'],
      'MeatAndFish':
          _tabCategories['MeatAndFish'] ?? ['Butcher', 'Fish & Seafood'],
      'DairyAndEggs': _tabCategories['DairyAndEggs'] ?? ['Dairy & Eggs'],
      'BakeryAndSweets':
          _tabCategories['BakeryAndSweets'] ?? ['Bakery', 'Sweets & Mithai'],
      'FruitsVegsOrganic':
          _tabCategories['FruitsVegsOrganic'] ?? ['Fruits & Vegs', 'Organic'],
      'Pharmacy': _tabCategories['Pharmacy'] ?? ['Pharmacy', 'Medical Store'],
      'Cosmetics': _tabCategories['Cosmetics'] ?? ['Cosmetics & Beauty'],
      'SalonAndBeauty': _tabCategories['SalonAndBeauty'] ?? ['Salon & Beauty'],
      'Stationery': _tabCategories['Stationery'] ?? ['Stationery'],
      'Grocery': _tabCategories['Supermarket'] ??
          _tabCategories['Grocery'] ??
          ['Grocery'],
      'Clothing': _tabCategories['Clothing'] ?? ['Clothing'],
      'Electronics': _tabCategories['Electronics'] ?? ['Electronics'],
      'Hardware': _tabCategories['Hardware'] ?? ['Hardware Store'],
    };

    try {
      await Future.wait(
        departments.entries.map((entry) async {
          final deptKey = entry.key;
          final categories = entry.value;

          // 100x Multi-Department Omnibus Count Parity:
          // Query all active nearby shops to count products in target department,
          // ensuring omnibus stores carrying food/cosmetics/clothing aren't excluded.
          final allNearbyShopIds = nearbyShops.map((s) => s.id).toList();
          if (allNearbyShopIds.isEmpty) {
            counts[deptKey] = 0;
            return;
          }

          try {
            // Direct PostgREST table query — exactly matches all_listings_page.dart:495-508
            final countResp = await _supabase
                .from('products')
                .select('id')
                .inFilter('shop_id', allNearbyShopIds)
                .inFilter('category', categories)
                .eq('is_deleted', false)
                .eq('is_available', true);

            counts[deptKey] = countResp.length;
          } catch (e) {
            debugPrint('Failed to count department $deptKey: $e');
          }
        }),
      );
    } catch (e) {
      debugPrint('Error in _fetchDepartmentTotalCounts: $e');
    }
    return counts;
  }

  /// Fetch ALL active shops & products, sorted by rating then total_orders.
  /// Used on initial load when no category tab is selected.
  Future<void> _loadAllData() async {
    final currentFetchId = ++_fetchId;
    _isFetching = true;

    if (mounted) {
      setState(() {
        _comingSoonMessage = null;
        _comingSoonSubMessage = null;
      });
    }

    // Only show the shimmer on the very first load. On subsequent loads
    // (e.g., GPS update or category deselect) keep old data visible.
    if (!_hasLoadedOnce) {
      setState(() => _isLoading = true);
    }
    try {
      final locationProvider = context.read<LocationProvider>();
      final config = context.read<PlatformConfigProvider>();

      // ── In-memory cache fast-path ─────────────────────────────────────────
      // Serve cached feed data when: (a) cache is warm, (b) TTL not expired,
      // (c) no user-driven filter change (tab or category filter unchanged).
      // This gives instant re-renders on GPS micro-updates and back-navigation.
      final now = DateTime.now();
      final loc = locationProvider.currentLocation;
      final isLocationSame = loc != null &&
          _cachedLocation != null &&
          locationProvider.distanceTo(_cachedLocation!) < 0.2;
      final isCacheWarm = _cachedShops != null &&
          _cachedProducts != null &&
          _cachedProductShops != null &&
          _cacheTimestamp != null &&
          now.difference(_cacheTimestamp!) < _cacheTtl &&
          (loc == null || isLocationSame) &&
          _selectedFilterCategories
              .isEmpty; // don't use stale cache when filtering
      if (isCacheWarm && _hasLoadedOnce) {
        if (mounted && _fetchId == currentFetchId) {
          _invalidateSortMemo();
          setState(() {
            _shops = _cachedShops!;
            _products = _cachedProducts!;
            _productShops = _cachedProductShops!;
            _departmentProductCounts = _cachedDepartmentProductCounts ?? {};
            _comingSoonMessage = null;
            _comingSoonSubMessage = null;
            _isLoading = false;
          });
        }
        _isFetching = false;
        return;
      }
      // ─────────────────────────────────────────────────────────────────────

      List<String> effectiveCategories = [];
      if (_selectedFilterCategories.isNotEmpty) {
        for (final cat in _selectedFilterCategories) {
          final subs = _tabCategories[cat] ?? [cat];
          effectiveCategories
              .addAll(subs.where((c) => config.isActiveCategory(c)));
        }
      } else {
        effectiveCategories = config.activeCategoryNames;
      }

      // Phase 16 Fix: Additive Geospatial fetch to prevent Pixel Blindness
      final shopsResponse = locationProvider.hasLocation
          ? await _supabase.rpc('get_nearby_shops', params: {
              'p_lat': locationProvider.currentLocation!.latitude,
              'p_lng': locationProvider.currentLocation!.longitude,
              'p_radius_km': DeliveryCalculator.maxRadiusKm,
              'p_limit':
                  500, // Fetch up to 500 nearby shops to prevent category starving
              if (effectiveCategories.isNotEmpty)
                'p_categories': effectiveCategories,
            })
          : [];

      final allShops = (shopsResponse as List)
          .map((s) => ShopModel.fromMap(s))
          .where((s) =>
              s.isActive &&
              (config.activeCategoryNames.isEmpty ||
                  config.isActiveCategory(s.category)))
          .toList();

      List<ShopModel> nearby;
      if (locationProvider.hasLocation) {
        for (final shop in allShops) {
          if (shop.location.latitude != 0 && shop.location.longitude != 0) {
            shop.distanceKm = locationProvider.distanceTo(shop.location);
          } else {
            shop.distanceKm = null;
          }
        }
        nearby = allShops
            .where((s) =>
                s.distanceKm != null &&
                DeliveryCalculator.isWithinRange(s.distanceKm!))
            .toList()
          ..sort((a, b) {
            // Priority 0: Open shops first!
            final openA = a.isOpenRightNow ? 1 : 0;
            final openB = b.isOpenRightNow ? 1 : 0;
            if (openA != openB) return openB.compareTo(openA);
            // Primary sort: higher rating first
            final ratingCmp = (b.rating).compareTo(a.rating);
            if (ratingCmp != 0) return ratingCmp;
            // Secondary: closer distance first
            return (a.distanceKm ?? double.infinity)
                .compareTo(b.distanceKm ?? double.infinity);
          });
      } else {
        // No GPS yet — show all active shops sorted by open first, then rating
        nearby = allShops
          ..sort((a, b) {
            final openA = a.isOpenRightNow ? 1 : 0;
            final openB = b.isOpenRightNow ? 1 : 0;
            if (openA != openB) return openB.compareTo(openA);
            return b.rating.compareTo(a.rating);
          });
      }

      // 100x Geospatial Radius Fortress: If no active shops exist within the delivery radius,
      // fail fast, purge stale in-memory static caches, and display the unserviceable location screen.
      if (nearby.isEmpty) {
        if (_fetchId != currentFetchId) return;
        _cachedShops = [];
        _cachedProducts = [];
        _cachedProductShops = {};
        _cachedDepartmentProductCounts = {};
        _cachedLocation = locationProvider.currentLocation;
        _cacheTimestamp = DateTime.now();

        if (mounted) {
          _invalidateSortMemo();
          setState(() {
            _shops = [];
            _products = [];
            _productShops = {};
            _departmentProductCounts = {};
            _comingSoonMessage = 'No stores deliver to this location yet';
            _comingSoonSubMessage =
                'We currently deliver within a ${DeliveryCalculator.maxRadiusKm.toInt()} km radius of our active hubs. Stores will be available in your area soon!';
            _isLoading = false;
            _hasLoadedOnce = true;
            _loadRetryCount = 0;
          });
        }
        return;
      }

      // Stratified Diverse Category Selection: Sample across Pharmacy, Grocery, Clothing, Food & other
      // to ensure all dedicated dashboard sections have rich product discovery without starving any category.
      bool isShopInCategories(ShopModel s, List<String> targetCats) {
        final lowerTargets =
            targetCats.map((c) => c.trim().toLowerCase()).toSet();
        if (lowerTargets.contains(s.category.trim().toLowerCase())) return true;
        if (s.categories
            .any((c) => lowerTargets.contains(c.trim().toLowerCase()))) {
          return true;
        }
        // 100x Multi-department omnibus store check: Supermarkets & Hypermarkets carry cosmetics departments
        if (lowerTargets
            .any((t) => t.contains('cosmetic') || t.contains('beauty'))) {
          final sCat = s.category.trim().toLowerCase();
          if (sCat.contains('supermarket') ||
              sCat.contains('hypermarket') ||
              sCat.contains('departmental')) {
            return true;
          }
        }
        return false;
      }

      // Stratified sampling: ensure all dedicated homepage department sections
      // (Food, Pharmacy, Grocery/Supermarket, Cosmetics, Stationery, Clothing,
      // Meat/Fish, Dairy, Bakery/Sweets, Fruits/Vegs, Electronics, Hardware, Salon)
      // have products by sampling shops from each category group.
      final foodShops = nearby
          .where((s) => isShopInCategories(s, _tabCategories['Food'] ?? []))
          .take(12);
      final bakeryShops = nearby
          .where((s) =>
              isShopInCategories(s, _tabCategories['BakeryAndSweets'] ?? []))
          .take(8);
      final dairyShops = nearby
          .where((s) =>
              isShopInCategories(s, _tabCategories['DairyAndEggs'] ?? []))
          .take(8);
      final fruitsVegsShops = nearby
          .where((s) =>
              isShopInCategories(s, _tabCategories['FruitsVegsOrganic'] ?? []))
          .take(8);
      final meatShops = nearby
          .where(
              (s) => isShopInCategories(s, _tabCategories['MeatAndFish'] ?? []))
          .take(8);
      final pharmacyShops = nearby
          .where((s) => isShopInCategories(s, _tabCategories['Pharmacy'] ?? []))
          .take(10);
      final cosmeticsShops = nearby
          .where(
              (s) => isShopInCategories(s, _tabCategories['Cosmetics'] ?? []))
          .take(8);
      final salonShops = nearby
          .where((s) =>
              isShopInCategories(s, _tabCategories['SalonAndBeauty'] ?? []))
          .take(8);
      final clothingShops = nearby
          .where((s) => isShopInCategories(s, _tabCategories['Clothing'] ?? []))
          .take(10);
      final electronicsShops = nearby
          .where(
              (s) => isShopInCategories(s, _tabCategories['Electronics'] ?? []))
          .take(8);
      final hardwareShops = nearby
          .where((s) => isShopInCategories(s, _tabCategories['Hardware'] ?? []))
          .take(8);
      final stationeryShops = nearby
          .where(
              (s) => isShopInCategories(s, _tabCategories['Stationery'] ?? []))
          .take(8);
      final groceryShops = nearby
          .where((s) => isShopInCategories(s, _tabCategories['Grocery'] ?? []))
          .take(12);
      final otherShops = nearby
          .where((s) =>
              !isShopInCategories(s, _tabCategories['Food'] ?? []) &&
              !isShopInCategories(s, _tabCategories['BakeryAndSweets'] ?? []) &&
              !isShopInCategories(s, _tabCategories['DairyAndEggs'] ?? []) &&
              !isShopInCategories(
                  s, _tabCategories['FruitsVegsOrganic'] ?? []) &&
              !isShopInCategories(s, _tabCategories['MeatAndFish'] ?? []) &&
              !isShopInCategories(s, _tabCategories['Pharmacy'] ?? []) &&
              !isShopInCategories(s, _tabCategories['Cosmetics'] ?? []) &&
              !isShopInCategories(s, _tabCategories['SalonAndBeauty'] ?? []) &&
              !isShopInCategories(s, _tabCategories['Clothing'] ?? []) &&
              !isShopInCategories(s, _tabCategories['Electronics'] ?? []) &&
              !isShopInCategories(s, _tabCategories['Hardware'] ?? []) &&
              !isShopInCategories(s, _tabCategories['Grocery'] ?? []) &&
              !isShopInCategories(s, _tabCategories['Stationery'] ?? []))
          .take(15);

      final diverseShopIds = <String>{};
      for (final s in foodShops) {
        diverseShopIds.add(s.id);
      }
      for (final s in bakeryShops) {
        diverseShopIds.add(s.id);
      }
      for (final s in dairyShops) {
        diverseShopIds.add(s.id);
      }
      for (final s in fruitsVegsShops) {
        diverseShopIds.add(s.id);
      }
      for (final s in meatShops) {
        diverseShopIds.add(s.id);
      }
      for (final s in pharmacyShops) {
        diverseShopIds.add(s.id);
      }
      for (final s in cosmeticsShops) {
        diverseShopIds.add(s.id);
      }
      for (final s in salonShops) {
        diverseShopIds.add(s.id);
      }
      for (final s in clothingShops) {
        diverseShopIds.add(s.id);
      }
      for (final s in electronicsShops) {
        diverseShopIds.add(s.id);
      }
      for (final s in hardwareShops) {
        diverseShopIds.add(s.id);
      }
      for (final s in groceryShops) {
        diverseShopIds.add(s.id);
      }
      for (final s in stationeryShops) {
        diverseShopIds.add(s.id);
      }
      for (final s in otherShops) {
        diverseShopIds.add(s.id);
      }

      for (final s in nearby) {
        if (diverseShopIds.length >= 95) break;
        diverseShopIds.add(s.id);
      }

      final perShopLimit = diverseShopIds.length <= 2 ? 16 : 12;
      final productsResponse = diverseShopIds.isEmpty
          ? []
          : await _supabase.rpc('get_feed_products', params: {
              'p_shop_ids': diverseShopIds.toList(),
              'p_limit_per_shop': perShopLimit,
              'p_categories': effectiveCategories,
            }).select('*, shops(*)');

      if (mounted) {
        final prods = <ProductModel>[];
        final prodShops = <String, ShopModel>{};

        for (final p in productsResponse) {
          final product = ProductModel.fromMap(p);
          if (p['shops'] == null) continue;

          final shop = ShopModel.fromMap(p['shops']);
          if (!shop.isActive || !config.isActiveCategory(shop.category)) {
            continue;
          }

          final matchesCategory = AppCategories.matchesBrowsingCategory(
            productCategory: product.category,
            shopCategory: shop.category,
            targetCategories: effectiveCategories,
            shopCategories: shop.categories,
          );
          if (!matchesCategory || !config.isActiveCategory(product.category)) {
            continue;
          }

          if (locationProvider.hasLocation) {
            if (shop.location.latitude == 0 || shop.location.longitude == 0) {
              continue;
            }
            final d = locationProvider.distanceTo(shop.location);
            if (!DeliveryCalculator.isWithinRange(d)) continue;
          }

          prods.add(product);
          prodShops[product.id] = shop;
        }

        // ── 100x Multi-Department Guaranteed Representation Fortress ──────────
        // If a dedicated department (e.g. Cosmetics & Beauty) has nearby stores
        // but was starved out by another department's high-volume items in a multi-department store,
        // proactively fetch a dedicated department sample so the showcase carousel always renders!
        final cosmeticCats =
            _tabCategories['Cosmetics & Beauty'] ?? ['Cosmetics & Beauty'];
        final hasCosmeticsInFeed =
            prods.any((p) => AppCategories.matchesBrowsingCategory(
                  productCategory: p.category,
                  shopCategory: prodShops[p.id]?.category,
                  targetCategories: cosmeticCats,
                  shopCategories: prodShops[p.id]?.categories,
                ));

        if (!hasCosmeticsInFeed && cosmeticsShops.isNotEmpty) {
          try {
            final cosShopIds = cosmeticsShops.map((s) => s.id).toList();
            final cosResp = await _supabase.rpc('get_feed_products', params: {
              'p_shop_ids': cosShopIds,
              'p_limit_per_shop': 8,
              'p_categories': cosmeticCats,
            }).select('*, shops(*)');

            for (final p in (cosResp as List)) {
              if (p['shops'] == null) continue;
              final shop = ShopModel.fromMap(p['shops']);
              if (!shop.isActive || !config.isActiveCategory(shop.category)) {
                continue;
              }
              final product = ProductModel.fromMap(p);
              if (!config.isActiveCategory(product.category)) continue;

              if (locationProvider.hasLocation) {
                if (shop.location.latitude == 0 ||
                    shop.location.longitude == 0) {
                  continue;
                }
                final d = locationProvider.distanceTo(shop.location);
                if (!DeliveryCalculator.isWithinRange(d)) continue;
              }

              prods.add(product);
              prodShops[product.id] = shop;
            }
          } catch (e) {
            debugPrint('_loadAllData: Cosmetics department backfill error: $e');
          }
        }

        prods.sort((a, b) {
          final sA = prodShops[a.id];
          final sB = prodShops[b.id];
          final availA = a.isAvailable && (sA?.isOpenRightNow ?? false);
          final availB = b.isAvailable && (sB?.isOpenRightNow ?? false);
          if (availA && !availB) return -1;
          if (!availA && availB) return 1;
          return b.rating.compareTo(a.rating);
        });

        if (_fetchId != currentFetchId) return; // Prevent async tab desync

        // ── Populate in-memory cache for fast subsequent renders ───────────
        _cachedShops = nearby;
        _cachedProducts = prods;
        _cachedProductShops = prodShops;
        _cachedLocation = locationProvider.currentLocation;
        _cacheTimestamp = DateTime.now();

        // ── 100x Department Aggregate Product Counts Fortress ────────────────
        // Query exact total available products across nearby shops by department
        // to ensure section header badges on the dashboard reflect true catalog
        // inventory matching AllListingsPage and CategoryProductsPage.
        final deptCounts = await _fetchDepartmentTotalCounts(nearby);
        _cachedDepartmentProductCounts = deptCounts;

        _invalidateSortMemo();
        // Atomic update: swap data and clear loading in a single setState
        setState(() {
          _shopsDisplayLimit = 3;
          _productsDisplayLimit = 6;
          _shops = nearby;
          _products = prods;
          _productShops = prodShops;
          _departmentProductCounts = deptCounts;
          _isLoading = false;
          _hasLoadedOnce = true;
          _loadRetryCount = 0; // Reset retry counter on success
        });
      }
    } catch (e, st) {
      // Log full error so we can debug exactly what Supabase query failed
      debugPrint('_loadAllData ERROR: $e\n$st');
      if (!mounted || _fetchId != currentFetchId) return;

      // ── Industrial-standard error classification ─────────────────────────
      // Transient: SocketException, TimeoutException, ClientException — safe to retry
      // Permanent: auth errors, query errors — fail fast, show actionable message
      final isTransient = e is SocketException ||
          e is TimeoutException ||
          (e.toString().contains('ClientException') &&
              !e.toString().contains('403') &&
              !e.toString().contains('401'));

      setState(() => _isLoading = false);

      if (isTransient && _loadRetryCount < _maxLoadRetries) {
        _loadRetryCount++;
        // Exponential backoff with jitter: 1s → 2s → 4s + up to 500ms random jitter
        final backoffSeconds = (1 << (_loadRetryCount - 1)); // 1, 2, 4
        final jitterMs =
            (500 * (DateTime.now().millisecondsSinceEpoch % 100) / 100).round();
        final delay = Duration(seconds: backoffSeconds, milliseconds: jitterMs);
        debugPrint(
            '_loadAllData: transient error, retry $_loadRetryCount/$_maxLoadRetries in ${delay.inSeconds}s');

        // Show silent inline status — no alarming red banner for network blips
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Text('Connection issue — retrying in ${backoffSeconds}s…'),
              ]),
              backgroundColor: const Color(0xFF2A2A2A),
              duration: delay + const Duration(milliseconds: 200),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        _retryTimer?.cancel();
        _retryTimer = Timer(delay, () {
          if (mounted) _loadAllData();
        });
      } else {
        // Permanent error or retries exhausted — show friendly actionable message
        _loadRetryCount = 0;
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                  'Couldn\'t load shops. Check your connection and pull down to refresh.'),
              backgroundColor: const Color(0xFF1A1A1A),
              duration: const Duration(seconds: 4),
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: 'Retry',
                textColor: AppColors.primary,
                onPressed: () {
                  _loadRetryCount = 0;
                  _loadAllData();
                },
              ),
            ),
          );
        }
      }
    } finally {
      if (_fetchId == currentFetchId) {
        _isFetching = false;
        if (_pendingLocationUpdate && mounted) {
          _pendingLocationUpdate = false;
          _onLocationChanged();
        }
      }
    }
  }

  Future<void> _loadData(String tabName) async {
    final currentFetchId = ++_fetchId;
    _isFetching = true;

    if (mounted) {
      setState(() {
        _comingSoonMessage = null;
        _comingSoonSubMessage = null;
      });
    }

    // Do NOT set _isLoading = true here on category switch — this causes the
    // existing content to disappear (the "flash"). Keep old data visible
    // and only swap data once the new fetch is complete.
    // Only show shimmer on the very first app load.
    if (!_hasLoadedOnce) {
      setState(() => _isLoading = true);
    }
    try {
      final locationProvider = context.read<LocationProvider>();
      final config = context.read<PlatformConfigProvider>();
      final rawSubcategories = _tabCategories[tabName] ?? [tabName];
      final subcategories =
          rawSubcategories.where((c) => config.isActiveCategory(c)).toList();

      // Guard: If category or all its subcategories are disabled by admin
      if (subcategories.isEmpty) {
        if (_fetchId != currentFetchId) return;
        setState(() {
          _shops = [];
          _products = [];
          _productShops = {};
          _comingSoonMessage = '$tabName Coming Soon!';
          _comingSoonSubMessage =
              'This category is currently paused in your area. We\'ll be back soon!';
          _isLoading = false;
          _hasLoadedOnce = true;
          _loadRetryCount = 0;
        });
        return;
      }

      List<String> effectiveCategories = [];
      if (_selectedFilterCategories.isNotEmpty) {
        for (final cat in _selectedFilterCategories) {
          final subs = _tabCategories[cat] ?? [cat];
          effectiveCategories
              .addAll(subs.where((c) => config.isActiveCategory(c)));
        }
      } else {
        effectiveCategories = config.activeCategoryNames;
      }

      final finalCategories =
          subcategories.where((c) => effectiveCategories.contains(c)).toList();

      if (finalCategories.isEmpty) {
        if (_fetchId != currentFetchId) return;
        setState(() {
          _shops = [];
          _products = [];
          _productShops = {};
          _comingSoonMessage = '$tabName Coming Soon!';
          _comingSoonSubMessage =
              'This category is currently paused in your area. We\'ll be back soon!';
          _isLoading = false;
          _hasLoadedOnce = true;
          _loadRetryCount = 0;
        });
        return;
      }

      // Phase 16 Fix: Additive Geospatial fetch to prevent Pixel Blindness
      final shopsResponse =
          (locationProvider.hasLocation && finalCategories.isNotEmpty)
              ? await _supabase.rpc('get_nearby_shops', params: {
                  'p_lat': locationProvider.currentLocation!.latitude,
                  'p_lng': locationProvider.currentLocation!.longitude,
                  'p_radius_km': DeliveryCalculator.maxRadiusKm,
                  'p_limit':
                      500, // Fetch ample pool, then filter down to subcategories locally
                  'p_categories': finalCategories,
                })
              : [];

      final allShops = (shopsResponse as List)
          .map((s) => ShopModel.fromMap(s))
          .where((s) =>
              s.isActive &&
              (config.activeCategoryNames.isEmpty ||
                  config.isActiveCategory(s.category)))
          .toList();

      List<ShopModel> nearby;
      if (locationProvider.hasLocation) {
        for (final shop in allShops) {
          if (shop.location.latitude != 0 && shop.location.longitude != 0) {
            shop.distanceKm = locationProvider.distanceTo(shop.location);
          } else {
            shop.distanceKm = null;
          }
        }
        nearby = allShops
            .where((s) =>
                s.distanceKm != null &&
                DeliveryCalculator.isWithinRange(s.distanceKm!))
            .toList()
          ..sort((a, b) {
            final openA = a.isOpenRightNow ? 1 : 0;
            final openB = b.isOpenRightNow ? 1 : 0;
            if (openA != openB) return openB.compareTo(openA);
            return (a.distanceKm ?? double.infinity)
                .compareTo(b.distanceKm ?? double.infinity);
          });
      } else {
        nearby = allShops
          ..sort((a, b) {
            final openA = a.isOpenRightNow ? 1 : 0;
            final openB = b.isOpenRightNow ? 1 : 0;
            if (openA != openB) return openB.compareTo(openA);
            return b.rating.compareTo(a.rating);
          });
      }

      // If no shops in delivery radius, show Coming Soon state
      if (nearby.isEmpty) {
        if (_fetchId != currentFetchId) return;
        setState(() {
          _shops = [];
          _products = [];
          _productShops = {};
          _comingSoonMessage = '$tabName Delivery Coming Soon!';
          _comingSoonSubMessage =
              'We\'re partnering with top local stores to bring $tabName to your location soon!';
          _isLoading = false;
          _hasLoadedOnce = true;
          _loadRetryCount = 0;
        });
        return;
      }

      // Phase 21 Fix: Prevent Pixel Overloading by using RPC to fetch a diverse per-shop limit
      final nearbyShopIds = nearby.map((s) => s.id).take(50).toList();
      final perShopLimit = nearbyShopIds.length <= 2 ? 12 : 8;

      final productsResponse = nearbyShopIds.isEmpty
          ? []
          : await _supabase.rpc('get_feed_products', params: {
              'p_shop_ids': nearbyShopIds,
              'p_limit_per_shop': perShopLimit,
              'p_categories': finalCategories,
            }).select('*, shops(*)');

      if (mounted) {
        final prods = <ProductModel>[];
        final prodShops = <String, ShopModel>{};

        for (final p in productsResponse) {
          if (p['shops'] == null) continue;

          final shop = ShopModel.fromMap(p['shops']);
          if (!shop.isActive || !config.isActiveCategory(shop.category)) {
            continue;
          }

          final product = ProductModel.fromMap(p);
          if (!config.isActiveCategory(product.category)) continue;

          final matchesCategory = AppCategories.matchesBrowsingCategory(
            productCategory: product.category,
            shopCategory: shop.category,
            targetCategories: finalCategories,
            shopCategories: shop.categories,
          );
          if (!matchesCategory) continue;

          if (locationProvider.hasLocation) {
            if (shop.location.latitude == 0 || shop.location.longitude == 0) {
              continue;
            }
            final d = locationProvider.distanceTo(shop.location);
            if (!DeliveryCalculator.isWithinRange(d)) continue;
          }

          prods.add(product);
          prodShops[product.id] = shop;
        }
        prods.sort((a, b) {
          final sA = prodShops[a.id];
          final sB = prodShops[b.id];
          final availA = a.isAvailable && (sA?.isOpenRightNow ?? false);
          final availB = b.isAvailable && (sB?.isOpenRightNow ?? false);
          if (availA && !availB) return -1;
          if (!availA && availB) return 1;
          return b.rating.compareTo(a.rating);
        });

        if (_fetchId != currentFetchId) return; // Prevent async tab desync

        _invalidateSortMemo();
        // Atomic update: swap data in a single setState
        setState(() {
          _shopsDisplayLimit = 3;
          _productsDisplayLimit = 6;
          _shops = nearby;
          _products = prods;
          _productShops = prodShops;
          _comingSoonMessage = prods.isEmpty && nearby.isEmpty
              ? '$tabName Delivery Coming Soon!'
              : null;
          _comingSoonSubMessage = prods.isEmpty && nearby.isEmpty
              ? 'We\'re partnering with top local stores to bring $tabName to your location soon!'
              : null;
          _isLoading = false;
          _hasLoadedOnce = true;
          _loadRetryCount = 0; // Reset retry counter on success
        });
      }
    } catch (e, st) {
      debugPrint('_loadData ERROR: $e\n$st');
      if (!mounted || _fetchId != currentFetchId) return;

      // ── Same error classification as _loadAllData ──────────────────────
      final isTransient = e is SocketException ||
          e is TimeoutException ||
          (e.toString().contains('ClientException') &&
              !e.toString().contains('403') &&
              !e.toString().contains('401'));

      setState(() => _isLoading = false);

      if (isTransient && _loadRetryCount < _maxLoadRetries) {
        _loadRetryCount++;
        final backoffSeconds = (1 << (_loadRetryCount - 1));
        final jitterMs =
            (500 * (DateTime.now().millisecondsSinceEpoch % 100) / 100).round();
        final delay = Duration(seconds: backoffSeconds, milliseconds: jitterMs);
        debugPrint(
            '_loadData: transient error, retry $_loadRetryCount/$_maxLoadRetries in ${delay.inSeconds}s');
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Text('Connection issue — retrying in ${backoffSeconds}s…'),
              ]),
              backgroundColor: const Color(0xFF2A2A2A),
              duration: delay + const Duration(milliseconds: 200),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        _retryTimer?.cancel();
        _retryTimer = Timer(delay, () {
          if (mounted) _loadData(tabName);
        });
      } else {
        _loadRetryCount = 0;
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                  'Couldn\'t load shops. Check your connection and pull down to refresh.'),
              backgroundColor: const Color(0xFF1A1A1A),
              duration: const Duration(seconds: 4),
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: 'Retry',
                textColor: AppColors.primary,
                onPressed: () {
                  _loadRetryCount = 0;
                  _loadData(tabName);
                },
              ),
            ),
          );
        }
      }
    } finally {
      if (_fetchId == currentFetchId) {
        _isFetching = false;
        if (_pendingLocationUpdate && mounted) {
          _pendingLocationUpdate = false;
          _onLocationChanged();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _invalidateSortMemo();
    final currentFiltering = _selectedTabIndex >= 0 ||
        _selectedFilterCategories.isNotEmpty ||
        _searchQuery.isNotEmpty;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (globalIsFiltering.value != currentFiltering) {
        globalIsFiltering.value = currentFiltering;
      }
    });

    final locationProvider = context.watch<LocationProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = themeProvider.isDarkMode;
    final productMeta = _getProductSectionMeta();
    final storeMeta = _getStoreSectionMeta();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: CustomScrollView(
          controller: _mainScrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            // ── Premium Modern AppBar ──────────────────────────────────────
            SliverAppBar(
              expandedHeight: _searchQuery.isNotEmpty ? 0 : 125,
              floating: true,
              pinned: true,
              elevation: 0,
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              surfaceTintColor: Colors.transparent,
              flexibleSpace: FlexibleSpaceBar(
                background: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _searchQuery.isNotEmpty ? 0.0 : 1.0,
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: Container(
                      padding: EdgeInsets.fromLTRB(
                          16, MediaQuery.of(context).padding.top + 10, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Row 1: Location Pill + actions
                          Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () async {
                                    await showAddressPickerSheet(context);
                                    if (mounted) {
                                      _locationDebounceTimer?.cancel();
                                      if (_selectedTabIndex < 0) {
                                        _loadAllData();
                                      } else {
                                        _loadData(_categories[_selectedTabIndex]
                                            ['name']! as String);
                                      }
                                    }
                                  },
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 7),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? const Color(0xFF1E1E2E)
                                            : const Color(0xFFF0F0F8),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: isDark
                                              ? Colors.white10
                                              : Colors.transparent,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (locationProvider
                                              .activeLabelIcon.isNotEmpty) ...[
                                            Text(
                                                locationProvider
                                                    .activeLabelIcon,
                                                style: const TextStyle(
                                                    fontSize: 14)),
                                            const SizedBox(width: 4),
                                            Text(
                                              locationProvider.activeLabel,
                                              style: GoogleFonts.outfit(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w900,
                                                color: isDark
                                                    ? Colors.white
                                                    : Colors.black,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Container(
                                              width: 4,
                                              height: 4,
                                              decoration: BoxDecoration(
                                                color: isDark
                                                    ? Colors.white30
                                                    : Colors.grey.shade400,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                          ] else ...[
                                            const Icon(
                                                Icons.location_on_rounded,
                                                size: 14,
                                                color: AppColors.primary),
                                            const SizedBox(width: 6),
                                          ],
                                          Flexible(
                                            child: Text(
                                              locationProvider.hasLocation
                                                  ? (locationProvider
                                                          .currentAddress
                                                          .isNotEmpty
                                                      ? locationProvider
                                                          .currentAddress
                                                      : 'Current Location')
                                                  : (locationProvider.isLoading
                                                      ? 'Locating... 📍'
                                                      : 'Set location...'),
                                              style: GoogleFonts.outfit(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w900,
                                                color: isDark
                                                    ? Colors.white
                                                    : Colors.black,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Icon(
                                              Icons.keyboard_arrow_down_rounded,
                                              size: 16,
                                              color: isDark
                                                  ? Colors.white38
                                                  : AppColors.textSecondary),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              NotificationBell(
                                iconColor: isDark
                                    ? Colors.white70
                                    : AppColors.textPrimary,
                                containerColor: isDark
                                    ? const Color(0xFF1E1E2E)
                                    : const Color(0xFFF0F0F8),
                              ),
                              const SizedBox(width: 8),
                              _buildCircleAction(
                                icon:
                                    isDark ? Icons.light_mode : Icons.dark_mode,
                                isDark: isDark,
                                onTap: () => themeProvider.toggleTheme(),
                              ),
                              const SizedBox(width: 8),
                              _buildCircleAction(
                                icon: Icons.person_outline,
                                isDark: isDark,
                                onTap: () {
                                  if (_isSettingsNavigating) return;
                                  _isSettingsNavigating = true;
                                  Navigator.pushNamed(
                                          context, AppRoutes.settings)
                                      .then(
                                          (_) => _isSettingsNavigating = false);
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(70),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Hero(
                    tag: 'search_bar',
                    child: Material(
                      color: Colors.transparent,
                      child: Row(
                        children: [
                          Expanded(
                            child: Stack(
                              alignment: Alignment.centerLeft,
                              children: [
                                TextField(
                                  controller: _searchController,
                                  onChanged: (v) {
                                    _searchDebounce?.cancel();
                                    if (v.trim().isEmpty) {
                                      _searchShops('');
                                    } else {
                                      setState(() {
                                        _searchQuery = v;
                                        _isSearching = true;
                                      });
                                      _searchDebounce = Timer(
                                        const Duration(milliseconds: 350),
                                        () => _searchShops(v),
                                      );
                                    }
                                  },
                                  decoration: InputDecoration(
                                    hintText: '',
                                    prefixIcon: const Icon(Icons.search,
                                        color: AppColors.primary),
                                    suffixIcon: _isSearching
                                        ? const Padding(
                                            padding: EdgeInsets.all(12),
                                            child: CupertinoActivityIndicator(
                                                radius: 9),
                                          )
                                        : _searchController.text.isNotEmpty
                                            ? IconButton(
                                                icon: const Icon(
                                                    Icons.close_rounded,
                                                    size: 18),
                                                onPressed: () {
                                                  _searchController.clear();
                                                  _searchShops('');
                                                },
                                              )
                                            : null,
                                    filled: true,
                                    fillColor: Theme.of(context)
                                            .inputDecorationTheme
                                            .fillColor ??
                                        Colors.grey.shade100,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide.none,
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide(
                                          color: isDark
                                              ? AppColors.primaryLight
                                              : AppColors.primary,
                                          width: 1.5),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 12),
                                  ),
                                ),
                                ValueListenableBuilder<TextEditingValue>(
                                  valueListenable: _searchController,
                                  builder: (context, value, _) {
                                    if (value.text.isNotEmpty) {
                                      return const SizedBox.shrink();
                                    }
                                    return Positioned(
                                      left: 44,
                                      right: 48,
                                      child: IgnorePointer(
                                        child: AnimatedSearchTicker(
                                          key: const ValueKey(
                                              'animated_search_ticker'),
                                          textStyle: GoogleFonts.outfit(
                                            color: isDark
                                                ? Colors.grey.shade400
                                                : Colors.grey.shade500,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => _showFilterSheet(context, isDark),
                            child: Container(
                              height: 48,
                              width: 48,
                              decoration: BoxDecoration(
                                color: _selectedFilterCategories.isNotEmpty
                                    ? AppColors.primary
                                    : (isDark
                                        ? const Color(0xFF1E1E2E)
                                        : Colors.grey.shade100),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.white10
                                      : Colors.transparent,
                                ),
                              ),
                              child: Icon(
                                Icons.tune_rounded,
                                color: _selectedFilterCategories.isNotEmpty
                                    ? Colors.white
                                    : (isDark
                                        ? Colors.white70
                                        : AppColors.textPrimary),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── Maintenance Mode Announcement Banner (Additive) ──────────────
            Builder(
              builder: (context) {
                final config = context.watch<PlatformConfigProvider>();
                if (!config.isMaintenanceMode) {
                  return const SliverToBoxAdapter(child: SizedBox.shrink());
                }
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isDark
                              ? [
                                  const Color(0xFF78350F),
                                  const Color(0xFF92400E)
                                ]
                              : [
                                  const Color(0xFFFEF3C7),
                                  const Color(0xFFFDE68A)
                                ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFFF59E0B)
                              .withValues(alpha: isDark ? 0.4 : 0.5),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('⚠️', style: TextStyle(fontSize: 20)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Ordering Temporarily Paused',
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? const Color(0xFFFDE68A)
                                        : const Color(0xFF92400E),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  config.maintenanceMessage,
                                  style: GoogleFonts.outfit(
                                    fontSize: 12,
                                    color: isDark
                                        ? const Color(0xFFFEF3C7)
                                        : const Color(0xFF78350F),
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

            // ── Trending Now Auto-Marquee Strip ──────────────────────────────────
            if (_searchQuery.isEmpty &&
                _selectedTabIndex < 0 &&
                _selectedFilterCategories.isEmpty)
              SliverToBoxAdapter(
                child: _buildTrendingStrip(isDark),
              ),

            // ── Search Filter Bar (visible during search only) ───────────
            if (_searchQuery.isNotEmpty)
              SliverToBoxAdapter(
                child: _buildSearchFilterBar(isDark),
              ),

            // ── Main Content ──────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: _isLoading
                  ? SliverToBoxAdapter(child: _buildShimmer())
                  : SliverMainAxisGroup(
                      slivers: [
                        // ──────────────────────────────────────────────────
                        // SEARCH MODE: clean results-only view
                        // ──────────────────────────────────────────────────
                        if (_searchQuery.isNotEmpty) ...[
                          const SliverToBoxAdapter(child: SizedBox(height: 4)),

                          // Header
                          SliverToBoxAdapter(
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _isSearching
                                            ? 'Searching...'
                                            : 'Search results',
                                        style: GoogleFonts.outfit(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                          color: isDark
                                              ? Colors.white
                                              : AppColors.textPrimary,
                                        ),
                                      ),
                                      if (!_isSearching)
                                        Text(
                                          '${_sortedShopResults.length + _sortedProductResults.length} result${(_sortedShopResults.length + _sortedProductResults.length) == 1 ? "" : "s"} for "$_searchQuery"',
                                          style: GoogleFonts.outfit(
                                              fontSize: 13,
                                              color: AppColors.textSecondary),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SliverToBoxAdapter(child: SizedBox(height: 16)),

                          // Contextual Multi-Coloured Event & Party Catering discovery when query matches party/event keywords
                          if (!_isSearching &&
                              !_searchError &&
                              _searchQuery.trim().isNotEmpty &&
                              RegExp(r'\b(party|event|cater|catering|wedding|birthday|bulk|gathering|feast)\b',
                                      caseSensitive: false)
                                  .hasMatch(_searchQuery)) ...[
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _buildBulkCateringCard(isDark),
                              ),
                            ),
                          ],

                          // Skeleton while loading
                          if (_isSearching)
                            SliverToBoxAdapter(
                                child: Column(
                                    children: List.generate(3,
                                        (_) => _buildSearchSkeleton(isDark))))

                          // Error state
                          else if (_searchError)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 60),
                                child: Center(
                                  child: Column(
                                    children: [
                                      Container(
                                        width: 80,
                                        height: 80,
                                        decoration: BoxDecoration(
                                          color: AppColors.danger
                                              .withValues(alpha: 0.1),
                                          borderRadius:
                                              BorderRadius.circular(24),
                                        ),
                                        child: const Center(
                                          child: Icon(Icons.wifi_off_rounded,
                                              size: 36,
                                              color: AppColors.danger),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Text('Search Failed',
                                          style: GoogleFonts.outfit(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w800,
                                              color: isDark
                                                  ? Colors.white
                                                  : AppColors.textPrimary)),
                                      const SizedBox(height: 8),
                                      Text(
                                          _searchErrorMessage.isNotEmpty
                                              ? _searchErrorMessage
                                              : 'Please check your internet connection',
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.outfit(
                                              fontSize: 13,
                                              color: AppColors.textSecondary)),
                                      const SizedBox(height: 24),
                                      ElevatedButton.icon(
                                        onPressed: () =>
                                            _searchShops(_searchQuery),
                                        icon: const Icon(Icons.refresh_rounded,
                                            color: Colors.white, size: 20),
                                        label: Text('Retry Search',
                                            style: GoogleFonts.outfit(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.primary,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 24, vertical: 12),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )

                          // Empty state
                          else if (_searchResults.isEmpty &&
                              _searchProductResults.isEmpty)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 60),
                                child: Center(
                                  child: Column(
                                    children: [
                                      Container(
                                        width: 80,
                                        height: 80,
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? AppColors.primary
                                                  .withValues(alpha: 0.15)
                                              : AppColors.primary
                                                  .withValues(alpha: 0.08),
                                          borderRadius:
                                              BorderRadius.circular(24),
                                        ),
                                        child: Center(
                                          child: Icon(
                                            Icons.search_off_rounded,
                                            size: 36,
                                            color: isDark
                                                ? AppColors.primaryLight
                                                : AppColors.primary,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Text('No results for',
                                          style: GoogleFonts.outfit(
                                              fontSize: 15,
                                              color: AppColors.textSecondary)),
                                      const SizedBox(height: 4),
                                      Text('"$_searchQuery"',
                                          style: GoogleFonts.outfit(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w800,
                                              color: isDark
                                                  ? Colors.white
                                                  : AppColors.textPrimary)),
                                      const SizedBox(height: 8),
                                      Text('Try a different keyword',
                                          style: GoogleFonts.outfit(
                                              fontSize: 13,
                                              color: AppColors.textLight)),
                                    ],
                                  ),
                                ),
                              ),
                            )

                          // Empty state when dietary filter produces zero matches
                          else if (_sortedProductResults.isEmpty &&
                              _sortedShopResults.isEmpty)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 48, horizontal: 24),
                                child: Center(
                                  child: Column(
                                    children: [
                                      Container(
                                        width: 72,
                                        height: 72,
                                        decoration: BoxDecoration(
                                          color: (_vegFilterMode ==
                                                      VegFilterMode.vegOnly
                                                  ? const Color(0xFF2E7D32)
                                                  : const Color(0xFFC62828))
                                              .withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(22),
                                        ),
                                        child: Center(
                                          child: Text(
                                            _vegFilterMode ==
                                                    VegFilterMode.vegOnly
                                                ? '🥦'
                                                : '🍗',
                                            style:
                                                const TextStyle(fontSize: 32),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        _vegFilterMode == VegFilterMode.vegOnly
                                            ? 'No Pure Veg items found'
                                            : 'No Non-Veg items found',
                                        style: GoogleFonts.outfit(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                          color: isDark
                                              ? Colors.white
                                              : AppColors.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'No matches for "$_searchQuery" under this filter.\nTry switching to All or resetting your dietary preference.',
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.outfit(
                                          fontSize: 13,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 18),
                                      OutlinedButton.icon(
                                        onPressed: () {
                                          HapticFeedback.lightImpact();
                                          setState(() => _vegFilterMode =
                                              VegFilterMode.all);
                                        },
                                        icon: const Icon(Icons.refresh_rounded,
                                            size: 16),
                                        label: Text(
                                          'Show All (${_searchProductResults.length + _searchResults.length})',
                                          style: GoogleFonts.outfit(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13),
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: AppColors.primary,
                                          side: const BorderSide(
                                              color: AppColors.primary),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(20)),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 20, vertical: 10),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )

                          // Results
                          else ...[
                            // Products first (most relevant for the user)
                            if (_sortedProductResults.isNotEmpty) ...[
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Row(
                                    children: [
                                      Container(
                                          width: 4,
                                          height: 18,
                                          decoration: BoxDecoration(
                                              color: AppColors.primary,
                                              borderRadius:
                                                  BorderRadius.circular(2))),
                                      const SizedBox(width: 8),
                                      Text('Items & Products',
                                          style: GoogleFonts.outfit(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                              color: isDark
                                                  ? Colors.white
                                                  : AppColors.textPrimary)),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                            color: AppColors.primary
                                                .withValues(alpha: 0.1),
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                        child: Text(
                                            '${_sortedProductResults.length}',
                                            style: GoogleFonts.outfit(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.primary)),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              SliverList.builder(
                                itemCount: _sortedProductResults.length,
                                itemBuilder: (context, index) {
                                  final product = _sortedProductResults[index];
                                  final shop = _searchProductShops[product.id];
                                  if (shop == null) {
                                    return const SizedBox.shrink();
                                  }
                                  return RepaintBoundary(
                                    key: ValueKey('search_p_${product.id}'),
                                    child: ProductSearchCard(
                                        product: product, shop: shop),
                                  );
                                },
                              ),
                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 16)),
                            ],

                            // ── Under "See more": The Restaurant Itself! ──────────────
                            if (_sortedShopResults.isNotEmpty) ...[
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding:
                                      const EdgeInsets.only(bottom: 12, top: 4),
                                  child: Row(
                                    children: [
                                      Container(
                                          width: 4,
                                          height: 18,
                                          decoration: BoxDecoration(
                                              color: AppColors.secondary,
                                              borderRadius:
                                                  BorderRadius.circular(2))),
                                      const SizedBox(width: 8),
                                      Text(
                                          AppCategories.groupFor(
                                                      _sortedShopResults
                                                          .first.category) ==
                                                  CategoryGroup.food
                                              ? 'Restaurant'
                                              : 'Shop & Store',
                                          style: GoogleFonts.outfit(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                              color: isDark
                                                  ? Colors.white
                                                  : AppColors.textPrimary)),
                                    ],
                                  ),
                                ),
                              ),
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: SizedBox(
                                    height: 280,
                                    child: RepaintBoundary(
                                      key: ValueKey(
                                          'search_top_shop_${_sortedShopResults.first.id}'),
                                      child: AppCategories.groupFor(
                                                  _sortedShopResults
                                                      .first.category) ==
                                              CategoryGroup.food
                                          ? RestaurantShopCard(
                                              shop: _sortedShopResults.first,
                                              onTap: () =>
                                                  showRestaurantDashboardSheet(
                                                      context,
                                                      _sortedShopResults
                                                          .first.id))
                                          : ShopCard(
                                              shop: _sortedShopResults.first,
                                              onTap: () => showShopDetailSheet(
                                                  context,
                                                  _sortedShopResults.first.id)),
                                    ),
                                  ),
                                ),
                              ),
                            ],

                            // ── Other Nearby Places (if any) ─────────────────────────
                            if (_sortedShopResults.length > 1) ...[
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding:
                                      const EdgeInsets.only(bottom: 12, top: 4),
                                  child: Row(
                                    children: [
                                      Container(
                                          width: 4,
                                          height: 18,
                                          decoration: BoxDecoration(
                                              color: AppColors.secondary,
                                              borderRadius:
                                                  BorderRadius.circular(2))),
                                      const SizedBox(width: 8),
                                      Text('Other Places Near You',
                                          style: GoogleFonts.outfit(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                              color: isDark
                                                  ? Colors.white
                                                  : AppColors.textPrimary)),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                            color: AppColors.secondary
                                                .withValues(alpha: 0.1),
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                        child: Text(
                                            '${_sortedShopResults.length - 1}',
                                            style: GoogleFonts.outfit(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.secondary)),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              SliverList.builder(
                                itemCount: math.min(
                                  _sortedShopResults.length - 1,
                                  _searchShopsDisplayLimit,
                                ),
                                itemBuilder: (context, index) {
                                  final shop = _sortedShopResults[index + 1];
                                  final isFood =
                                      AppCategories.groupFor(shop.category) ==
                                          CategoryGroup.food;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: SizedBox(
                                      height: 280,
                                      child: RepaintBoundary(
                                        key: ValueKey('search_s_${shop.id}'),
                                        child: isFood
                                            ? RestaurantShopCard(
                                                shop: shop,
                                                onTap: () =>
                                                    showRestaurantDashboardSheet(
                                                        context, shop.id))
                                            : ShopCard(
                                                shop: shop,
                                                onTap: () =>
                                                    showShopDetailSheet(
                                                        context, shop.id)),
                                      ),
                                    ),
                                  );
                                },
                              ),
                              if (_sortedShopResults.length - 1 >
                                  _searchShopsDisplayLimit)
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                        top: 8, bottom: 8),
                                    child: Center(
                                      child: TextButton(
                                        onPressed: () => setState(() =>
                                            _searchShopsDisplayLimit += 10),
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 24, vertical: 12),
                                          backgroundColor: isDark
                                              ? Colors.white
                                                  .withValues(alpha: 0.05)
                                              : AppColors.secondary
                                                  .withValues(alpha: 0.05),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(20)),
                                        ),
                                        child: Text(
                                          'Load more stores',
                                          style: GoogleFonts.outfit(
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.secondary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ],

                          // Precise Industrial-Standard Bottom Nav Clearance:
                          // Ensures search results stop with a clean 12dp margin above the floating bottom navigation bar
                          SliverToBoxAdapter(
                            child: SizedBox(
                              height: _getFloatingBottomNavClearance(context),
                            ),
                          ),

                          // ──────────────────────────────────────────────────
                          // NORMAL MODE: banner + shops + products
                          // ──────────────────────────────────────────────────
                        ] else ...[
                          // Active Catering Quote Banner (always shown at top if customer has an active quote)
                          SliverToBoxAdapter(
                            child: _buildActiveQuoteBanner(isDark),
                          ),
                          if (_selectedTabIndex < 0 &&
                              _selectedFilterCategories.isEmpty) ...[
                            // Featured Banner
                            SliverToBoxAdapter(child: _buildFeaturedBanner()),
                            const SliverToBoxAdapter(
                                child: SizedBox(height: 24)),
                          ],

                          // ── Explore Categories ─────────────────────────────────
                          // Shown FIRST so users can orient themselves immediately.
                          // Always visible when no search + no filter chip active.
                          if (_searchQuery.isEmpty &&
                              _selectedFilterCategories.isEmpty) ...[
                            SliverToBoxAdapter(
                              child: _buildCategorySection(isDark),
                            ),
                            // ── Host an Event or Party? ──
                            // Positioned directly after Explore Categories
                            SliverToBoxAdapter(
                              child: _buildBulkCateringCard(isDark),
                            ),
                          ],

                          // ── Recently Viewed ─────────────────────────────
                          if (_selectedTabIndex < 0 &&
                              _selectedFilterCategories.isEmpty)
                            SliverToBoxAdapter(
                              child: Builder(builder: (ctx) {
                                final recentProv =
                                    ctx.watch<RecentlyViewedProvider>();
                                if (!recentProv.hasItems) {
                                  return const SizedBox.shrink();
                                }

                                // Filter out products whose shop is closed
                                final availableRecent =
                                    recentProv.products.where((p) {
                                  final shop = _productShops[p.id];
                                  return shop != null && shop.isActive;
                                }).toList();

                                if (availableRecent.isEmpty) {
                                  return const SizedBox.shrink();
                                }

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildSectionTitle(
                                      'Recently Viewed',
                                      subtitle: 'Continue where you left off',
                                      isLoading: recentProv.isLoading,
                                      onSeeAllTap: (recentProv.products.length <
                                              recentProv.totalIdsCount)
                                          ? () => recentProv.loadAll()
                                          : null,
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      height: 245,
                                      child: ListView.builder(
                                        scrollDirection: Axis.horizontal,
                                        physics: const BouncingScrollPhysics(),
                                        itemCount: availableRecent.length,
                                        itemBuilder: (_, index) {
                                          final p = availableRecent[index];
                                          final shop = _productShops[p.id];
                                          return SizedBox(
                                            width: 146,
                                            child: Padding(
                                              padding: const EdgeInsets.only(
                                                  right: 10),
                                              child: ProductCard(
                                                product: p,
                                                shop: shop,
                                                imageAspectRatio: 1.12,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                  ],
                                );
                              }),
                            ),

                          // ── Dedicated Department Category Showcases (Primary) ──
                          // Hierarchy: Food → Bakery → Dairy → Fruits/Vegs → Meat/Fish → Medicines → Cosmetics → Salon → Clothing → Electronics → Hardware → Stationery → Supermarket
                          if (_selectedTabIndex < 0) ...[
                            // 1. Food & Restaurants (Bakery-free Showcase)
                            if (_sortedFoodProducts.isNotEmpty) ...[
                              Builder(builder: (ctx) {
                                final recentProv =
                                    ctx.watch<RecentlyViewedProvider>();
                                final hasRecent = recentProv.hasItems &&
                                    recentProv.products.any((p) {
                                      final shop = _productShops[p.id];
                                      return shop != null && shop.isActive;
                                    });
                                // Symmetrical Vertical Spacing Fortress:
                                // If Recently Viewed is shown, it already provides its own 24dp bottom spacer.
                                // If Recently Viewed is empty, add 8dp to pair with the card's 12dp bottom margin
                                // to yield an exact 20dp gap below, perfectly mirroring the 20dp gap above!
                                return SliverToBoxAdapter(
                                  child: SizedBox(height: hasRecent ? 0 : 8),
                                );
                              }),
                              SliverToBoxAdapter(
                                child: _buildDepartmentSectionHeader(
                                  title: 'Food & Restaurants',
                                  subtitle:
                                      'Fresh meals, snacks & cuisines delivered hot',
                                  emoji: '🍔',
                                  count: math.max(
                                      _departmentProductCounts['Food'] ?? 0,
                                      _sortedFoodProducts.length),
                                  accentGradient: const [
                                    Color(0xFFFF6B6B),
                                    Color(0xFFEE5A24),
                                  ],
                                  onSeeAllTap: () => _openCategoryListing(
                                    title: 'Food & Restaurants',
                                    products: _sortedFoodProducts,
                                    categories: _tabCategories['Food'] ?? [],
                                  ),
                                  isDark: isDark,
                                ),
                              ),
                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 14)),
                              SliverToBoxAdapter(
                                child: _buildCategoryHorizontalCarousel(
                                  products: _sortedFoodProducts,
                                  sectionTitle: 'Food',
                                  onViewAllTap: () => _openCategoryListing(
                                    title: 'Food & Restaurants',
                                    products: _sortedFoodProducts,
                                    categories: _tabCategories['Food'] ?? [],
                                  ),
                                  isDark: isDark,
                                ),
                              ),
                            ],

                            // 2. Bakery, Sweets & Mithai (Dedicated Showcase)
                            if (_sortedBakeryProducts.isNotEmpty) ...[
                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 24)),
                              SliverToBoxAdapter(
                                child: _buildDepartmentSectionHeader(
                                  title: 'Bakery, Sweets & Mithai',
                                  subtitle:
                                      'Fresh bread, artisan cakes, cookies & traditional mithai',
                                  emoji: '🥖',
                                  count: math.max(
                                      _departmentProductCounts[
                                              'BakeryAndSweets'] ??
                                          0,
                                      _sortedBakeryProducts.length),
                                  accentGradient: const [
                                    Color(0xFFF59E0B),
                                    Color(0xFFD97706),
                                  ],
                                  onSeeAllTap: () => _openCategoryListing(
                                    title: 'Bakery, Sweets & Mithai',
                                    products: _sortedBakeryProducts,
                                    categories:
                                        _tabCategories['BakeryAndSweets'] ?? [],
                                  ),
                                  isDark: isDark,
                                ),
                              ),
                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 14)),
                              SliverToBoxAdapter(
                                child: _buildCategoryHorizontalCarousel(
                                  products: _sortedBakeryProducts,
                                  sectionTitle: 'Bakery & Sweets',
                                  onViewAllTap: () => _openCategoryListing(
                                    title: 'Bakery, Sweets & Mithai',
                                    products: _sortedBakeryProducts,
                                    categories:
                                        _tabCategories['BakeryAndSweets'] ?? [],
                                  ),
                                  isDark: isDark,
                                ),
                              ),
                            ],

                            // 3. Fresh Milk, Butter, Cheese & Eggs
                            if (_sortedDairyProducts.isNotEmpty) ...[
                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 24)),
                              SliverToBoxAdapter(
                                child: _buildDepartmentSectionHeader(
                                  title: 'Fresh Milk, Butter, Cheese & Eggs',
                                  subtitle:
                                      'Farm-fresh milk, butter, artisanal cheese & eggs',
                                  emoji: '🥛',
                                  count: math.max(
                                      _departmentProductCounts[
                                              'DairyAndEggs'] ??
                                          0,
                                      _sortedDairyProducts.length),
                                  accentGradient: const [
                                    Color(0xFF0288D1),
                                    Color(0xFF26C6DA),
                                  ],
                                  onSeeAllTap: () => _openCategoryListing(
                                    title: 'Fresh Milk, Butter, Cheese & Eggs',
                                    products: _sortedDairyProducts,
                                    categories:
                                        _tabCategories['DairyAndEggs'] ?? [],
                                  ),
                                  isDark: isDark,
                                ),
                              ),
                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 14)),
                              SliverToBoxAdapter(
                                child: _buildCategoryHorizontalCarousel(
                                  products: _sortedDairyProducts,
                                  sectionTitle: 'Dairy & Eggs',
                                  onViewAllTap: () => _openCategoryListing(
                                    title: 'Fresh Milk, Butter, Cheese & Eggs',
                                    products: _sortedDairyProducts,
                                    categories:
                                        _tabCategories['DairyAndEggs'] ?? [],
                                  ),
                                  isDark: isDark,
                                ),
                              ),
                            ],

                            // 4. Fruits, Vegs & Organic
                            if (_sortedFruitsVegsProducts.isNotEmpty) ...[
                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 24)),
                              SliverToBoxAdapter(
                                child: _buildDepartmentSectionHeader(
                                  title: 'Fruits, Vegs & Organic',
                                  subtitle:
                                      'Farm fresh fruits, crisp vegetables & certified organic',
                                  emoji: '🥬',
                                  count: math.max(
                                      _departmentProductCounts[
                                              'FruitsVegsOrganic'] ??
                                          0,
                                      _sortedFruitsVegsProducts.length),
                                  accentGradient: const [
                                    Color(0xFF10B981),
                                    Color(0xFF059669),
                                  ],
                                  onSeeAllTap: () => _openCategoryListing(
                                    title: 'Fruits, Vegs & Organic',
                                    products: _sortedFruitsVegsProducts,
                                    categories:
                                        _tabCategories['FruitsVegsOrganic'] ??
                                            [],
                                  ),
                                  isDark: isDark,
                                ),
                              ),
                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 14)),
                              SliverToBoxAdapter(
                                child: _buildCategoryHorizontalCarousel(
                                  products: _sortedFruitsVegsProducts,
                                  sectionTitle: 'Fruits & Vegs',
                                  onViewAllTap: () => _openCategoryListing(
                                    title: 'Fruits, Vegs & Organic',
                                    products: _sortedFruitsVegsProducts,
                                    categories:
                                        _tabCategories['FruitsVegsOrganic'] ??
                                            [],
                                  ),
                                  isDark: isDark,
                                ),
                              ),
                            ],

                            // 5. Fish, Mutton & Meat
                            if (_sortedMeatAndFishProducts.isNotEmpty) ...[
                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 24)),
                              SliverToBoxAdapter(
                                child: _buildDepartmentSectionHeader(
                                  title: 'Fish, Mutton & Meat',
                                  subtitle:
                                      'Fresh cut chicken, mutton, fish & seafood',
                                  emoji: '🥩',
                                  count: math.max(
                                      _departmentProductCounts['MeatAndFish'] ??
                                          0,
                                      _sortedMeatAndFishProducts.length),
                                  accentGradient: const [
                                    Color(0xFFE53935),
                                    Color(0xFFD32F2F),
                                  ],
                                  onSeeAllTap: () => _openCategoryListing(
                                    title: 'Fish, Mutton & Meat',
                                    products: _sortedMeatAndFishProducts,
                                    categories:
                                        _tabCategories['MeatAndFish'] ?? [],
                                  ),
                                  isDark: isDark,
                                ),
                              ),
                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 14)),
                              SliverToBoxAdapter(
                                child: _buildCategoryHorizontalCarousel(
                                  products: _sortedMeatAndFishProducts,
                                  sectionTitle: 'Meat & Fish',
                                  onViewAllTap: () => _openCategoryListing(
                                    title: 'Fish, Mutton & Meat',
                                    products: _sortedMeatAndFishProducts,
                                    categories:
                                        _tabCategories['MeatAndFish'] ?? [],
                                  ),
                                  isDark: isDark,
                                ),
                              ),
                            ],

                            // 6. Medicines & Healthcare
                            if (_sortedPharmacyProducts.isNotEmpty) ...[
                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 24)),
                              SliverToBoxAdapter(
                                child: _buildDepartmentSectionHeader(
                                  title: 'Medicines & Healthcare',
                                  subtitle:
                                      'Prescription drugs, vitamins & wellness',
                                  emoji: '💊',
                                  count: math.max(
                                      _departmentProductCounts['Pharmacy'] ?? 0,
                                      _sortedPharmacyProducts.length),
                                  accentGradient: const [
                                    Color(0xFF0284C7),
                                    Color(0xFF06B6D4),
                                  ],
                                  onSeeAllTap: () => _openCategoryListing(
                                    title: 'Medicines & Healthcare',
                                    products: _sortedPharmacyProducts,
                                    categories:
                                        _tabCategories['Pharmacy'] ?? [],
                                  ),
                                  isDark: isDark,
                                ),
                              ),
                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 14)),
                              SliverToBoxAdapter(
                                child: _buildCategoryHorizontalCarousel(
                                  products: _sortedPharmacyProducts,
                                  sectionTitle: 'Medicines',
                                  onViewAllTap: () => _openCategoryListing(
                                    title: 'Medicines & Healthcare',
                                    products: _sortedPharmacyProducts,
                                    categories:
                                        _tabCategories['Pharmacy'] ?? [],
                                  ),
                                  isDark: isDark,
                                ),
                              ),
                            ],

                            // 7. Cosmetics & Beauty
                            if (_sortedCosmeticsProducts.isNotEmpty) ...[
                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 24)),
                              SliverToBoxAdapter(
                                child: _buildDepartmentSectionHeader(
                                  title: 'Cosmetics & Beauty',
                                  subtitle:
                                      'Skincare, makeup & fragrances near you',
                                  emoji: '💄',
                                  count: math.max(
                                      _departmentProductCounts['Cosmetics'] ??
                                          0,
                                      _sortedCosmeticsProducts.length),
                                  accentGradient: const [
                                    Color(0xFFE91E8C),
                                    Color(0xFFFF6FB5),
                                  ],
                                  onSeeAllTap: () => _openCategoryListing(
                                    title: 'Cosmetics & Beauty',
                                    products: _sortedCosmeticsProducts,
                                    categories:
                                        _tabCategories['Cosmetics'] ?? [],
                                  ),
                                  isDark: isDark,
                                ),
                              ),
                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 14)),
                              SliverToBoxAdapter(
                                child: _buildCategoryHorizontalCarousel(
                                  products: _sortedCosmeticsProducts,
                                  sectionTitle: 'Beauty',
                                  onViewAllTap: () => _openCategoryListing(
                                    title: 'Cosmetics & Beauty',
                                    products: _sortedCosmeticsProducts,
                                    categories:
                                        _tabCategories['Cosmetics'] ?? [],
                                  ),
                                  isDark: isDark,
                                ),
                              ),
                            ],

                            // 8. Salon & Beauty
                            if (_sortedSalonProducts.isNotEmpty) ...[
                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 24)),
                              SliverToBoxAdapter(
                                child: _buildDepartmentSectionHeader(
                                  title: 'Salon & Beauty',
                                  subtitle:
                                      'Haircare, styling, grooming & professional salon essentials',
                                  emoji: '💇',
                                  count: math.max(
                                      _departmentProductCounts[
                                              'SalonAndBeauty'] ??
                                          0,
                                      _sortedSalonProducts.length),
                                  accentGradient: const [
                                    Color(0xFFD946EF),
                                    Color(0xFFA855F7),
                                  ],
                                  onSeeAllTap: () => _openCategoryListing(
                                    title: 'Salon & Beauty',
                                    products: _sortedSalonProducts,
                                    categories:
                                        _tabCategories['SalonAndBeauty'] ?? [],
                                  ),
                                  isDark: isDark,
                                ),
                              ),
                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 14)),
                              SliverToBoxAdapter(
                                child: _buildCategoryHorizontalCarousel(
                                  products: _sortedSalonProducts,
                                  sectionTitle: 'Salon & Beauty',
                                  onViewAllTap: () => _openCategoryListing(
                                    title: 'Salon & Beauty',
                                    products: _sortedSalonProducts,
                                    categories:
                                        _tabCategories['SalonAndBeauty'] ?? [],
                                  ),
                                  isDark: isDark,
                                ),
                              ),
                            ],

                            // 9. Clothing & Footwear
                            if (_sortedClothingProducts.isNotEmpty) ...[
                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 24)),
                              SliverToBoxAdapter(
                                child: _buildDepartmentSectionHeader(
                                  title: 'Clothing & Footwear',
                                  subtitle:
                                      'Trending styles, apparel, footwear & accessories',
                                  emoji: '👕',
                                  count: math.max(
                                      _departmentProductCounts['Clothing'] ?? 0,
                                      _sortedClothingProducts.length),
                                  accentGradient: const [
                                    Color(0xFF8B5CF6),
                                    Color(0xFFEC4899),
                                  ],
                                  onSeeAllTap: () => _openCategoryListing(
                                    title: 'Clothing & Footwear',
                                    products: _sortedClothingProducts,
                                    categories:
                                        _tabCategories['Clothing'] ?? [],
                                  ),
                                  isDark: isDark,
                                ),
                              ),
                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 14)),
                              SliverToBoxAdapter(
                                child: _buildCategoryHorizontalCarousel(
                                  products: _sortedClothingProducts,
                                  sectionTitle: 'Fashion',
                                  onViewAllTap: () => _openCategoryListing(
                                    title: 'Clothing & Footwear',
                                    products: _sortedClothingProducts,
                                    categories:
                                        _tabCategories['Clothing'] ?? [],
                                  ),
                                  isDark: isDark,
                                ),
                              ),
                            ],

                            // 10. Electronics & Gadgets
                            if (_sortedElectronicsProducts.isNotEmpty) ...[
                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 24)),
                              SliverToBoxAdapter(
                                child: _buildDepartmentSectionHeader(
                                  title: 'Electronics & Gadgets',
                                  subtitle:
                                      'Smartphones, audio, smart gadgets & accessories',
                                  emoji: '📱',
                                  count: math.max(
                                      _departmentProductCounts['Electronics'] ??
                                          0,
                                      _sortedElectronicsProducts.length),
                                  accentGradient: const [
                                    Color(0xFF3B82F6),
                                    Color(0xFF1D4ED8),
                                  ],
                                  onSeeAllTap: () => _openCategoryListing(
                                    title: 'Electronics & Gadgets',
                                    products: _sortedElectronicsProducts,
                                    categories:
                                        _tabCategories['Electronics'] ?? [],
                                  ),
                                  isDark: isDark,
                                ),
                              ),
                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 14)),
                              SliverToBoxAdapter(
                                child: _buildCategoryHorizontalCarousel(
                                  products: _sortedElectronicsProducts,
                                  sectionTitle: 'Electronics',
                                  onViewAllTap: () => _openCategoryListing(
                                    title: 'Electronics & Gadgets',
                                    products: _sortedElectronicsProducts,
                                    categories:
                                        _tabCategories['Electronics'] ?? [],
                                  ),
                                  isDark: isDark,
                                ),
                              ),
                            ],

                            // 11. Hardware & Tools
                            if (_sortedHardwareProducts.isNotEmpty) ...[
                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 24)),
                              SliverToBoxAdapter(
                                child: _buildDepartmentSectionHeader(
                                  title: 'Hardware & Tools',
                                  subtitle:
                                      'Tools, fixtures, electrical & home repair essentials',
                                  emoji: '🔨',
                                  count: math.max(
                                      _departmentProductCounts['Hardware'] ?? 0,
                                      _sortedHardwareProducts.length),
                                  accentGradient: const [
                                    Color(0xFFF97316),
                                    Color(0xFFEA580C),
                                  ],
                                  onSeeAllTap: () => _openCategoryListing(
                                    title: 'Hardware & Tools',
                                    products: _sortedHardwareProducts,
                                    categories:
                                        _tabCategories['Hardware'] ?? [],
                                  ),
                                  isDark: isDark,
                                ),
                              ),
                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 14)),
                              SliverToBoxAdapter(
                                child: _buildCategoryHorizontalCarousel(
                                  products: _sortedHardwareProducts,
                                  sectionTitle: 'Hardware',
                                  onViewAllTap: () => _openCategoryListing(
                                    title: 'Hardware & Tools',
                                    products: _sortedHardwareProducts,
                                    categories:
                                        _tabCategories['Hardware'] ?? [],
                                  ),
                                  isDark: isDark,
                                ),
                              ),
                            ],

                            // 12. Stationery & Office Supplies
                            if (_sortedStationeryProducts.isNotEmpty) ...[
                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 24)),
                              SliverToBoxAdapter(
                                child: _buildDepartmentSectionHeader(
                                  title: 'Stationery & Office Supplies',
                                  subtitle:
                                      'Books, pens, art & school essentials',
                                  emoji: '📚',
                                  count: math.max(
                                      _departmentProductCounts['Stationery'] ??
                                          0,
                                      _sortedStationeryProducts.length),
                                  accentGradient: const [
                                    Color(0xFF5B86E5),
                                    Color(0xFF36D1DC),
                                  ],
                                  onSeeAllTap: () => _openCategoryListing(
                                    title: 'Stationery & Office Supplies',
                                    products: _sortedStationeryProducts,
                                    categories:
                                        _tabCategories['Stationery'] ?? [],
                                  ),
                                  isDark: isDark,
                                ),
                              ),
                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 14)),
                              SliverToBoxAdapter(
                                child: _buildCategoryHorizontalCarousel(
                                  products: _sortedStationeryProducts,
                                  sectionTitle: 'Stationery',
                                  onViewAllTap: () => _openCategoryListing(
                                    title: 'Stationery & Office Supplies',
                                    products: _sortedStationeryProducts,
                                    categories:
                                        _tabCategories['Stationery'] ?? [],
                                  ),
                                  isDark: isDark,
                                ),
                              ),
                            ],

                            // 13. Supermarket, Hypermarket & Grocery
                            if (_sortedSupermarketProducts.isNotEmpty) ...[
                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 24)),
                              SliverToBoxAdapter(
                                child: _buildDepartmentSectionHeader(
                                  title: 'Supermarket & Grocery',
                                  subtitle:
                                      'Daily staples, fresh veggies & household needs',
                                  emoji: '🏬',
                                  count: math.max(
                                      _departmentProductCounts['Grocery'] ?? 0,
                                      _sortedSupermarketProducts.length),
                                  accentGradient: const [
                                    Color(0xFF00B074),
                                    Color(0xFF10B981),
                                  ],
                                  onSeeAllTap: () => _openCategoryListing(
                                    title: 'Supermarket & Grocery',
                                    products: _sortedSupermarketProducts,
                                    categories: _tabCategories['Supermarket'] ??
                                        _tabCategories['Grocery'] ??
                                        [],
                                  ),
                                  isDark: isDark,
                                ),
                              ),
                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 14)),
                              SliverToBoxAdapter(
                                child: _buildCategoryHorizontalCarousel(
                                  products: _sortedSupermarketProducts,
                                  sectionTitle: 'Grocery',
                                  onViewAllTap: () => _openCategoryListing(
                                    title: 'Supermarket & Grocery',
                                    products: _sortedSupermarketProducts,
                                    categories: _tabCategories['Supermarket'] ??
                                        _tabCategories['Grocery'] ??
                                        [],
                                  ),
                                  isDark: isDark,
                                ),
                              ),
                            ],
                          ],

                          // ── Products Section / Popular in your area ─────────────────
                          // Positioned directly under Supermarket & Grocery
                          if (_products.isNotEmpty) ...[
                            const SliverToBoxAdapter(
                                child: SizedBox(height: 8)),
                            if ((_selectedTabIndex >= 0 &&
                                    _categories.isNotEmpty &&
                                    _selectedTabIndex < _categories.length &&
                                    _categories[_selectedTabIndex]['name'] ==
                                        'Clothing') ||
                                _selectedFeedDemographic != 'All') ...[
                              SliverToBoxAdapter(
                                child: _buildFeedDemographicSelector(isDark),
                              ),
                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 8)),
                            ],
                            SliverToBoxAdapter(
                              child: _buildSectionTitle(
                                productMeta.sectionTitle,
                              ),
                            ),
                            const SliverToBoxAdapter(
                                child: SizedBox(height: 16)),
                            if (_sortedNormalProducts.isEmpty)
                              SliverToBoxAdapter(
                                child: _buildDemographicEmptyState(isDark),
                              )
                            else
                              SliverLayoutBuilder(
                                builder: (context, constraints) {
                                  final crossAxisCount =
                                      Responsive.getGridCrossAxisCount(context,
                                          mobile: 2, tablet: 4, desktop: 5);
                                  const crossAxisSpacing = 16.0;
                                  final availableWidth =
                                      constraints.crossAxisExtent;
                                  final itemWidth = (availableWidth -
                                          (crossAxisSpacing *
                                              (crossAxisCount - 1))) /
                                      crossAxisCount;
                                  final itemHeight = itemWidth + 134;
                                  final childAspectRatio =
                                      itemWidth / itemHeight;
                                  final targetGridCount = crossAxisCount == 2
                                      ? 6
                                      : (crossAxisCount * 2);
                                  final effectiveLimit = math.max(
                                      _productsDisplayLimit, targetGridCount);
                                  final displayProducts = _sortedNormalProducts
                                      .take(effectiveLimit)
                                      .toList();

                                  return SliverGrid.builder(
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: crossAxisCount,
                                      childAspectRatio: childAspectRatio,
                                      mainAxisSpacing: 16,
                                      crossAxisSpacing: crossAxisSpacing,
                                    ),
                                    itemCount: displayProducts.length,
                                    itemBuilder: (context, index) {
                                      final product = displayProducts[index];
                                      final shop = _productShops[product.id];
                                      return RepaintBoundary(
                                        key: ValueKey('home_p_${product.id}'),
                                        child: ProductCard(
                                            product: product, shop: shop),
                                      );
                                    },
                                  );
                                },
                              ),
                            if (_sortedNormalProducts.isNotEmpty) ...[
                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 8)),
                              SliverToBoxAdapter(
                                child: _buildModernSeeAllButton(
                                  context,
                                  label: productMeta.buttonLabel,
                                  onTap: () => Navigator.pushNamed(
                                    context,
                                    AppRoutes.allListings,
                                    arguments: {
                                      'type': ListingType.products,
                                      'products': List<ProductModel>.from(
                                          _sortedNormalProducts),
                                      'productShops':
                                          Map<String, ShopModel>.from(
                                              _productShops),
                                      'shops': List<ShopModel>.from(_shops),
                                      'categoryFilter':
                                          productMeta.categoryFilter,
                                      'sectionTitle': productMeta.sectionTitle,
                                    },
                                  ),
                                  isDark: isDark,
                                ),
                              ),
                            ],
                          ],

                          // ── Stores Near You (At the very end of homepage) ─────────
                          if (_shops.isNotEmpty) ...[
                            const SliverToBoxAdapter(
                                child: SizedBox(height: 24)),
                            SliverToBoxAdapter(
                              child: _buildSectionTitle(
                                storeMeta.sectionTitle,
                                subtitle:
                                    '${_shops.length} within ${DeliveryCalculator.maxRadiusKm.toInt()} km',
                                count: _shops.length,
                              ),
                            ),
                            const SliverToBoxAdapter(
                                child: SizedBox(height: 16)),
                            SliverLayoutBuilder(
                              builder: (context, constraints) {
                                final crossAxisCount =
                                    Responsive.getGridCrossAxisCount(context,
                                        mobile: 1, tablet: 2, desktop: 3);
                                List<ShopModel> displayShops;
                                if (_selectedTabIndex < 0) {
                                  displayShops =
                                      _getTop4DiverseShops(_sortedNormalShops);
                                } else {
                                  displayShops = _sortedNormalShops
                                      .take(_shopsDisplayLimit)
                                      .toList();
                                }
                                return SliverGrid.builder(
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: crossAxisCount,
                                    mainAxisExtent:
                                        280, // Fixed extent for the card
                                    crossAxisSpacing: 16,
                                    mainAxisSpacing: 16,
                                  ),
                                  itemCount: displayShops.length,
                                  itemBuilder: (context, index) {
                                    final shop = displayShops[index];
                                    final isFood =
                                        AppCategories.groupFor(shop.category) ==
                                            CategoryGroup.food;
                                    return RepaintBoundary(
                                      key: ValueKey('home_s_${shop.id}'),
                                      child: isFood
                                          ? RestaurantShopCard(
                                              shop: shop,
                                              onTap: () =>
                                                  showRestaurantDashboardSheet(
                                                      context, shop.id),
                                            )
                                          : ShopCard(
                                              shop: shop,
                                              onTap: () => showShopDetailSheet(
                                                  context, shop.id),
                                            ),
                                    );
                                  },
                                );
                              },
                            ),
                            // ── Professional "See all" button ──
                            if (_sortedNormalShops.isNotEmpty) ...[
                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 8)),
                              SliverToBoxAdapter(
                                child: _buildModernSeeAllButton(
                                  context,
                                  label: storeMeta.buttonLabel,
                                  onTap: () => Navigator.pushNamed(
                                    context,
                                    AppRoutes.allListings,
                                    arguments: {
                                      'type': _isFoodTab
                                          ? ListingType.restaurants
                                          : ListingType.shops,
                                      'shops': List<ShopModel>.from(
                                          _sortedNormalShops),
                                      'categoryFilter':
                                          storeMeta.categoryFilter,
                                      'sectionTitle': storeMeta.sectionTitle,
                                    },
                                  ),
                                  isDark: isDark,
                                ),
                              ),
                            ],
                          ] else if (!_isLoading) ...[
                            if (_comingSoonMessage != null) ...[
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 60),
                                  child: Center(
                                    child: Column(
                                      children: [
                                        Container(
                                          width: 80,
                                          height: 80,
                                          decoration: BoxDecoration(
                                            color: isDark
                                                ? AppColors.primary
                                                    .withValues(alpha: 0.15)
                                                : AppColors.primary
                                                    .withValues(alpha: 0.08),
                                            borderRadius:
                                                BorderRadius.circular(24),
                                          ),
                                          child: Center(
                                            child: Icon(
                                              Icons.rocket_launch_rounded,
                                              size: 36,
                                              color: isDark
                                                  ? AppColors.primaryLight
                                                  : AppColors.primary,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        Text(_comingSoonMessage!,
                                            textAlign: TextAlign.center,
                                            style: GoogleFonts.outfit(
                                                fontSize: 20,
                                                fontWeight: FontWeight.w800,
                                                color: isDark
                                                    ? Colors.white
                                                    : AppColors.textPrimary)),
                                        if (_comingSoonSubMessage != null) ...[
                                          const SizedBox(height: 8),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 32),
                                            child: Text(
                                              _comingSoonSubMessage!,
                                              textAlign: TextAlign.center,
                                              style: GoogleFonts.outfit(
                                                fontSize: 14,
                                                color: isDark
                                                    ? Colors.white54
                                                    : AppColors.textSecondary,
                                              ),
                                            ),
                                          ),
                                        ]
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ] else if (_selectedTabIndex >= 0 ||
                                _selectedFilterCategories.isNotEmpty) ...[
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 60),
                                  child: Center(
                                    child: Column(
                                      children: [
                                        Container(
                                          width: 80,
                                          height: 80,
                                          decoration: BoxDecoration(
                                            color: isDark
                                                ? AppColors.primary
                                                    .withValues(alpha: 0.15)
                                                : AppColors.primary
                                                    .withValues(alpha: 0.08),
                                            borderRadius:
                                                BorderRadius.circular(24),
                                          ),
                                          child: Center(
                                            child: Icon(
                                              Icons.rocket_launch_rounded,
                                              size: 36,
                                              color: isDark
                                                  ? AppColors.primaryLight
                                                  : AppColors.primary,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                            _comingSoonMessage ??
                                                'Delivery Coming Soon!',
                                            textAlign: TextAlign.center,
                                            style: GoogleFonts.outfit(
                                                fontSize: 20,
                                                fontWeight: FontWeight.w800,
                                                color: isDark
                                                    ? Colors.white
                                                    : AppColors.textPrimary)),
                                        const SizedBox(height: 8),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 32),
                                          child: Text(
                                              _comingSoonSubMessage ??
                                                  'We\'re partnering with top local stores to bring this category to your location soon!',
                                              textAlign: TextAlign.center,
                                              style: GoogleFonts.outfit(
                                                  fontSize: 14,
                                                  color: isDark
                                                      ? Colors.white54
                                                      : AppColors.textSecondary,
                                                  height: 1.4)),
                                        ),
                                        const SizedBox(height: 20),
                                        ElevatedButton.icon(
                                          onPressed: () {
                                            setState(() {
                                              _selectedTabIndex = -1;
                                              _selectedFilterCategories.clear();
                                              _selectedFeedDemographic = 'All';
                                              _comingSoonMessage = null;
                                              _comingSoonSubMessage = null;
                                            });
                                            _loadAllData();
                                          },
                                          icon: const Icon(
                                              Icons.storefront_rounded,
                                              size: 18),
                                          label: Text('Explore All Stores',
                                              style: GoogleFonts.outfit(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w700)),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppColors.primary,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 20, vertical: 12),
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(16)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ] else if (_selectedTabIndex < 0 &&
                                _selectedFilterCategories.isEmpty) ...[
                              SliverToBoxAdapter(
                                child: locationProvider.hasLocation
                                    ? _buildNoShopsNearby()
                                    : _buildLocationRequired(),
                              ),
                            ],
                          ],
                          // Precise Industrial-Standard Bottom Nav Clearance:
                          // Ensures content stops exactly with a 12dp optical margin above the floating bottom navigation bar
                          SliverToBoxAdapter(
                            child: SizedBox(
                              height: _getFloatingBottomNavClearance(context,
                                  hasPrecedingButtonPadding:
                                      _sortedNormalShops.isNotEmpty),
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchFilterBar(bool isDark) {
    final filters = [
      {
        'mode': _SortMode.relevant,
        'label': 'Relevant',
        'icon': Icons.bolt_rounded
      },
      {
        'mode': _SortMode.bestRating,
        'label': 'Best Rating',
        'icon': Icons.star_rounded
      },
      {
        'mode': _SortMode.priceLow,
        'label': 'Price: Low to High',
        'icon': Icons.trending_up_rounded
      },
      {
        'mode': _SortMode.priceHigh,
        'label': 'Price: High to Low',
        'icon': Icons.trending_down_rounded
      },
      {
        'mode': _SortMode.discount,
        'label': 'Biggest Discount',
        'icon': Icons.local_offer_rounded
      },
    ];

    final hasDemographicCategories = _searchProductResults.any((p) => [
              'Clothing',
              'Footwear',
              'Jewellery',
              'Cosmetics & Beauty',
              'Salon & Beauty'
            ].contains(p.category)) ||
        _selectedSearchDemographic != 'All';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_hasFoodItemsInSearch) _buildDietaryFilterRow(isDark),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: filters.map((filter) {
              final mode = filter['mode'] as _SortMode;
              final isSelected = _sortMode == mode;

              return GestureDetector(
                onTap: () => setState(() {
                  _sortMode = mode;
                  _invalidateSortMemo();
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.primary
                          : (isDark ? Colors.white24 : Colors.grey.shade300),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        filter['icon'] as IconData,
                        size: 16,
                        color: isSelected
                            ? Colors.white
                            : (isDark ? Colors.white70 : AppColors.textPrimary),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        filter['label'] as String,
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected
                              ? Colors.white
                              : (isDark
                                  ? Colors.white70
                                  : AppColors.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        if (hasDemographicCategories)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: DemographicUtils.customerDemographics
                  .map((demo) => Padding(
                        padding:
                            const EdgeInsets.only(right: 8, top: 8, bottom: 8),
                        child: ChoiceChip(
                          label: Text(demo),
                          selected: _selectedSearchDemographic == demo,
                          onSelected: (selected) {
                            if (selected) {
                              setState(() {
                                _selectedSearchDemographic = demo;
                              });
                              _searchShops(_searchQuery, skipNLP: true);
                            }
                          },
                          selectedColor: AppColors.primary,
                          labelStyle: TextStyle(
                            color: _selectedSearchDemographic == demo
                                ? Colors.white
                                : (isDark
                                    ? Colors.white
                                    : AppColors.textPrimary),
                            fontFamily: 'Poppins',
                            fontSize: 13,
                          ),
                          backgroundColor:
                              isDark ? const Color(0xFF1E1E2E) : Colors.white,
                          side: BorderSide(
                            color: _selectedSearchDemographic == demo
                                ? AppColors.primary
                                : (isDark
                                    ? Colors.white24
                                    : Colors.grey.shade300),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildDietaryFilterRow(bool isDark) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // All chip
          _buildDietaryChip(
            mode: VegFilterMode.all,
            label: 'All',
            iconWidget: Icon(
              Icons.restaurant_menu_rounded,
              size: 14,
              color: _vegFilterMode == VegFilterMode.all
                  ? Colors.white
                  : (isDark ? Colors.white70 : AppColors.textPrimary),
            ),
            isSelected: _vegFilterMode == VegFilterMode.all,
            activeColor: AppColors.primary,
            isDark: isDark,
          ),
          const SizedBox(width: 8),

          // Pure Veg chip
          _buildDietaryChip(
            mode: VegFilterMode.vegOnly,
            label: 'Pure Veg',
            iconWidget: _buildDietBadgeEmblem(isVeg: true),
            isSelected: _vegFilterMode == VegFilterMode.vegOnly,
            activeColor: const Color(0xFF2E7D32),
            isDark: isDark,
          ),
          const SizedBox(width: 8),

          // Non-Veg chip
          _buildDietaryChip(
            mode: VegFilterMode.nonVegOnly,
            label: 'Non-Veg',
            iconWidget: _buildDietBadgeEmblem(isVeg: false),
            isSelected: _vegFilterMode == VegFilterMode.nonVegOnly,
            activeColor: const Color(0xFFC62828),
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildDietaryChip({
    required VegFilterMode mode,
    required String label,
    required Widget iconWidget,
    required bool isSelected,
    required Color activeColor,
    required bool isDark,
  }) {
    final bgColor = isSelected
        ? (mode == VegFilterMode.all
            ? activeColor
            : activeColor.withValues(alpha: isDark ? 0.25 : 0.12))
        : (isDark ? const Color(0xFF1E1E2E) : Colors.white);

    final borderColor = isSelected
        ? activeColor
        : (isDark ? Colors.white24 : Colors.grey.shade300);

    final textColor = isSelected
        ? (mode == VegFilterMode.all
            ? Colors.white
            : (isDark ? Colors.white : activeColor))
        : (isDark ? Colors.white70 : AppColors.textPrimary);

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() {
          if (_vegFilterMode == mode) {
            // Tapping selected dietary toggle reverts to All
            _vegFilterMode = VegFilterMode.all;
          } else {
            _vegFilterMode = mode;
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: borderColor,
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: isSelected && !isDark
              ? [
                  BoxShadow(
                    color: activeColor.withValues(alpha: 0.15),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            iconWidget,
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: textColor,
              ),
            ),
            if (isSelected && mode != VegFilterMode.all) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.check_rounded,
                size: 14,
                color: isDark ? Colors.white : activeColor,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDietBadgeEmblem({required bool isVeg}) {
    final color = isVeg ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color, width: 1.2),
      ),
      child: Center(
        child: Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  Widget _buildSearchSkeleton(bool isDark) {
    final shimmerBase =
        isDark ? const Color(0xFF1E1E2E) : const Color(0xFFF0F0F8);
    final shimmerHigh =
        isDark ? const Color(0xFF2A2A3E) : const Color(0xFFE0E0E8);
    return Shimmer.fromColors(
      baseColor: shimmerBase,
      highlightColor: shimmerHigh,
      child: Container(
        height: 100,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: shimmerBase,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Container(
              width: 100,
              decoration: BoxDecoration(
                color: shimmerHigh,
                borderRadius:
                    const BorderRadius.horizontal(left: Radius.circular(20)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                      height: 14,
                      width: 140,
                      decoration: BoxDecoration(
                          color: shimmerHigh,
                          borderRadius: BorderRadius.circular(7))),
                  const SizedBox(height: 8),
                  Container(
                      height: 10,
                      width: 100,
                      decoration: BoxDecoration(
                          color: shimmerHigh,
                          borderRadius: BorderRadius.circular(5))),
                  const SizedBox(height: 10),
                  Container(
                      height: 12,
                      width: 60,
                      decoration: BoxDecoration(
                          color: shimmerHigh,
                          borderRadius: BorderRadius.circular(6))),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                width: 60,
                height: 34,
                decoration: BoxDecoration(
                    color: shimmerHigh,
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCircleAction(
      {required IconData icon,
      required bool isDark,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1D30) : const Color(0xFFEEF0FF),
          shape: BoxShape.circle,
          border:
              Border.all(color: isDark ? Colors.white10 : Colors.transparent),
        ),
        child: Icon(icon,
            color: isDark ? Colors.white70 : AppColors.textPrimary, size: 20),
      ),
    );
  }

  Widget _buildBulkCateringCard(bool isDark) {
    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 12),
      child: PerspectiveCard(
        borderRadius: 20,
        pressScale: 0.985,
        maxTiltAngle: 0.04,
        enableHaptics: true,
        enableSpecular: true,
        onTap: () {
          SensoryHaptics.light();
          Navigator.pushNamed(context, AppRoutes.bulkOrderDiscovery);
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            // Multi-coloured celebration border harmonized with Enything brand (Cobalt Blue + Warm Coral + Festive Gold)
            gradient: const LinearGradient(
              colors: [
                Color(0xFF1E3FD8), // Enything Vivid Cobalt (Brand Primary)
                Color(0xFF6366F1), // Electric Indigo / Violet
                Color(0xFFFF007F), // Festive Celebration Magenta
                Color(0xFFFF6B35), // Enything Warm Coral (Brand CTA)
                Color(0xFFFFB800), // Sparkling Gold / Amber (Brand Accent)
                Color(0xFF1E3FD8), // Seamless loop back to Cobalt Blue
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1E3FD8)
                    .withValues(alpha: isDark ? 0.28 : 0.12),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: const Color(0xFFFF6B35)
                    .withValues(alpha: isDark ? 0.18 : 0.08),
                blurRadius: 10,
                offset: const Offset(2, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.all(
              1.5), // Crisp 1.5px multi-colour gradient border
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18.5),
              // App-harmonized canvas: Enything crisp surface with subtle celebratory champagne warmth
              gradient: LinearGradient(
                colors: isDark
                    ? [
                        const Color(0xFF0C0E1A), // Enything darkBg
                        const Color(0xFF141626), // Enything darkSurface
                        const Color(0xFF1A1D30), // Enything darkCard
                        const Color(0xFF161936), // Deep cobalt midnight depth
                      ]
                    : [
                        const Color(0xFFFFFFFF), // Crisp white card surface
                        const Color(
                            0xFFF5F6FF), // Enything AppColors.background (slight cobalt tint)
                        const Color(
                            0xFFEEF0FF), // Enything surfaceElevatedLight
                        const Color(
                            0xFFFFF9F2), // Subtle warm celebratory champagne glow
                      ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row 1: Header - Perfectly balanced SpaceBetween row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Left: Category Pill Badge - Enything Cobalt to Electric Violet
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8.5, vertical: 3.5),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF1E3FD8), Color(0xFF6366F1)],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF1E3FD8)
                                    .withValues(alpha: 0.30),
                                blurRadius: 5,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('🎉', style: TextStyle(fontSize: 10)),
                              SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  'HOST & EVENT PARTY',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 9.0,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.7,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),

                      // Right: High-Energy Savings Pill - Enything Coral to Gold
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8.5, vertical: 3.5),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFF6B35), Color(0xFFFFB800)],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFF6B35)
                                  .withValues(alpha: 0.25),
                              blurRadius: 5,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('⚡', style: TextStyle(fontSize: 9.5)),
                            SizedBox(width: 3),
                            Text(
                              'UP TO 30% OFF',
                              style: TextStyle(
                                fontSize: 9.0,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF3E1E00),
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8.0),

                  // Row 2: Content Row - 3D Emblem + Copy + Gradient CTA Button
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // 3D Celebration Cluster Container (Harmonized Cobalt to Coral)
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(13),
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF1E3FD8), // Cobalt
                              Color(0xFF6366F1), // Electric Indigo
                              Color(0xFFFF6B35), // Warm Coral
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.40),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF1E3FD8)
                                  .withValues(alpha: 0.35),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Stack(
                          alignment: Alignment.center,
                          children: [
                            Text('🎉', style: TextStyle(fontSize: 22)),
                            Positioned(
                              top: 2,
                              right: 3,
                              child: Text('✨', style: TextStyle(fontSize: 8.5)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 11),

                      // Text Info (Title, Subtitle, Reassurance)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Multicoloured Brand-Harmonized Title (Cobalt to Warm Coral)
                            ShaderMask(
                              shaderCallback: (bounds) => LinearGradient(
                                colors: isDark
                                    ? const [
                                        Color(0xFF93C5FD), // Soft Electric Blue
                                        Color(0xFFC4B5FD), // Festive Lavender
                                        Color(
                                            0xFFFFCF40), // Enything Accent Gold
                                      ]
                                    : const [
                                        Color(0xFF0F1E80), // Deep Brand Cobalt
                                        Color(0xFF1E3FD8), // Vivid Brand Cobalt
                                        Color(0xFFFF6B35), // Warm Brand Coral
                                      ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ).createShader(bounds),
                              child: Text(
                                'Host an Event or Party? 🎊',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: -0.2,
                                  height: 1.15,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Bulk catering for 20 to 500+ guests',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w500,
                                color: isDark
                                    ? Colors.white70
                                    : const Color(0xFF475569),
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 3),
                            // Feature reassurance line
                            Row(
                              children: [
                                Icon(
                                  Icons.verified_rounded,
                                  size: 11.0,
                                  color: isDark
                                      ? const Color(0xFF4ADE80)
                                      : const Color(0xFF16A34A),
                                ),
                                const SizedBox(width: 3.0),
                                Flexible(
                                  child: Text(
                                    'Chef quotes in 15 mins · Custom menus',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? Colors.white60
                                          : const Color(0xFF64748B),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Sleek Brand Gradient Action Button (Cobalt to Coral)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9.5, vertical: 6.5),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF1E3FD8), // Brand Cobalt Blue
                              Color(0xFF4F46E5), // Indigo
                              Color(0xFFFF6B35), // Brand Coral Orange
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF1E3FD8)
                                  .withValues(alpha: 0.30),
                              blurRadius: 7,
                              offset: const Offset(0, 2.5),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Plan Event',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.2,
                              ),
                            ),
                            SizedBox(width: 2.5),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 11.5,
                              color: Colors.white,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveQuoteBanner(bool isDark) {
    final quoteProv = context.watch<QuoteRequestProvider>();
    final activeOrder = quoteProv.activeCateringOrder;

    // ── 1. Priority: Live Active Catering Order in Progress ──────────────────
    if (activeOrder != null) {
      final orderId = activeOrder['id']?.toString() ?? '';
      final status = activeOrder['status']?.toString() ?? 'bulk_pending';
      final totalAmount =
          (activeOrder['total_amount'] as num?)?.toDouble() ?? 0.0;
      final deliveryOtp = activeOrder['delivery_otp']?.toString() ?? '';
      final eventName = activeOrder['event_name']?.toString() ??
          quoteProv.customerQuotes
              .where((q) => q.resultingOrderId == orderId)
              .firstOrNull
              ?.eventName ??
          'Event Catering';

      final eventNameLower = eventName.toLowerCase();
      final isSupplies = eventNameLower.contains('rental') ||
          eventNameLower.contains('equipment') ||
          eventNameLower.contains('decor') ||
          eventNameLower.contains('supplies') ||
          eventNameLower.contains('chair') ||
          eventNameLower.contains('tent');

      final Color primaryColor;
      final String emoji;
      final String title;
      final String subtitle;
      final String statusTag;
      final String buttonText;

      switch (status) {
        case 'bulk_confirmed':
        case 'bulk_preparing':
          primaryColor = const Color(0xFF2563EB); // Royal Blue
          emoji = isSupplies ? '📦' : '👨‍🍳';
          title = isSupplies
              ? 'Supplies Confirmed · Preparation in Progress!'
              : 'Kitchen Confirmed · Cooking in Progress!';
          subtitle = isSupplies
              ? '$eventName · ₹${totalAmount.toStringAsFixed(0)} · Catering team is preparing and packing your event supplies.'
              : '$eventName · ₹${totalAmount.toStringAsFixed(0)} · Kitchen chefs are preparing and cooking your feast fresh.';
          statusTag = isSupplies ? 'PREPARING SUPPLIES' : 'KITCHEN COOKING';
          buttonText = 'Live Prep Details →';
          break;
        case 'bulk_ready':
          primaryColor = const Color(0xFF8B5CF6); // Purple / Violet
          emoji = isSupplies ? '✨' : '🍱';
          title = isSupplies
              ? 'All Event Supplies Prepared & Ready!'
              : 'All Food Prepared & Ready!';
          subtitle = isSupplies
              ? '$eventName · All items packed, awaiting dispatch.'
              : '$eventName · All dishes freshly packed in containers, awaiting dispatch.';
          statusTag =
              isSupplies ? 'ALL SUPPLIES PACKED' : 'ALL FOOD PACKED & READY';
          buttonText = 'View Packing Status →';
          break;
        case 'bulk_dispatched':
          primaryColor = const Color(0xFF059669); // Emerald Green
          emoji = '🚗';
          title = isSupplies
              ? 'Event Supplies Out for Delivery${deliveryOtp.isNotEmpty ? ' · OTP: $deliveryOtp' : ''}'
              : 'Feast Out for Delivery${deliveryOtp.isNotEmpty ? ' · OTP: $deliveryOtp' : ''}';
          subtitle =
              '$eventName · In-house delivery team is en route to your venue! Share OTP $deliveryOtp upon arrival.';
          statusTag = 'OUT FOR DELIVERY';
          buttonText = 'Track Fleet Live →';
          break;
        case 'bulk_pending':
        default:
          primaryColor = const Color(0xFFF59E0B); // Amber / Gold
          emoji = '🎉';
          title = isSupplies
              ? 'Event Order Booked · Scheduling Dispatch'
              : 'Feast Booked · Scheduling Kitchen';
          subtitle = isSupplies
              ? '$eventName · ₹${totalAmount.toStringAsFixed(0)} · Catering team is appointing dedicated fulfillment staff.'
              : '$eventName · ₹${totalAmount.toStringAsFixed(0)} · Catering team is appointing your dedicated kitchen.';
          statusTag = isSupplies ? 'SCHEDULING DISPATCH' : 'SCHEDULING KITCHEN';
          buttonText = isSupplies ? 'Track Order →' : 'Track Feast →';
          break;
      }

      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [
                      primaryColor.withValues(alpha: 0.32),
                      const Color(0xFF16192E),
                    ]
                  : [
                      primaryColor.withValues(alpha: 0.18),
                      Colors.white,
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: primaryColor.withValues(alpha: 0.85),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: primaryColor.withValues(alpha: 0.22),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                Navigator.pushNamed(
                  context,
                  AppRoutes.bulkOrderTracking,
                  arguments: {'order_id': orderId},
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.22),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 22),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: isDark
                                      ? Colors.white
                                      : AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  fontSize: 12.5,
                                  color:
                                      isDark ? Colors.white70 : Colors.black87,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: primaryColor.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      color: primaryColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    statusTag,
                                    style: GoogleFonts.outfit(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      color: primaryColor,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (status == 'bulk_dispatched' &&
                                deliveryOtp.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: primaryColor.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(8),
                                  border:
                                      Border.all(color: primaryColor, width: 1),
                                ),
                                child: Text(
                                  'OTP: $deliveryOtp',
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: primaryColor,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          buttonText,
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    // ── 2. Priority: Delivered Catering Order Celebration (Single-View Dismissal) ─
    final deliveredCelebration = quoteProv.deliveredCateringOrderToCelebrate;
    if (deliveredCelebration != null) {
      final orderId = deliveredCelebration['id']?.toString() ?? '';
      final deliveryOtp =
          deliveredCelebration['delivery_otp']?.toString() ?? '';
      final eventName = deliveredCelebration['event_name']?.toString() ??
          quoteProv.customerQuotes
              .where((q) => q.resultingOrderId == orderId)
              .firstOrNull
              ?.eventName ??
          'Event Catering';

      const primaryColor = Color(0xFF10B981); // Emerald Green Celebration

      // Mark as seen in background so it won't resurrect on subsequent app sessions
      WidgetsBinding.instance.addPostFrameCallback((_) {
        quoteProv.markDeliveredCateringCelebrationSeen(orderId);
      });

      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [
                      primaryColor.withValues(alpha: 0.35),
                      const Color(0xFF064E3B).withValues(alpha: 0.6),
                      const Color(0xFF16192E),
                    ]
                  : [
                      const Color(0xFFD1FAE5),
                      Colors.white,
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: primaryColor,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: primaryColor.withValues(alpha: 0.25),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () async {
                // Tapping card opens tracking and automatically dismisses so it disappears on return
                await quoteProv.dismissDeliveredCateringCelebration(orderId);
                if (mounted) {
                  Navigator.pushNamed(
                    context,
                    AppRoutes.bulkOrderTracking,
                    arguments: {'order_id': orderId},
                  );
                }
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.25),
                            shape: BoxShape.circle,
                          ),
                          child:
                              const Text('🎉', style: TextStyle(fontSize: 24)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (eventName.toLowerCase().contains('rental') ||
                                        eventName
                                            .toLowerCase()
                                            .contains('equipment') ||
                                        eventName
                                            .toLowerCase()
                                            .contains('decor') ||
                                        eventName
                                            .toLowerCase()
                                            .contains('supplies'))
                                    ? 'Event Supplies Delivered & Verified! 🎉'
                                    : 'Feast Delivered & Handover Verified! 🎉',
                                style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: isDark
                                      ? Colors.white
                                      : AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                (eventName.toLowerCase().contains('rental') ||
                                        eventName
                                            .toLowerCase()
                                            .contains('equipment') ||
                                        eventName
                                            .toLowerCase()
                                            .contains('decor') ||
                                        eventName
                                            .toLowerCase()
                                            .contains('supplies'))
                                    ? '$eventName · Delivered with OTP${deliveryOtp.isNotEmpty ? ' ($deliveryOtp)' : ''}. Have a wonderful celebration!'
                                    : '$eventName · Delivered with OTP${deliveryOtp.isNotEmpty ? ' ($deliveryOtp)' : ''}. Have a wonderful celebration! Enjoy your feast.',
                                style: GoogleFonts.outfit(
                                  fontSize: 12.5,
                                  color:
                                      isDark ? Colors.white70 : Colors.black87,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // 1-Tap Dismiss "X" Button
                        InkWell(
                          onTap: () => quoteProv
                              .dismissDeliveredCateringCelebration(orderId),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.close_rounded,
                              size: 16,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: primaryColor, width: 1),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_circle_rounded,
                                  size: 14, color: primaryColor),
                              const SizedBox(width: 6),
                              Text(
                                'DELIVERED · OTP VERIFIED ✅',
                                style: GoogleFonts.outfit(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: primaryColor,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () => quoteProv
                              .dismissDeliveredCateringCelebration(orderId),
                          child: Text(
                            'Got it! 🎉',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    // ── 3. Fallback: Pre-Order Custom Event Quotes ───────────────────────────
    final activeQuotes = quoteProv.customerQuotes.where((q) {
      return q.quoteStatus == 'quoted' ||
          q.quoteStatus == 'pending_review' ||
          q.quoteStatus == 'customer_accepted';
    }).toList();

    if (activeQuotes.isEmpty) return const SizedBox.shrink();

    activeQuotes.sort((a, b) {
      if (a.quoteStatus == 'quoted' && b.quoteStatus != 'quoted') return -1;
      if (b.quoteStatus == 'quoted' && a.quoteStatus != 'quoted') return 1;
      return b.createdAt.compareTo(a.createdAt);
    });

    final quote = activeQuotes.first;
    final isQuoted = quote.quoteStatus == 'quoted';
    final isAccepted = quote.quoteStatus == 'customer_accepted';

    final Color primaryColor = isQuoted
        ? const Color(0xFF10B981) // Emerald
        : isAccepted
            ? const Color(0xFFF59E0B) // Amber
            : const Color(0xFF6366F1); // Indigo

    final String title = isQuoted
        ? '🧾 Catering Quote Ready: ₹${quote.quotedAmount?.toStringAsFixed(0)}'
        : isAccepted
            ? '✅ Quote Accepted — Payment Pending'
            : '⏳ Catering Request Under Review';

    final String subtitle = isQuoted
        ? '${quote.eventName} · Muhtashim priced your request. Tap to review & accept!'
        : isAccepted
            ? '${quote.eventName} (₹${quote.quotedAmount?.toStringAsFixed(0)}) · Manager will call to complete offline payment.'
            : '${quote.eventName} (${quote.estimatedGuestCount} guests) · Reviewing requirements, custom quote arriving shortly.';

    final String buttonText = isQuoted ? 'Review & Accept →' : 'View Details →';

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [
                    primaryColor.withValues(alpha: 0.28),
                    const Color(0xFF16192E),
                  ]
                : [
                    primaryColor.withValues(alpha: 0.18),
                    Colors.white,
                  ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: primaryColor.withValues(alpha: isQuoted ? 0.9 : 0.4),
            width: isQuoted ? 2 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: primaryColor.withValues(alpha: isQuoted ? 0.25 : 0.08),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              Navigator.pushNamed(
                context,
                AppRoutes.quoteResponse,
                arguments: {'quote_id': quote.id},
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          isQuoted
                              ? '🎉'
                              : isAccepted
                                  ? '📞'
                                  : '📋',
                          style: const TextStyle(fontSize: 20),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: isDark
                                    ? Colors.white
                                    : AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                fontSize: 12.5,
                                color: isDark ? Colors.white70 : Colors.black87,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          isQuoted
                              ? 'ACTION REQUIRED'
                              : quote.quoteStatus
                                  .replaceAll('_', ' ')
                                  .toUpperCase(),
                          style: GoogleFonts.outfit(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: primaryColor,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      Text(
                        buttonText,
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: primaryColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeaturedBanner() {
    final isDark = context.watch<ThemeProvider>().isDarkMode;
    final slides = [
      {
        'tag': '🔥 HOT & FRESH',
        'title': 'Get Food Instantly\nDelivered to you',
        'sub': 'Fast, fresh, and local restaurants',
        'icon': Icons.local_dining_rounded,
        'colors': <Color>[
          const Color(0xFFFF512F),
          const Color(0xFFF09819),
          const Color(0xFFFF6A00)
        ],
        'accent': const Color(0xFFFFE082),
        'emoji': '🍔',
        'action': () {
          if (!context.read<LocationProvider>().hasLocation) {
            _promptEnableLocation();
            return;
          }
          final idx = _categories.indexWhere((c) => c['name'] == 'Food');
          if (idx == -1) {
            setState(() {
              _selectedTabIndex = -1;
              _selectedFilterCategories.clear();
              _selectedFeedDemographic = 'All';
              _comingSoonMessage = 'Food Delivery Coming Soon!';
              _comingSoonSubMessage =
                  'We are partnering with the best local restaurants. Stay tuned!';
              _shops = [];
              _products = [];
              _isLoading = false;
            });
            return;
          }
          setState(() {
            _selectedTabIndex = idx;
            _selectedFilterCategories.clear();
            _selectedFeedDemographic = 'All';
          });
          _loadData('Food');
        },
      },
      {
        'tag': '🛒 DAILY GROCERIES',
        'title': 'Fresh Groceries\nAt your doorstep',
        'sub': 'Supermarkets, fruits & daily essentials',
        'icon': Icons.shopping_basket_rounded,
        'colors': <Color>[
          const Color(0xFF11998E),
          const Color(0xFF38EF7D),
          const Color(0xFF00B09B)
        ],
        'accent': const Color(0xFFB9F6CA),
        'emoji': '🥦🥕',
        'action': () {
          if (!context.read<LocationProvider>().hasLocation) {
            _promptEnableLocation();
            return;
          }
          final idx = _categories
              .indexWhere((c) => c['name'] == 'Supermarket / Hypermarket');
          if (idx == -1) {
            setState(() {
              _selectedTabIndex = -1;
              _selectedFilterCategories.clear();
              _selectedFeedDemographic = 'All';
              _comingSoonMessage = 'Groceries & Supermarket Coming Soon!';
              _comingSoonSubMessage =
                  'Daily essentials delivered to your doorstep, launching soon.';
              _shops = [];
              _products = [];
              _isLoading = false;
            });
            return;
          }
          setState(() {
            _selectedTabIndex = idx;
            _selectedFilterCategories.clear();
            _selectedFeedDemographic = 'All';
          });
          _loadData('Grocery');
        },
      },
      {
        'tag': '💊 MEDICINES & HEALTH',
        'title': 'Medicines & Pharmacy\nDelivered in minutes',
        'sub': 'Local licensed pharmacies & wellness essentials',
        'icon': Icons.local_pharmacy_rounded,
        'colors': <Color>[
          const Color(0xFF004D40),
          const Color(0xFF00796B),
          const Color(0xFF00BFA5),
        ],
        'accent': const Color(0xFFA7FFEB),
        'emoji': '💊🏥',
        'action': () {
          if (!context.read<LocationProvider>().hasLocation) {
            _promptEnableLocation();
            return;
          }
          final idx = _categories.indexWhere((c) => c['name'] == 'Pharmacy');
          if (idx == -1) {
            setState(() {
              _selectedTabIndex = -1;
              _selectedFilterCategories.clear();
              _selectedFeedDemographic = 'All';
              _comingSoonMessage = 'Pharmacy & Medicines Coming Soon!';
              _comingSoonSubMessage =
                  'We are partnering with licensed local pharmacies. Stay tuned!';
              _shops = [];
              _products = [];
              _isLoading = false;
            });
            return;
          }
          setState(() {
            _selectedTabIndex = idx;
            _selectedFilterCategories.clear();
            _selectedFeedDemographic = 'All';
          });
          _loadData('Pharmacy');
        },
      },
      {
        'tag': '👔 MEN & BOYS',
        'title': 'Trending Styles\nFor Men & Boys',
        'sub': 'Apparel, shoes, grooming & essentials',
        'icon': Icons.man_rounded,
        'colors': <Color>[
          const Color(0xFF0D1B2A),
          const Color(0xFF1B263B),
          const Color(0xFF2E5BFF),
        ],
        'accent': const Color(0xFF4DEEEA),
        'emoji': '👟👕',
        'action': () {
          if (!context.read<LocationProvider>().hasLocation) {
            _promptEnableLocation();
            return;
          }
          final idx = _categories.indexWhere((c) => c['name'] == 'Clothing');
          if (idx == -1) {
            setState(() {
              _selectedTabIndex = -1;
              _selectedFilterCategories.clear();
              _selectedFeedDemographic = 'All';
              _comingSoonMessage = 'Men\'s Fashion Coming Soon!';
              _comingSoonSubMessage =
                  'Your favorite local apparel stores will be here shortly.';
              _shops = [];
              _products = [];
              _isLoading = false;
            });
            return;
          }
          setState(() {
            _selectedTabIndex = idx;
            _selectedFilterCategories.clear();
            _selectedFeedDemographic = 'Men/Boys';
          });
          _loadData('Clothing');
        },
      },
      {
        'tag': '👗 WOMEN & GIRLS',
        'title': 'Chic Fashion\nFor Women & Girls',
        'sub': 'Trending apparel, footwear & beauty',
        'icon': Icons.woman_rounded,
        'colors': <Color>[
          const Color(0xFF5E0B4B),
          const Color(0xFF9C27B0),
          const Color(0xFFE040FB),
        ],
        'accent': const Color(0xFFFF80AB),
        'emoji': '👠💄',
        'action': () {
          if (!context.read<LocationProvider>().hasLocation) {
            _promptEnableLocation();
            return;
          }
          final idx = _categories.indexWhere((c) => c['name'] == 'Clothing');
          if (idx == -1) {
            setState(() {
              _selectedTabIndex = -1;
              _selectedFilterCategories.clear();
              _selectedFeedDemographic = 'All';
              _comingSoonMessage = 'Women\'s Fashion Coming Soon!';
              _comingSoonSubMessage =
                  'Your favorite local apparel stores will be here shortly.';
              _shops = [];
              _products = [];
              _isLoading = false;
            });
            return;
          }
          setState(() {
            _selectedTabIndex = idx;
            _selectedFilterCategories.clear();
            _selectedFeedDemographic = 'Women/Girls';
          });
          _loadData('Clothing');
        },
      },
      {
        'tag': '🎉 EVENT & CATERING',
        'title': 'Bulk Food Catering\nFor Parties & Events',
        'sub': 'Tiered discounts · Advance slots · Fleet delivery',
        'icon': Icons.celebration_rounded,
        'colors': <Color>[
          const Color(0xFF581C87),
          const Color(0xFF8E24AA),
          const Color(0xFFE11D48),
          const Color(0xFFEA580C),
        ],
        'accent': const Color(0xFFFFD54F),
        'emoji': '🍕🎉',
        'action': () {
          Navigator.pushNamed(context, AppRoutes.bulkOrderDiscovery);
        },
      },
    ];

    return Column(
      children: [
        MouseRegion(
          onEnter: (_) => _isBannerHovered = true,
          onExit: (_) => _isBannerHovered = false,
          child: SizedBox(
            height: 130,
            child: PageView.builder(
              controller: _bannerController,
              onPageChanged: (i) => _bannerIndex.value = i,
              itemCount: slides.length,
              itemBuilder: (_, i) {
                final s = slides[i];
                final colors = s['colors'] as List<Color>;
                final accent = s['accent'] as Color;
                final emoji = s['emoji'] as String;
                return GestureDetector(
                  onTap: () {
                    SensoryHaptics.light();
                    (s['action'] as VoidCallback)();
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: colors,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                            color: colors[1].withValues(alpha: 0.5),
                            blurRadius: 20,
                            offset: const Offset(0, 10)),
                      ],
                    ),
                    child: Stack(
                      children: [
                        // Large background circle
                        Positioned(
                            right: -30,
                            top: -30,
                            child: Container(
                                width: 140,
                                height: 140,
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color:
                                        Colors.white.withValues(alpha: 0.05)))),
                        // Smaller circle
                        Positioned(
                            left: -15,
                            bottom: -15,
                            child: Container(
                                width: 70,
                                height: 70,
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color:
                                        Colors.white.withValues(alpha: 0.04)))),
                        // Background icon
                        Positioned(
                            right: -5,
                            bottom: -15,
                            child: Icon(s['icon'] as IconData,
                                size: 90,
                                color: Colors.white.withValues(alpha: 0.07))),
                        // Big emoji top-right
                        Positioned(
                            right: 16,
                            top: 16,
                            child: Text(emoji,
                                style: const TextStyle(fontSize: 36))),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 70, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                    color: accent,
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: [
                                      BoxShadow(
                                          color: accent.withValues(alpha: 0.4),
                                          blurRadius: 6)
                                    ]),
                                child: Text(s['tag'] as String,
                                    style: GoogleFonts.outfit(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.black87,
                                        letterSpacing: 0.5)),
                              ),
                              const SizedBox(height: 8),
                              Text(s['title'] as String,
                                  style: GoogleFonts.outfit(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                      height: 1.15,
                                      letterSpacing: -0.3)),
                              const SizedBox(height: 4),
                              Text(s['sub'] as String,
                                  style: GoogleFonts.outfit(
                                      fontSize: 10,
                                      color:
                                          Colors.white.withValues(alpha: 0.72),
                                      height: 1.3)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Premium animated pill indicator
        ValueListenableBuilder<int>(
          valueListenable: _bannerIndex,
          builder: (context, bannerIndex, _) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(slides.length, (i) {
                final active = bannerIndex == i;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 22 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    gradient: active
                        ? const LinearGradient(
                            colors: [Color(0xFF1E3FD8), Color(0xFF3D6BFF)])
                        : null,
                    color: active
                        ? null
                        : (isDark ? Colors.white24 : AppColors.textLight),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: active
                        ? [
                            BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.5),
                                blurRadius: 8)
                          ]
                        : [],
                  ),
                );
              }),
            );
          },
        ),
      ],
    );
  }

  Widget _buildFeedDemographicSelector(bool isDark) {
    const demos = [
      {'key': 'All', 'label': 'All Fashion', 'emoji': '🛍️'},
      {'key': 'Men/Boys', 'label': 'Men & Boys', 'emoji': '👔'},
      {'key': 'Women/Girls', 'label': 'Women & Girls', 'emoji': '👗'},
      {'key': 'Kids', 'label': 'Kids', 'emoji': '🧸'},
      {'key': 'Unisex', 'label': 'Unisex', 'emoji': '✨'},
    ];

    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: demos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final d = demos[i];
          final isSelected = _selectedFeedDemographic == d['key'];
          return GestureDetector(
            onTap: () {
              SensoryHaptics.light();
              setState(() {
                _selectedFeedDemographic = d['key']!;
                _invalidateSortMemo();
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: isSelected
                    ? const LinearGradient(
                        colors: [Color(0xFF1E3FD8), Color(0xFF3D6BFF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: isSelected
                    ? null
                    : (isDark ? const Color(0xFF1E1E2E) : Colors.grey.shade100),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? Colors.transparent
                      : (isDark ? Colors.white10 : Colors.grey.shade300),
                  width: 1,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        )
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(d['emoji']!, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                  Text(
                    d['label']!,
                    style: GoogleFonts.outfit(
                      fontSize: 12.5,
                      fontWeight:
                          isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: isSelected
                          ? Colors.white
                          : (isDark
                              ? Colors.white.withValues(alpha: 0.85)
                              : AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDemographicEmptyState(bool isDark) {
    final emoji = _selectedFeedDemographic == 'Men/Boys'
        ? '👔'
        : (_selectedFeedDemographic == 'Women/Girls'
            ? '👗'
            : (_selectedFeedDemographic == 'Kids'
                ? '🧸'
                : (_selectedFeedDemographic == 'Unisex' ? '✨' : '🛍️')));
    final label = _selectedFeedDemographic == 'Men/Boys'
        ? 'Men & Boys'
        : (_selectedFeedDemographic == 'Women/Girls'
            ? 'Women & Girls'
            : (_selectedFeedDemographic == 'Kids'
                ? 'Kids'
                : (_selectedFeedDemographic == 'Unisex'
                    ? 'Unisex'
                    : 'Fashion')));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: isDark ? 0.2 : 0.1),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 28)),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'No $label items found nearby',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Showing all other available items in your area',
              style: GoogleFonts.outfit(
                fontSize: 12,
                color: isDark ? Colors.white60 : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: () {
                SensoryHaptics.light();
                setState(() {
                  _selectedFeedDemographic = 'All';
                  _invalidateSortMemo();
                });
              },
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Show All Fashion Items'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(
    String title, {
    String? subtitle,
    int? count,
    bool isHighlighted = false,
    bool isLoading = false,
    VoidCallback? onSeeAllTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isNarrow = MediaQuery.of(context).size.width < 380;
    final double titleFontSize = isNarrow
        ? (title.length > 25 ? 14.5 : (title.length > 18 ? 15.5 : 17.0))
        : (title.length > 25 ? 15.5 : (title.length > 18 ? 16.5 : 18.0));

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Colored left accent bar
              Container(
                width: 4,
                height: 34,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isHighlighted
                        ? [AppColors.secondary, const Color(0xFFFF3366)]
                        : [AppColors.primary, AppColors.primaryLight],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: GoogleFonts.outfit(
                              fontSize: titleFontSize,
                              fontWeight: FontWeight.w900,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF1A1A2E),
                              letterSpacing: -0.2,
                              height: 1.15,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (count != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: isHighlighted
                                    ? [
                                        const Color(0xFFFF6B35)
                                            .withValues(alpha: 0.12),
                                        const Color(0xFFFF3366)
                                            .withValues(alpha: 0.08),
                                      ]
                                    : [
                                        const Color(0xFF0A2A9E)
                                            .withValues(alpha: 0.10),
                                        const Color(0xFF1E40AF)
                                            .withValues(alpha: 0.06),
                                      ],
                              ),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isHighlighted
                                    ? const Color(0xFFFF3366)
                                        .withValues(alpha: 0.25)
                                    : AppColors.primary.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Text(
                              '$count',
                              style: GoogleFonts.outfit(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: isHighlighted
                                    ? const Color(0xFFFF3366)
                                    : AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: GoogleFonts.outfit(
                          fontSize: 11.5,
                          color:
                              isDark ? Colors.white54 : AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                          height: 1.15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        if (onSeeAllTap != null || isLoading)
          GestureDetector(
            onTap: isLoading ? null : onSeeAllTap,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 9.5, vertical: 4.5),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.07)
                    : AppColors.primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark
                      ? Colors.white10
                      : AppColors.primary.withValues(alpha: 0.12),
                ),
              ),
              child: isLoading
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: isDark ? Colors.white70 : AppColors.primary,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'See all',
                          style: GoogleFonts.outfit(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white70 : AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 2.5),
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: 13,
                          color: isDark ? Colors.white70 : AppColors.primary,
                        ),
                      ],
                    ),
            ),
          ),
      ],
    );
  }

  List<ShopModel> _getTop4DiverseShops(List<ShopModel> allShops) {
    if (allShops.isEmpty) return [];

    final sortedByRating = List<ShopModel>.from(allShops)
      ..sort((a, b) => b.rating.compareTo(a.rating));

    ShopModel? restaurant;
    ShopModel? grocery;
    ShopModel? clothing;
    ShopModel? pharmacy;

    final remaining = <ShopModel>[];

    for (final shop in sortedByRating) {
      final group = AppCategories.groupFor(shop.category);
      final catLower = shop.category.toLowerCase();

      if (restaurant == null && group == CategoryGroup.food) {
        restaurant = shop;
      } else if (grocery == null &&
          (group == CategoryGroup.perishable ||
              catLower.contains('grocery') ||
              catLower.contains('supermarket'))) {
        grocery = shop;
      } else if (clothing == null && catLower.contains('clothing')) {
        clothing = shop;
      } else if (pharmacy == null && group == CategoryGroup.pharmacy) {
        pharmacy = shop;
      } else {
        remaining.add(shop);
      }
    }

    final selected = <ShopModel>[];
    if (restaurant != null) selected.add(restaurant);
    if (grocery != null) selected.add(grocery);
    if (clothing != null) selected.add(clothing);
    if (pharmacy != null) selected.add(pharmacy);

    for (final shop in remaining) {
      if (selected.length >= 4) break;
      selected.add(shop);
    }

    return selected;
  }

  Widget _buildModernSeeAllButton(BuildContext context,
      {required String label,
      required VoidCallback onTap,
      required bool isDark}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : AppColors.primary.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : AppColors.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 20,
                  color: isDark ? Colors.white : AppColors.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Industrial Standard Floating Bottom Nav Clearance
  /// Calculates the exact clearance required for the floating bottom navigation bar
  /// so that scrolled content stops exactly with a 12dp optical margin above the bar.
  /// Zero overlap, zero excessive whitespace, and zero text/footer widgets.
  double _getFloatingBottomNavClearance(BuildContext context,
      {bool hasPrecedingButtonPadding = false}) {
    // 100x Forensic Geometry: Read raw hardware inset from viewPadding.
    // In Flutter, Scaffold(extendBody: true) automatically inflates MediaQuery.paddingOf(context).bottom
    // by the height of the bottomNavigationBar. Using paddingOf causes a double-counting bug.
    // viewPaddingOf contains the true unpolluted hardware inset (e.g. 34.0 on iOS, 48.0 on 3-button nav).
    final hardwareBottomInset = MediaQuery.viewPaddingOf(context).bottom;

    final double barBottomMargin;
    if (hardwareBottomInset <= 0) {
      // Hardware buttons / Web / Desktop / older iPhone
      barBottomMargin = 10.0;
    } else if (hardwareBottomInset >= 36.0) {
      // Android 3-button or 2-button navigation bar (typically 40.0 to 54.0 dp)
      barBottomMargin = hardwareBottomInset + 4.0;
    } else if (Theme.of(context).platform == TargetPlatform.iOS) {
      // iOS Home Indicator (typically 34.0 dp)
      barBottomMargin = hardwareBottomInset;
    } else {
      // Android Gesture Navigation (typically 16.0 to 24.0 dp)
      barBottomMargin = hardwareBottomInset + 4.0;
    }

    // Floating bar is 68.0 dp tall.
    // Floating bar top edge from bottom of screen = 68.0 + barBottomMargin.
    // Setting optical cushion to 28.0 dp ensures the "See all stores ->" button and product cards
    // clear the floating bar and its blur shadow with a clean, comfortable breathing gap (~16-20 dp),
    // eliminating any overlap while strictly preventing excessive white space void.
    const double opticalCushion = 28.0;

    return 68.0 + barBottomMargin + opticalCushion;
  }

  void _openCategoryListing({
    required String title,
    required List<ProductModel> products,
    required List<String> categories,
  }) {
    HapticFeedback.lightImpact();
    final lowerCats = categories.map((c) => c.trim().toLowerCase()).toSet();
    final matchingShops = _shops.where((s) {
      if (lowerCats.contains(s.category.trim().toLowerCase())) return true;
      if (s.categories.any((c) => lowerCats.contains(c.trim().toLowerCase()))) {
        return true;
      }
      // 100x Multi-department omnibus store check: Supermarkets & Hypermarkets carry cosmetics, grocery, dairy, produce, bakery, meat, etc.
      if (lowerCats.any((t) =>
          t.contains('cosmetic') ||
          t.contains('beauty') ||
          t.contains('grocery') ||
          t.contains('dairy') ||
          t.contains('fruit') ||
          t.contains('bakery') ||
          t.contains('meat') ||
          t.contains('fish') ||
          t.contains('sweets') ||
          t.contains('egg'))) {
        final sCat = s.category.trim().toLowerCase();
        if (sCat.contains('supermarket') ||
            sCat.contains('hypermarket') ||
            sCat.contains('departmental')) {
          return true;
        }
      }
      return false;
    }).toList();
    Navigator.pushNamed(
      context,
      AppRoutes.allListings,
      arguments: {
        'type': ListingType.products,
        'products': List<ProductModel>.from(products),
        'productShops': Map<String, ShopModel>.from(_productShops),
        'shops': matchingShops,
        'sectionTitle': title,
        'categoryFilter': List<String>.from(categories),
      },
    );
  }

  Widget _buildDepartmentSectionHeader({
    required String title,
    required String subtitle,
    required String emoji,
    required int count,
    required List<Color> accentGradient,
    required VoidCallback onSeeAllTap,
    required bool isDark,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 380;
    final titleFontSize = isCompact
        ? (title.length > 20 ? 14.0 : 15.0)
        : (title.length > 20 ? 15.5 : 17.0);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Department Emoji / Gradient Pill
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      accentGradient.first
                          .withValues(alpha: isDark ? 0.25 : 0.14),
                      accentGradient.last
                          .withValues(alpha: isDark ? 0.15 : 0.07),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: accentGradient.first
                        .withValues(alpha: isDark ? 0.35 : 0.20),
                    width: 1.2,
                  ),
                ),
                child: Center(
                  child: Text(
                    emoji,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: GoogleFonts.outfit(
                              fontSize: titleFontSize,
                              fontWeight: FontWeight.w900,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF1A1A2E),
                              letterSpacing: -0.2,
                              height: 1.15,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                accentGradient.first.withValues(alpha: 0.12),
                                accentGradient.last.withValues(alpha: 0.06),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color:
                                  accentGradient.first.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Text(
                            '$count',
                            style: GoogleFonts.outfit(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: accentGradient.first,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.outfit(
                        fontSize: 11.5,
                        color:
                            isDark ? Colors.white54 : AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                        height: 1.15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onSeeAllTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9.5, vertical: 4.5),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : AppColors.primary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark
                    ? Colors.white10
                    : AppColors.primary.withValues(alpha: 0.12),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'See all',
                  style: GoogleFonts.outfit(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white70 : AppColors.primary,
                  ),
                ),
                const SizedBox(width: 2.5),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 13,
                  color: isDark ? Colors.white70 : AppColors.primary,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryHorizontalCarousel({
    required List<ProductModel> products,
    required String sectionTitle,
    required VoidCallback onViewAllTap,
    required bool isDark,
  }) {
    final carouselItems = products.take(12).toList();

    return SizedBox(
      height: 245,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(right: 6),
        itemCount: carouselItems.length + 1,
        itemBuilder: (context, index) {
          if (index < carouselItems.length) {
            final product = carouselItems[index];
            final shop = _productShops[product.id] ??
                _shops.cast<ShopModel?>().firstWhere(
                      (s) => s?.id == product.shopId,
                      orElse: () => null,
                    );
            return SizedBox(
              width: 146,
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: RepaintBoundary(
                  key: ValueKey('sec_p_${product.id}'),
                  child: ProductCard(
                    product: product,
                    shop: shop,
                    imageAspectRatio: 1.12,
                  ),
                ),
              ),
            );
          }

          // ── Sleek "View All" End-Card ──────────────────────────────
          return SizedBox(
            width: 136,
            child: Padding(
              padding: const EdgeInsets.only(right: 4, top: 4, bottom: 4),
              child: RepaintBoundary(
                key: ValueKey('sec_end_$sectionTitle'),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onViewAllTap,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1E1E2E)
                            : const Color(0xFFF7F8FC),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isDark
                              ? Colors.white12
                              : Colors.black.withValues(alpha: 0.07),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black
                                .withValues(alpha: isDark ? 0.25 : 0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  AppColors.primary,
                                  AppColors.primaryLight,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      AppColors.primary.withValues(alpha: 0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.arrow_forward_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'View All',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color:
                                  isDark ? Colors.white : AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$sectionTitle Items',
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Colors.white60
                                  : AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: AppColors.primary
                                  .withValues(alpha: isDark ? 0.20 : 0.08),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${products.length}+ items',
                              style: GoogleFonts.outfit(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? AppColors.primaryLight
                                    : AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNoShopsNearby() {
    final loc = context.watch<LocationProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentAddress =
        loc.currentAddress.isNotEmpty ? loc.currentAddress : 'Your location';

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.primary.withValues(alpha: 0.15)
                    : AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Text('📍', style: TextStyle(fontSize: 38)),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No Stores Deliver Here Yet',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color:
                    isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.location_on_rounded,
                      size: 14, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      currentAddress,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color:
                            isDark ? Colors.white70 : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'We currently deliver within a ${DeliveryCalculator.maxRadiusKm.toInt()} km radius of our active store hubs.\nWe\'ll be expanding to your area soon!',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 14,
                color: isDark ? Colors.white54 : AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () async {
                    await showAddressPickerSheet(context);
                    if (mounted) {
                      _locationDebounceTimer?.cancel();
                      if (_selectedTabIndex < 0) {
                        _loadAllData();
                      } else {
                        _loadData(
                            _categories[_selectedTabIndex]['name']! as String);
                      }
                    }
                  },
                  icon: const Icon(Icons.edit_location_alt_rounded, size: 18),
                  label: Text(
                    'Change Location',
                    style: GoogleFonts.outfit(
                        fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    loc.requestLocation(isUserAction: true);
                  },
                  icon: const Icon(Icons.my_location_rounded, size: 18),
                  label: Text(
                    'Recheck GPS',
                    style: GoogleFonts.outfit(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor:
                        isDark ? Colors.white70 : AppColors.textPrimary,
                    side: BorderSide(
                      color: isDark ? Colors.white24 : Colors.black12,
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationRequired() {
    return AnimatedBuilder(
      animation: _locationGlowAnim,
      builder: (context, child) {
        return Container(
          key: _locationRequiredKey,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              if (_locationGlowAnim.value > 0)
                BoxShadow(
                  color: AppColors.primary
                      .withValues(alpha: 0.3 * _locationGlowAnim.value),
                  blurRadius: 15 * _locationGlowAnim.value,
                  spreadRadius: 5 * _locationGlowAnim.value,
                )
            ],
            border: Border.all(
              color:
                  AppColors.primary.withValues(alpha: _locationGlowAnim.value),
              width: 2 * _locationGlowAnim.value,
            ),
          ),
          child: child,
        );
      },
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('📍', style: TextStyle(fontSize: 72)),
              const SizedBox(height: 20),
              Text(
                'Location Required',
                style: GoogleFonts.outfit(
                    fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text(
                'We need your location to show nearby shops and ensure delivery is available.',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                    color: AppColors.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 28),
              ElevatedButton.icon(
                onPressed: () => context
                    .read<LocationProvider>()
                    .requestLocation(isUserAction: true),
                icon: const Icon(Icons.my_location),
                label: const Text('Enable Location'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _promptEnableLocation() {
    if (_locationRequiredKey.currentContext != null) {
      Scrollable.ensureVisible(
        _locationRequiredKey.currentContext!,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
    _locationGlowCtrl.forward(from: 0).then((_) {
      _locationGlowCtrl.reverse();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Please enable location to view nearby items.'),
        backgroundColor: AppColors.danger,
        duration: Duration(seconds: 3),
      ),
    );
  }

  Widget _buildShimmer() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? const Color(0xFF1A1A2E) : const Color(0xFFE8E8EE);
    final highlight =
        isDark ? const Color(0xFF26263A) : const Color(0xFFF4F4FA);
    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      child: Column(
        children: [
          const SizedBox(height: 8),
          // Banner skeleton
          Container(
            height: 190,
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
            ),
          ),
          // Card skeletons (restaurant-style)
          ...List.generate(
            2,
            (_) => Container(
              margin: const EdgeInsets.only(bottom: 24),
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                children: [
                  // Banner skeleton
                  Container(
                    height: 185,
                    decoration: BoxDecoration(
                      color: base,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Name bar
                        Container(
                            height: 18,
                            width: 200,
                            decoration: BoxDecoration(
                                color: base,
                                borderRadius: BorderRadius.circular(9))),
                        const SizedBox(height: 8),
                        // Cuisine chips
                        Row(
                          children: [
                            Container(
                                height: 22,
                                width: 70,
                                decoration: BoxDecoration(
                                    color: base,
                                    borderRadius: BorderRadius.circular(8))),
                            const SizedBox(width: 8),
                            Container(
                                height: 22,
                                width: 80,
                                decoration: BoxDecoration(
                                    color: base,
                                    borderRadius: BorderRadius.circular(8))),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Divider(color: base, height: 1),
                        const SizedBox(height: 12),
                        // Meta chips row
                        Row(
                          children: [
                            Container(
                                height: 28,
                                width: 80,
                                decoration: BoxDecoration(
                                    color: base,
                                    borderRadius: BorderRadius.circular(9))),
                            const SizedBox(width: 8),
                            Container(
                                height: 28,
                                width: 100,
                                decoration: BoxDecoration(
                                    color: base,
                                    borderRadius: BorderRadius.circular(9))),
                            const SizedBox(width: 8),
                            Container(
                                height: 28,
                                width: 60,
                                decoration: BoxDecoration(
                                    color: base,
                                    borderRadius: BorderRadius.circular(9))),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isFilterSheetOpen = false;
  void _showFilterSheet(BuildContext context, bool isDark) {
    if (_isFilterSheetOpen) return;
    _isFilterSheetOpen = true;

    // Cache available sizes if no size filter is currently active
    if (_selectedSizes.isEmpty) {
      _cachedAvailableSizes.clear();
      final productsToCheck =
          _searchQuery.isNotEmpty ? _searchProductResults : _products;
      for (final p in productsToCheck) {
        for (final v in p.variants) {
          if (v.name.trim().isNotEmpty && v.isAvailable) {
            _cachedAvailableSizes.add(v.name.trim());
          }
        }
      }
    }
    final sortedAvailableSizes = _cachedAvailableSizes.toList()..sort();

    // Create localized state copies to prevent desync on sheet dismissal
    final Set<String> tempSelectedSizes = Set.from(_selectedSizes);
    final Set<String> tempCategories = Set.from(_selectedFilterCategories);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(builder: (context, setSheetState) {
          bool isApplying = false;
          final catNames = AppCategories.names;
          return Container(
            padding: const EdgeInsets.all(24),
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Filters',
                        style: GoogleFonts.outfit(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black)),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Sort By',
                            style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color:
                                    isDark ? Colors.white70 : Colors.black54)),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildSortChip('Relevant', _SortMode.relevant,
                                setSheetState, isDark),
                            _buildSortChip('Nearest', _SortMode.nearest,
                                setSheetState, isDark),
                            _buildSortChip('Price: Low to High',
                                _SortMode.priceLow, setSheetState, isDark),
                            _buildSortChip('Price: High to Low',
                                _SortMode.priceHigh, setSheetState, isDark),
                            _buildSortChip('Best Rating', _SortMode.bestRating,
                                setSheetState, isDark),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Text('Categories',
                            style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color:
                                    isDark ? Colors.white70 : Colors.black54)),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: catNames.map((cat) {
                            final isSelected = tempCategories.contains(cat);
                            return ChoiceChip(
                              label: Text(cat),
                              selected: isSelected,
                              onSelected: (selected) {
                                setSheetState(() {
                                  if (selected) {
                                    tempCategories.add(cat);
                                  } else {
                                    tempCategories.remove(cat);
                                  }
                                });
                              },
                              selectedColor:
                                  AppColors.primary.withValues(alpha: 0.15),
                              backgroundColor: isDark
                                  ? const Color(0xFF2A2A3E)
                                  : Colors.grey.shade100,
                              labelStyle: TextStyle(
                                  color: isSelected
                                      ? AppColors.primary
                                      : (isDark
                                          ? Colors.white70
                                          : Colors.black)),
                              side: BorderSide(
                                  color: isSelected
                                      ? AppColors.primary
                                      : Colors.transparent),
                            );
                          }).toList(),
                        ),
                        if (sortedAvailableSizes.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          Text('Sizes',
                              style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.black54)),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: sortedAvailableSizes.map((size) {
                              final isSelected =
                                  tempSelectedSizes.contains(size);
                              return ChoiceChip(
                                label: Text(size),
                                selected: isSelected,
                                onSelected: (selected) {
                                  setSheetState(() {
                                    if (selected) {
                                      tempSelectedSizes.add(size);
                                    } else {
                                      tempSelectedSizes.remove(size);
                                    }
                                  });
                                },
                                selectedColor:
                                    AppColors.primary.withValues(alpha: 0.15),
                                backgroundColor: isDark
                                    ? const Color(0xFF2A2A3E)
                                    : Colors.grey.shade100,
                                labelStyle: TextStyle(
                                    color: isSelected
                                        ? AppColors.primary
                                        : (isDark
                                            ? Colors.white70
                                            : Colors.black)),
                                side: BorderSide(
                                    color: isSelected
                                        ? AppColors.primary
                                        : Colors.transparent),
                              );
                            }).toList(),
                          ),
                        ],
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () {
                      if (isApplying) return;
                      isApplying = true;

                      // Apply temp localized state to parent state
                      _selectedSizes.clear();
                      _selectedSizes.addAll(tempSelectedSizes);
                      _selectedFilterCategories.clear();
                      _selectedFilterCategories.addAll(tempCategories);

                      Navigator.pop(context);
                      setState(() {});
                      if (_searchQuery.isNotEmpty) {
                        _searchShops(_searchQuery, skipNLP: true);
                      } else {
                        if (_selectedTabIndex < 0) {
                          _loadAllData();
                        } else {
                          _loadData(_categories[_selectedTabIndex]['name']!
                              as String);
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text('Apply Filters',
                        style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                  ),
                ),
              ],
            ),
          );
        });
      },
    ).then((_) {
      _isFilterSheetOpen = false;
    });
  }

  Widget _buildSortChip(
      String label, _SortMode mode, StateSetter setSheetState, bool isDark) {
    final isSelected = _sortMode == mode;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setSheetState(() => _sortMode = mode);
          setState(() {
            _sortMode = mode;
            _invalidateSortMemo();
          });
        }
      },
      selectedColor: AppColors.primary,
      backgroundColor: isDark ? const Color(0xFF2A2A3E) : Colors.grey.shade100,
      labelStyle: TextStyle(
          color: isSelected
              ? Colors.white
              : (isDark ? Colors.white70 : Colors.black)),
      side: BorderSide(
          color: isSelected ? AppColors.primary : Colors.transparent),
    );
  }

  // ── Trending Now Auto-Marquee Strip ──────────────────────────────────────────
  // Purely additive UI — no SQL, no new state, reuses existing _searchShops().
  Widget _buildTrendingStrip(bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF512F), Color(0xFFF09819)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🔥', style: TextStyle(fontSize: 11)),
                      const SizedBox(width: 4),
                      Text(
                        'Trending',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Tap to search instantly',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    color: isDark ? Colors.white38 : Colors.black38,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Builder(builder: (context) {
            // Active list: DB-fetched trending OR static fallback if DB empty/error
            final activeKeywords = _dynamicTrendingKeywords.isNotEmpty
                ? _dynamicTrendingKeywords
                : _staticFallbackKeywords;
            return SizedBox(
              height: 36,
              child: ListView.builder(
                controller: _trendingScrollController,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                // Duplicate list for infinite loop illusion
                itemCount: activeKeywords.length * 2,
                itemBuilder: (context, index) {
                  final kw = activeKeywords[index % activeKeywords.length];
                  final label = kw['label'] as String;
                  final emoji = kw['emoji'] as String;
                  return GestureDetector(
                    onTap: () {
                      // Pause auto-scroll temporarily so user can see result
                      _trendingScrollTimer?.cancel();
                      _searchController.text = label;
                      _searchShops(label);
                      // Resume after 5 seconds
                      Future.delayed(const Duration(seconds: 5), () {
                        if (mounted) _startTrendingScroll();
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E2035) : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.grey.shade200,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: isDark
                                ? Colors.black.withValues(alpha: 0.25)
                                : Colors.black.withValues(alpha: 0.05),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(emoji, style: const TextStyle(fontSize: 13)),
                          const SizedBox(width: 5),
                          Text(
                            label,
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Colors.white70
                                  : const Color(0xFF2D3748),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          }),
        ],
      ),
    );
  }

  String _formatCategoryDisplayLabel(String name) {
    if (name == 'Supermarket / Hypermarket') return 'Supermarket\nHypermarket';
    if (name.contains(' & ')) {
      final parts = name.split(' & ');
      return '${parts[0]}\n& ${parts[1]}';
    }
    if (name.contains(' / ')) {
      final parts = name.split(' / ');
      return '${parts[0]}\n${parts[1]}';
    }
    return name;
  }

  // ── Shop by Category Section ────────────────────────────────────────────────
  // Primary department categories + a "See More" card, horizontally swipable.
  // Tap: filter home page in-place (same logic as old upper chips).
  // Long-press: navigate to dedicated CategoryProductsPage.
  Widget _buildCategorySection(bool isDark) {
    // Primary department categories (excluding 'More' which is represented by the dedicated See All card)
    final mainCats = _categories.where((c) => c['name'] != 'More').toList();
    final config = context.read<PlatformConfigProvider>();
    final activeCount = config.activeCategoryMaps.length;
    final remainingCount = math.max(0, activeCount - mainCats.length);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
          'Explore Categories',
          subtitle: _selectedTabIndex >= 0
              ? 'Filtering feed • Tap again to show all'
              : 'Tap to filter feed • Hold to view catalog',
          onSeeAllTap: () =>
              Navigator.pushNamed(context, AppRoutes.allCategories),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 116,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 2),
            // +1 for the "See More" card
            itemCount: mainCats.length + 1,
            itemBuilder: (context, index) {
              // ── "See More" card (last item) ────────────────────────────────
              if (index == mainCats.length) {
                return PerspectiveCard(
                  enableHaptics: false,
                  borderRadius: 22,
                  maxTiltAngle: 0.08,
                  pressScale: 0.95,
                  onTap: () {
                    SensoryHaptics.light();
                    Navigator.pushNamed(context, AppRoutes.allCategories);
                  },
                  child: Container(
                    width: 90,
                    margin: const EdgeInsets.only(right: 10, top: 2, bottom: 4),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF16192B)
                          : const Color(0xFFF4F6FB),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.12)
                            : AppColors.primary.withValues(alpha: 0.20),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isDark
                              ? Colors.black.withValues(alpha: 0.35)
                              : AppColors.primary.withValues(alpha: 0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        // Subtle gradient accent aura in corner
                        Positioned(
                          top: -15,
                          right: -15,
                          child: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.primary.withValues(alpha: 0.12),
                            ),
                          ),
                        ),
                        Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      AppColors.primary,
                                      AppColors.primaryDark,
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primary
                                          .withValues(alpha: 0.35),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.grid_view_rounded,
                                  size: 19,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'See All',
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: isDark
                                      ? Colors.white
                                      : AppColors.textPrimary,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 2),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primary
                                      .withValues(alpha: isDark ? 0.22 : 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '+$remainingCount More',
                                  style: GoogleFonts.outfit(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? AppColors.primaryLight
                                        : AppColors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              // ── Main category card ─────────────────────────────────────────
              final cat = mainCats[index];
              final grad = cat['grad'] as List<Color>;
              final catName = cat['name'] as String;
              final displayLabel = _formatCategoryDisplayLabel(catName);
              final imageUrl = AppCategories.getImageUrl(catName);
              final isSelected = _selectedTabIndex == index;

              return PerspectiveCard(
                enableHaptics: false,
                borderRadius: 22,
                maxTiltAngle: 0.08,
                pressScale: 0.95,
                // Tap: filter home page in-place (same exact logic as old upper chips)
                onTap: () {
                  SensoryHaptics.light();
                  if (!context.read<LocationProvider>().hasLocation) {
                    _promptEnableLocation();
                    return;
                  }
                  if (_selectedTabIndex == index) {
                    // Toggle off: already selected → reset to all
                    setState(() {
                      _selectedTabIndex = -1;
                      _selectedFeedDemographic = 'All';
                    });
                    _loadAllData();
                  } else {
                    // Select: filter by this category
                    setState(() {
                      _selectedTabIndex = index;
                      _selectedFeedDemographic = 'All';
                    });
                    _loadData(catName);
                  }
                },
                // Long-press: navigate to dedicated full category page
                onLongPress: () {
                  SensoryHaptics.medium();
                  if (!context.read<LocationProvider>().hasLocation) {
                    _promptEnableLocation();
                    return;
                  }
                  Navigator.pushNamed(
                    context,
                    AppRoutes.categoryProducts,
                    arguments: {'categoryName': catName},
                  );
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  width: isSelected ? 96 : 90,
                  margin: const EdgeInsets.only(right: 10, top: 2, bottom: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    // Selected state: vibrant ambient halo glow
                    boxShadow: [
                      BoxShadow(
                        color: isSelected
                            ? grad.first.withValues(alpha: 0.55)
                            : isDark
                                ? Colors.black.withValues(alpha: 0.30)
                                : Colors.black.withValues(alpha: 0.08),
                        blurRadius: isSelected ? 16 : 10,
                        offset: Offset(0, isSelected ? 6 : 3),
                      ),
                    ],
                    border: Border.all(
                      color: isSelected
                          ? Colors.white
                          : isDark
                              ? Colors.white.withValues(alpha: 0.09)
                              : Colors.black.withValues(alpha: 0.05),
                      width: isSelected ? 2.5 : 1.0,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(isSelected ? 19.5 : 21),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Background Hero Photo
                        CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          memCacheWidth: 300,
                          maxWidthDiskCache: 600,
                          fadeInDuration: const Duration(milliseconds: 250),
                          placeholder: (context, url) => Container(
                            color: grad.first.withValues(alpha: 0.25),
                            child: Center(
                              child: Text(
                                cat['emoji'] as String? ?? '🏬',
                                style: const TextStyle(fontSize: 24),
                              ),
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: grad,
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                cat['emoji'] as String? ?? '🏬',
                                style: const TextStyle(fontSize: 26),
                              ),
                            ),
                          ),
                        ),

                        // High-contrast gradient scrim (Clear top, deep elegant glass bottom)
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.black.withValues(alpha: 0.05),
                                Colors.black.withValues(alpha: 0.35),
                                Colors.black.withValues(alpha: 0.88),
                              ],
                              stops: const [0.0, 0.45, 1.0],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),

                        // Selected checkmark badge & active indicator ring
                        if (isSelected)
                          Positioned(
                            top: 6,
                            left: 6,
                            child: Container(
                              padding: const EdgeInsets.all(3.5),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.3),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.check_rounded,
                                size: 11,
                                color: grad.first,
                              ),
                            ),
                          ),

                        // Category Label + Emoji Micro-avatar
                        Positioned.fill(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.bottomCenter,
                                  child: Text(
                                    displayLabel,
                                    style: GoogleFonts.outfit(
                                      fontSize: 11.5,
                                      fontWeight: isSelected
                                          ? FontWeight.w900
                                          : FontWeight.w800,
                                      color: Colors.white,
                                      height: 1.12,
                                      shadows: [
                                        Shadow(
                                          color: Colors.black
                                              .withValues(alpha: 0.6),
                                          blurRadius: 4,
                                          offset: const Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                    maxLines: 2,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                if (isSelected) ...[
                                  const SizedBox(height: 3),
                                  Container(
                                    width: 14,
                                    height: 3,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}
