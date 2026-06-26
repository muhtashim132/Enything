import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/premium_effects.dart';
import '../../models/product_model.dart';
import '../../models/shop_model.dart';
import '../../widgets/product_card.dart';
import '../../widgets/shop_card.dart';
import '../../widgets/restaurant_shop_card.dart';

import 'package:google_fonts/google_fonts.dart';
import '../../utils/responsive_layout.dart';
import '../../widgets/shop_detail_sheet.dart';
import '../../widgets/restaurant_dashboard_sheet.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _supabase = Supabase.instance.client;

  List<ProductModel> _favoriteProducts = [];
  List<ShopModel> _favoriteShops = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadFavorites();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    setState(() => _isLoading = true);
    final favs = context.read<FavoritesProvider>();

    try {
      if (favs.favoriteProductIds.isNotEmpty) {
        final productIds =
            favs.favoriteProductIds.map((id) => '"$id"').join(',');
        final productRes = await _supabase
            .from('products')
            .select()
            .filter('id', 'in', '($productIds)');
        _favoriteProducts =
            (productRes as List).map((p) => ProductModel.fromMap(p)).toList();
      } else {
        _favoriteProducts = [];
      }

      if (favs.favoriteShopIds.isNotEmpty) {
        final shopIds = favs.favoriteShopIds.map((id) => '"$id"').join(',');
        final shopRes = await _supabase
            .from('shops')
            .select()
            .filter('id', 'in', '($shopIds)');
        _favoriteShops =
            (shopRes as List).map((s) => ShopModel.fromMap(s)).toList();
      } else {
        _favoriteShops = [];
      }
    } catch (e) {
      debugPrint('Error loading full favorite objects: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildEmptyState(String title, String subtitle, IconData icon, bool isDark) {
    return Center(
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
                  AppColors.primaryLight.withValues(alpha: isDark ? 0.12 : 0.06),
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
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              decoration: BoxDecoration(
                gradient: AppColors.ctaGradient,
                borderRadius: PremiumRadius.mediumBorder,
                boxShadow: PremiumShadows.floatingButtonLight,
              ),
              child: Text(
                'Start Exploring',
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final favProvider = context.watch<FavoritesProvider>();
    final isDark = context.watch<ThemeProvider>().isDarkMode;

    // Keep lists in sync if user un-favorites something while on this page
    _favoriteProducts
        .removeWhere((p) => !favProvider.favoriteProductIds.contains(p.id));
    _favoriteShops
        .removeWhere((s) => !favProvider.favoriteShopIds.contains(s.id));

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0E0E1A) : const Color(0xFFF4F6FB),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF12121A) : Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.07) : const Color(0xFFF0F0F8),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.arrow_back_ios_new_rounded,
                size: 16, color: isDark ? Colors.white70 : AppColors.textPrimary),
          ),
        ),
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
              color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(24),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: isDark ? Colors.white : Colors.white,
              unselectedLabelColor: isDark ? Colors.white54 : AppColors.textSecondary,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                gradient: AppColors.ctaGradient,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 13),
              unselectedLabelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13),
              tabs: const [
                Tab(text: 'Items & Products'),
                Tab(text: 'Shops & Restaurants'),
              ],
            ),
          ),
        ),
      ),
      body: MaxWidthContainer(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
              controller: _tabController,
              children: [
                // Products Tab
                _favoriteProducts.isEmpty
                    ? _buildEmptyState(
                        'No favorite items yet',
                        'Tap the heart icon on any item you love\nto save it for later.',
                        Icons.favorite_border_rounded,
                        isDark)
                    : RefreshIndicator(
                        onRefresh: _loadFavorites,
                        color: AppColors.primary,
                        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
                        child: GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 0.54,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                          ),
                          itemCount: _favoriteProducts.length,
                          itemBuilder: (context, index) {
                            return ProductCard(
                                product: _favoriteProducts[index]);
                          },
                        ),
                      ),

                // Shops Tab
                _favoriteShops.isEmpty
                    ? _buildEmptyState(
                        'No favorite shops yet',
                        'Save your go-to restaurants and stores\nfor quick access.',
                        Icons.storefront_outlined,
                        isDark)
                    : RefreshIndicator(
                        onRefresh: _loadFavorites,
                        color: AppColors.primary,
                        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _favoriteShops.length,
                          itemBuilder: (context, index) {
                            final shop = _favoriteShops[index];
                            final isFood =
                                shop.category.toLowerCase().contains('food') ||
                                    shop.category
                                        .toLowerCase()
                                        .contains('restaurant');

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: isFood
                                  ? RestaurantShopCard(
                                      shop: shop,
                                      onTap: () => showRestaurantDashboardSheet(
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
