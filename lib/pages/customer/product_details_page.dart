import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/app_categories.dart';
import '../../widgets/shop_detail_sheet.dart';
import '../../widgets/restaurant_dashboard_sheet.dart';
import '../../models/product_model.dart';
import '../../models/shop_model.dart';
import '../../utils/responsive_layout.dart';
import '../../providers/cart_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/location_provider.dart';
import '../../utils/delivery_calculator.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/premium_effects.dart';
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
  ProductVariant? _selectedVariant;

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
        if (product.variants.isNotEmpty) {
          _selectedVariant = product.variants.first;
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDarkMode;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF0E0E1A) : const Color(0xFFF4F6FB),
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        )
      );
    }
    if (_product == null) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF0E0E1A) : const Color(0xFFF4F6FB),
        body: Center(
          child: Text('Product not found', style: GoogleFonts.outfit(color: isDark ? Colors.white : AppColors.textPrimary))
        )
      );
    }

    final cart = context.watch<CartProvider>();
    final favs = context.watch<FavoritesProvider>();
    final auth = context.watch<AuthProvider>();
    final quantity = cart.getItemQuantity(_product!.id, variantName: _selectedVariant?.name);
    final isFav = favs.isProductFavorite(_product!.id);
    final location = context.watch<LocationProvider>();
    final distanceKm = _shop != null ? location.distanceTo(_shop!.location) : 0.0;
    final deliveryLabel = DeliveryCalculator.deliveryChargeLabel(distanceKm, _product!.price);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0E0E1A) : const Color(0xFFF4F6FB),
      body: MaxWidthContainer(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 380,
              pinned: true,
              backgroundColor: isDark ? const Color(0xFF12121A) : Colors.white,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              leading: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.25),
                    shape: BoxShape.circle,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(50),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                    ),
                  ),
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
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.25),
                      shape: BoxShape.circle,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(50),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Icon(
                            isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                            color: isFav ? AppColors.danger : Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    ScaffoldMessenger.of(context).clearSnackBars();
                    Navigator.pushNamed(context, AppRoutes.cart);
                  },
                  child: Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.25),
                      shape: BoxShape.circle,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(50),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: const Padding(
                          padding: EdgeInsets.all(10),
                          child: Icon(Icons.shopping_cart_outlined, color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: _product!.images.isNotEmpty
                    ? Stack(
                        children: [
                          PageView.builder(
                            itemCount: _product!.images.length,
                            onPageChanged: (i) => setState(() => _currentImageIndex = i),
                            itemBuilder: (ctx, i) => CachedNetworkImage(
                              imageUrl: i == 0 ? _product!.displayImage : _product!.images[i],
                              fit: BoxFit.cover,
                              errorWidget: (c, e, s) => Container(
                                color: isDark ? AppColors.darkSurface : AppColors.primary.withValues(alpha: 0.05),
                                child: const Center(
                                    child: Icon(Icons.shopping_bag_outlined,
                                        size: 80, color: AppColors.primary)),
                              ),
                            ),
                          ),
                          // Premium gradient overlay for readability
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.black.withValues(alpha: 0.3),
                                    Colors.transparent,
                                    isDark ? const Color(0xFF0E0E1A) : Colors.white,
                                  ],
                                  stops: const [0.0, 0.5, 1.0],
                                ),
                              ),
                            ),
                          ),
                          if (_product!.images.length > 1)
                            Positioned(
                              bottom: 24,
                              left: 0,
                              right: 0,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(
                                  _product!.images.length,
                                  (i) => AnimatedContainer(
                                    duration: PremiumAnimations.normal,
                                    width: i == _currentImageIndex ? 24 : 8,
                                    height: 8,
                                    margin: const EdgeInsets.symmetric(horizontal: 4),
                                    decoration: BoxDecoration(
                                      color: i == _currentImageIndex
                                          ? AppColors.primary
                                          : AppColors.primary.withValues(alpha: 0.3),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      )
                    : Container(
                        color: isDark ? AppColors.darkSurface : AppColors.primary.withValues(alpha: 0.05),
                        child: const Center(
                          child: Icon(Icons.shopping_bag_outlined,
                              size: 100, color: AppColors.primary),
                        ),
                      ),
              ),
            ),
            SliverToBoxAdapter(
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF12121A) : Colors.white,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                ),
                padding: const EdgeInsets.all(24),
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
                                style: GoogleFonts.outfit(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: isDark ? Colors.white : AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                                        const SizedBox(width: 4),
                                        Text(
                                          _product!.rating > 0
                                              ? _product!.rating.toStringAsFixed(1)
                                              : 'New',
                                          style: GoogleFonts.outfit(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                            color: Colors.amber.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                      ],
                    ),
                    const SizedBox(height: 16),
                    Builder(
                      builder: (context) {
                        final currentPrice = _selectedVariant?.price ?? _product!.price;
                        final currentOriginalPrice = _selectedVariant?.originalPrice ?? _product!.originalPrice;
                        final currentDiscountPercent = _selectedVariant?.discountPercent ?? _product!.discountPercent;

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '₹${currentPrice.toStringAsFixed(0)}',
                              style: GoogleFonts.outfit(
                                fontSize: 32,
                                fontWeight: FontWeight.w800,
                                color: isDark ? Colors.white : AppColors.textPrimary,
                              ),
                            ),
                            if (currentDiscountPercent != null && currentOriginalPrice != null) ...[
                              const SizedBox(width: 12),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(
                                  '₹${currentOriginalPrice.toStringAsFixed(0)}',
                                  style: GoogleFonts.outfit(
                                    fontSize: 18,
                                    color: isDark ? Colors.white38 : AppColors.textLight,
                                    decoration: TextDecoration.lineThrough,
                                    decorationThickness: 2,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  gradient: AppColors.successGradient,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  'SAVE ${currentDiscountPercent.toInt()}%',
                                  style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        );
                      }
                    ),
                    if (_product!.variants.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text(
                        'Select Variation',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _product!.variants.map((v) {
                          final isSelected = _selectedVariant?.name == v.name;
                          return GestureDetector(
                            onTap: () => setState(() => _selectedVariant = v),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected 
                                    ? AppColors.primary.withValues(alpha: 0.1) 
                                    : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade100),
                                borderRadius: BorderRadius.circular(100),
                                border: Border.all(
                                  color: isSelected 
                                      ? AppColors.primary 
                                      : Colors.transparent,
                                ),
                              ),
                              child: Text(
                                '${v.name} - ₹${v.price.toStringAsFixed(0)}',
                                style: GoogleFonts.outfit(
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  color: isSelected 
                                      ? AppColors.primary 
                                      : (isDark ? Colors.white70 : AppColors.textSecondary),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 28),
                    // Shop info Card
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
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkSurface : Colors.white,
                          borderRadius: PremiumRadius.largeBorder,
                          boxShadow: isDark ? PremiumShadows.cardDark : PremiumShadows.cardLight,
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.storefront_rounded, color: AppColors.primary, size: 24),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Sold by',
                                    style: GoogleFonts.outfit(
                                      fontSize: 12,
                                      color: isDark ? Colors.white54 : AppColors.textSecondary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _shop?.name ?? 'Unknown Shop',
                                    style: GoogleFonts.outfit(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: isDark ? Colors.white : AppColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.arrow_forward_ios_rounded, size: 16, color: isDark ? Colors.white30 : AppColors.textLight),
                          ],
                        ),
                      ),
                    ),
                    if (_product!.description != null && _product!.description!.isNotEmpty) ...[
                      const SizedBox(height: 32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Description',
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: isDark ? Colors.white : AppColors.textPrimary,
                            ),
                          ),
                          if (_product!.isVeg != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: _product!.isVeg! 
                                    ? AppColors.vegGreen.withValues(alpha: 0.1) 
                                    : AppColors.nonVegRed.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(100),
                                border: Border.all(
                                  color: _product!.isVeg! 
                                      ? AppColors.vegGreen.withValues(alpha: 0.3) 
                                      : AppColors.nonVegRed.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _product!.isVeg! ? '🥦' : '🍗',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _product!.isVeg! ? 'Veg' : 'Non-Veg',
                                    style: GoogleFonts.outfit(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: _product!.isVeg! 
                                          ? AppColors.vegGreen 
                                          : AppColors.nonVegRed,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _product!.description!,
                        style: GoogleFonts.outfit(
                          color: isDark ? Colors.white70 : AppColors.textSecondary,
                          height: 1.6,
                          fontSize: 15,
                        ),
                      ),
                    ],
                    // Extra Trust Row
                    const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildTrustItem(Icons.verified_user_outlined, 'Genuine', isDark),
                        _buildTrustItem(Icons.local_shipping_outlined, 'Fast Delivery', isDark),
                      ],
                    ),

                    // Delivery & Distance Info
                    if (_shop != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withValues(alpha: 0.03) : const Color(0xFFF4F6FB),
                          borderRadius: BorderRadius.circular(PremiumRadius.medium),
                          border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade200),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.location_on_rounded, size: 16, color: AppColors.primary),
                                const SizedBox(width: 8),
                                Text(
                                  '${distanceKm.toStringAsFixed(1)} km away',
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: isDark ? Colors.white70 : AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                const Icon(Icons.delivery_dining_rounded, size: 16, color: AppColors.success),
                                const SizedBox(width: 8),
                                Text(
                                  deliveryLabel,
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: AppColors.success,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 120),
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
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A1A24) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: isDark ? PremiumShadows.cardDark : PremiumShadows.cardLight,
            ),
            child: quantity > 0
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _qtyBtn(Icons.remove, () {
                        if (_shop != null) cart.updateQuantity(_product!.id, quantity - 1, variantName: _selectedVariant?.name);
                      }),
                      const SizedBox(width: 28),
                      Text(
                        '$quantity',
                        style: GoogleFonts.outfit(
                            fontSize: 24, fontWeight: FontWeight.w800, color: isDark ? Colors.white : AppColors.textPrimary),
                      ),
                      const SizedBox(width: 28),
                      _qtyBtn(Icons.add, () {
                        if (_shop != null) cart.addItem(_product!, _shop!, selectedVariant: _selectedVariant);
                      }),
                      const SizedBox(width: 24),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            ScaffoldMessenger.of(context).clearSnackBars();
                            Navigator.pushNamed(context, AppRoutes.cart);
                          },
                          child: Container(
                            height: 56,
                            decoration: BoxDecoration(
                              gradient: AppColors.ctaGradient,
                              borderRadius: PremiumRadius.mediumBorder,
                              boxShadow: PremiumShadows.floatingButtonLight,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.shopping_cart_checkout_rounded, color: Colors.white, size: 20),
                                const SizedBox(width: 8),
                                Text('View Cart', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                              ],
                            ),
                          ),
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
                              cart.addItem(_product!, _shop!, selectedVariant: _selectedVariant);
                              ScaffoldMessenger.of(context).clearSnackBars();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('${_product!.name} added to cart! 🛒', style: GoogleFonts.outfit()),
                                  backgroundColor: AppColors.success,
                                  behavior: SnackBarBehavior.floating,
                                  duration: const Duration(seconds: 2),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  action: SnackBarAction(
                                    label: 'View Cart',
                                    textColor: Colors.white,
                                    onPressed: () {
                                      ScaffoldMessenger.of(context).clearSnackBars();
                                      Navigator.pushNamed(context, AppRoutes.cart);
                                    },
                                  ),
                                ),
                              );
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            side: const BorderSide(color: AppColors.primary, width: 2),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: Text('ADD TO CART',
                              style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.primary)),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            if (_shop != null) {
                              cart.addItem(_product!, _shop!);
                              ScaffoldMessenger.of(context).clearSnackBars();
                              Navigator.pushNamed(context, AppRoutes.cart);
                            }
                          },
                          child: Container(
                            height: 56,
                            decoration: BoxDecoration(
                              gradient: AppColors.ctaGradient,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: PremiumShadows.floatingButtonLight,
                            ),
                            child: Center(
                              child: Text('BUY NOW',
                                  style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrustItem(IconData icon, String text, bool isDark) {
    return Column(
      children: [
        Icon(icon, color: isDark ? Colors.white54 : AppColors.textLight, size: 24),
        const SizedBox(height: 8),
        Text(
          text,
          style: GoogleFonts.outfit(
            fontSize: 12,
            color: isDark ? Colors.white54 : AppColors.textLight,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _qtyBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(50),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: AppColors.primary, size: 20),
      ),
    );
  }
}
