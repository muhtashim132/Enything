import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import '../../models/shop_model.dart';
import '../../models/product_model.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_colors.dart';
import '../../widgets/product_card.dart';
import '../../widgets/common/enything_map.dart';

class RestaurantPage extends StatefulWidget {
  final String shopId;
  const RestaurantPage({super.key, required this.shopId});

  @override
  State<RestaurantPage> createState() => _RestaurantPageState();
}

class _RestaurantPageState extends State<RestaurantPage> {
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

      setState(() {
        _shop = ShopModel.fromMap(shopData);
        _products =
            (productsData as List).map((p) => ProductModel.fromMap(p)).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }

    if (_shop == null) {
      return const Scaffold(
          body: Center(child: Text('Shop not found')));
    }

    final favs = context.watch<FavoritesProvider>();
    final auth = context.watch<AuthProvider>();
    final isFav = favs.isShopFavorite(_shop!.id);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            stretch: true,
            leading: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_back, color: Colors.white),
              ),
            ),
            actions: [
              GestureDetector(
                onTap: () {
                  if (auth.currentUserId != null) {
                    favs.toggleShopFavorite(auth.currentUserId!, _shop!.id);
                  }
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: isFav ? Colors.red : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                _shop!.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Poppins',
                  shadows: [Shadow(blurRadius: 12, color: Colors.black)],
                ),
              ),
              background: _shop!.bannerImage != null
                  ? CachedNetworkImage(
                      imageUrl: _shop!.bannerImage!,
                      fit: BoxFit.cover,
                      errorWidget: (c, e, s) => Container(
                        decoration: const BoxDecoration(
                            gradient: AppColors.foodGradient),
                        child: const Center(
                            child: Text('🛍️',
                                style: TextStyle(fontSize: 64))),
                      ),
                    )
                  : Container(
                      decoration:
                          const BoxDecoration(gradient: AppColors.foodGradient),
                      child: const Center(
                          child:
                              Text('🛍️', style: TextStyle(fontSize: 64))),
                    ),
            ),
          ),
          SliverToBoxAdapter(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Text(
                              _shop!.rating.toStringAsFixed(1),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13),
                            ),
                            const Icon(Icons.star,
                                color: Colors.white, size: 12),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${_shop!.totalOrders}+ orders',
                        style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13),
                      ),
                      const Spacer(),
                      const Icon(Icons.timer_outlined,
                          size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        '${_shop!.prepTimeMinutes} mins',
                        style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined,
                          size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _shop!.address,
                          style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_shop!.location.latitude != 0 && _shop!.location.longitude != 0)
                    Container(
                      height: 150,
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: EnythingMap(
                          center: _shop!.location,
                          zoom: 15,
                          interactive: false,
                        ),
                      ),
                    ),
                  if (_shop!.cuisineType != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.foodRed.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _shop!.cuisineType!,
                        style: const TextStyle(
                          color: AppColors.foodRed,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Poppins',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  const Text(
                    'Products',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'Poppins',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_products.length} items',
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_products.isEmpty)
            const SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: Column(
                    children: [
                      Text('🛍️', style: TextStyle(fontSize: 48)),
                      SizedBox(height: 12),
                      Text('No products available',
                          style: TextStyle(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.65,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => ProductCard(
                    product: _products[index],
                    shop: _shop,
                  ),
                  childCount: _products.length,
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}
