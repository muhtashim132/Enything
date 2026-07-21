import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../config/app_categories.dart';
import '../../models/product_model.dart';
import '../../models/shop_model.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_colors.dart';
import '../../widgets/product_card.dart';
import '../../widgets/shop_card.dart';
import '../../widgets/restaurant_shop_card.dart';
import '../../widgets/shop_detail_sheet.dart';
import '../../widgets/restaurant_dashboard_sheet.dart';
import '../../utils/responsive_layout.dart';

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
/// products. Receives pre-fetched data from the home page — makes zero
/// Supabase calls so the existing SQL / RPC logic is entirely untouched.
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

  final _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;

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
    var list = widget.shops.toList();
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list
          .where((s) =>
              s.name.toLowerCase().contains(q) ||
              (s.cuisineType ?? '').toLowerCase().contains(q) ||
              s.category.toLowerCase().contains(q))
          .toList();
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

  // ── Sorted + filtered products ────────────────────────────────────────────
  List<ProductModel> get _sortedProducts {
    var list = widget.products.toList();
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list
          .where((p) =>
              p.name.toLowerCase().contains(q) ||
              (p.description ?? '').toLowerCase().contains(q) ||
              p.category.toLowerCase().contains(q))
          .toList();
    }
    switch (_sortMode) {
      case _AllListingsSortMode.bestRating:
        list.sort((a, b) => b.rating.compareTo(a.rating));
      case _AllListingsSortMode.nearest:
        list.sort((a, b) {
          final sA = widget.productShops[a.id];
          final sB = widget.productShops[b.id];
          return (sA?.distanceKm ?? double.infinity)
              .compareTo(sB?.distanceKm ?? double.infinity);
        });
      case _AllListingsSortMode.priceLow:
        list.sort((a, b) => a.price.compareTo(b.price));
      case _AllListingsSortMode.priceHigh:
        list.sort((a, b) => b.price.compareTo(a.price));
      case _AllListingsSortMode.discount:
        list.sort((a, b) =>
            (b.discountPercent ?? 0).compareTo(a.discountPercent ?? 0));
    }
    return list;
  }

  bool get _isProducts => widget.type == ListingType.products;

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
    final isDark = themeProvider.isDarkMode;
    final totalCount =
        _isProducts ? widget.products.length : widget.shops.length;

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
                            if (mounted) setState(() => _searchQuery = v.trim());
                          },
                        );
                      },
                      decoration: InputDecoration(
                        hintText:
                            'Search within $_pageTitle...',
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
                                icon:
                                    const Icon(Icons.close_rounded, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
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
                          borderSide: BorderSide.none,
                        ),
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
                  // ── Sort chips ──────────────────────────────────────
                  SizedBox(
                    height: 46,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      itemCount: _sortFilters.length,
                      itemBuilder: (context, index) {
                        final f = _sortFilters[index];
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
        body: _isProducts
            ? _buildProductsBody(isDark)
            : _buildShopsBody(isDark),
      ),
    );
  }

  // ── Products grid ─────────────────────────────────────────────────────────
  Widget _buildProductsBody(bool isDark) {
    final sorted = _sortedProducts;
    if (sorted.isEmpty) return _buildEmptyState(isDark);

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          sliver: SliverLayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = Responsive.getGridCrossAxisCount(
                  context,
                  mobile: 2,
                  tablet: 4,
                  desktop: 5);
              const crossAxisSpacing = 16.0;
              final itemWidth =
                  (constraints.crossAxisExtent -
                          crossAxisSpacing * (crossAxisCount - 1)) /
                      crossAxisCount;
              final childAspectRatio = itemWidth / (itemWidth + 178);

              return SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: childAspectRatio,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: crossAxisSpacing,
                ),
                itemCount: sorted.length,
                itemBuilder: (_, i) {
                  final product = sorted[i];
                  final shop = widget.productShops[product.id];
                  return ProductCard(product: product, shop: shop);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Shops/Restaurants grid ────────────────────────────────────────────────
  Widget _buildShopsBody(bool isDark) {
    final sorted = _sortedShops;
    if (sorted.isEmpty) return _buildEmptyState(isDark);

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          sliver: SliverLayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = Responsive.getGridCrossAxisCount(
                  context,
                  mobile: 1,
                  tablet: 2,
                  desktop: 3);

              return SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisExtent: 280,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: sorted.length,
                itemBuilder: (_, i) {
                  final shop = sorted[i];
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
                          onTap: () =>
                              showShopDetailSheet(context, shop.id),
                        );
                },
              );
            },
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
              hasSearch
                  ? 'No results for "$_searchQuery"'
                  : 'Nothing here yet',
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
                  setState(() => _searchQuery = '');
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
          ],
        ),
      ),
    );
  }
}
