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
  
  static const Map<String, List<String>> _tabCategories = {
    'Food': ['Restaurant', 'Fast Food', 'Bakery', 'Sweets & Mithai', 'Tea & Coffee', 'Ice Cream', 'Paan Shop', 'Beverages'],
    'Grocery': ['Grocery', 'Supermarket / Hypermarket', 'Fruits & Vegs', 'Dairy & Eggs', 'Butcher', 'Fish & Seafood', 'Organic'],
    'Pharmacy': ['Pharmacy', 'Medical Store'],
    'Clothing': ['Clothing', 'Footwear', 'Jewellery'],
    'Electronics': ['Electronics', 'Mobile & Repair'],
    'More': ['Hardware Store', 'Stationery', 'Toys & Games', 'Sports', 'Pet Supplies', 'Cosmetics & Beauty', 'Salon & Beauty', 'Flowers', 'Home Decor', 'Furniture', 'Auto Parts', 'Other'],
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
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

      final subcategories = _tabCategories[widget.categoryName] ?? [widget.categoryName];

      if (lat != null && lng != null) {
        final productsResponse = await _supabase.rpc('search_products_geospatial', params: {
          'p_lat': lat,
          'p_lng': lng,
          'p_query': null,
          'p_categories': subcategories,
          'p_radius_km': DeliveryCalculator.maxRadiusKm,
          'p_limit': 150
        }).select('*, shops(*)');

        final prods = <ProductModel>[];
        final prodShops = <String, ShopModel>{};

        for (final p in productsResponse) {
          final product = ProductModel.fromMap(p);
          if (!product.isAvailable) continue;
          if (p['shops'] == null) continue;

          final shop = ShopModel.fromMap(p['shops']);
          if (!shop.isActive || !shop.isOpenRightNow) continue;

          if (shop.location.latitude != 0 && shop.location.longitude != 0) {
            shop.distanceKm = locationProvider.distanceTo(shop.location);
          }

          prods.add(product);
          prodShops[product.id] = shop;
        }

        // Sort by rating first
        prods.sort((a, b) => b.rating.compareTo(a.rating));

        if (mounted) {
          setState(() {
            _products = prods;
            _productShops = prodShops;
            _isLoading = false;
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
    final shimmerBase = isDark ? const Color(0xFF1E1E2E) : const Color(0xFFF0F0F8);
    final shimmerHigh = isDark ? const Color(0xFF2A2A3E) : const Color(0xFFE0E0E8);
    
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
        iconTheme: IconThemeData(color: isDark ? Colors.white : AppColors.textPrimary),
      ),
      body: _isLoading
          ? _buildShimmer(isDark)
          : _hasError
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline_rounded, size: 64, color: AppColors.danger.withValues(alpha: 0.7)),
                      const SizedBox(height: 16),
                      Text(
                        'Oops! Something went wrong.',
                        style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _fetchProducts,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text('Retry', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                )
              : _products.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 64, color: isDark ? Colors.white30 : Colors.black26),
                          const SizedBox(height: 16),
                          Text(
                            'No products found',
                            style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'We couldn\'t find any products for this category.',
                            style: GoogleFonts.outfit(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final crossAxisCount = Responsive.getGridCrossAxisCount(context, mobile: 2, tablet: 4, desktop: 5);
                        const crossAxisSpacing = 16.0;
                        final availableWidth = constraints.maxWidth;
                        final itemWidth = (availableWidth - (crossAxisSpacing * (crossAxisCount + 1))) / crossAxisCount;
                        final itemHeight = itemWidth + 178;
                        final childAspectRatio = itemWidth / itemHeight;

                        return GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            childAspectRatio: childAspectRatio,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: crossAxisSpacing,
                          ),
                          itemCount: _products.length,
                          itemBuilder: (context, index) {
                            final product = _products[index];
                            final shop = _productShops[product.id];
                            return ProductCard(product: product, shop: shop);
                          },
                        );
                      },
                    ),
    );
  }
}
