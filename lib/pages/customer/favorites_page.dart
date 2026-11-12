import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/premium_effects.dart';
import '../../config/routes.dart';
import '../../widgets/product_card.dart';
import '../../widgets/shop_card.dart';
import '../../widgets/restaurant_shop_card.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../utils/responsive_layout.dart';
import '../../widgets/shop_detail_sheet.dart';
import '../../widgets/restaurant_dashboard_sheet.dart';

class FavoritesPage extends StatefulWidget {
  final bool isEmbedded;
  final VoidCallback? onExplore;

  const FavoritesPage({
    super.key,
    this.isEmbedded = false,
    this.onExplore,
  });

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      if (auth.currentUserId != null) {
        context.read<FavoritesProvider>().fetchFavorites(auth.currentUserId!);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _handleRefresh() async {
    final auth = context.read<AuthProvider>();
    if (auth.currentUserId != null) {
      await context
          .read<FavoritesProvider>()
          .fetchFavorites(auth.currentUserId!);
    }
  }

  Widget _buildEmptyState({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isDark,
    required VoidCallback onAction,
    required String actionLabel,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: isDark ? 0.2 : 0.1),
                    AppColors.primaryLight
                        .withValues(alpha: isDark ? 0.12 : 0.06),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 56,
                color: isDark ? AppColors.primaryLight : AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 14,
                color: isDark ? Colors.white54 : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 32),
            GestureDetector(
              onTap: onAction,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                decoration: BoxDecoration(
                  gradient: AppColors.ctaGradient,
                  borderRadius: PremiumRadius.mediumBorder,
                  boxShadow: PremiumShadows.floatingButtonLight,
                ),
                child: Text(
                  actionLabel,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final favProvider = context.watch<FavoritesProvider>();
    final auth = context.watch<AuthProvider>();
    final isDark = context.watch<ThemeProvider>().isDarkMode;

    final favoriteProducts = favProvider.favoriteProducts;
    final favoriteShops = favProvider.favoriteShops;
    final productShops = favProvider.productShops;
    final isLoggedIn = auth.currentUserId != null;

    void onExploreAction() {
      if (widget.onExplore != null) {
        widget.onExplore!();
      } else if (!widget.isEmbedded && Navigator.canPop(context)) {
        Navigator.pop(context);
      } else {
        Navigator.pushReplacementNamed(context, AppRoutes.customerHome);
      }
    }

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0E0E1A) : const Color(0xFFF4F6FB),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF12121A) : Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        leading: widget.isEmbedded
            ? null
            : (Navigator.canPop(context)
                ? GestureDetector(
                    onTap: () => Navigator.maybePop(context),
                    child: Container(
                      margin: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.07)
                            : const Color(0xFFF0F0F8),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.arrow_back_ios_new_rounded,
                          size: 16,
                          color:
                              isDark ? Colors.white70 : AppColors.textPrimary),
                    ),
                  )
                : null),
        title: Text(
          'Favorites',
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(24),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: isDark ? Colors.white : Colors.white,
              unselectedLabelColor:
                  isDark ? Colors.white54 : AppColors.textSecondary,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                gradient: AppColors.ctaGradient,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              labelStyle:
                  GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 13),
              unselectedLabelStyle:
                  GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13),
              tabs: const [
                Tab(text: 'Items & Products'),
                Tab(text: 'Shops & Restaurants'),
              ],
            ),
          ),
        ),
      ),
      body: MaxWidthContainer(
        child: favProvider.isLoading &&
                favoriteProducts.isEmpty &&
                favoriteShops.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabController,
                children: [
                  // ── Tab 1: Products ─────────────────────────────────
                  !isLoggedIn
                      ? RefreshIndicator(
                          onRefresh: _handleRefresh,
                          color: AppColors.primary,
                          backgroundColor:
                              isDark ? AppColors.darkSurface : Colors.white,
                          child: CustomScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            slivers: [
                              SliverFillRemaining(
                                hasScrollBody: false,
                                child: _buildEmptyState(
                                  title: 'Sign in to view favorites',
                                  subtitle:
                                      'Save your favorite products to access them anytime.',
                                  icon: Icons.favorite_border_rounded,
                                  isDark: isDark,
                                  actionLabel: 'Sign In 🔐',
                                  onAction: () => Navigator.pushNamed(
                                      context, AppRoutes.login),
                                ),
                              ),
                            ],
                          ),
                        )
                      : favoriteProducts.isEmpty
                          ? RefreshIndicator(
                              onRefresh: _handleRefresh,
                              color: AppColors.primary,
                              backgroundColor:
                                  isDark ? AppColors.darkSurface : Colors.white,
                              child: CustomScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                slivers: [
                                  SliverFillRemaining(
                                    hasScrollBody: false,
                                    child: _buildEmptyState(
                                      title: 'No favorite items yet',
                                      subtitle:
                                          'Tap the heart or bookmark icon on any item you love\nto save it for later.',
                                      icon: Icons.favorite_border_rounded,
                                      isDark: isDark,
                                      actionLabel: 'Start Exploring',
                                      onAction: onExploreAction,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _handleRefresh,
                              color: AppColors.primary,
                              backgroundColor:
                                  isDark ? AppColors.darkSurface : Colors.white,
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  const crossAxisCount = 2;
                                  const crossAxisSpacing = 16.0;
                                  final availableWidth =
                                      constraints.maxWidth - 32;
                                  final itemWidth = (availableWidth -
                                          (crossAxisSpacing *
                                              (crossAxisCount - 1))) /
                                      crossAxisCount;
                                  final itemHeight = itemWidth + 134;
                                  final childAspectRatio =
                                      itemWidth / itemHeight;

                                  return GridView.builder(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 16, 16, 120),
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: crossAxisCount,
                                      childAspectRatio: childAspectRatio,
                                      mainAxisSpacing: 16,
                                      crossAxisSpacing: crossAxisSpacing,
                                    ),
                                    itemCount: favoriteProducts.length,
                                    itemBuilder: (context, index) {
                                      final prod = favoriteProducts[index];
                                      return ProductCard(
                                        product: prod,
                                        shop: productShops[prod.shopId],
                                      );
                                    },
                                  );
                                },
                              ),
                            ),

                  // ── Tab 2: Shops & Restaurants ───────────────────────
                  !isLoggedIn
                      ? RefreshIndicator(
                          onRefresh: _handleRefresh,
                          color: AppColors.primary,
                          backgroundColor:
                              isDark ? AppColors.darkSurface : Colors.white,
                          child: CustomScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            slivers: [
                              SliverFillRemaining(
                                hasScrollBody: false,
                                child: _buildEmptyState(
                                  title: 'Sign in to view favorites',
                                  subtitle:
                                      'Save your favorite restaurants and stores to access them anytime.',
                                  icon: Icons.storefront_outlined,
                                  isDark: isDark,
                                  actionLabel: 'Sign In 🔐',
                                  onAction: () => Navigator.pushNamed(
                                      context, AppRoutes.login),
                                ),
                              ),
                            ],
                          ),
                        )
                      : favoriteShops.isEmpty
                          ? RefreshIndicator(
                              onRefresh: _handleRefresh,
                              color: AppColors.primary,
                              backgroundColor:
                                  isDark ? AppColors.darkSurface : Colors.white,
                              child: CustomScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                slivers: [
                                  SliverFillRemaining(
                                    hasScrollBody: false,
                                    child: _buildEmptyState(
                                      title: 'No favorite shops yet',
                                      subtitle:
                                          'Save your go-to restaurants and stores\nfor quick access.',
                                      icon: Icons.storefront_outlined,
                                      isDark: isDark,
                                      actionLabel: 'Start Exploring',
                                      onAction: onExploreAction,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _handleRefresh,
                              color: AppColors.primary,
                              backgroundColor:
                                  isDark ? AppColors.darkSurface : Colors.white,
                              child: ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding:
                                    const EdgeInsets.fromLTRB(16, 16, 16, 120),
                                itemCount: favoriteShops.length,
                                itemBuilder: (context, index) {
                                  final shop = favoriteShops[index];
                                  final isFood = shop.category
                                          .toLowerCase()
                                          .contains('food') ||
                                      shop.category
                                          .toLowerCase()
                                          .contains('restaurant');

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: SizedBox(
                                      height: 280,
                                      child: isFood
                                          ? RestaurantShopCard(
                                              shop: shop,
                                              onTap: () =>
                                                  showRestaurantDashboardSheet(
                                                context,
                                                shop.id,
                                              ),
                                            )
                                          : ShopCard(
                                              shop: shop,
                                              onTap: () => showShopDetailSheet(
                                                context,
                                                shop.id,
                                              ),
                                            ),
                                    ),
                                  );
                                },
                              ),
                            ),
                ],
              ),
      ),
    );
  }
}
