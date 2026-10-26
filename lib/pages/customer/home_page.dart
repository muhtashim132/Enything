import 'dart:async';
import 'dart:io';
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
import '../../utils/responsive_layout.dart';
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

  @override
  State<CustomerHomeView> createState() => CustomerHomeViewState();
}

enum _SortMode { relevant, bestRating, priceLow, priceHigh, discount, nearest }

class CustomerHomeViewState extends State<CustomerHomeView>
    with SingleTickerProviderStateMixin {
  static final ValueNotifier<bool> globalIsFiltering = ValueNotifier(false);

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
  int _searchProductsDisplayLimit = 10;
  List<ShopModel> _shops = [];
  List<ShopModel> _searchResults = [];
  List<ProductModel> _searchProductResults = [];
  Map<String, ShopModel> _searchProductShops = {};
  List<ProductModel> _products = [];
  Map<String, ShopModel> _productShops = {};
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
      'milk',
      'bread',
      'eggs',
      'supermarket',
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
    'More': [
      'cosmetics',
      'cosmetic',
      'makeup',
      'beauty',
      'skincare',
      'skin care',
      'lipstick',
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
      'shampoo',
      'conditioner',
      'perfume',
      'deodorant',
      'body spray',
      'nail polish',
      'stationery',
      'notebook',
      'pen',
      'pencil',
      'toys',
      'games',
      'sports',
      'pet supplies',
      'flowers',
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
  List<ProductModel>? _memoizedSortedGroceryProducts;
  List<ProductModel>? _memoizedSortedPharmacyProducts;
  List<ProductModel>? _memoizedSortedClothingProducts;
  List<ShopModel>? _memoizedSortedShopResults;
  List<ShopModel>? _memoizedSortedNormalShops;

  void _invalidateSortMemo() {
    _memoizedSortedProductResults = null;
    _memoizedSortedNormalProducts = null;
    _memoizedSortedGroceryProducts = null;
    _memoizedSortedPharmacyProducts = null;
    _memoizedSortedClothingProducts = null;
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
          return 0; // Maintain original order
      }
    });
    return list;
  }

  /// 100x Demographic matcher for feed items (Men/Boys & Women/Girls)
  bool _matchesDemographic(ProductModel product, String demographic) {
    if (demographic == 'All') return true;

    final tags = product.specialTags
        .map((t) => t.trim().toLowerCase().replaceAll('#', ''))
        .toList();

    if (demographic == 'Men/Boys') {
      // 1. Direct positive tag matches
      final hasMenTag = tags.any((t) =>
          t == 'men' ||
          t == 'boys' ||
          t == 'boy' ||
          t == 'kids' ||
          t == 'unisex');
      if (hasMenTag) return true;

      // 2. Strict negative tag matches: if explicitly tagged for Women/Girls, reject
      final hasWomenTag = tags.any((t) =>
          t == 'women' ||
          t == 'girls' ||
          t == 'girl');
      if (hasWomenTag) return false;

      // 3. Fallback to name & description keyword analysis for untagged items
      final text = '${product.name} ${product.description}'.toLowerCase();
      // Block if text clearly mentions women/girls
      if (RegExp(r"\b(women|womens|women's|girls|girl's|ladies|lady|female|kurti|saree|lehenga|bra|makeup)\b").hasMatch(text)) {
        return false;
      }
      return RegExp(r"\b(men|mens|men's|boy|boys|boy's|gent|gents|gent's|male)\b").hasMatch(text);
    } else if (demographic == 'Women/Girls') {
      // 1. Direct positive tag matches
      final hasWomenTag = tags.any((t) =>
          t == 'women' ||
          t == 'girls' ||
          t == 'girl' ||
          t == 'kids' ||
          t == 'unisex');
      if (hasWomenTag) return true;

      // 2. Strict negative tag matches: if explicitly tagged for Men/Boys, reject
      final hasMenTag = tags.any((t) =>
          t == 'men' ||
          t == 'boys' ||
          t == 'boy');
      if (hasMenTag) return false;

      // 3. Fallback to name & description keyword analysis for untagged items
      final text = '${product.name} ${product.description}'.toLowerCase();
      // Block if text clearly mentions men/boys
      if (RegExp(r"\b(men|mens|men's|boys|boy's|gents|gent's|male)\b").hasMatch(text)) {
        return false;
      }
      return RegExp(r"\b(women|womens|women's|girl|girls|girl's|ladies|lady|female|kurti|saree|lehenga|dress|beauty|cosmetics)\b").hasMatch(text);
    }

    return true;
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
    final lowerTargets =
        targetCategories.map((c) => c.trim().toLowerCase()).toSet();
    var list = _products.where((p) {
      return lowerTargets.contains(p.category.trim().toLowerCase());
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

  /// Returns normal products filtered for Grocery & Daily Essentials (immune to clothing demographic filter)
  List<ProductModel> get _sortedGroceryProducts {
    if (_memoizedSortedGroceryProducts != null) {
      return _memoizedSortedGroceryProducts!;
    }
    _memoizedSortedGroceryProducts = _computeSortedCategoryProducts(
      _tabCategories['Grocery'] ?? [],
      applyDemographic: false,
    );
    return _memoizedSortedGroceryProducts!;
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

    list.sort((a, b) {
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
        Timer.periodic(const Duration(milliseconds: 30), (_) {
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
      _searchProductsDisplayLimit = 10;
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
      final List<String> terms = cleanQuery
          .toLowerCase()
          .split(RegExp(r'\s+'))
          .where((t) => t.isNotEmpty)
          .toList();
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
          effectiveCategories.addAll(subs.where((c) => config.isActiveCategory(c)));
        }
      } else {
        effectiveCategories = config.activeCategoryNames;
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
          rethrow;
        }

        // Phase 26 Fix: Fetch products without .select('*, shops(*)')  which
        // causes PostgREST to reject embedded-resource requests on SETOF RPCs.
        // Instead, we batch-fetch shops separately and reconstruct the map.
        debugPrint(
            '[Search] Step 2/4: search_products_geospatial (byName) BYPASS q="$query"');
        List<dynamic> rawProductsByName = [];
        try {
          // Offload geospatial ST_DWithin and ST_Distance to the working shops RPC
          final nearbyShops =
              await _supabase.rpc('search_shops_geospatial', params: {
            'p_lat': lat,
            'p_lng': lng,
            'p_query': null, // All shops in radius to search their products
            'p_categories': effectiveCategories,
            'p_radius_km': maxRadius,
            'p_limit': 150
          });

          final shopIds =
              (nearbyShops as List).map((s) => s['id'] as String).toList();

          if (shopIds.isNotEmpty) {
            var q = _supabase
                .from('products')
                .select()
                .eq('is_deleted', false)
                .eq('is_available', true)
                .inFilter('shop_id', shopIds);

            for (final term in terms) {
              q = q.or(
                'name.ilike.%$term%,description.ilike.%$term%,brand.ilike.%$term%,category.ilike.%$term%,menu_category.ilike.%$term%,sub_category.ilike.%$term%',
              );
            }

            final allProducts = await q;

            // Pre-truncation Local Size & Demographic Filter (Avoids PostgREST JSONB operator mismatch)
            final filteredProducts = allProducts.where((p) {
              if (terms.isNotEmpty) {
                final searchable =
                    '${p['name']} ${p['description'] ?? ''} ${p['brand'] ?? ''} ${p['category'] ?? ''} ${p['sub_category'] ?? ''} ${p['menu_category'] ?? ''} ${p['medicine_type'] ?? ''}'
                        .toLowerCase();
                if (!terms.every((t) => searchable.contains(t))) return false;
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
                final tagsRaw = p['special_tags'];
                final List<String> tags = (tagsRaw is List)
                    ? tagsRaw.map((t) => t.toString().trim()).toList()
                    : [];
                final targetTag = '#$_selectedSearchDemographic';
                final allowedTags = <String>[targetTag, '#Unisex'];
                if (_selectedSearchDemographic == 'Boys' ||
                    _selectedSearchDemographic == 'Girls') {
                  allowedTags.add('#Kids');
                } else if (_selectedSearchDemographic == 'Kids') {
                  allowedTags.addAll(['#Boys', '#Girls']);
                }
                final matchesDemographic =
                    tags.any((t) => allowedTags.contains(t));
                if (!matchesDemographic) return false;
              }

              return true;
            }).toList();

            // Group, sort by rating, limit 5 per shop
            final productsByShop = <String, List<dynamic>>{};
            for (final p in filteredProducts) {
              final sid = p['shop_id'] as String;
              productsByShop.putIfAbsent(sid, () => []).add(p);
            }

            // Iterate through sorted shops to maintain distance ordering
            for (final shop in nearbyShops) {
              final sid = shop['id'] as String;
              if (productsByShop.containsKey(sid)) {
                final shopProds = productsByShop[sid]!;
                shopProds.sort((a, b) {
                  final ratingA = (a['rating'] as num?)?.toDouble() ?? 0.0;
                  final ratingB = (b['rating'] as num?)?.toDouble() ?? 0.0;
                  return ratingB.compareTo(ratingA);
                });
                rawProductsByName.addAll(shopProds.take(5));
                if (rawProductsByName.length >= 50) break;
              }
            }
            if (rawProductsByName.length > 50) {
              rawProductsByName = rawProductsByName.sublist(0, 50);
            }
          }
          debugPrint(
              '[Search] Step 2/4 OK: ${rawProductsByName.length} products found');
        } catch (e) {
          debugPrint('[Search] Step 2/4 FAILED (byName bypass): $e');
          rethrow;
        }

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
              'p_limit': 50
            });
            debugPrint(
                '[Search] Step 3/4 OK: ${shopsByCat.length} shops found');
          } catch (e) {
            debugPrint(
                '[Search] Step 3/4 FAILED (search_shops_geospatial byCat): $e');
            rethrow;
          }

          debugPrint(
              '[Search] Step 4/4: search_products_geospatial (byCat) BYPASS cats=$matchedSubcategories');
          try {
            // Leverage shopsByCat from Step 3 which is already distance sorted
            final shopIds = shopsByCat.map((s) => s['id'] as String).toList();

            if (shopIds.isNotEmpty) {
              final allProducts = await _supabase
                  .from('products')
                  .select()
                  .eq('is_deleted', false)
                  .eq('is_available', true)
                  .inFilter('shop_id', shopIds);

              // Pre-truncation Local Size & Demographic Filter (Avoids PostgREST JSONB operator mismatch)
              final filteredProducts = allProducts.where((p) {
                if (terms.isNotEmpty) {
                  final searchable =
                      '${p['name']} ${p['description'] ?? ''} ${p['brand'] ?? ''} ${p['category'] ?? ''} ${p['sub_category'] ?? ''} ${p['menu_category'] ?? ''} ${p['medicine_type'] ?? ''}'
                          .toLowerCase();
                  if (!terms.every((t) => searchable.contains(t))) return false;
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
                  final tagsRaw = p['special_tags'];
                  final List<String> tags = (tagsRaw is List)
                      ? tagsRaw.map((t) => t.toString().trim()).toList()
                      : [];
                  final targetTag = '#$_selectedSearchDemographic';
                  final allowedTags = <String>[targetTag, '#Unisex'];
                  if (_selectedSearchDemographic == 'Boys' ||
                      _selectedSearchDemographic == 'Girls') {
                    allowedTags.add('#Kids');
                  } else if (_selectedSearchDemographic == 'Kids') {
                    allowedTags.addAll(['#Boys', '#Girls']);
                  }
                  final matchesDemographic =
                      tags.any((t) => allowedTags.contains(t));
                  if (!matchesDemographic) return false;
                }

                return true;
              }).toList();

              final productsByShop = <String, List<dynamic>>{};
              for (final p in filteredProducts) {
                final sid = p['shop_id'] as String;
                productsByShop.putIfAbsent(sid, () => []).add(p);
              }

              for (final shop in shopsByCat) {
                final sid = shop['id'] as String;
                if (productsByShop.containsKey(sid)) {
                  final shopProds = productsByShop[sid]!;
                  shopProds.sort((a, b) {
                    final ratingA = (a['rating'] as num?)?.toDouble() ?? 0.0;
                    final ratingB = (b['rating'] as num?)?.toDouble() ?? 0.0;
                    return ratingB.compareTo(ratingA);
                  });
                  rawProductsByCat.addAll(shopProds.take(5));
                  if (rawProductsByCat.length >= 100) break;
                }
              }
              if (rawProductsByCat.length > 100) {
                rawProductsByCat = rawProductsByCat.sublist(0, 100);
              }
            }
            debugPrint(
                '[Search] Step 4/4 OK: ${rawProductsByCat.length} products found');
          } catch (e) {
            debugPrint('[Search] Step 4/4 FAILED (byCat bypass): $e');
            rethrow;
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

        // Single batch query for all shops referenced by the product results.
        final Map<String, Map<String, dynamic>> shopById = {};
        if (productShopIds.isNotEmpty) {
          debugPrint(
              '[Search] Batch-fetching ${productShopIds.length} shop(s) for product results');
          final shopRows = await _supabase
              .from('shops')
              .select('*')
              .inFilter('id', productShopIds.toList());
          for (final s in shopRows as List) {
            final sm = s as Map<String, dynamic>;
            shopById[sm['id'] as String] = sm;
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
          if (!shop.isActive || !config.isActiveCategory(shop.category)) continue;
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

      if (mounted) {
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
      'Bakery',
      'Sweets & Mithai',
      'Tea & Coffee',
      'Ice Cream',
      'Paan Shop',
      'Beverages'
    ],
    'Grocery': [
      'Grocery',
      'Supermarket / Hypermarket',
      'Fruits & Vegs',
      'Dairy & Eggs',
      'Butcher',
      'Fish & Seafood',
      'Organic'
    ],
    'Pharmacy': ['Pharmacy', 'Medical Store'],
    'GroceryAndMed': [
      'Grocery',
      'Supermarket / Hypermarket',
      'Fruits & Vegs',
      'Dairy & Eggs',
      'Butcher',
      'Fish & Seafood',
      'Organic',
      'Pharmacy',
      'Medical Store'
    ],
    'Clothing': ['Clothing', 'Footwear', 'Jewellery'],
    'Electronics': ['Electronics', 'Mobile & Repair'],
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

  /// Fetch ALL active shops & products, sorted by rating then total_orders.
  /// Used on initial load when no category tab is selected.
  Future<void> _loadAllData() async {
    final currentFetchId = ++_fetchId;
    _isFetching = true;

    // Only show the shimmer on the very first load. On subsequent loads
    // (e.g., GPS update or category deselect) keep old data visible.
    if (!_hasLoadedOnce) {
      setState(() => _isLoading = true);
    }
    try {
      final locationProvider = context.read<LocationProvider>();
      final config = context.read<PlatformConfigProvider>();

      List<String> effectiveCategories = [];
      if (_selectedFilterCategories.isNotEmpty) {
        for (final cat in _selectedFilterCategories) {
          final subs = _tabCategories[cat] ?? [cat];
          effectiveCategories.addAll(subs.where((c) => config.isActiveCategory(c)));
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

      // Stratified Diverse Category Selection: Sample across Pharmacy, Grocery, Clothing, Food & other
      // to ensure all dedicated dashboard sections have rich product discovery without starving any category.
      bool isShopInCategories(ShopModel s, List<String> targetCats) {
        final lowerTargets =
            targetCats.map((c) => c.trim().toLowerCase()).toSet();
        if (lowerTargets.contains(s.category.trim().toLowerCase())) return true;
        return s.categories
            .any((c) => lowerTargets.contains(c.trim().toLowerCase()));
      }

      final pharmacyShops = nearby
          .where((s) => isShopInCategories(s, _tabCategories['Pharmacy'] ?? []))
          .take(15);
      final groceryShops = nearby
          .where((s) => isShopInCategories(s, _tabCategories['Grocery'] ?? []))
          .take(15);
      final clothingShops = nearby
          .where((s) => isShopInCategories(s, _tabCategories['Clothing'] ?? []))
          .take(15);
      final otherShops = nearby
          .where((s) =>
              !isShopInCategories(s, _tabCategories['Pharmacy'] ?? []) &&
              !isShopInCategories(s, _tabCategories['Grocery'] ?? []) &&
              !isShopInCategories(s, _tabCategories['Clothing'] ?? []))
          .take(25);

      final diverseShopIds = <String>{};
      for (final s in pharmacyShops) {
        diverseShopIds.add(s.id);
      }
      for (final s in groceryShops) {
        diverseShopIds.add(s.id);
      }
      for (final s in clothingShops) {
        diverseShopIds.add(s.id);
      }
      for (final s in otherShops) {
        diverseShopIds.add(s.id);
      }

      for (final s in nearby) {
        if (diverseShopIds.length >= 70) break;
        diverseShopIds.add(s.id);
      }

      final productsResponse = diverseShopIds.isEmpty
          ? []
          : await _supabase.rpc('get_feed_products', params: {
              'p_shop_ids': diverseShopIds.toList(),
              'p_limit_per_shop': 5,
              'p_categories': effectiveCategories,
            }).select('*, shops(*)');

      if (mounted) {
        final prods = <ProductModel>[];
        final prodShops = <String, ShopModel>{};

        for (final p in productsResponse) {
          final product = ProductModel.fromMap(p);
          if (!effectiveCategories.contains(product.category) ||
              !config.isActiveCategory(product.category)) {
            continue;
          }
          if (p['shops'] == null) continue;

          final shop = ShopModel.fromMap(p['shops']);
          if (!shop.isActive || !config.isActiveCategory(shop.category)) continue;

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
        // Atomic update: swap data and clear loading in a single setState
        setState(() {
          _shopsDisplayLimit = 3;
          _productsDisplayLimit = 6;
          _shops = nearby;
          _products = prods;
          _productShops = prodShops;
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
          effectiveCategories.addAll(subs.where((c) => config.isActiveCategory(c)));
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

      final productsResponse = nearbyShopIds.isEmpty
          ? []
          : await _supabase.rpc('get_feed_products', params: {
              'p_shop_ids': nearbyShopIds,
              'p_limit_per_shop': 5,
              'p_categories': finalCategories,
            }).select('*, shops(*)');

      if (mounted) {
        final prods = <ProductModel>[];
        final prodShops = <String, ShopModel>{};

        for (final p in productsResponse) {
          final product = ProductModel.fromMap(p);
          if (!effectiveCategories.contains(product.category) ||
              !config.isActiveCategory(product.category)) {
            continue;
          }
          if (p['shops'] == null) continue;

          final shop = ShopModel.fromMap(p['shops']);
          if (!shop.isActive || !config.isActiveCategory(shop.category)) continue;

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
                                  onTap: () => showAddressPickerSheet(context),
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
                                                  ? locationProvider
                                                          .currentAddress
                                                          .isNotEmpty
                                                      ? locationProvider
                                                          .currentAddress
                                                      : 'Current Location'
                                                  : 'Set location...',
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
                                    if (v.trim().isNotEmpty) {
                                      setState(() {
                                        _searchQuery = v;
                                        _isSearching = true;
                                      });
                                    }
                                    _searchDebounce = Timer(
                                      const Duration(milliseconds: 350),
                                      () => _searchShops(v),
                                    );
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
                                if (_searchController.text.isEmpty)
                                  Positioned(
                                    left: 44,
                                    right: 48,
                                    child: IgnorePointer(
                                      child: AnimatedSearchTicker(
                                        textStyle: GoogleFonts.outfit(
                                          color: isDark
                                              ? Colors.grey.shade400
                                              : Colors.grey.shade500,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
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
                if (!config.isMaintenanceMode) return const SliverToBoxAdapter(child: SizedBox.shrink());
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isDark
                              ? [const Color(0xFF78350F), const Color(0xFF92400E)]
                              : [const Color(0xFFFEF3C7), const Color(0xFFFDE68A)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.4 : 0.5),
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
                                    color: isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  config.maintenanceMessage,
                                  style: GoogleFonts.outfit(
                                    fontSize: 12,
                                    color: isDark ? const Color(0xFFFEF3C7) : const Color(0xFF78350F),
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
            // ── Main Content ──────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
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
                                itemCount: _sortedProductResults.length >
                                        _searchProductsDisplayLimit
                                    ? _searchProductsDisplayLimit
                                    : _sortedProductResults.length,
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
                              if (_sortedProductResults.length >
                                  _searchProductsDisplayLimit)
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                        top: 8, bottom: 8),
                                    child: Center(
                                      child: TextButton(
                                        onPressed: () => setState(() =>
                                            _searchProductsDisplayLimit += 20),
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 24, vertical: 12),
                                          backgroundColor: isDark
                                              ? Colors.white
                                                  .withValues(alpha: 0.05)
                                              : AppColors.primary
                                                  .withValues(alpha: 0.05),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(20)),
                                        ),
                                        child: Text(
                                          'Load more items',
                                          style: GoogleFonts.outfit(
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 16)),
                            ],

                            // Shops below products
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
                                      Text('Shops & Restaurants',
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
                                        child: Text('${_sortedShopResults.length}',
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
                                itemCount: _sortedShopResults.length >
                                        _searchShopsDisplayLimit
                                    ? _searchShopsDisplayLimit
                                    : _sortedShopResults.length,
                                itemBuilder: (context, index) {
                                  final shop = _sortedShopResults[index];
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
                                                onTap: () => showShopDetailSheet(
                                                    context, shop.id)),
                                      ),
                                    ),
                                  );
                                },
                              ),
                              if (_sortedShopResults.length >
                                  _searchShopsDisplayLimit)
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                        top: 8, bottom: 8),
                                    child: Center(
                                      child: TextButton(
                                        onPressed: () => setState(() =>
                                            _searchShopsDisplayLimit += 20),
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 24, vertical: 12),
                                          backgroundColor: isDark
                                              ? Colors.white
                                                  .withValues(alpha: 0.05)
                                              : AppColors.primary
                                                  .withValues(alpha: 0.05),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(20)),
                                        ),
                                        child: Text(
                                          'Load more shops',
                                          style: GoogleFonts.outfit(
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ],

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
                                      height: 280,
                                      child: ListView.builder(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: availableRecent.length,
                                        itemBuilder: (_, index) {
                                          final p = availableRecent[index];
                                          final shop = _productShops[p.id];
                                          return SizedBox(
                                            width: 148,
                                            child: Padding(
                                              padding: const EdgeInsets.only(
                                                  right: 12),
                                              child: ProductCard(
                                                  product: p, shop: shop),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                  ],
                                );
                              }),
                            ),

                          if (_shops.isNotEmpty) ...[
                            // ── Normal category browse ───────────────────
                            SliverToBoxAdapter(
                              child: _buildSectionTitle(
                                _selectedTabIndex < 0
                                    ? 'Stores near you'
                                    : _isFoodTab
                                        ? 'Restaurants near you'
                                        : _selectedFeedDemographic == 'Men/Boys'
                                            ? 'Men & Boys Stores'
                                            : (_selectedFeedDemographic == 'Women/Girls'
                                                ? 'Women & Girls Stores'
                                                : 'Shops near you'),
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
                                  label: _isFoodTab
                                      ? 'See all restaurants'
                                      : 'See all stores',
                                  onTap: () => Navigator.pushNamed(
                                    context,
                                    AppRoutes.allListings,
                                    arguments: {
                                      'type': _isFoodTab
                                          ? ListingType.restaurants
                                          : ListingType.shops,
                                      'shops': List<ShopModel>.from(
                                          _sortedNormalShops),
                                      'sectionTitle': _selectedTabIndex < 0
                                          ? 'Stores Near You'
                                          : _isFoodTab
                                              ? 'All Restaurants'
                                              : 'All Shops',
                                    },
                                  ),
                                  isDark: isDark,
                                ),
                              ),
                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 8)),
                            ],
                          ] else if (!_isLoading &&
                              _selectedTabIndex < 0 &&
                              _selectedFilterCategories.isEmpty) ...[
                            SliverToBoxAdapter(
                              child: locationProvider.hasLocation
                                  ? _buildNoShopsNearby()
                                  : _buildLocationRequired(),
                            ),
                          ],

                          // Products Section
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
                                _selectedFeedDemographic == 'Men/Boys'
                                    ? 'Popular for Men & Boys'
                                    : (_selectedFeedDemographic == 'Women/Girls'
                                        ? 'Popular for Women & Girls'
                                        : 'Popular in your area'),
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
                                  final childAspectRatio = itemWidth / itemHeight;
                                  final displayProducts = _sortedNormalProducts
                                      .take(_productsDisplayLimit)
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
                                  label: 'See all popular items',
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
                                      'sectionTitle':
                                          _selectedFeedDemographic == 'Men/Boys'
                                              ? 'Popular for Men & Boys'
                                              : (_selectedFeedDemographic ==
                                                      'Women/Girls'
                                                  ? 'Popular for Women & Girls'
                                                  : 'Popular in Your Area'),
                                    },
                                  ),
                                  isDark: isDark,
                                ),
                              ),
                            ],

                            // ── Dedicated Department Category Showcases ────
                            if (_selectedTabIndex < 0) ...[
                              // 1. Daily Grocery & Essentials
                              if (_sortedGroceryProducts.isNotEmpty) ...[
                                const SliverToBoxAdapter(
                                    child: SizedBox(height: 24)),
                                SliverToBoxAdapter(
                                  child: _buildDepartmentSectionHeader(
                                    title: 'Daily Grocery & Essentials',
                                    subtitle:
                                        'Fresh staples, veggies & daily needs near you',
                                    emoji: '🛒',
                                    count: _sortedGroceryProducts.length,
                                    accentGradient: const [
                                      Color(0xFF00B074),
                                      Color(0xFF10B981),
                                    ],
                                    onSeeAllTap: () => _openCategoryListing(
                                      title: 'Daily Grocery & Essentials',
                                      products: _sortedGroceryProducts,
                                      categories:
                                          _tabCategories['Grocery'] ?? [],
                                    ),
                                    isDark: isDark,
                                  ),
                                ),
                                const SliverToBoxAdapter(
                                    child: SizedBox(height: 14)),
                                SliverToBoxAdapter(
                                  child: _buildCategoryHorizontalCarousel(
                                    products: _sortedGroceryProducts,
                                    sectionTitle: 'Grocery',
                                    onViewAllTap: () => _openCategoryListing(
                                      title: 'Daily Grocery & Essentials',
                                      products: _sortedGroceryProducts,
                                      categories:
                                          _tabCategories['Grocery'] ?? [],
                                    ),
                                    isDark: isDark,
                                  ),
                                ),
                              ],

                              // 2. Medicines & Healthcare
                              if (_sortedPharmacyProducts.isNotEmpty) ...[
                                const SliverToBoxAdapter(
                                    child: SizedBox(height: 24)),
                                SliverToBoxAdapter(
                                  child: _buildDepartmentSectionHeader(
                                    title: 'Medicines & Healthcare',
                                    subtitle:
                                        'Prescription drugs, vitamins & wellness',
                                    emoji: '💊',
                                    count: _sortedPharmacyProducts.length,
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

                              // 3. Clothing & Fashion
                              if (_sortedClothingProducts.isNotEmpty) ...[
                                const SliverToBoxAdapter(
                                    child: SizedBox(height: 24)),
                                SliverToBoxAdapter(
                                  child: _buildDepartmentSectionHeader(
                                    title: 'Clothing & Fashion',
                                    subtitle:
                                        'Trending styles, apparel & accessories',
                                    emoji: '👕',
                                    count: _sortedClothingProducts.length,
                                    accentGradient: const [
                                      Color(0xFF8B5CF6),
                                      Color(0xFFEC4899),
                                    ],
                                    onSeeAllTap: () => _openCategoryListing(
                                      title: 'Clothing & Fashion',
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
                                      title: 'Clothing & Fashion',
                                      products: _sortedClothingProducts,
                                      categories:
                                          _tabCategories['Clothing'] ?? [],
                                    ),
                                    isDark: isDark,
                                  ),
                                ),
                              ],
                            ],
                          ] else if (_shops.isNotEmpty && !_isLoading) ...[
                            // ── "Popular in your area" empty state ──────────────
                            // Shows when shops exist but no products returned yet.
                            // This prevents the section from silently disappearing.
                            const SliverToBoxAdapter(
                                child: SizedBox(height: 8)),
                            SliverToBoxAdapter(
                              child: _buildSectionTitle('Popular in your area'),
                            ),
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 28, horizontal: 20),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 64,
                                        height: 64,
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? AppColors.primary
                                                  .withValues(alpha: 0.12)
                                              : AppColors.primary
                                                  .withValues(alpha: 0.07),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Icon(
                                          Icons.storefront_outlined,
                                          size: 30,
                                          color: isDark
                                              ? AppColors.primaryLight
                                              : AppColors.primary,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'No popular items right now',
                                        style: GoogleFonts.outfit(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: isDark
                                              ? Colors.white70
                                              : AppColors.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Check back soon — shops near you will list their popular items here.',
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.outfit(
                                          fontSize: 13,
                                          color: isDark
                                              ? Colors.white38
                                              : AppColors.textSecondary,
                                          height: 1.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ] else if (_comingSoonMessage != null &&
                              !_isLoading) ...[
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
                          ] else if (_shops.isEmpty &&
                              (_selectedTabIndex >= 0 ||
                                  _selectedFilterCategories.isNotEmpty) &&
                              !_isLoading) ...[
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
                                        icon: const Icon(Icons.storefront_rounded, size: 18),
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
                          ],
                          SliverToBoxAdapter(
                            child: SizedBox(
                              height: 120 + MediaQuery.paddingOf(context).bottom,
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
        if (_hasFoodItemsInSearch)
          _buildDietaryFilterRow(isDark),
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
              children: ['All', 'Men', 'Women', 'Boys', 'Girls', 'Kids']
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
      margin: const EdgeInsets.only(top: 16, bottom: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF281838), const Color(0xFF1B2338)]
              : [const Color(0xFFFFF4EB), const Color(0xFFF3E8FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF8E24AA).withValues(alpha: 0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.purple.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            Navigator.pushNamed(context, AppRoutes.bulkOrderDiscovery);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFF8E24AA).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Center(
                    child: Text('🎉', style: TextStyle(fontSize: 26)),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Host an Event or Party?',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF8E24AA).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'NEW',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF8E24AA),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Order 20 to 500+ items with tiered discounts & guaranteed kitchen slots.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark ? Colors.white70 : Colors.grey[700],
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF8E24AA)),
              ],
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
      final totalAmount = (activeOrder['total_amount'] as num?)?.toDouble() ?? 0.0;
      final deliveryOtp = activeOrder['delivery_otp']?.toString() ?? '';
      final eventName = activeOrder['event_name']?.toString() ??
          quoteProv.customerQuotes.where((q) => q.resultingOrderId == orderId).firstOrNull?.eventName ??
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
          statusTag = isSupplies ? 'ALL SUPPLIES PACKED' : 'ALL FOOD PACKED & READY';
          buttonText = 'View Packing Status →';
          break;
        case 'bulk_dispatched':
          primaryColor = const Color(0xFF059669); // Emerald Green
          emoji = '🚗';
          title = isSupplies
              ? 'Event Supplies Out for Delivery${deliveryOtp.isNotEmpty ? ' · OTP: $deliveryOtp' : ''}'
              : 'Feast Out for Delivery${deliveryOtp.isNotEmpty ? ' · OTP: $deliveryOtp' : ''}';
          subtitle = '$eventName · In-house delivery team is en route to your venue! Share OTP $deliveryOtp upon arrival.';
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
                                  color: isDark ? Colors.white : AppColors.textPrimary,
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
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                            if (status == 'bulk_dispatched' && deliveryOtp.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: primaryColor.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: primaryColor, width: 1),
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
      final deliveryOtp = deliveredCelebration['delivery_otp']?.toString() ?? '';
      final eventName = deliveredCelebration['event_name']?.toString() ??
          quoteProv.customerQuotes.where((q) => q.resultingOrderId == orderId).firstOrNull?.eventName ??
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
                          child: const Text('🎉', style: TextStyle(fontSize: 24)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (eventName.toLowerCase().contains('rental') ||
                                        eventName.toLowerCase().contains('equipment') ||
                                        eventName.toLowerCase().contains('decor') ||
                                        eventName.toLowerCase().contains('supplies'))
                                    ? 'Event Supplies Delivered & Verified! 🎉'
                                    : 'Feast Delivered & Handover Verified! 🎉',
                                style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: isDark ? Colors.white : AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                (eventName.toLowerCase().contains('rental') ||
                                        eventName.toLowerCase().contains('equipment') ||
                                        eventName.toLowerCase().contains('decor') ||
                                        eventName.toLowerCase().contains('supplies'))
                                    ? '$eventName · Delivered with OTP${deliveryOtp.isNotEmpty ? ' ($deliveryOtp)' : ''}. Have a wonderful celebration!'
                                    : '$eventName · Delivered with OTP${deliveryOtp.isNotEmpty ? ' ($deliveryOtp)' : ''}. Have a wonderful celebration! Enjoy your feast.',
                                style: GoogleFonts.outfit(
                                  fontSize: 12.5,
                                  color: isDark ? Colors.white70 : Colors.black87,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // 1-Tap Dismiss "X" Button
                        InkWell(
                          onTap: () => quoteProv.dismissDeliveredCateringCelebration(orderId),
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
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: primaryColor, width: 1),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_circle_rounded, size: 14, color: primaryColor),
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
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () => quoteProv.dismissDeliveredCateringCelebration(orderId),
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

    final String buttonText = isQuoted
        ? 'Review & Accept →'
        : 'View Details →';

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
                                color: isDark ? Colors.white : AppColors.textPrimary,
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
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          isQuoted
                              ? 'ACTION REQUIRED'
                              : quote.quoteStatus.replaceAll('_', ' ').toUpperCase(),
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
          const Color(0xFF4A0E4E),
          const Color(0xFF8E24AA),
          const Color(0xFF673AB7),
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
                                      color: Colors.white.withValues(alpha: 0.72),
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
                    : (isDark
                        ? const Color(0xFF1E1E2E)
                        : Colors.grey.shade100),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? Colors.transparent
                      : (isDark
                          ? Colors.white10
                          : Colors.grey.shade300),
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
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
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
    final isMen = _selectedFeedDemographic == 'Men/Boys';
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
                child: Text(isMen ? '👔' : '👗', style: const TextStyle(fontSize: 28)),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              isMen
                  ? 'No Men & Boys items found nearby'
                  : 'No Women & Girls items found nearby',
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
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
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
                height: 36,
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
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: GoogleFonts.outfit(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF1A1A2E),
                              letterSpacing: -0.3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (count != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
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
                                fontSize: 11,
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
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color:
                              isDark ? Colors.white54 : AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (onSeeAllTap != null || isLoading)
          GestureDetector(
            onTap: isLoading ? null : onSeeAllTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.07)
                    : AppColors.primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(20),
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
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white70 : AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: 14,
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

  void _openCategoryListing({
    required String title,
    required List<ProductModel> products,
    required List<String> categories,
  }) {
    HapticFeedback.lightImpact();
    final lowerCats = categories.map((c) => c.trim().toLowerCase()).toSet();
    final matchingShops = _shops.where((s) {
      if (lowerCats.contains(s.category.trim().toLowerCase())) return true;
      return s.categories
          .any((c) => lowerCats.contains(c.trim().toLowerCase()));
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Department Emoji / Gradient Pill
                Container(
                  width: 38,
                  height: 38,
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
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: accentGradient.first
                          .withValues(alpha: isDark ? 0.35 : 0.20),
                      width: 1.2,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      emoji,
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
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
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF1A1A2E),
                                letterSpacing: -0.3,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  accentGradient.first.withValues(alpha: 0.12),
                                  accentGradient.last.withValues(alpha: 0.06),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: accentGradient.first
                                    .withValues(alpha: 0.25),
                              ),
                            ),
                            child: Text(
                              '$count',
                              style: GoogleFonts.outfit(
                                fontSize: 11,
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
                          fontSize: 12,
                          color: isDark
                              ? Colors.white54
                              : AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
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
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white70 : AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 14,
                    color: isDark ? Colors.white70 : AppColors.primary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryHorizontalCarousel({
    required List<ProductModel> products,
    required String sectionTitle,
    required VoidCallback onViewAllTap,
    required bool isDark,
  }) {
    final carouselItems = products.take(10).toList();

    return SizedBox(
      height: 285,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
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
              width: 156,
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: RepaintBoundary(
                  key: ValueKey('sec_p_${product.id}'),
                  child: ProductCard(
                    product: product,
                    shop: shop,
                  ),
                ),
              ),
            );
          }

          // ── Sleek "View All" End-Card ──────────────────────────────
          return SizedBox(
            width: 140,
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
                            color: Colors.black.withValues(
                                alpha: isDark ? 0.25 : 0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 46,
                            height: 46,
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
                                  color: AppColors.primary
                                      .withValues(alpha: 0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.arrow_forward_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'View All',
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: isDark
                                  ? Colors.white
                                  : AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$sectionTitle Items',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Colors.white60
                                  : AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.primary
                                  .withValues(alpha: isDark ? 0.20 : 0.08),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${products.length}+ items',
                              style: GoogleFonts.outfit(
                                fontSize: 10,
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            const Text('🏪', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            Text(
              'No shops nearby',
              style:
                  GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'No shops found within ${DeliveryCalculator.maxRadiusKm.toInt()} km of\nyour location in this category.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                  color: AppColors.textSecondary, height: 1.5),
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
                onPressed: () =>
                    context.read<LocationProvider>().requestLocation(isUserAction: true),
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

  // ── Shop by Category Section ────────────────────────────────────────────────
  // 5 main categories + a "See More" card, horizontally swipable.
  // Tap: filter home page in-place (same logic as old upper chips).
  // Long-press: navigate to dedicated CategoryProductsPage.
  Widget _buildCategorySection(bool isDark) {
    // First 5 entries from the already-existing _categories list
    final mainCats = _categories.take(5).toList();
    final remainingCount = _categories.length > 5 ? _categories.length - 5 : 29;

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
              final displayLabel = catName == 'Supermarket / Hypermarket'
                  ? 'Supermarket\nHypermarket'
                  : catName;
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
                    borderRadius:
                        BorderRadius.circular(isSelected ? 19.5 : 21),
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
                                          color: Colors.black.withValues(alpha: 0.6),
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
        const SizedBox(height: 24),
      ],
    );
  }
}
