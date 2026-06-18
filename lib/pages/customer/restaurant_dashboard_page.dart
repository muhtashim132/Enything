import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/shop_model.dart';
import '../../models/product_model.dart';
import '../../providers/cart_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_colors.dart';
import '../../config/routes.dart';

/// Full-screen premium restaurant page — Swiggy/Zomato-style layout.
/// Used exclusively when the shop belongs to the Food / Restaurant category.
class RestaurantDashboardPage extends StatefulWidget {
  final String shopId;
  const RestaurantDashboardPage({super.key, required this.shopId});

  @override
  State<RestaurantDashboardPage> createState() =>
      _RestaurantDashboardPageState();
}

class _RestaurantDashboardPageState extends State<RestaurantDashboardPage>
    with TickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  ShopModel? _shop;
  List<ProductModel> _products = [];
  bool _isLoading = true;
  String _selectedCategory = 'All';
  final _scrollController = ScrollController();
  bool _headerCollapsed = false;
  late AnimationController _cartBounce;

  @override
  void initState() {
    super.initState();
    _cartBounce = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scrollController.addListener(_onScroll);
    _fetchData();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _cartBounce.dispose();
    super.dispose();
  }

  void _onScroll() {
    final collapsed = _scrollController.offset > 200;
    if (collapsed != _headerCollapsed) {
      setState(() => _headerCollapsed = collapsed);
    }
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
      : _products.where((p) => 
          p.menuCategory != null && 
          p.menuCategory!.trim().toLowerCase() == _selectedCategory.toLowerCase()
        ).toList();

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();

    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFFAFAFA),
        body: _buildShimmer(),
      );
    }

    if (_shop == null) {
      return const Scaffold(
        body: Center(child: Text('Restaurant not found')),
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFFFAFAFA),
        body: Stack(
          children: [
            CustomScrollView(
              controller: _scrollController,
              slivers: [
                _buildHeroAppBar(),
                _buildInfoStrip(),
                _buildCategoryTabs(),
                _buildMenuGrid(),
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            ),
            // Sticky cart bar at bottom
            if (cart.totalItemCount > 0)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildCartBar(cart),
              ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Hero SliverAppBar
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildHeroAppBar() {
    final favs = context.watch<FavoritesProvider>();
    final auth = context.watch<AuthProvider>();
    final isFav = _shop != null ? favs.isShopFavorite(_shop!.id) : false;

    return SliverAppBar(
      expandedHeight: 260,
      pinned: true,
      stretch: true,
      elevation: 0,
      backgroundColor: const Color(0xFF1A0533),
      leading: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          margin: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.arrow_back_ios_new,
              color: Colors.white, size: 18),
        ),
      ),
      actions: [
        GestureDetector(
          onTap: () {
            if (auth.currentUserId != null && _shop != null) {
              favs.toggleShopFavorite(auth.currentUserId!, _shop!.id);
            }
          },
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: isFav ? Colors.red : AppColors.textSecondary,
                size: 20,
              ),
            ),
          ),
        ),
        GestureDetector(
          onTap: () => Navigator.pushNamed(context, AppRoutes.cart),
          child: Container(
            margin: const EdgeInsets.all(10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                const Icon(Icons.shopping_bag_outlined,
                    color: Colors.white, size: 18),
                const SizedBox(width: 4),
                Consumer<CartProvider>(
                  builder: (_, c, __) => c.totalItemCount > 0
                      ? Text('${c.totalItemCount}',
                          style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700))
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),
      ],
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [StretchMode.zoomBackground],
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Banner
            _shop!.bannerImage != null
                ? CachedNetworkImage(
                    imageUrl: _shop!.bannerImage!,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => _heroBannerPlaceholder(),
                    errorWidget: (_, __, ___) => _heroBannerPlaceholder(),
                  )
                : _heroBannerPlaceholder(),
            // Dark gradient overlay
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.75),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.4, 1.0],
                ),
              ),
            ),
            // Shop name & cuisine at bottom of hero
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _shop!.name,
                    style: GoogleFonts.outfit(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      shadows: [
                        const Shadow(blurRadius: 12, color: Colors.black54),
                      ],
                    ),
                  ),
                  if (_shop!.cuisineType != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _shop!.cuisineType!,
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.85),
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
        color: const Color(0xFF2D0B6B),
        child: const Center(
          child: Text('🍽️', style: TextStyle(fontSize: 72)),
        ),
      );

  // ─────────────────────────────────────────────────────────────────────────
  // Info strip (rating | time | distance | veg badge | FSSAI)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildInfoStrip() {
    return SliverToBoxAdapter(
      child: Container(
        color: Colors.white,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Quick stats row
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  _statBox(
                    label: _shop!.totalOrders > 0 ? _shop!.rating.toStringAsFixed(1) : 'New',
                    sub: 'Rating',
                    icon: Icons.star_rounded,
                    iconColor: const Color(0xFF48BB78),
                  ),
                  _divider(),
                  _statBox(
                    label: '${_shop!.prepTimeMinutes} min',
                    sub: 'Prep time',
                    icon: Icons.timer_outlined,
                    iconColor: Colors.blue.shade600,
                  ),
                  _divider(),
                  _statBox(
                    label: '${_shop!.totalOrders}+',
                    sub: 'Orders',
                    icon: Icons.receipt_long_outlined,
                    iconColor: Colors.orange.shade700,
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFF0F0F0)),
            // Address row
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.location_on_outlined,
                      size: 15, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _shop!.address,
                      style: GoogleFonts.outfit(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            // Badge row
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Wrap(
                spacing: 8,
                children: [
                  if (_shop!.isVegOnly)
                    _badge('Pure Veg', Icons.eco, Colors.green.shade600),
                  if (_shop!.fssaiNumber != null)
                    _badge('FSSAI: ${_shop!.fssaiNumber}',
                        Icons.verified_outlined, Colors.blue.shade600),
                  if (_shop!.openingHours != null)
                    _badge(_shop!.openingHours!, Icons.access_time_outlined,
                        Colors.grey.shade600),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFF0F0F0)),
          ],
        ),
      ),
    );
  }

  Widget _statBox(
      {required String label,
      required String sub,
      required IconData icon,
      required Color iconColor}) {
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 4),
              Text(label,
                  style: GoogleFonts.outfit(
                      fontSize: 16, fontWeight: FontWeight.w800)),
            ],
          ),
          Text(sub,
              style: GoogleFonts.outfit(
                  fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _divider() => Container(
      width: 1,
      height: 36,
      color: const Color(0xFFE5E7EB),
      margin: const EdgeInsets.symmetric(horizontal: 4));

  Widget _badge(String label, IconData icon, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: GoogleFonts.outfit(
                    fontSize: 11, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      );

  // ─────────────────────────────────────────────────────────────────────────
  // Category tabs (horizontal scrollable chips)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildCategoryTabs() {
    final cats = _menuCategories;
    return SliverPersistentHeader(
      pinned: true,
      delegate: _StickyTabsDelegate(
        child: Container(
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Text(
                  'Menu',
                  style: GoogleFonts.outfit(
                      fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: cats.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final isSelected = _selectedCategory == cats[i];
                    return GestureDetector(
                      onTap: () => setState(() => _selectedCategory = cats[i]),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primary
                              : const Color(0xFFF0F0F8),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          cats[i],
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isSelected
                                ? Colors.white
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              const Divider(height: 1, color: Color(0xFFF0F0F0)),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Menu list — full-width horizontal item rows (food-style)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildMenuGrid() {
    final items = _filteredProducts;

    if (items.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(48),
          child: Center(
            child: Column(
              children: [
                Text('🍽️', style: TextStyle(fontSize: 56)),
                SizedBox(height: 12),
                Text('No items in this category',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 15)),
              ],
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (_, i) => _buildMenuItem(items[i]),
          childCount: items.length,
        ),
      ),
    );
  }

  Widget _buildMenuItem(ProductModel product) {
    final cart = context.read<CartProvider>();
    final quantity = cart.getItemQuantity(product.id);
    final isVeg = product.isVeg;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Info ────────────────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Veg / Non-veg indicator
                if (isVeg != null) ...[
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: isVeg ? Colors.green : Colors.red, width: 1.5),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Center(
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isVeg ? Colors.green : Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                Text(
                  product.name,
                  style: GoogleFonts.outfit(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                if (product.description != null &&
                    product.description!.isNotEmpty)
                  Text(
                    product.description!,
                    style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        height: 1.4),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 8),
                Text(
                  '₹${product.price.toStringAsFixed(0)}',
                  style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // ── Image + Add button ──────────────────────────────────────
          Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: product.displayImage.isNotEmpty
                    ? Image.network(
                        product.displayImage,
                        width: 100,
                        height: 90,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _foodImgPlaceholder(),
                      )
                    : _foodImgPlaceholder(),
              ),
              const SizedBox(height: 8),
              // Quantity stepper / ADD button
              quantity == 0
                  ? GestureDetector(
                      onTap: () {
                        cart.addItem(product, _shop!);
                        setState(() {});
                      },
                      child: Container(
                        width: 100,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border:
                              Border.all(color: AppColors.primary, width: 1.5),
                          boxShadow: [
                            BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.12),
                                blurRadius: 8),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            'ADD',
                            style: GoogleFonts.outfit(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w800,
                                fontSize: 13),
                          ),
                        ),
                      ),
                    )
                  : Container(
                      width: 100,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          GestureDetector(
                            onTap: () {
                              cart.updateQuantity(product.id, quantity - 1);
                              setState(() {});
                            },
                            child: const Icon(Icons.remove,
                                color: Colors.white, size: 18),
                          ),
                          Text('$quantity',
                              style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14)),
                          GestureDetector(
                            onTap: () {
                              cart.addItem(product, _shop!);
                              setState(() {});
                            },
                            child: const Icon(Icons.add,
                                color: Colors.white, size: 18),
                          ),
                        ],
                      ),
                    ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _foodImgPlaceholder() => Container(
        width: 100,
        height: 90,
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3EE),
          borderRadius: BorderRadius.circular(14),
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
        onTap: () => Navigator.pushNamed(context, AppRoutes.cart),
        child: Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0A2A9E), Color(0xFF1A3FBA)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                  color: const Color(0xFF0A2A9E).withValues(alpha: 0.4),
                  blurRadius: 18,
                  offset: const Offset(0, 8)),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${cart.totalItemCount} item${cart.totalItemCount > 1 ? 's' : ''}',
                  style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13),
                ),
              ),
              const Spacer(),
              Text(
                'View Cart  →',
                style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15),
              ),
              const SizedBox(width: 8),
              Text(
                '₹${cart.subtotal.toStringAsFixed(0)}',
                style: GoogleFonts.outfit(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w700,
                    fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Shimmer loading
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildShimmer() {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        children: [
          Container(height: 260, color: const Color(0xFFE0E0E0)),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: List.generate(
                4,
                (_) => Container(
                  height: 120,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0E0E0),
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            ),
          ),
        ],
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
  double get minExtent => 102;
  @override
  double get maxExtent => 102;

  @override
  Widget build(
          BuildContext context, double shrinkOffset, bool overlapsContent) =>
      child;

  @override
  bool shouldRebuild(_StickyTabsDelegate oldDelegate) =>
      oldDelegate.child != child;
}
