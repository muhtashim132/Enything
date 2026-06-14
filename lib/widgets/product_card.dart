import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/product_model.dart';
import '../models/shop_model.dart';
import '../providers/cart_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';
import '../config/routes.dart';

class ProductCard extends StatefulWidget {
  final ProductModel product;
  final ShopModel? shop;

  const ProductCard({super.key, required this.product, this.shop});

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard> {
  bool _isPressed = false;

  ProductModel get product => widget.product;
  ShopModel? get shop => widget.shop;

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final favs = context.watch<FavoritesProvider>();
    final auth = context.watch<AuthProvider>();
    final quantity = cart.getItemQuantity(product.id);
    final isFav = favs.isProductFavorite(product.id);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => Navigator.pushNamed(
        context,
        AppRoutes.productDetails,
        arguments: {'productId': product.id},
      ),
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: isDark ? Border.all(color: Colors.white.withValues(alpha: 0.06)) : null,
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.3)
                  : Colors.black.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Product Image ──────────────────────────────────────────
            Expanded(
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    child: product.firstImage.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: product.firstImage,
                            width: double.infinity,
                            fit: BoxFit.contain,
                            placeholder: (c, i) => Container(color: Colors.grey.shade100),
                            errorWidget: (c, e, s) => Container(
                              color: AppColors.primary.withValues(alpha: 0.05),
                              child: const Center(
                                child: Icon(Icons.shopping_bag_outlined, size: 40, color: AppColors.primary),
                              ),
                            ),
                          )
                        : Container(
                            width: double.infinity,
                            color: AppColors.primary.withValues(alpha: 0.05),
                            child: const Center(
                              child: Icon(Icons.shopping_bag_outlined, size: 40, color: AppColors.primary),
                            ),
                          ),
                  ),
                  
                  // Favorite Button
                  Positioned(
                    top: 8,
                    left: 8,
                    child: GestureDetector(
                      onTap: () {
                        if (auth.currentUserId != null) {
                          favs.toggleProductFavorite(auth.currentUserId!, product.id);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8)
                          ],
                        ),
                        child: Icon(
                          isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          size: 16,
                          color: isFav ? Colors.red : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  
                  // Veg/NonVeg indicator
                  if (product.isVeg != null)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                        ),
                        child: Icon(
                          Icons.circle,
                          size: 10,
                          color: product.isVeg! ? AppColors.vegGreen : AppColors.nonVegRed,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            
            // ── Info ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    product.name,
                                    style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: isDark ? Colors.white : AppColors.textPrimary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (shop != null && shop!.name.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      shop!.name,
                                      style: GoogleFonts.outfit(
                                        fontWeight: FontWeight.w500,
                                        fontSize: 11,
                                        color: isDark ? Colors.white38 : AppColors.textSecondary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 4),
                            Row(
                              children: [
                                const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                                const SizedBox(width: 2),
                                Text(
                                  product.rating > 0 ? product.rating.toStringAsFixed(1) : 'New',
                                    style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                      color: isDark ? Colors.white : AppColors.textPrimary,
                                    ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              '₹${product.price.toStringAsFixed(0)}',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                                fontSize: 16,
                              ),
                            ),
                            if (product.originalPrice != null) ...[
                              const SizedBox(width: 4),
                              Text(
                                '₹${product.originalPrice!.toStringAsFixed(0)}',
                                style: GoogleFonts.outfit(
                                  color: AppColors.textLight,
                                  fontSize: 11,
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                    
                    // ── Add to cart ─────────────────────────────────────
                    if (quantity > 0)
                      Container(
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            GestureDetector(
                              onTap: () => context.read<CartProvider>().updateQuantity(product.id, quantity - 1),
                              child: const Icon(Icons.remove, size: 16, color: Colors.white),
                            ),
                            Text(
                              '$quantity',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: Colors.white,
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                if (shop != null) context.read<CartProvider>().addItem(product, shop!);
                              },
                              child: const Icon(Icons.add, size: 16, color: Colors.white),
                            ),
                          ],
                        ),
                      )
                    else
                      GestureDetector(
                        onTap: () {
                          if (shop != null) {
                            context.read<CartProvider>().addItem(product, shop!);
                            _showAddedToast(context, product.name);
                          }
                        },
                        child: Container(
                          width: double.infinity,
                          height: 32,
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.primary, width: 1.5),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Text(
                              'ADD',
                              style: GoogleFonts.outfit(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
              ),
            ),
          ],
        ),
      )),
    );
  }

  void _showAddedToast(BuildContext context, String name) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$name added! 🛒'),
        duration: const Duration(seconds: 1),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 100, left: 24, right: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
