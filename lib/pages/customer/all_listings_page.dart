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

  const AllListingsPage({
    super.key,
    required this.type,
    this.shops = const [],
    this.products = const [],
    this.productShops = const {},
    this.sectionTitle,
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
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _totalAvailableProducts = 0;
  int _currentOffset = 0;
  static const int _batchSize = 50;

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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initializeAndFetchProductCatalog();
      });
    }
  }

  Future<List<String>> _resolveNearbyShopIds() async {
    final loc = context.read<LocationProvider>();

    // 1. Dynamic geospatial query using LocationProvider + DeliveryCalculator.maxRadiusKm
    try {
      if (loc.hasLocation && loc.currentLocation != null) {
        final resp = await Supabase.instance.client.rpc('get_nearby_shops', params: {
          'p_lat': loc.currentLocation!.latitude,
          'p_lng': loc.currentLocation!.longitude,
          'p_radius_km': DeliveryCalculator.maxRadiusKm,
          'p_limit': 500,
        });
        final fetched =
            (resp as List).map((s) => ShopModel.fromMap(s)).toList();
        final validIds = <String>[];
        for (final s in fetched) {
          if (s.location.latitude != 0 && s.location.longitude != 0) {
            final dist = loc.distanceTo(s.location);
            if (DeliveryCalculator.isWithinRange(dist)) {
              s.distanceKm = dist;
              _shopsMap[s.id] = s;
              validIds.add(s.id);
            }
          }
        }
        if (validIds.isNotEmpty) return validIds;
      }
    } catch (e) {
      debugPrint('[AllListingsPage] _resolveNearbyShopIds error: $e');
    }

    // 2. From widget.shops if already provided, filtering strictly by delivery radius
    if (widget.shops.isNotEmpty) {
      return widget.shops
          .where((s) {
            if (!loc.hasLocation) return true;
            if (s.location.latitude == 0 || s.location.longitude == 0) return false;
            final d = s.distanceKm ?? loc.distanceTo(s.location);
            return DeliveryCalculator.isWithinRange(d);
          })
          .map((s) => s.id)
          .toList();
    }

    // 3. From shops already cached in _shopsMap, filtering strictly by delivery radius
    if (_shopsMap.isNotEmpty) {
      return _shopsMap.values
          .where((s) {
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
      final shopIds = await _resolveNearbyShopIds();
      if (!mounted || shopIds.isEmpty) return;

      // 1. Query exact total product count in database for nearby shops (excluding soft deletes)
      final countResp = await Supabase.instance.client
          .from('products')
          .select('id')
          .inFilter('shop_id', shopIds)
          .eq('is_deleted', false)
          .eq('is_available', true);

      final totalInDb = (countResp as List).length;

      if (mounted) {
        setState(() {
          _totalAvailableProducts =
              math.max(totalInDb, _allProducts.length);
        });
      }

      // If database has more products than the initial preview sample, load next batch immediately
      if (_allProducts.length < totalInDb) {
        await _fetchMoreProductsFromDb(shopIds, config);
      } else {
        if (mounted) {
          setState(() {
            _hasMore = false;
          });
        }
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

      final response = await Supabase.instance.client
          .from('products')
          .select()
          .inFilter('shop_id', shopIds)
          .eq('is_deleted', false)
          .eq('is_available', true)
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

  @override
  void dispose() {
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

  // ── Sorted + filtered shops ───────────────────────────────────────────────
  List<ShopModel> get _sortedShops {
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
      final q = _searchQuery.toLowerCase();
      list = list
          .where((s) =>
              s.name.toLowerCase().contains(q) ||
              (s.cuisineType ?? '').toLowerCase().contains(q) ||
              s.category.toLowerCase().contains(q))
          .toList();
    }

    if (_vegFilterMode == VegFilterMode.vegOnly) {
      list = list.where((s) => s.isVegOnly).toList();
    } else if (_vegFilterMode == VegFilterMode.nonVegOnly) {
      list = list.where((s) => !s.isVegOnly).toList();
    }

    switch (_sortMode) {
      case _AllListingsSortMode.bestRating:
        list.sort((a, b) {
          final rCmp = b.rating.compareTo(a.rating);
          if (rCmp != 0) return rCmp;
          return (a.distanceKm ?? double.infinity)
              .compareTo(b.distanceKm ?? double.infinity);
        });
      case _AllListingsSortMode.nearest:
        list.sort((a, b) => (a.distanceKm ?? double.infinity)
            .compareTo(b.distanceKm ?? double.infinity));
      case _AllListingsSortMode.priceLow:
      case _AllListingsSortMode.priceHigh:
      case _AllListingsSortMode.discount:
        // For shops, these fall back to rating sort
        list.sort((a, b) => b.rating.compareTo(a.rating));
    }
    return list;
  }

  List<ProductModel> get _sortedProducts {
    final loc = context.read<LocationProvider>();
    var list = _allProducts.where((p) {
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
      final q = _searchQuery.toLowerCase();
      list = list
          .where((p) =>
              p.name.toLowerCase().contains(q) ||
              (p.description ?? '').toLowerCase().contains(q) ||
              p.category.toLowerCase().contains(q))
          .toList();
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
                        _searchDebounce = Timer(
                          const Duration(milliseconds: 250),
                          () {
                            if (mounted) {
                              setState(() {
                                _searchQuery = v.trim();
                                _displayLimit = 20;
                              });
                            }
                          },
                        );
                      },
                      decoration: InputDecoration(
                        hintText: 'Search within $_pageTitle...',
                        hintStyle: GoogleFonts.outfit(
                          color: isDark
                              ? Colors.grey.shade500
                              : Colors.grey.shade400,
                          fontSize: 13,
                        ),
                        prefixIcon: const Icon(Icons.search_rounded,
                            color: AppColors.primary, size: 20),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close_rounded, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {
                                    _searchQuery = '';
                                    _displayLimit = 20;
                                    _vegFilterMode = VegFilterMode.all;
                                  });
                                },
                              )
                            : null,
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
                          onTap: () => setState(() => _sortMode = mode),
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

  // ── Products grid ─────────────────────────────────────────────────────────
  Widget _buildProductsBody(bool isDark) {
    final sorted = _sortedProducts;
    if (sorted.isEmpty) return _buildEmptyState(isDark);

    final displayProducts = sorted.take(_displayLimit).toList();

    return CustomScrollView(
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
              final childAspectRatio = itemWidth / (itemWidth + 120);

              return SliverGrid.builder(
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
                  return ProductCard(product: product, shop: shop);
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
                          if (_displayLimit >= sorted.length && _hasMore) {
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
                        'You\'ve reached the end of popular items in your area 🛍️',
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
                  return isFood
                      ? RestaurantShopCard(
                          shop: shop,
                          onTap: () =>
                              showRestaurantDashboardSheet(context, shop.id),
                        )
                      : ShopCard(
                          shop: shop,
                          onTap: () => showShopDetailSheet(context, shop.id),
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
                    setState(() => _displayLimit += 20);
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
                  ? 'Try a different search term.'
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
                    _displayLimit = 20;
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
