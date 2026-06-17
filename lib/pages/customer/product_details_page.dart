import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../widgets/common/notification_bell.dart';
import '../../config/app_categories.dart';
import '../../widgets/shop_detail_sheet.dart';
import '../../widgets/restaurant_dashboard_sheet.dart';
import '../../models/product_model.dart';
import '../../models/shop_model.dart';
import '../../utils/responsive_layout.dart';
import '../../providers/cart_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_colors.dart';
import '../../config/routes.dart';

class ProductDetailsPage extends StatefulWidget {
  final String productId;
  const ProductDetailsPage({super.key, required this.productId});

  @override
  State<ProductDetailsPage> createState() => _ProductDetailsPageState();
}

class _ProductDetailsPageState extends State<ProductDetailsPage> {
  final _supabase = Supabase.instance.client;
  ProductModel? _product;
  ShopModel? _shop;
  bool _isLoading = true;
  int _currentImageIndex = 0;

  @override
  void initState() {
    super.initState();
    _fetchProduct();
  }

  Future<void> _fetchProduct() async {
    try {
      final productData = await _supabase
          .from('products')
          .select()
          .eq('id', widget.productId)
          .single();

      final product = ProductModel.fromMap(productData);

      final shopData = await _supabase
          .from('shops')
          .select()
          .eq('id', product.shopId)
          .single();

      setState(() {
        _product = product;
        _shop = ShopModel.fromMap(shopData);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_product == null) {
      return const Scaffold(body: Center(child: Text('Product not found')));
    }

    final cart = context.watch<CartProvider>();
    final favs = context.watch<FavoritesProvider>();
    final auth = context.watch<AuthProvider>();
    final quantity = cart.getItemQuantity(_product!.id);
    final isFav = favs.isProductFavorite(_product!.id);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: MaxWidthContainer(
        child: CustomScrollView(
          slivers: [
          SliverAppBar(
            expandedHeight: 320,
            pinned: true,
            leading: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_back, color: Colors.white),
              ),
            ),
            actions: [
              GestureDetector(
                onTap: () {
                  if (auth.currentUserId != null) {
                    favs.toggleProductFavorite(auth.currentUserId!, _product!.id);
                  }
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  decoration: const BoxDecoration(
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
              GestureDetector(
                onTap: () {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  Navigator.pushNamed(context, AppRoutes.cart);
                },
                child: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    shape: BoxShape.circle,
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.shopping_cart_outlined,
                        color: Colors.white),
                  ),
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: _product!.images.isNotEmpty
                  ? Stack(
                      children: [
                        PageView.builder(
                          itemCount: _product!.images.length,
                          onPageChanged: (i) =>
                              setState(() => _currentImageIndex = i),
                          itemBuilder: (ctx, i) => CachedNetworkImage(
                            imageUrl: i == 0 ? _product!.displayImage : _product!.images[i],
                            fit: BoxFit.contain,
                            errorWidget: (c, e, s) => Container(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              child: const Center(
                                  child: Icon(Icons.shopping_bag_outlined,
                                      size: 80, color: AppColors.primary)),
                            ),
                          ),
                        ),
                        if (_product!.images.length > 1)
                          Positioned(
                            bottom: 12,
                            left: 0,
                            right: 0,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(
                                _product!.images.length,
                                (i) => Container(
                                  width:
                                      i == _currentImageIndex ? 20 : 6,
                                  height: 6,
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 2),
                                  decoration: BoxDecoration(
                                    color: i == _currentImageIndex
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: 0.5),
                                    borderRadius:
                                        BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    )
                  : Container(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      child: const Center(
                        child: Icon(Icons.shopping_bag_outlined,
                            size: 100, color: AppColors.primary),
                      ),
                    ),
            ),
          ),
          SliverToBoxAdapter(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _product!.name,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                fontFamily: 'Poppins',
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.star_rounded, color: Colors.amber, size: 18),
                                const SizedBox(width: 4),
                                Text(
                                  _product!.rating > 0 ? _product!.rating.toStringAsFixed(1) : 'New',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (_product!.isVeg == true)
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: AppColors.vegGreen, width: 2),
                          ),
                          child: const Center(
                            child: Icon(Icons.circle,
                                size: 12, color: AppColors.vegGreen),
                          ),
                        )
                      else if (_product!.isVeg == false)
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: AppColors.nonVegRed, width: 2),
                          ),
                          child: const Center(
                            child: Icon(Icons.change_history,
                                size: 12, color: AppColors.nonVegRed),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        '₹${_product!.price.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                          fontFamily: 'Poppins',
                        ),
                      ),
                      if (_product!.originalPrice != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          '₹${_product!.originalPrice!.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 16,
                            color: AppColors.textLight,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        if (_product!.discountPercent != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${_product!.discountPercent!.toInt()}% OFF',
                              style: const TextStyle(
                                color: AppColors.success,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                  const Divider(height: 28),
                  // Shop info
                  GestureDetector(
                    onTap: () {
                      if (_shop != null) {
                        final isFood = AppCategories.groupFor(_shop!.category) == CategoryGroup.food;
                        if (isFood) {
                          showRestaurantDashboardSheet(context, _shop!.id);
                        } else {
                          showShopDetailSheet(context, _shop!.id);
                        }
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.store_outlined,
                              color: AppColors.primary, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _shop?.name ?? 'Unknown Shop',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontFamily: 'Poppins',
                              ),
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios,
                              size: 14, color: AppColors.textSecondary),
                        ],
                      ),
                    ),
                  ),
                  if (_product!.description != null &&
                      _product!.description!.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Text(
                      'Description',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Poppins'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _product!.description!,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        height: 1.6,
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ],
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: MaxWidthContainer(
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: quantity > 0
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _qtyBtn(Icons.remove, () {
                    if (_shop != null) {
                      cart.updateQuantity(_product!.id, quantity - 1);
                    }
                  }),
                  const SizedBox(width: 28),
                  Text(
                    '$quantity',
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 28),
                  _qtyBtn(Icons.add, () {
                    if (_shop != null) {
                      cart.addItem(_product!, _shop!);
                    }
                  }),
                  const SizedBox(width: 20),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        Navigator.pushNamed(context, AppRoutes.cart);
                      },
                      child: const Text('View Cart'),
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        if (_shop != null) {
                          cart.addItem(_product!, _shop!);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content:
                                  Text('${_product!.name} added to cart! 🛒'),
                              backgroundColor: AppColors.success,
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 2),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              action: SnackBarAction(
                                label: 'View Cart',
                                textColor: Colors.white,
                                onPressed: () {
                                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                  Navigator.pushNamed(context, AppRoutes.cart);
                                },
                              ),
                            ),
                          );
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: AppColors.primary, width: 2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('ADD TO CART',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primary)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        if (_shop != null) {
                          cart.addItem(_product!, _shop!);
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          Navigator.pushNamed(context, AppRoutes.cart);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('BUY NOW',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ),
    );
  }

  Widget _qtyBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(50),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.primary, width: 2),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: AppColors.primary, size: 18),
      ),
    );
  }
}
