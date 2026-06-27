import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/shop_model.dart';
import '../models/product_model.dart';
import '../providers/cart_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';
import '../config/routes.dart';
import 'common/sheet_skeleton_loader.dart';
import 'product_detail_sheet.dart';

void showRestaurantDashboardSheet(BuildContext context, String shopId) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    useRootNavigator: true,
    builder: (_) => RestaurantDashboardSheet(shopId: shopId),
  );
}

class RestaurantDashboardSheet extends StatefulWidget {
  final String shopId;
  const RestaurantDashboardSheet({super.key, required this.shopId});

  @override
  State<RestaurantDashboardSheet> createState() =>
      _RestaurantDashboardSheetState();
}

class _RestaurantDashboardSheetState extends State<RestaurantDashboardSheet>
    with TickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  ShopModel? _shop;
  List<ProductModel> _products = [];
  bool _isLoading = true;
  String _selectedCategory = 'All';

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

  List<String> get _menuCategories {
    final Map<String, String> catsMap = {'all': 'All'};
    for (final p in _products) {
      if (p.menuCategory != null && p.menuCategory!.trim().isNotEmpty) {
        final lower = p.menuCategory!.trim().toLowerCase();
        if (!catsMap.containsKey(lower)) {
          catsMap[lower] = p.menuCategory!.trim();
        }
      }
    }
    return catsMap.values.toList();
  }

  List<ProductModel> get _filteredProducts => _selectedCategory == 'All'
      ? _products
      : _products
          .where((p) =>
              p.menuCategory != null &&
              p.menuCategory!.trim().toLowerCase() ==
                  _selectedCategory.toLowerCase())
          .toList();

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
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0D0D1A) : const Color(0xFFF7F8FC),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: _isLoading
              ? SheetSkeletonLoader(isDark: isDark)
              : _shop == null
                  ? const Center(child: Text('Restaurant not found'))
                  : Stack(
                      children: [
                        CustomScrollView(
                          controller: scrollController,
                          slivers: [
                            // Drag handle
                            SliverToBoxAdapter(
                              child: Center(
                                child: Container(
                                  margin: const EdgeInsets.only(
                                      top: 12, bottom: 4),
                                  width: 44,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white24
                                        : Colors.grey.shade300,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            ),
                            _buildHeroAppBar(isDark),
                            _buildInfoStrip(isDark),
                            _buildCategoryTabs(isDark),
                            _buildMenuGrid(isDark),
                            const SliverToBoxAdapter(
                                child: SizedBox(height: 120)),
                          ],
                        ),
                        // Sticky cart bar at bottom
                        Consumer<CartProvider>(
                          builder: (context, cart, child) {
                            if (cart.totalItemCount > 0) {
                              return Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: _buildCartBar(cart),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ],
                    ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Hero SliverAppBar
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildHeroAppBar(bool isDark) {
    final favs = context.watch<FavoritesProvider>();
    final auth = context.watch<AuthProvider>();
    final isFav = favs.isShopFavorite(_shop!.id);

    return SliverAppBar(
      expandedHeight: 230,
      pinned: true,
      stretch: true,
      elevation: 0,
      backgroundColor:
          isDark ? const Color(0xFF0D0D1A) : const Color(0xFFF7F8FC),
      leading: const SizedBox.shrink(),
      leadingWidth: 0,
      actions: [
        GestureDetector(
          onTap: () {
            if (auth.currentUserId != null) {
              favs.toggleShopFavorite(auth.currentUserId!, _shop!.id);
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
        stretchModes: const [StretchMode.zoomBackground],
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Banner image
            _shop!.bannerImage != null
                ? CachedNetworkImage(
                    imageUrl: _shop!.bannerImage!,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => _heroBannerPlaceholder(),
                    errorWidget: (_, __, ___) => _heroBannerPlaceholder(),
                  )
                : _heroBannerPlaceholder(),
            // Cinematic gradient overlay
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.80),
                  ],
                  stops: const [0.0, 0.45, 1.0],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            // Name + cuisine at bottom
            Positioned(
              bottom: 20,
              left: 20,
              right: 72,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Bestseller badge
                  if (_shop!.rating >= 4.2 && _shop!.totalReviews > 20) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF9F43), Color(0xFFEE5A24)],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.local_fire_department_rounded,
                              size: 11, color: Colors.white),
                          const SizedBox(width: 4),
                          Text('BESTSELLER',
                              style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.6)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    _shop!.name,
                    style: GoogleFonts.outfit(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.5,
                      shadows: const [
                        Shadow(blurRadius: 16, color: Colors.black54),
                      ],
                    ),
                  ),
                  if (_shop!.cuisineType != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _shop!.cuisineType!,
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
    );
  }

  Widget _heroBannerPlaceholder() => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1A0040), Color(0xFF4A0080), Color(0xFF6D1B9A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const Center(
          child: Text('🍽️', style: TextStyle(fontSize: 72)),
        ),
      );

  // ─────────────────────────────────────────────────────────────────────────
  // Info strip — glassmorphism stat boxes
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildInfoStrip(bool isDark) {
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Stats row
            Row(
              children: [
                _statCard(
                  label: _shop!.totalReviews > 0
                      ? _shop!.rating.toStringAsFixed(1)
                      : 'New',
                  sub: 'Rating',
                  icon: Icons.star_rounded,
                  iconColor: const Color(0xFF48BB78),
                  gradColors: isDark
                      ? [const Color(0xFF1A2A1A), const Color(0xFF162416)]
                      : [const Color(0xFFF0FFF4), Colors.white],
                  isDark: isDark,
                ),
                const SizedBox(width: 10),
                _statCard(
                  label: '${_shop!.prepTimeMinutes} min',
                  sub: 'Prep time',
                  icon: Icons.timer_rounded,
                  iconColor: const Color(0xFF4299E1),
                  gradColors: isDark
                      ? [const Color(0xFF1A1E2A), const Color(0xFF141824)]
                      : [const Color(0xFFEBF8FF), Colors.white],
                  isDark: isDark,
                ),
                const SizedBox(width: 10),
                _statCard(
                  label: '${_shop!.totalOrders}+',
                  sub: 'Orders',
                  icon: Icons.receipt_long_rounded,
                  iconColor: const Color(0xFFED8936),
                  gradColors: isDark
                      ? [const Color(0xFF2A1E10), const Color(0xFF241810)]
                      : [const Color(0xFFFFFAF0), Colors.white],
                  isDark: isDark,
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Address row
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: isDark
                    ? Border.all(color: Colors.white.withValues(alpha: 0.08))
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
                      _shop!.address,
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

            const SizedBox(height: 12),

            // Badge row
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_shop!.isVegOnly)
                  _modernBadge('Pure Veg', Icons.eco, Colors.green.shade600,
                      isDark),
                if (_shop!.fssaiNumber != null)
                  _modernBadge(
                      'FSSAI: ${_shop!.fssaiNumber}',
                      Icons.verified_outlined,
                      Colors.blue.shade600,
                      isDark),
                if (_shop!.openingHours != null)
                  _modernBadge(_shop!.openingHours!, Icons.access_time_rounded,
                      Colors.grey.shade600, isDark),
              ],
            ),

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
    );
  }

  Widget _statCard({
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
                        color: isDark ? Colors.white : const Color(0xFF1A1A2E))),
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

  // ─────────────────────────────────────────────────────────────────────────
  // Category tabs — underline style (Swiggy-style)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildCategoryTabs(bool isDark) {
    final cats = _menuCategories;
    return SliverPersistentHeader(
      pinned: true,
      delegate: _StickyTabsDelegate(
        child: Container(
          color: isDark ? const Color(0xFF0D0D1A) : const Color(0xFFF7F8FC),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Text(
                  'Menu',
                  style: GoogleFonts.outfit(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: cats.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 4),
                  itemBuilder: (_, i) {
                    final isSelected = _selectedCategory == cats[i];
                    return GestureDetector(
                      onTap: () =>
                          setState(() => _selectedCategory = cats[i]),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primary
                              : (isDark
                                  ? Colors.white.withValues(alpha: 0.07)
                                  : Colors.white),
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
                                      color: AppColors.primary
                                          .withValues(alpha: 0.35),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4)),
                                ]
                              : [],
                        ),
                        child: Text(
                          cats[i],
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isSelected
                                ? Colors.white
                                : (isDark
                                    ? Colors.white60
                                    : AppColors.textSecondary),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
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
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Menu list — premium food item rows
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildMenuGrid(bool isDark) {
    final items = _filteredProducts;

    if (items.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Center(
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
                    child: Text('🍽️', style: TextStyle(fontSize: 38)),
                  ),
                ),
                const SizedBox(height: 14),
                Text('No items in this category',
                    style: GoogleFonts.outfit(
                        color: AppColors.textSecondary, fontSize: 15)),
              ],
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (_, i) => _buildMenuItem(items[i], isDark),
          childCount: items.length,
        ),
      ),
    );
  }

  Widget _buildMenuItem(ProductModel product, bool isDark) {
    final cart = context.read<CartProvider>();
    final quantity = cart.getItemQuantity(product.id);
    final isVeg = product.isVeg;
    final isBestseller =
        product.rating >= 4.2 && product.totalReviews > 10;
    final hasDiscount = product.discountPercent != null &&
        product.discountPercent! > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: isDark
            ? Border.all(color: Colors.white.withValues(alpha: 0.07))
            : null,
        boxShadow: [
          BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.3)
                  : Colors.black.withValues(alpha: 0.06),
              blurRadius: 14,
              offset: const Offset(0, 5)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Info ───────────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [


                  // Bestseller tag
                  if (isBestseller) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF9F43), Color(0xFFEE5A24)],
                        ),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.local_fire_department_rounded,
                              size: 10, color: Colors.white),
                          const SizedBox(width: 3),
                          Text('Bestseller',
                              style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],

                  Text(
                    product.name,
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                    ),
                  ),
                  if (product.description != null &&
                      product.description!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      product.description!,
                      style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: isDark
                              ? Colors.white54
                              : AppColors.textSecondary,
                          height: 1.4),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        '₹${product.price.toStringAsFixed(0)}',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                        ),
                      ),
                      if (hasDiscount) ...[
                        const SizedBox(width: 6),
                        Text(
                          '₹${product.originalPrice!.toStringAsFixed(0)}',
                          style: GoogleFonts.outfit(
                            color: isDark
                                ? Colors.white38
                                : AppColors.textLight,
                            fontSize: 12,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF3366)
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${product.discountPercent!.toStringAsFixed(0)}% off',
                            style: GoogleFonts.outfit(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFFFF3366)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // ── Image + Add button ────────────────────────────────────
            Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: product.displayImage.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: product.displayImage,
                          width: 100,
                          height: 90,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                              _foodImgPlaceholder(isDark),
                        )
                      : _foodImgPlaceholder(isDark),
                ),
                const SizedBox(height: 8),
                // ADD / Stepper
                product.variants.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          Navigator.pop(context); // close sheet
                          showProductDetailSheet(context, product.id, highlightVariants: true);
                        },
                        child: Container(
                          width: 100,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.secondary.withValues(alpha: 0.07),
                                AppColors.secondary.withValues(alpha: 0.12),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(
                                color: AppColors.secondary.withValues(alpha: 0.5),
                                width: 1.3),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.add_rounded,
                                  size: 14, color: AppColors.secondary),
                              const SizedBox(width: 3),
                              Text(
                                'ADD',
                                style: GoogleFonts.outfit(
                                    color: AppColors.secondary,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      )
                    : quantity == 0
                        ? GestureDetector(
                            onTap: () {
                          cart.addItem(product, _shop!);
                          setState(() {});
                        },
                        child: Container(
                          width: 100,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.secondary.withValues(alpha: 0.07),
                                AppColors.secondary.withValues(alpha: 0.12),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(
                                color: AppColors.secondary.withValues(alpha: 0.5),
                                width: 1.3),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.add_rounded,
                                  size: 14, color: AppColors.secondary),
                              const SizedBox(width: 3),
                              Text(
                                'ADD',
                                style: GoogleFonts.outfit(
                                    color: AppColors.secondary,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Container(
                        width: 100,
                        height: 38,
                        decoration: BoxDecoration(
                          gradient: AppColors.ctaGradient,
                          borderRadius: BorderRadius.circular(11),
                          boxShadow: [
                            BoxShadow(
                                color: AppColors.secondary
                                    .withValues(alpha: 0.35),
                                blurRadius: 10,
                                offset: const Offset(0, 4)),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            GestureDetector(
                              onTap: () {
                                cart.updateQuantity(product.id, quantity - 1);
                                setState(() {});
                              },
                              child: const Icon(Icons.remove_rounded,
                                  color: Colors.white, size: 18),
                            ),
                            Text('$quantity',
                                style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14)),
                            GestureDetector(
                              onTap: () {
                                cart.addItem(product, _shop!);
                                setState(() {});
                              },
                              child: const Icon(Icons.add_rounded,
                                  color: Colors.white, size: 18),
                            ),
                          ],
                        ),
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _foodImgPlaceholder(bool isDark) => Container(
        width: 100,
        height: 90,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [const Color(0xFF242438), const Color(0xFF1A1A2E)]
                : [const Color(0xFFFFF3EE), const Color(0xFFFFE4D6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Text('🍴', style: TextStyle(fontSize: 30)),
        ),
      );

  // ─────────────────────────────────────────────────────────────────────────
  // Sticky cart bottom bar
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildCartBar(CartProvider cart) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: GestureDetector(
        onTap: () {
          Navigator.pop(context);
          Navigator.pushNamed(context, AppRoutes.cart);
        },
        child: Container(
          height: 62,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0A1260), Color(0xFF162AC4), Color(0xFF1E40AF)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                  color: const Color(0xFF0A2A9E).withValues(alpha: 0.45),
                  blurRadius: 20,
                  offset: const Offset(0, 8)),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2)),
                ),
                child: Text(
                  '${cart.totalItemCount} item${cart.totalItemCount > 1 ? 's' : ''}',
                  style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13),
                ),
              ),
              const Spacer(),
              Text(
                'View Cart',
                style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 15),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.arrow_forward_rounded,
                    color: Colors.white, size: 16),
              ),
              const SizedBox(width: 10),
              Text(
                '₹${cart.subtotal.toStringAsFixed(0)}',
                style: GoogleFonts.outfit(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontWeight: FontWeight.w800,
                    fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SliverPersistentHeaderDelegate for sticky category tabs
// ─────────────────────────────────────────────────────────────────────────────
class _StickyTabsDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  _StickyTabsDelegate({required this.child});

  @override
  double get minExtent => 106;
  @override
  double get maxExtent => 106;

  @override
  Widget build(
          BuildContext context, double shrinkOffset, bool overlapsContent) =>
      child;

  @override
  bool shouldRebuild(_StickyTabsDelegate oldDelegate) =>
      oldDelegate.child != child;
}
