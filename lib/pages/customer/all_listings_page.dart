import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_categories.dart';
import '../../models/product_model.dart';
import '../../models/shop_model.dart';
import '../../providers/theme_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/platform_config_provider.dart';
import '../../theme/app_colors.dart';
import '../../utils/delivery_calculator.dart';
import '../../widgets/product_card.dart';
import '../../widgets/shop_card.dart';
import '../../widgets/restaurant_shop_card.dart';
import '../../widgets/shop_detail_sheet.dart';
import '../../widgets/restaurant_dashboard_sheet.dart';
import '../../utils/responsive_layout.dart';
import '../../providers/cart_provider.dart';
import '../../widgets/customer/floating_cart_bar.dart';

// ── Listing type enum ──────────────────────────────────────────────────────────
enum ListingType { shops, restaurants, products }

// ── Internal sort mode ────────────────────────────────────────────────────────
enum _AllListingsSortMode {
  bestRating,
  nearest,
  priceLow,
  priceHigh,
  discount,
}

/// A dedicated full-screen page that shows all shops, all restaurants, or all
/// products. Seamlessly exhausts the full catalog for nearby shops with pagination
/// while preserving the admin-configured delivery radius.
class AllListingsPage extends StatefulWidget {
  final ListingType type;
  final List<ShopModel> shops;
  final List<ProductModel> products;
  final Map<String, ShopModel> productShops;
  final String? sectionTitle;
  final List<String>? categoryFilter;

  const AllListingsPage({
    super.key,
    required this.type,
    this.shops = const [],
    this.products = const [],
    this.productShops = const {},
    this.sectionTitle,
    this.categoryFilter,
  });

  @override
  State<AllListingsPage> createState() => _AllListingsPageState();
}

class _AllListingsPageState extends State<AllListingsPage> {
  _AllListingsSortMode _sortMode = _AllListingsSortMode.bestRating;
  VegFilterMode _vegFilterMode = VegFilterMode.all;
  int _displayLimit = 20;

  final _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;

  // ── 100x Dynamic Product Catalog State ────────────────────────────────────
  late List<ProductModel> _allProducts;
  late Map<String, ShopModel> _allProductShops;
  final Map<String, ShopModel> _shopsMap = {};
  final ScrollController _scrollController = ScrollController();
  bool _isLoadingMore = false;
  bool _isSearchingRemote = false;
  bool _hasMore = true;
  int _totalAvailableProducts = 0;
  int _currentOffset = 0;
  static const int _batchSize = 75;

  @override
  void initState() {
    super.initState();
    _allProducts = List<ProductModel>.from(widget.products);
    _allProductShops = Map<String, ShopModel>.from(widget.productShops);

    for (final s in widget.shops) {
      _shopsMap[s.id] = s;
    }
    for (final s in widget.productShops.values) {
      _shopsMap[s.id] = s;
    }

    if (widget.type == ListingType.products) {
      _totalAvailableProducts = widget.products.length;
      _currentOffset = widget.products.length;
      _scrollController.addListener(_onScroll);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initializeAndFetchProductCatalog();
      });
    }
  }

  // ── Department Keywords for Broad Section Searches ───────────────────────
  static const Map<String, List<String>> _departmentKeywords = {
    'Pharmacy': [
      'medicine',
      'medicines',
      'med',
      'meds',
      'pharmacy',
      'medical',
      'medical store',
      'healthcare',
      'health',
      'pharma',
      'drugs',
      'drug',
      'clinic',
      'wellness',
      'chemist',
      'doctor',
      'all medicines',
    ],
    'Grocery': [
      'grocery',
      'groceries',
      'essentials',
      'supermarket',
      'hypermarket',
      'ration',
      'daily essentials',
      'daily needs',
      'provisions',
      'staples',
      'all groceries',
    ],
    'Clothing': [
      'clothing',
      'clothes',
      'fashion',
      'apparel',
      'wear',
      'garments',
      'outfit',
      'all clothes',
    ],
    'Food': [
      'food',
      'restaurant',
      'restaurants',
      'eat',
      'meal',
      'cafe',
      'dishes',
      'all food',
    ],
    'Popular': [
      'popular',
      'popular items',
      'all items',
      'all products',
      'everything',
      'items',
      'products',
    ],
  };

  static Set<String> get _allDepartmentWords {
    final words = <String>{};
    for (final list in _departmentKeywords.values) {
      for (final w in list) {
        words.add(w.toLowerCase());
      }
    }
    return words;
  }

  static String _getCategorySynonyms(String category, [ShopModel? shop]) {
    final catName = category.trim();
    final shopCat = shop?.category.trim() ?? '';
    final shopCats = shop?.categories ?? [];

    final buffer = StringBuffer();

    void addCategoryWords(String cat) {
      if (cat.isEmpty) return;
      final collection = AppCategories.getCustomerCollection(cat).toLowerCase();
      final subtitle = AppCategories.getCustomerSubtitle(cat).toLowerCase();
      final catLower = cat.toLowerCase();

      buffer.write(' $catLower $collection $subtitle ');

      if (collection.contains('pharmacy') ||
          collection.contains('health') ||
          catLower.contains('pharmacy') ||
          catLower.contains('medical')) {
        buffer.write(
            ' medicine medicines med meds medical pharmacy healthcare health pharma drugs clinic wellness chemist doctor tablet syrup cream pill drops ointment injection salts salt composition active chemical formula paracetamol rosuvastatin atorvastatin fenofibrate capsule tabs strip ');
      }
      if (collection.contains('grocery') ||
          collection.contains('fresh') ||
          catLower.contains('grocery') ||
          catLower.contains('supermarket') ||
          catLower.contains('butcher') ||
          catLower.contains('fish') ||
          catLower.contains('dairy')) {
        buffer.write(
            ' grocery groceries supermarket hypermarket essentials daily essentials provisions staples ration food meat chicken fish mutton veggies vegetables milk noodle noodles maggi pasta macaroni snack snacks biscuits oil ghee ');
      }
      if (collection.contains('fashion') ||
          collection.contains('lifestyle') ||
          catLower.contains('clothing') ||
          catLower.contains('footwear')) {
        buffer.write(
            ' clothing clothes fashion apparel wear garments outfit shoes footwear shirt pant dress jeans denim trousers jacket sneakers ');
      }
      if (collection.contains('food') ||
          collection.contains('dining') ||
          catLower.contains('restaurant') ||
          catLower.contains('fast food') ||
          catLower.contains('bakery')) {
        buffer.write(
            ' food restaurant fast food meal dishes eat bakery cafe sweets snacks burger pizza biryani noodle noodles maggi chowmein pasta ');
      }
      if (collection.contains('cosmetics') ||
          collection.contains('beauty') ||
          catLower.contains('cosmetics') ||
          catLower.contains('salon')) {
        buffer.write(
            ' cosmetics cosmetic makeup beauty skincare lipstick lip balm eyeliner mascara foundation cream lotion serum perfume ');
      }
      if (collection.contains('electronics') ||
          collection.contains('utilities') ||
          catLower.contains('electronics') ||
          catLower.contains('mobile')) {
        buffer.write(
            ' electronics mobile phone gadget device computer laptop charger cable repair ');
      }
    }

    addCategoryWords(catName);
    if (shopCat.isNotEmpty && shopCat != catName) {
      addCategoryWords(shopCat);
    }
    for (final c in shopCats) {
      if (c != catName && c != shopCat) {
        addCategoryWords(c);
      }
    }

    return buffer.toString();
  }

  bool _isDepartmentQuery(String query) {
    final lower = query.trim().toLowerCase();
    if (lower.isEmpty) return false;

    final title = _pageTitle.toLowerCase();
    if (title == lower || (lower.length >= 4 && title.contains(lower))) return true;

    // Check if query directly references an entire shop name alone
    for (final s in widget.shops) {
      final sName = s.name.trim().toLowerCase();
      if (sName.isNotEmpty && (sName == lower || lower.contains(sName))) {
        final remainder = lower.replaceAll(sName, '').trim();
        if (remainder.isEmpty) return true;
      }
    }
    for (final s in _shopsMap.values) {
      final sName = s.name.trim().toLowerCase();
      if (sName.isNotEmpty && (sName == lower || lower.contains(sName))) {
        final remainder = lower.replaceAll(sName, '').trim();
        if (remainder.isEmpty) return true;
      }
    }

    final terms = lower.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (terms.isEmpty) return false;

    for (final entry in _departmentKeywords.entries) {
      final deptKey = entry.key.toLowerCase();
      final inFilter = widget.categoryFilter?.any((c) {
            final cLower = c.toLowerCase();
            return cLower.contains(deptKey) ||
                deptKey.contains(cLower) ||
                entry.value.any((k) => cLower.contains(k));
          }) ??
          false;
      final inTitle = title.contains(deptKey) ||
          entry.value.any((k) => title.contains(k));
      if (inFilter || inTitle || entry.key == 'Popular') {
        if (entry.value.contains(lower)) return true;

        // Query is a department query ONLY if all terms are department words
        // (if a specific product term like "dolo" is present, it must NOT suppress product filtering)
        final allTermsAreDeptWords = terms.every((t) =>
            entry.value.contains(t) ||
            t == deptKey ||
            t == 'all' ||
            t == 'item' ||
            t == 'items' ||
            t == 'store' ||
            t == 'shop' ||
            t == 'products' ||
            t == 'product');
        if (allTermsAreDeptWords) return true;
      }
    }
    return false;
  }

  Future<List<String>> _resolveNearbyShopIds() async {
    final loc = context.read<LocationProvider>();
    final resolvedIds = <String>{};

    // 0. Include shops already provided from the caller
    for (final s in widget.shops) {
      resolvedIds.add(s.id);
      _shopsMap[s.id] = s;
    }

    // 1. Dynamic geospatial query using LocationProvider + DeliveryCalculator.maxRadiusKm
    try {
      if (loc.hasLocation && loc.currentLocation != null) {
        final params = <String, dynamic>{
          'p_lat': loc.currentLocation!.latitude,
          'p_lng': loc.currentLocation!.longitude,
          'p_radius_km': DeliveryCalculator.maxRadiusKm,
          'p_limit': 500,
          'p_categories': widget.categoryFilter,
        };
        dynamic resp;
        try {
          resp = await Supabase.instance.client.rpc('get_nearby_shops', params: params);
        } catch (_) {
          // Resilient fallback to search_shops_geospatial (single canonical signature)
          resp = await Supabase.instance.client.rpc('search_shops_geospatial', params: {
            'p_lat': loc.currentLocation!.latitude,
            'p_lng': loc.currentLocation!.longitude,
            'p_query': null,
            'p_categories': widget.categoryFilter,
            'p_radius_km': DeliveryCalculator.maxRadiusKm,
            'p_limit': 500,
          });
        }

        if (resp != null) {
          final fetched =
              (resp as List).map((s) => ShopModel.fromMap(s)).toList();
          for (final s in fetched) {
            if (s.location.latitude != 0 && s.location.longitude != 0) {
              final dist = loc.distanceTo(s.location);
              if (DeliveryCalculator.isWithinRange(dist)) {
                s.distanceKm = dist;
                _shopsMap[s.id] = s;
                resolvedIds.add(s.id);
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[AllListingsPage] _resolveNearbyShopIds error: $e');
    }

    if (resolvedIds.isNotEmpty) return resolvedIds.toList();

    // 2. From shops already cached in _shopsMap, filtering strictly by delivery radius & category
    if (_shopsMap.isNotEmpty) {
      final lowerFilters = widget.categoryFilter != null && widget.categoryFilter!.isNotEmpty
          ? widget.categoryFilter!.map((c) => c.trim().toLowerCase()).toSet()
          : null;

      return _shopsMap.values
          .where((s) {
            if (lowerFilters != null) {
              final matches = lowerFilters.contains(s.category.trim().toLowerCase()) ||
                  s.categories.any((c) => lowerFilters.contains(c.trim().toLowerCase()));
              if (!matches) return false;
            }
            if (!loc.hasLocation) return true;
            if (s.location.latitude == 0 || s.location.longitude == 0) return false;
            final d = s.distanceKm ?? loc.distanceTo(s.location);
            return DeliveryCalculator.isWithinRange(d);
          })
          .map((s) => s.id)
          .toList();
    }

    return [];
  }

  Future<void> _initializeAndFetchProductCatalog() async {
    if (!mounted || widget.type != ListingType.products) return;

    try {
      final config = context.read<PlatformConfigProvider>();
      final loc = context.read<LocationProvider>();

      // 0. Resolve missing shops for initial products if any
      final missingInitialShopIds = _allProducts
          .map((p) => p.shopId)
          .where((id) => !_shopsMap.containsKey(id))
          .toSet();
      if (missingInitialShopIds.isNotEmpty) {
        try {
          final initialShopRows = await Supabase.instance.client
              .from('shops')
              .select('*')
              .inFilter('id', missingInitialShopIds.toList());
          for (final sr in (initialShopRows as List)) {
            final sm = ShopModel.fromMap(sr);
            if (loc.hasLocation &&
                sm.location.latitude != 0 &&
                sm.location.longitude != 0) {
              sm.distanceKm = loc.distanceTo(sm.location);
            }
            _shopsMap[sm.id] = sm;
          }
          for (final p in _allProducts) {
            if (_shopsMap.containsKey(p.shopId)) {
              _allProductShops[p.id] = _shopsMap[p.shopId]!;
            }
          }
        } catch (_) {}
      }

      final shopIds = await _resolveNearbyShopIds();
      if (!mounted) return;
      if (shopIds.isEmpty) {
        setState(() {
          _hasMore = false;
          _isLoadingMore = false;
        });
        return;
      }

      // 1. Query exact total product count in database for nearby shops (excluding soft deletes)
      final countQuery = Supabase.instance.client
          .from('products')
          .select('id')
          .inFilter('shop_id', shopIds)
          .eq('is_deleted', false)
          .eq('is_available', true);

      final countResp = await countQuery;
      final totalInDb = (countResp as List).length;

      // 2. High-speed single-shot catalog fetch (up to 500 items)
      final fetchQuery = Supabase.instance.client
          .from('products')
          .select()
          .inFilter('shop_id', shopIds)
          .eq('is_deleted', false)
          .eq('is_available', true);

      final response = await fetchQuery
          .order('rating', ascending: false)
          .order('created_at', ascending: false)
          .limit(500);

      final rows = response as List<dynamic>;
      final existingIds = _allProducts.map((p) => p.id).toSet();
      final newProducts = <ProductModel>[];
      final missingShopIds = <String>{};

      for (final r in rows) {
        final p = ProductModel.fromMap(r as Map<String, dynamic>);
        if (!existingIds.contains(p.id) && config.isActiveCategory(p.category)) {
          newProducts.add(p);
          existingIds.add(p.id);
          if (!_shopsMap.containsKey(p.shopId)) {
            missingShopIds.add(p.shopId);
          }
        }
      }

      if (missingShopIds.isNotEmpty) {
        try {
          final shopRows = await Supabase.instance.client
              .from('shops')
              .select('*')
              .inFilter('id', missingShopIds.toList());
          for (final sr in (shopRows as List)) {
            final sm = ShopModel.fromMap(sr);
            if (loc.hasLocation &&
                sm.location.latitude != 0 &&
                sm.location.longitude != 0) {
              sm.distanceKm = loc.distanceTo(sm.location);
            }
            _shopsMap[sm.id] = sm;
          }
        } catch (_) {}
      }

      for (final p in newProducts) {
        if (_shopsMap.containsKey(p.shopId)) {
          _allProductShops[p.id] = _shopsMap[p.shopId]!;
        }
      }

      if (mounted) {
        setState(() {
          _allProducts.addAll(newProducts);
          _currentOffset = _allProducts.length;
          _hasMore = totalInDb > _allProducts.length;
          _totalAvailableProducts = math.max(totalInDb, _allProducts.length);
          _isLoadingMore = false;
          _invalidateSortMemo();
        });
      }
    } catch (e) {
      debugPrint('[AllListingsPage] Catalog init error: $e');
    }
  }

  Future<void> _fetchMoreProductsFromDb(
      [List<String>? providedShopIds, PlatformConfigProvider? config]) async {
    if (_isLoadingMore || !_hasMore || !mounted) return;

    setState(() => _isLoadingMore = true);

    try {
      final effectiveConfig =
          config ?? context.read<PlatformConfigProvider>();
      final loc = context.read<LocationProvider>();
      final shopIds = providedShopIds ?? await _resolveNearbyShopIds();
      if (!mounted || shopIds.isEmpty) {
        if (mounted) {
          setState(() {
            _isLoadingMore = false;
            _hasMore = false;
          });
        }
        return;
      }

      final fetchQuery = Supabase.instance.client
          .from('products')
          .select()
          .inFilter('shop_id', shopIds)
          .eq('is_deleted', false)
          .eq('is_available', true);

      final response = await fetchQuery
          .order('rating', ascending: false)
          .order('created_at', ascending: false)
          .range(_currentOffset, _currentOffset + _batchSize - 1);

      final rows = response as List<dynamic>;
      if (rows.isEmpty) {
        if (mounted) {
          setState(() {
            _hasMore = false;
            _isLoadingMore = false;
          });
        }
        return;
      }

      final existingIds = _allProducts.map((p) => p.id).toSet();
      final newProducts = <ProductModel>[];
      final missingShopIds = <String>{};

      for (final r in rows) {
        final p = ProductModel.fromMap(r as Map<String, dynamic>);
        if (!existingIds.contains(p.id) &&
            effectiveConfig.isActiveCategory(p.category)) {
          newProducts.add(p);
          existingIds.add(p.id);
          if (!_shopsMap.containsKey(p.shopId)) {
            missingShopIds.add(p.shopId);
          }
        }
      }

      // Batch-fetch missing shop details if any product belongs to a shop not yet cached
      if (missingShopIds.isNotEmpty) {
        try {
          final shopRows = await Supabase.instance.client
              .from('shops')
              .select('*')
              .inFilter('id', missingShopIds.toList());
          for (final sr in (shopRows as List)) {
            final sm = ShopModel.fromMap(sr);
            if (loc.hasLocation &&
                sm.location.latitude != 0 &&
                sm.location.longitude != 0) {
              sm.distanceKm = loc.distanceTo(sm.location);
            }
            _shopsMap[sm.id] = sm;
          }
        } catch (e) {
          debugPrint('[AllListingsPage] Error fetching missing shops: $e');
        }
      }

      for (final p in newProducts) {
        if (_shopsMap.containsKey(p.shopId)) {
          _allProductShops[p.id] = _shopsMap[p.shopId]!;
        }
      }

      if (mounted) {
        setState(() {
          _allProducts.addAll(newProducts);
          _currentOffset += rows.length;
          _isLoadingMore = false;
          _invalidateSortMemo();
          if (rows.length < _batchSize ||
              _allProducts.length >= _totalAvailableProducts) {
            _hasMore = false;
          }
          if (_allProducts.length > _totalAvailableProducts) {
            _totalAvailableProducts = _allProducts.length;
          }
        });
      }
    } catch (e) {
      debugPrint('[AllListingsPage] Fetch error: $e');
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 400) {
      if (_hasMore && !_isLoadingMore && _searchQuery.isEmpty) {
        setState(() {
          _displayLimit += 20;
        });
        _fetchMoreProductsFromDb();
      }
    }
  }

  Future<void> _performLiveProductSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty || !mounted || widget.type != ListingType.products) {
      return;
    }

    setState(() => _isSearchingRemote = true);

    try {
      final loc = context.read<LocationProvider>();
      final config = context.read<PlatformConfigProvider>();
      final shopIds = await _resolveNearbyShopIds();
      if (shopIds.isEmpty || !mounted) {
        if (mounted) setState(() => _isSearchingRemote = false);
        return;
      }

      // 1. Department query fast-path (e.g. typing "medicine", "grocery", "clothing", or store name)
      if (_isDepartmentQuery(trimmed)) {
        final catalogRows = await Supabase.instance.client
            .from('products')
            .select()
            .inFilter('shop_id', shopIds)
            .eq('is_deleted', false)
            .eq('is_available', true)
            .order('rating', ascending: false)
            .order('created_at', ascending: false)
            .limit(500);

        if (!mounted || _searchQuery != trimmed) return;

        final rows = catalogRows as List<dynamic>;
        final existingIds = _allProducts.map((p) => p.id).toSet();
        final newProducts = <ProductModel>[];
        final missingShopIds = <String>{};

        for (final r in rows) {
          final p = ProductModel.fromMap(r as Map<String, dynamic>);
          if (!existingIds.contains(p.id) && config.isActiveCategory(p.category)) {
            newProducts.add(p);
            existingIds.add(p.id);
            if (!_shopsMap.containsKey(p.shopId)) {
              missingShopIds.add(p.shopId);
            }
          }
        }

        if (missingShopIds.isNotEmpty) {
          try {
            final shopRows = await Supabase.instance.client
                .from('shops')
                .select('*')
                .inFilter('id', missingShopIds.toList());
            for (final sr in (shopRows as List)) {
              final sm = ShopModel.fromMap(sr);
              if (loc.hasLocation &&
                  sm.location.latitude != 0 &&
                  sm.location.longitude != 0) {
                sm.distanceKm = loc.distanceTo(sm.location);
              }
              _shopsMap[sm.id] = sm;
            }
          } catch (_) {}
        }

        for (final p in newProducts) {
          if (_shopsMap.containsKey(p.shopId)) {
            _allProductShops[p.id] = _shopsMap[p.shopId]!;
          }
        }

        if (mounted && _searchQuery == trimmed) {
          setState(() {
            _allProducts.addAll(newProducts);
            _totalAvailableProducts = math.max(_totalAvailableProducts, _allProducts.length);
            _isSearchingRemote = false;
            _invalidateSortMemo();
          });
        }
        return;
      }

      // 2. Multi-column remote live search across all products of nearby shops
      var q = Supabase.instance.client
          .from('products')
          .select()
          .inFilter('shop_id', shopIds)
          .eq('is_deleted', false)
          .eq('is_available', true);

      final cleanQuery = trimmed.replaceAll(RegExp(r'[,()"\x27]'), ' ');
      final rawTerms =
          cleanQuery.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
      final deptWords = _allDepartmentWords;
      final specificTerms = rawTerms.length > 1
          ? rawTerms.where((t) => !deptWords.contains(t.toLowerCase())).toList()
          : rawTerms;
      final terms = specificTerms.isNotEmpty ? specificTerms : rawTerms;

      for (final term in terms) {
        q = q.or(
          'name.ilike.%$term%,description.ilike.%$term%,brand.ilike.%$term%,menu_category.ilike.%$term%,sub_category.ilike.%$term%,category.ilike.%$term%,medicine_type.ilike.%$term%',
        );
      }

      final response =
          await q.order('rating', ascending: false).limit(500);

      if (!mounted || _searchQuery != trimmed) return;

      final rows = response as List<dynamic>;
      final existingIds = _allProducts.map((p) => p.id).toSet();
      final newProducts = <ProductModel>[];
      final missingShopIds = <String>{};

      for (final r in rows) {
        final p = ProductModel.fromMap(r as Map<String, dynamic>);
        if (!existingIds.contains(p.id) &&
            config.isActiveCategory(p.category)) {
          newProducts.add(p);
          existingIds.add(p.id);
          if (!_shopsMap.containsKey(p.shopId)) {
            missingShopIds.add(p.shopId);
          }
        }
      }

      // Batch-fetch missing shop details if any
      if (missingShopIds.isNotEmpty) {
        try {
          final shopRows = await Supabase.instance.client
              .from('shops')
              .select('*')
              .inFilter('id', missingShopIds.toList());
          for (final sr in (shopRows as List)) {
            final sm = ShopModel.fromMap(sr);
            if (loc.hasLocation &&
                sm.location.latitude != 0 &&
                sm.location.longitude != 0) {
              sm.distanceKm = loc.distanceTo(sm.location);
            }
            _shopsMap[sm.id] = sm;
          }
        } catch (e) {
          debugPrint('[AllListingsPage] Error fetching search missing shops: $e');
        }
      }

      for (final p in newProducts) {
        if (_shopsMap.containsKey(p.shopId)) {
          _allProductShops[p.id] = _shopsMap[p.shopId]!;
        }
      }

      if (mounted && _searchQuery == trimmed) {
        setState(() {
          _allProducts.addAll(newProducts);
          _isSearchingRemote = false;
          _invalidateSortMemo();
        });
      }
    } catch (e) {
      debugPrint('[AllListingsPage] Remote product search error: $e');
      if (mounted) {
        setState(() => _isSearchingRemote = false);
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // ── Page title ────────────────────────────────────────────────────────────
  String get _pageTitle {
    if (widget.sectionTitle != null) return widget.sectionTitle!;
    switch (widget.type) {
      case ListingType.restaurants:
        return 'All Restaurants';
      case ListingType.shops:
        return 'All Shops';
      case ListingType.products:
        return 'All Products';
    }
  }

  String get _itemLabel {
    switch (widget.type) {
      case ListingType.restaurants:
        return 'restaurants';
      case ListingType.shops:
        return 'shops';
      case ListingType.products:
        return 'products';
    }
  }

  // ── Sorted + filtered shops (Memoized per build frame) ─────────────────────
  List<ShopModel>? _memoizedSortedShops;
  List<ProductModel>? _memoizedSortedProducts;

  void _invalidateSortMemo() {
    _memoizedSortedShops = null;
    _memoizedSortedProducts = null;
  }

  List<ShopModel> get _sortedShops {
    if (_memoizedSortedShops != null) return _memoizedSortedShops!;
    _memoizedSortedShops = _computeSortedShops();
    return _memoizedSortedShops!;
  }

  List<ShopModel> _computeSortedShops() {
    final loc = context.read<LocationProvider>();
    var list = widget.shops.where((s) {
      if (loc.hasLocation) {
        if (s.location.latitude == 0 || s.location.longitude == 0) return false;
        final d = s.distanceKm ?? loc.distanceTo(s.location);
        if (!DeliveryCalculator.isWithinRange(d)) return false;
      }
      return true;
    }).toList();

    if (_searchQuery.isNotEmpty) {
      final cleanQuery = _searchQuery.replaceAll(RegExp(r'[,()"\x27]'), ' ');
      final terms = cleanQuery
          .toLowerCase()
          .split(RegExp(r'\s+'))
          .where((t) => t.isNotEmpty)
          .toList();
      list = list.where((s) {
        final syn = _getCategorySynonyms(s.category, s);
        final searchable =
            '${s.name} ${s.cuisineType ?? ''} ${s.category} ${s.categories.join(' ')} $syn'
                .toLowerCase();
        return terms.every((t) => searchable.contains(t));
      }).toList();
    }

    if (_vegFilterMode == VegFilterMode.vegOnly) {
      list = list.where((s) => s.isVegOnly).toList();
    } else if (_vegFilterMode == VegFilterMode.nonVegOnly) {
      list = list.where((s) => !s.isVegOnly).toList();
    }

    list.sort((a, b) {
      final openA = a.isOpenRightNow ? 1 : 0;
      final openB = b.isOpenRightNow ? 1 : 0;
      if (openA != openB) return openB.compareTo(openA);

      switch (_sortMode) {
        case _AllListingsSortMode.bestRating:
          final rCmp = b.rating.compareTo(a.rating);
          if (rCmp != 0) return rCmp;
          return (a.distanceKm ?? double.infinity)
              .compareTo(b.distanceKm ?? double.infinity);
        case _AllListingsSortMode.nearest:
          return (a.distanceKm ?? double.infinity)
              .compareTo(b.distanceKm ?? double.infinity);
        case _AllListingsSortMode.priceLow:
        case _AllListingsSortMode.priceHigh:
        case _AllListingsSortMode.discount:
          return b.rating.compareTo(a.rating);
      }
    });
    return list;
  }

  List<ProductModel> get _sortedProducts {
    if (_memoizedSortedProducts != null) return _memoizedSortedProducts!;
    _memoizedSortedProducts = _computeSortedProducts();
    return _memoizedSortedProducts!;
  }

  List<ProductModel> _computeSortedProducts() {
    final loc = context.read<LocationProvider>();
    final lowerFilters = widget.categoryFilter != null && widget.categoryFilter!.isNotEmpty
        ? widget.categoryFilter!.map((c) => c.trim().toLowerCase()).toSet()
        : null;

    var list = _allProducts.where((p) {
      if (lowerFilters != null) {
        final pCat = p.category.trim().toLowerCase();
        final shop = _allProductShops[p.id] ?? _shopsMap[p.shopId];
        final sCat = shop?.category.trim().toLowerCase() ?? '';
        final matchesProdCat = lowerFilters.contains(pCat);
        final matchesShopCat = sCat.isNotEmpty && lowerFilters.contains(sCat);
        final matchesShopMultiCat = shop?.categories.any((c) => lowerFilters.contains(c.trim().toLowerCase())) ?? false;
        final matchesShopScope = widget.shops.any((s) => s.id == p.shopId);
        if (!matchesProdCat && !matchesShopCat && !matchesShopMultiCat && !matchesShopScope) {
          return false;
        }
      }
      final shop = _allProductShops[p.id] ?? _shopsMap[p.shopId];
      if (loc.hasLocation && shop != null) {
        if (shop.location.latitude == 0 || shop.location.longitude == 0) {
          return false;
        }
        final d = shop.distanceKm ?? loc.distanceTo(shop.location);
        if (!DeliveryCalculator.isWithinRange(d)) return false;
      }
      return true;
    }).toList();

    if (_searchQuery.isNotEmpty) {
      if (!_isDepartmentQuery(_searchQuery)) {
        final cleanQuery = _searchQuery.replaceAll(RegExp(r'[,()"\x27]'), ' ');
        final terms = cleanQuery
            .toLowerCase()
            .split(RegExp(r'\s+'))
            .where((t) => t.isNotEmpty)
            .toList();
        list = list.where((p) {
          final shop = _allProductShops[p.id] ?? _shopsMap[p.shopId];
          final syn = _getCategorySynonyms(p.category, shop);
          final variantNames = p.variants.map((v) => v.name).join(' ');
          final searchable =
              '${p.name} ${p.description ?? ''} ${p.brand ?? ''} ${p.category} ${p.subCategory ?? ''} ${p.menuCategory ?? ''} ${p.medicineType} ${p.unitType} $variantNames ${p.specialTags.join(' ')} ${shop?.name ?? ''} ${shop?.category ?? ''} $syn'
                  .toLowerCase();
          return terms.every((t) => searchable.contains(t));
        }).toList();
      }
    }

    if (_vegFilterMode == VegFilterMode.vegOnly) {
      list = list.where((p) => p.isVeg == true).toList();
    } else if (_vegFilterMode == VegFilterMode.nonVegOnly) {
      list = list.where((p) => p.isVeg == false).toList();
    }

    list.sort((a, b) {
      final sA = _allProductShops[a.id] ?? _shopsMap[a.shopId];
      final sB = _allProductShops[b.id] ?? _shopsMap[b.shopId];
      final availA = a.isAvailable && (sA?.isOpenRightNow ?? true);
      final availB = b.isAvailable && (sB?.isOpenRightNow ?? true);

      if (availA && !availB) return -1;
      if (!availA && availB) return 1;

      switch (_sortMode) {
        case _AllListingsSortMode.bestRating:
          return b.rating.compareTo(a.rating);
        case _AllListingsSortMode.nearest:
          return (sA?.distanceKm ?? double.infinity)
              .compareTo(sB?.distanceKm ?? double.infinity);
        case _AllListingsSortMode.priceLow:
          return a.price.compareTo(b.price);
        case _AllListingsSortMode.priceHigh:
          return b.price.compareTo(a.price);
        case _AllListingsSortMode.discount:
          return (b.discountPercent ?? 0).compareTo(a.discountPercent ?? 0);
      }
    });
    return list;
  }

  bool get _isProducts => widget.type == ListingType.products;

  bool get _hasFoodItems {
    if (widget.categoryFilter != null &&
        widget.categoryFilter!.isNotEmpty &&
        !widget.categoryFilter!.any((c) => AppCategories.isFoodCategory(c))) {
      return false;
    }
    if (widget.type == ListingType.restaurants) return true;
    return _allProducts.any((p) => p.isFood || p.isVeg != null);
  }

  // ── Sort chip definitions ─────────────────────────────────────────────────
  List<Map<String, dynamic>> get _sortFilters => [
        {
          'mode': _AllListingsSortMode.bestRating,
          'label': 'Best Rating',
          'icon': Icons.star_rounded,
        },
        {
          'mode': _AllListingsSortMode.nearest,
          'label': 'Nearest',
          'icon': Icons.location_on_rounded,
        },
        if (_isProducts) ...[
          {
            'mode': _AllListingsSortMode.priceLow,
            'label': 'Price ↑',
            'icon': Icons.trending_up_rounded,
          },
          {
            'mode': _AllListingsSortMode.priceHigh,
            'label': 'Price ↓',
            'icon': Icons.trending_down_rounded,
          },
          {
            'mode': _AllListingsSortMode.discount,
            'label': 'Discount',
            'icon': Icons.local_offer_rounded,
          },
        ],
      ];

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final cart = context.watch<CartProvider>();
    final isDark = themeProvider.isDarkMode;
    final totalCount = _isProducts
        ? (_totalAvailableProducts > 0
            ? (_searchQuery.isNotEmpty || _vegFilterMode != VegFilterMode.all
                ? _sortedProducts.length
                : _totalAvailableProducts)
            : _sortedProducts.length)
        : widget.shops.length;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          // ── AppBar ──────────────────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            floating: false,
            elevation: 0,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            surfaceTintColor: Colors.transparent,
            leading: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1E1E2E)
                        : const Color(0xFFF0F0F8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: isDark ? Colors.white10 : Colors.transparent),
                  ),
                  child: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 16,
                    color: isDark ? Colors.white70 : AppColors.textPrimary,
                  ),
                ),
              ),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _pageTitle,
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    '$totalCount $_itemLabel',
                    key: ValueKey(totalCount),
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(106),
              child: Column(
                children: [
                  // ── In-page search bar ─────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) {
                        _searchDebounce?.cancel();
                        final trimmed = v.trim();
                        setState(() {
                          _searchQuery = trimmed;
                          _displayLimit = 20;
                          _invalidateSortMemo();
                        });
                        if (trimmed.isNotEmpty &&
                            widget.type == ListingType.products) {
                          _searchDebounce = Timer(
                            const Duration(milliseconds: 250),
                            () => _performLiveProductSearch(trimmed),
                          );
                        } else {
                          setState(() => _isSearchingRemote = false);
                        }
                      },
                      decoration: InputDecoration(
                        hintText: widget.categoryFilter != null &&
                                widget.categoryFilter!.any(
                                    (c) => AppCategories.isPharmacyCategory(c))
                            ? 'Search medicines by name or salt/composition...'
                            : 'Search within $_pageTitle...',
                        hintStyle: GoogleFonts.outfit(
                          color: isDark
                              ? Colors.grey.shade500
                              : Colors.grey.shade400,
                          fontSize: 13,
                        ),
                        prefixIcon: const Icon(Icons.search_rounded,
                            color: AppColors.primary, size: 20),
                        suffixIcon: _isSearchingRemote
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.primary,
                                  ),
                                ),
                              )
                            : (_searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.close_rounded,
                                        size: 18),
                                    onPressed: () {
                                      _searchDebounce?.cancel();
                                      _searchController.clear();
                                      setState(() {
                                        _searchQuery = '';
                                        _isSearchingRemote = false;
                                        _displayLimit = 20;
                                        _vegFilterMode = VegFilterMode.all;
                                        _invalidateSortMemo();
                                      });
                                    },
                                  )
                                : null),
                        filled: true,
                        fillColor:
                            Theme.of(context).inputDecorationTheme.fillColor ??
                                (isDark
                                    ? const Color(0xFF1A1D30)
                                    : Colors.grey.shade100),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: isDark
                                ? AppColors.primaryLight
                                : AppColors.primary,
                            width: 1.5,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                      ),
                    ),
                  ),
                  // ── Chips row (Dietary + Sort) ──────────────────────
                  SizedBox(
                    height: 46,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      itemCount: (_hasFoodItems ? 2 : 0) + _sortFilters.length,
                      itemBuilder: (context, index) {
                        if (_hasFoodItems && index == 0) {
                          // Pure Veg chip
                          final isSelected =
                              _vegFilterMode == VegFilterMode.vegOnly;
                          return GestureDetector(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              setState(() {
                                _vegFilterMode = isSelected
                                    ? VegFilterMode.all
                                    : VegFilterMode.vegOnly;
                                _displayLimit = 20;
                                _invalidateSortMemo();
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFF2E7D32)
                                        .withValues(alpha: isDark ? 0.25 : 0.12)
                                    : (isDark
                                        ? const Color(0xFF1A1D30)
                                        : Colors.grey.shade100),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFF2E7D32)
                                      : (isDark
                                          ? Colors.white12
                                          : Colors.grey.shade300),
                                  width: isSelected ? 1.5 : 1.0,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildDietBadgeEmblem(isVeg: true),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Pure Veg',
                                    style: GoogleFonts.outfit(
                                      fontSize: 12,
                                      fontWeight: isSelected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: isSelected
                                          ? (isDark
                                              ? Colors.white
                                              : const Color(0xFF2E7D32))
                                          : (isDark
                                              ? Colors.white70
                                              : AppColors.textPrimary),
                                    ),
                                  ),
                                  if (isSelected) ...[
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.check_rounded,
                                      size: 13,
                                      color: isDark
                                          ? Colors.white
                                          : const Color(0xFF2E7D32),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        }

                        if (_hasFoodItems && index == 1) {
                          // Non-Veg chip
                          final isSelected =
                              _vegFilterMode == VegFilterMode.nonVegOnly;
                          return GestureDetector(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              setState(() {
                                _vegFilterMode = isSelected
                                    ? VegFilterMode.all
                                    : VegFilterMode.nonVegOnly;
                                _displayLimit = 20;
                                _invalidateSortMemo();
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFFC62828)
                                        .withValues(alpha: isDark ? 0.25 : 0.12)
                                    : (isDark
                                        ? const Color(0xFF1A1D30)
                                        : Colors.grey.shade100),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFFC62828)
                                      : (isDark
                                          ? Colors.white12
                                          : Colors.grey.shade300),
                                  width: isSelected ? 1.5 : 1.0,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildDietBadgeEmblem(isVeg: false),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Non-Veg',
                                    style: GoogleFonts.outfit(
                                      fontSize: 12,
                                      fontWeight: isSelected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: isSelected
                                          ? (isDark
                                              ? Colors.white
                                              : const Color(0xFFC62828))
                                          : (isDark
                                              ? Colors.white70
                                              : AppColors.textPrimary),
                                    ),
                                  ),
                                  if (isSelected) ...[
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.check_rounded,
                                      size: 13,
                                      color: isDark
                                          ? Colors.white
                                          : const Color(0xFFC62828),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        }

                        final sortIndex =
                            index - (_hasFoodItems ? 2 : 0);
                        final f = _sortFilters[sortIndex];
                        final mode = f['mode'] as _AllListingsSortMode;
                        final isSelected = _sortMode == mode;
                        return GestureDetector(
                          onTap: () => setState(() {
                            _sortMode = mode;
                            _invalidateSortMemo();
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              gradient: isSelected
                                  ? const LinearGradient(
                                      colors: [
                                        AppColors.primary,
                                        AppColors.primaryLight,
                                      ],
                                    )
                                  : null,
                              color: isSelected
                                  ? null
                                  : (isDark
                                      ? const Color(0xFF1A1D30)
                                      : Colors.grey.shade100),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected
                                    ? Colors.transparent
                                    : (isDark
                                        ? Colors.white12
                                        : Colors.grey.shade300),
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: AppColors.primary
                                            .withValues(alpha: 0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  f['icon'] as IconData,
                                  size: 14,
                                  color: isSelected
                                      ? Colors.white
                                      : (isDark
                                          ? Colors.white60
                                          : AppColors.textSecondary),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  f['label'] as String,
                                  style: GoogleFonts.outfit(
                                    fontSize: 12,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
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
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        body: Stack(
          children: [
            _isProducts ? _buildProductsBody(isDark) : _buildShopsBody(isDark),
            // Sticky cart bar at bottom
            if (cart.totalItemCount > 0)
              const FloatingCartBar(bottomOffset: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _onRefresh() async {
    HapticFeedback.lightImpact();
    setState(() {
      _currentOffset = 0;
      _displayLimit = 20;
      _hasMore = true;
      _isLoadingMore = false;
      _allProducts.clear();
      _allProductShops.clear();
      _invalidateSortMemo();
    });
    await _initializeAndFetchProductCatalog();
  }

  // ── Products grid ─────────────────────────────────────────────────────────
  Widget _buildProductsBody(bool isDark) {
    final sorted = _sortedProducts;
    if (sorted.isEmpty) {
      if (_isSearchingRemote) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Searching full store catalog for "$_searchQuery"...',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        );
      }
      return _buildEmptyState(isDark);
    }

    final displayProducts = _searchQuery.isNotEmpty
        ? sorted
        : sorted.take(_displayLimit).toList();

    return RefreshIndicator(
      onRefresh: _onRefresh,
      color: AppColors.primary,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          sliver: SliverLayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = Responsive.getGridCrossAxisCount(context,
                  mobile: 2, tablet: 4, desktop: 5);
              const crossAxisSpacing = 16.0;
              final itemWidth = (constraints.crossAxisExtent -
                      crossAxisSpacing * (crossAxisCount - 1)) /
                  crossAxisCount;
              final itemHeight = itemWidth + 134;
              final childAspectRatio = itemWidth / itemHeight;

              return SliverGrid.builder(
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: true,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: childAspectRatio,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: crossAxisSpacing,
                ),
                itemCount: displayProducts.length,
                itemBuilder: (_, i) {
                  final product = displayProducts[i];
                  final shop =
                      _allProductShops[product.id] ?? _shopsMap[product.shopId];
                  return RepaintBoundary(
                    key: ValueKey('all_prod_${product.id}'),
                    child: ProductCard(product: product, shop: shop),
                  );
                },
              );
            },
          ),
        ),
        // ── Load More / Infinite Pagination / End of Feed Footer ─────────────
        if (sorted.length > _displayLimit || _hasMore)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _isLoadingMore
                      ? null
                      : () {
                          HapticFeedback.lightImpact();
                          setState(() {
                            _displayLimit += 20;
                          });
                          if (_displayLimit >= sorted.length &&
                              _hasMore &&
                              !_isLoadingMore) {
                            _fetchMoreProductsFromDb();
                          }
                        },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
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
                        if (_isLoadingMore) ...[
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Loading more items...',
                            style: GoogleFonts.outfit(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : AppColors.primary,
                            ),
                          ),
                        ] else ...[
                          Text(
                            'Load more products',
                            style: GoogleFonts.outfit(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 20,
                            color: isDark ? Colors.white : AppColors.primary,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          )
        else if (!_hasMore && sorted.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 24,
                      height: 1,
                      color: isDark ? Colors.white24 : Colors.black12,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _searchQuery.isNotEmpty
                            ? 'End of results for "$_searchQuery" 🛍️'
                            : 'You\'ve reached the end of ${_pageTitle.toLowerCase()} 🛍️',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 24,
                      height: 1,
                      color: isDark ? Colors.white24 : Colors.black12,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

  // ── Shops/Restaurants grid ────────────────────────────────────────────────
  Widget _buildShopsBody(bool isDark) {
    final sorted = _sortedShops;
    if (sorted.isEmpty) return _buildEmptyState(isDark);

    final displayShops = sorted.take(_displayLimit).toList();

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          sliver: SliverLayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = Responsive.getGridCrossAxisCount(context,
                  mobile: 1, tablet: 2, desktop: 3);

              return SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisExtent: 280,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: displayShops.length,
                itemBuilder: (_, i) {
                  final shop = displayShops[i];
                  final isFood = AppCategories.groupFor(shop.category) ==
                      CategoryGroup.food;
                  return RepaintBoundary(
                    key: ValueKey('all_shop_${shop.id}'),
                    child: isFood
                        ? RestaurantShopCard(
                            shop: shop,
                            onTap: () =>
                                showRestaurantDashboardSheet(context, shop.id),
                          )
                        : ShopCard(
                            shop: shop,
                            onTap: () => showShopDetailSheet(context, shop.id),
                          ),
                  );
                },
              );
            },
          ),
        ),
        if (sorted.length > _displayLimit)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() {
                      _displayLimit =
                          math.min(_displayLimit + 20, sorted.length);
                    });
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
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
                          'Load more shops',
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 20,
                          color: isDark ? Colors.white : AppColors.primary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ── Empty state ────────────────────────────────────────────────────────────
  Widget _buildEmptyState(bool isDark) {
    final hasSearch = _searchQuery.isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.primary.withValues(alpha: 0.12)
                    : AppColors.primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Center(
                child: Icon(
                  hasSearch
                      ? Icons.search_off_rounded
                      : (_isProducts
                          ? Icons.inventory_2_outlined
                          : Icons.storefront_outlined),
                  size: 40,
                  color: isDark ? AppColors.primaryLight : AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              hasSearch ? 'No results for "$_searchQuery"' : 'Nothing here yet',
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : AppColors.textPrimary,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasSearch
                  ? 'No matching items found in $_pageTitle. Try searching with a different brand or generic keyword.'
                  : 'Check back soon — more $_itemLabel are being added.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            if (hasSearch) ...[
              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _searchQuery = '';
                    _isSearchingRemote = false;
                    _displayLimit = 20;
                    _invalidateSortMemo();
                  });
                },
                icon: const Icon(Icons.clear_rounded,
                    color: AppColors.primary, size: 18),
                label: Text(
                  'Clear search',
                  style: GoogleFonts.outfit(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            if (_vegFilterMode != VegFilterMode.all) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  setState(() {
                    _vegFilterMode = VegFilterMode.all;
                    _displayLimit = 20;
                  });
                },
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: Text(
                  'Show All Food',
                  style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                ),
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
}
