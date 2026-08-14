import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/product_model.dart';
import '../../models/shop_model.dart';
import '../../providers/theme_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/platform_config_provider.dart';
import '../../theme/app_colors.dart';
import '../../widgets/product_card.dart';
import '../../utils/responsive_layout.dart';
import '../../utils/delivery_calculator.dart';

class CategoryProductsPage extends StatefulWidget {
  final String categoryName;

  const CategoryProductsPage({super.key, required this.categoryName});

  @override
  State<CategoryProductsPage> createState() => _CategoryProductsPageState();
}

class _CategoryProductsPageState extends State<CategoryProductsPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _isLoading = true;
  bool _hasError = false;
  List<ProductModel> _products = [];
  Map<String, ShopModel> _productShops = {};
  int _displayLimit = 20;
  String _selectedDemographic = 'All';
  String _selectedSize = 'All';
  List<String> _availableSizes = [];

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Guard: if this category is disabled by admin, don't fetch & pop back
      final config = context.read<PlatformConfigProvider>();
      if (!config.isActiveCategory(widget.categoryName)) {
        Navigator.of(context).pop();
        return;
      }
      _fetchProducts();
    });
  }

  Future<void> _fetchProducts() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final locationProvider = context.read<LocationProvider>();
      final lat = locationProvider.currentLocation?.latitude;
      final lng = locationProvider.currentLocation?.longitude;

      final subcategories =
          _tabCategories[widget.categoryName] ?? [widget.categoryName];

      if (lat != null && lng != null) {
        // Phase 26 Fix (Ported): Fetch products WITHOUT .select('*, shops(*)')
        // which causes PostgREST to reject embedded-resource requests on
        // SECURITY DEFINER SETOF RPCs. Batch-fetch shops separately instead.
        // Phase 31 Fix: Bypass PostgREST overload bug entirely
        final nearbyShops =
            await _supabase.rpc('search_shops_geospatial', params: {
          'p_lat': lat,
          'p_lng': lng,
          'p_query': null,
          'p_categories': subcategories,
          'p_radius_km': DeliveryCalculator.maxRadiusKm,
          'p_limit': 150,
        });

        List<dynamic> rawProducts = [];
        final shopIds =
            (nearbyShops as List).map((s) => s['id'] as String).toList();

        if (shopIds.isNotEmpty) {
          var q = _supabase
              .from('products')
              .select()
              .eq('is_deleted', false)
              .eq('is_available', true)
              .inFilter('shop_id', shopIds);

          if (_selectedDemographic != 'All') {
            final List<String> overlapTags = [
              '#$_selectedDemographic',
              '#Unisex'
            ];
            if (_selectedDemographic == 'Boys' ||
                _selectedDemographic == 'Girls') {
              overlapTags.add('#Kids');
            }
            q = q.overlaps('special_tags', overlapTags);
          }

          final allProducts = await q;

          final filteredProducts = _selectedSize == 'All'
              ? allProducts
              : allProducts.where((p) {
                  final variants = p['variants'] as List<dynamic>? ?? [];
                  return variants.any((v) {
                    final name = (v['name'] as String?)?.trim() ?? '';
                    return name == _selectedSize;
                  });
                }).toList();

          final productsByShop = <String, List<dynamic>>{};
          for (final p in filteredProducts) {
            final sid = p['shop_id'] as String;
            productsByShop.putIfAbsent(sid, () => []).add(p);
          }

          for (final shop in nearbyShops) {
            final sid = shop['id'] as String;
            if (productsByShop.containsKey(sid)) {
              final shopProds = productsByShop[sid]!;
              shopProds.sort((a, b) {
                final ratingA = (a['rating'] as num?)?.toDouble() ?? 0.0;
                final ratingB = (b['rating'] as num?)?.toDouble() ?? 0.0;
                return ratingB.compareTo(ratingA);
              });
              rawProducts.addAll(shopProds.take(5));
              if (rawProducts.length >= 150) break;
            }
          }
          if (rawProducts.length > 150) {
            rawProducts = rawProducts.sublist(0, 150);
          }
        }

        // Collect unique shop_ids for a single batch query
        final Set<String> productShopIds = {};
        for (final p in rawProducts) {
          final sid = (p as Map<String, dynamic>)['shop_id'] as String?;
          if (sid != null && sid.isNotEmpty) productShopIds.add(sid);
        }

        // Single batch query for all referenced shops
        final Map<String, Map<String, dynamic>> shopById = {};
        if (productShopIds.isNotEmpty) {
          final shopRows = await _supabase
              .from('shops')
              .select('*')
              .inFilter('id', productShopIds.toList());
          for (final s in shopRows as List) {
            final sm = s as Map<String, dynamic>;
            shopById[sm['id'] as String] = sm;
          }
        }

        // Reconstruct with 'shops' key for downstream ProductModel parsing
        final productsResponse = rawProducts.map((p) {
          final m = Map<String, dynamic>.from(p as Map<String, dynamic>);
          m['shops'] = shopById[m['shop_id'] as String?];
          return m;
        }).toList();

        final prods = <ProductModel>[];
        final prodShops = <String, ShopModel>{};

        for (final p in productsResponse) {
          final product = ProductModel.fromMap(p);
          if (!product.isAvailable) continue;
          if (p['shops'] == null) continue;

          final shop = ShopModel.fromMap(p['shops']);
          if (!shop.isActive) continue;

          if (shop.location.latitude != 0 && shop.location.longitude != 0) {
            shop.distanceKm = locationProvider.distanceTo(shop.location);
          }

          prods.add(product);
          prodShops[product.id] = shop;
        }

        // Sort by availability first, then by rating
        prods.sort((a, b) {
          final sA = prodShops[a.id];
          final sB = prodShops[b.id];
          final availA = a.isAvailable && (sA?.isOpenRightNow ?? true);
          final availB = b.isAvailable && (sB?.isOpenRightNow ?? true);

          if (availA && !availB) return -1;
          if (!availA && availB) return 1;

          return b.rating.compareTo(a.rating);
        });

        if (mounted) {
          setState(() {
            _products = prods;
            _productShops = prodShops;
            _isLoading = false;

            if (_selectedSize == 'All') {
              final Set<String> sizes = {};
              for (final p in prods) {
                if (_selectedDemographic != 'All') {
                  final List<String> allowedTags = [
                    '#$_selectedDemographic',
                    '#Unisex'
                  ];
                  if (_selectedDemographic == 'Boys' ||
                      _selectedDemographic == 'Girls') {
                    allowedTags.add('#Kids');
                  }
                  if (!p.specialTags.any((tag) => allowedTags.contains(tag))) {
                    continue;
                  }
                }
                for (final v in p.variants) {
                  if (v.name.trim().isNotEmpty && v.isAvailable) {
                    sizes.add(v.name.trim());
                  }
                }
              }
              _availableSizes = sizes.toList()..sort();
            }
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('CategoryProductsPage Error: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildShimmer(bool isDark) {
    final shimmerBase =
        isDark ? const Color(0xFF1E1E2E) : const Color(0xFFF0F0F8);
    final shimmerHigh =
        isDark ? const Color(0xFF2A2A3E) : const Color(0xFFE0E0E8);

    return Shimmer.fromColors(
      baseColor: shimmerBase,
      highlightColor: shimmerHigh,
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.7,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
        ),
        itemCount: 8,
        itemBuilder: (_, __) => Container(
          decoration: BoxDecoration(
            color: shimmerBase,
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDarkMode;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          widget.categoryName,
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w800,
            fontSize: 20,
            color: isDark ? Colors.white : AppColors.textPrimary,
          ),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme:
            IconThemeData(color: isDark ? Colors.white : AppColors.textPrimary),
        bottom: ([
          'Clothing',
          'Footwear',
          'Jewellery',
          'Cosmetics & Beauty',
          'Salon & Beauty'
        ].contains(widget.categoryName))
            ? PreferredSize(
                preferredSize:
                    Size.fromHeight(_availableSizes.isNotEmpty ? 100 : 50),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      child: Row(
                        children: ['All', 'Men', 'Women', 'Boys', 'Girls']
                            .map((demo) => Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: Text(demo),
                                    selected: _selectedDemographic == demo,
                                    onSelected: (selected) {
                                      if (selected) {
                                        setState(() {
                                          _selectedDemographic = demo;
                                          _selectedSize = 'All';
                                          _fetchProducts();
                                        });
                                      }
                                    },
                                    selectedColor: AppColors.primary,
                                    labelStyle: TextStyle(
                                      color: _selectedDemographic == demo
                                          ? Colors.white
                                          : (isDark
                                              ? Colors.white
                                              : AppColors.textPrimary),
                                    ),
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                    if (_availableSizes.isNotEmpty)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        child: Row(
                          children: ['All', ..._availableSizes]
                              .map((size) => Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ChoiceChip(
                                      label: Text(size),
                                      selected: _selectedSize == size,
                                      onSelected: (selected) {
                                        if (selected) {
                                          setState(() {
                                            _selectedSize = size;
                                            _fetchProducts();
                                          });
                                        }
                                      },
                                      selectedColor: AppColors.primary
                                          .withValues(alpha: 0.2),
                                      backgroundColor: isDark
                                          ? const Color(0xFF2A2A3E)
                                          : Colors.grey.shade100,
                                      labelStyle: TextStyle(
                                        color: _selectedSize == size
                                            ? AppColors.primary
                                            : (isDark
                                                ? Colors.white70
                                                : Colors.black),
                                      ),
                                      side: BorderSide(
                                          color: _selectedSize == size
                                              ? AppColors.primary
                                              : Colors.transparent),
                                    ),
                                  ))
                              .toList(),
                        ),
                      ),
                  ],
                ),
              )
            : null,
      ),
      body: _isLoading
          ? _buildShimmer(isDark)
          : _hasError
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline_rounded,
                          size: 64,
                          color: AppColors.danger.withValues(alpha: 0.7)),
                      const SizedBox(height: 16),
                      Text(
                        'Oops! Something went wrong.',
                        style: GoogleFonts.outfit(
                            fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _fetchProducts,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text('Retry',
                            style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                )
              : _products.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inventory_2_outlined,
                              size: 64,
                              color: isDark ? Colors.white30 : Colors.black26),
                          const SizedBox(height: 16),
                          Text(
                            'No products found',
                            style: GoogleFonts.outfit(
                                fontSize: 20, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'We couldn\'t find any products for this category.',
                            style: GoogleFonts.outfit(
                                color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final crossAxisCount = Responsive.getGridCrossAxisCount(
                            context,
                            mobile: 2,
                            tablet: 4,
                            desktop: 5);
                        const crossAxisSpacing = 16.0;
                        final availableWidth = constraints.maxWidth;
                        final itemWidth = (availableWidth -
                                (crossAxisSpacing * (crossAxisCount + 1))) /
                            crossAxisCount;
                        final itemHeight = itemWidth + 178;
                        final childAspectRatio = itemWidth / itemHeight;

                        var filteredProducts = _products;
                        if (_selectedDemographic != 'All') {
                          final List<String> allowedTags = [
                            '#$_selectedDemographic',
                            '#Unisex'
                          ];
                          if (_selectedDemographic == 'Boys' ||
                              _selectedDemographic == 'Girls') {
                            allowedTags.add('#Kids');
                          }
                          filteredProducts = filteredProducts
                              .where((p) => p.specialTags
                                  .any((tag) => allowedTags.contains(tag)))
                              .toList();
                        }

                        final displayProducts =
                            filteredProducts.take(_displayLimit).toList();

                        return CustomScrollView(
                          slivers: [
                            SliverPadding(
                              padding: const EdgeInsets.all(16),
                              sliver: SliverGrid.builder(
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
                                  return ProductCard(
                                      product: product, shop: shop);
                                },
                              ),
                            ),
                            if (filteredProducts.length > _displayLimit)
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding:
                                      const EdgeInsets.only(top: 8, bottom: 24),
                                  child: Center(
                                    child: TextButton(
                                      onPressed: () =>
                                          setState(() => _displayLimit += 20),
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
                                        'Load more products',
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
                        );
                      },
                    ),
    );
  }
}
