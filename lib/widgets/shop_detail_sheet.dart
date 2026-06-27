import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import '../models/product_model.dart';
import '../models/shop_model.dart';
import '../providers/favorites_provider.dart';
import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';
import 'product_card.dart';
import 'common/enything_map.dart';
import '../utils/share_utils.dart';
import 'common/sheet_skeleton_loader.dart';

void showShopDetailSheet(BuildContext context, String shopId) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    useRootNavigator: true,
    clipBehavior: Clip.antiAliasWithSaveLayer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => ShopDetailSheet(shopId: shopId),
  );
}

class ShopDetailSheet extends StatefulWidget {
  final String shopId;
  const ShopDetailSheet({super.key, required this.shopId});

  @override
  State<ShopDetailSheet> createState() => _ShopDetailSheetState();
}

class _ShopDetailSheetState extends State<ShopDetailSheet> {
  final _supabase = Supabase.instance.client;
  ShopModel? _shop;
  List<ProductModel> _products = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      final shopData = await _supabase
          .from('shops')
          .select()
          .eq('id', widget.shopId)
          .single();

      final productsData = await _supabase
          .from('products')
          .select()
          .eq('shop_id', widget.shopId)
          .eq('is_available', true);

      if (mounted) {
        setState(() {
          _shop = ShopModel.fromMap(shopData);
          _products = (productsData as List)
              .map((p) => ProductModel.fromMap(p))
              .toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 1.0,
      snap: true,
      snapSizes: const [0.65, 1.0],
      builder: (context, scrollController) {
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0D0D1A) : const Color(0xFFF7F8FC),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: _isLoading
              ? SheetSkeletonLoader(isDark: isDark)
              : _shop == null
                  ? const Center(child: Text('Shop not found'))
                  : _SheetContent(
                      shop: _shop!,
                      products: _products,
                      scrollController: scrollController,
                      isDark: isDark,
                    ),
        );
      },
    );
  }
}

class _SheetContent extends StatefulWidget {
  final ShopModel shop;
  final List<ProductModel> products;
  final ScrollController scrollController;
  final bool isDark;

  const _SheetContent({
    required this.shop,
    required this.products,
    required this.scrollController,
    required this.isDark,
  });

  @override
  State<_SheetContent> createState() => _SheetContentState();
}

class _SheetContentState extends State<_SheetContent> {
  String _selectedCategory = 'All';

  ShopModel get shop => widget.shop;
  List<ProductModel> get allProducts => widget.products;
  bool get isDark => widget.isDark;

  // Deduplicated ordered category list from products
  List<String> get _categories {
    final Map<String, String> catsMap = {'all': 'All'};
    for (final p in allProducts) {
      final cat = p.category.trim();
      if (cat.isNotEmpty) {
        final lower = cat.toLowerCase();
        if (!catsMap.containsKey(lower)) catsMap[lower] = cat;
      }
    }
    return catsMap.values.toList();
  }

  List<ProductModel> get _filteredProducts => _selectedCategory == 'All'
      ? allProducts
      : allProducts
          .where((p) =>
              p.category.trim().toLowerCase() ==
              _selectedCategory.toLowerCase())
          .toList();

  @override
  Widget build(BuildContext context) {
    final favs = context.watch<FavoritesProvider>();
    final auth = context.watch<AuthProvider>();
    final isFav = favs.isShopFavorite(shop.id);
    final filteredProducts = _filteredProducts;
    final cats = _categories;

    return CustomScrollView(
      controller: widget.scrollController,
      slivers: [
        // Drag handle
        SliverToBoxAdapter(
          child: Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),

        // Hero SliverAppBar
        SliverAppBar(
          expandedHeight: 230,
          pinned: true,
          stretch: true,
          elevation: 0,
          backgroundColor:
              isDark ? const Color(0xFF0D0D1A) : const Color(0xFFF7F8FC),
          leading: const SizedBox.shrink(),
          leadingWidth: 0,
          actions: [
            // Share button
            GestureDetector(
              onTap: () => ShareUtils.shareShop(shop),
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 10)
                  ],
                ),
                child: const Icon(Icons.ios_share_rounded,
                    size: 18, color: AppColors.primary),
              ),
            ),
            // Favourite button
            GestureDetector(
              onTap: () {
                if (auth.currentUserId != null) {
                  favs.toggleShopFavorite(auth.currentUserId!, shop.id);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: isFav
                      ? Colors.red.withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.92),
                  shape: BoxShape.circle,
                  border: isFav
                      ? Border.all(
                          color: Colors.red.withValues(alpha: 0.3), width: 1.5)
                      : null,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 10)
                  ],
                ),
                child: Icon(
                  isFav
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: isFav ? Colors.red : AppColors.textSecondary,
                  size: 20,
                ),
              ),
            ),
          ],
          flexibleSpace: FlexibleSpaceBar(
            titlePadding: EdgeInsets.zero,
            background: Stack(
              fit: StackFit.expand,
              children: [
                shop.bannerImage != null
                    ? CachedNetworkImage(
                        imageUrl: shop.bannerImage!,
                        fit: BoxFit.cover,
                        errorWidget: (c, e, s) => _heroBannerPlaceholder(),
                      )
                    : _heroBannerPlaceholder(),
                // Gradient overlay
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.75),
                      ],
                      stops: const [0.0, 0.4, 1.0],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
                // Shop name at bottom
                Positioned(
                  bottom: 20,
                  left: 20,
                  right: 72,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shop.name,
                        style: GoogleFonts.outfit(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -0.4,
                          shadows: const [
                            Shadow(blurRadius: 16, color: Colors.black54),
                          ],
                        ),
                      ),
                      if (shop.cuisineType != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          shop.cuisineType!,
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.82),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Info section
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Stats row
                Row(
                  children: [
                    _statCard(
                      context: context,
                      label: shop.totalReviews > 0
                          ? shop.rating.toStringAsFixed(1)
                          : 'New',
                      sub: 'Rating',
                      icon: Icons.star_rounded,
                      iconColor: const Color(0xFF48BB78),
                      gradColors: isDark
                          ? [
                              const Color(0xFF1A2A1A),
                              const Color(0xFF162416)
                            ]
                          : [const Color(0xFFF0FFF4), Colors.white],
                      isDark: isDark,
                    ),
                    const SizedBox(width: 10),
                    _statCard(
                      context: context,
                      label: '${shop.prepTimeMinutes} min',
                      sub: 'Prep time',
                      icon: Icons.timer_rounded,
                      iconColor: const Color(0xFF4299E1),
                      gradColors: isDark
                          ? [
                              const Color(0xFF1A1E2A),
                              const Color(0xFF141824)
                            ]
                          : [const Color(0xFFEBF8FF), Colors.white],
                      isDark: isDark,
                    ),
                    const SizedBox(width: 10),
                    _statCard(
                      context: context,
                      label: '${shop.totalOrders}+',
                      sub: 'Orders',
                      icon: Icons.receipt_long_rounded,
                      iconColor: const Color(0xFFED8936),
                      gradColors: isDark
                          ? [
                              const Color(0xFF2A1E10),
                              const Color(0xFF241810)
                            ]
                          : [const Color(0xFFFFFAF0), Colors.white],
                      isDark: isDark,
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Address card
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: isDark
                        ? Border.all(
                            color: Colors.white.withValues(alpha: 0.08))
                        : Border.all(color: Colors.grey.shade100),
                    boxShadow: isDark
                        ? []
                        : [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 8)
                          ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.location_on_rounded,
                            size: 14, color: AppColors.primary),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          shop.address,
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            color: isDark
                                ? Colors.white60
                                : AppColors.textSecondary,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Map
                if (shop.location.latitude != 0 &&
                    shop.location.longitude != 0) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      height: 150,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.grey.shade200,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: EnythingMap(
                          center: shop.location,
                          zoom: 15,
                          interactive: false,
                        ),
                      ),
                    ),
                  ),
                ],

                // Badge row
                if (shop.cuisineType != null || shop.isVegOnly) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (shop.isVegOnly)
                        _modernBadge('Pure Veg', Icons.eco,
                            Colors.green.shade600, isDark),
                      if (shop.cuisineType != null)
                        _modernBadge(shop.cuisineType!,
                            Icons.restaurant_menu_rounded,
                            AppColors.foodRed, isDark),
                    ],
                  ),
                ],

                const SizedBox(height: 16),
                Divider(
                  height: 1,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.grey.shade100,
                ),
              ],
            ),
          ),
        ),

        // ── Category filter chips ──────────────────────────────────────────
        if (cats.length > 1)
          SliverToBoxAdapter(
            child: SizedBox(
              height: 48,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: cats.length,
                itemBuilder: (_, i) {
                  final cat = cats[i];
                  final isSelected = _selectedCategory == cat;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedCategory = cat),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary
                            : isDark
                                ? Colors.white.withValues(alpha: 0.07)
                                : const Color(0xFFF0F4FF),
                        borderRadius: BorderRadius.circular(20),
                        border: isSelected
                            ? null
                            : Border.all(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.12)
                                    : Colors.grey.shade200),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                    color: AppColors.primary.withValues(alpha: 0.35),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3))
                              ]
                            : [],
                      ),
                      child: Text(
                        cat,
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                          color: isSelected
                              ? Colors.white
                              : isDark
                                  ? Colors.white60
                                  : const Color(0xFF4A5568),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

        // Products header
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Text(
                  _selectedCategory == 'All' ? 'Products' : _selectedCategory,
                  style: GoogleFonts.outfit(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primary.withValues(alpha: 0.12),
                        AppColors.primary.withValues(alpha: 0.08),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.2)),
                  ),
                  child: Text(
                    '${filteredProducts.length} items',
                    style: GoogleFonts.outfit(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Products grid
        if (filteredProducts.isEmpty)
          SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : const Color(0xFFF0F0F8),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Text('🛍️', style: TextStyle(fontSize: 36)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'No products in this category',
                      style: GoogleFonts.outfit(
                          color: AppColors.textSecondary, fontSize: 15),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.54,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => ProductCard(
                  product: filteredProducts[index],
                  shop: shop,
                ),
                childCount: filteredProducts.length,
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  Widget _heroBannerPlaceholder() => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1E3FD8), Color(0xFF3D6BFF), Color(0xFF6B9FFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const Center(
          child: Text('🛍️', style: TextStyle(fontSize: 64)),
        ),
      );

  Widget _statCard({
    required BuildContext context,
    required String label,
    required String sub,
    required IconData icon,
    required Color iconColor,
    required List<Color> gradColors,
    required bool isDark,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: isDark
              ? Border.all(color: Colors.white.withValues(alpha: 0.08))
              : Border.all(color: Colors.grey.shade100),
          boxShadow: isDark
              ? []
              : [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 3)),
                ],
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: iconColor),
                const SizedBox(width: 4),
                Text(label,
                    style: GoogleFonts.outfit(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: isDark
                            ? Colors.white
                            : const Color(0xFF1A1A2E))),
              ],
            ),
            const SizedBox(height: 3),
            Text(sub,
                style: GoogleFonts.outfit(
                    fontSize: 11,
                    color: isDark
                        ? Colors.white54
                        : AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _modernBadge(
      String label, IconData icon, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? color.withValues(alpha: 0.15)
            : color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: GoogleFonts.outfit(
                  fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

