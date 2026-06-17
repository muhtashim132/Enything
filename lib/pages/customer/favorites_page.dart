import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/favorites_provider.dart';
import '../../theme/app_colors.dart';
import '../../models/product_model.dart';
import '../../models/shop_model.dart';
import '../../widgets/product_card.dart';
import '../../widgets/shop_card.dart';
import '../../widgets/restaurant_shop_card.dart';
import '../../config/routes.dart';
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

  Widget _buildEmptyState(String title, String subtitle, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon,
              size: 80, color: AppColors.textSecondary.withValues(alpha: 0.3)),
          const SizedBox(height: 24),
          Text(
            title,
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 15,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text('Start Exploring',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final favProvider = context.watch<FavoritesProvider>();

    // Keep lists in sync if user un-favorites something while on this page
    _favoriteProducts
        .removeWhere((p) => !favProvider.favoriteProductIds.contains(p.id));
    _favoriteShops
        .removeWhere((s) => !favProvider.favoriteShopIds.contains(s.id));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Favorites',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'Items & Products'),
            Tab(text: 'Shops & Restaurants'),
          ],
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
                        Icons.favorite_border_rounded)
                    : RefreshIndicator(
                        onRefresh: _loadFavorites,
                        child: GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 0.65,
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
                        Icons.storefront_outlined)
                    : RefreshIndicator(
                        onRefresh: _loadFavorites,
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
