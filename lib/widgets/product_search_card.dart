import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/product_model.dart';
import '../models/shop_model.dart';
import '../providers/cart_provider.dart';
import '../theme/app_colors.dart';
import '../config/routes.dart';

class ProductSearchCard extends StatefulWidget {
  final ProductModel product;
  final ShopModel shop;

  const ProductSearchCard({super.key, required this.product, required this.shop});

  @override
  State<ProductSearchCard> createState() => _ProductSearchCardState();
}

class _ProductSearchCardState extends State<ProductSearchCard> {
  bool _isPressed = false;

  ProductModel get product => widget.product;
  ShopModel get shop => widget.shop;

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final quantity = cart.getItemQuantity(product.id);
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
        height: 120,
        margin: const EdgeInsets.only(bottom: 16),
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
        child: Row(
          children: [
            // Image
            Container(
              width: 120,
              height: 120,
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.horizontal(left: Radius.circular(24)),
              ),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(24)),
                    child: product.displayImage.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: product.displayImage,
                            width: double.infinity,
                            height: double.infinity,
                            fit: BoxFit.contain,
                            placeholder: (c, i) => Container(color: Colors.grey.shade100),
                            errorWidget: (c, e, s) => Container(
                              color: AppColors.primary.withValues(alpha: 0.05),
                              child: const Center(
                                child: Icon(Icons.shopping_bag_outlined, size: 30, color: AppColors.primary),
                              ),
                            ),
                          )
                        : Container(
                            width: double.infinity,
                            height: double.infinity,
                            color: AppColors.primary.withValues(alpha: 0.05),
                            child: const Center(
                              child: Icon(Icons.shopping_bag_outlined, size: 30, color: AppColors.primary),
                            ),
                          ),
                  ),
                  if (product.isVeg != null)
                    Positioned(
                      top: 8,
                      right: 8,
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
            
            // Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            product.name,
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Row(
                          children: [
                            const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              product.rating > 0 ? product.rating.toStringAsFixed(1) : 'New',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (shop.bannerImage != null && shop.bannerImage!.isNotEmpty) ...[
                          CircleAvatar(
                            radius: 8,
                            backgroundImage: CachedNetworkImageProvider(shop.bannerImage!),
                            backgroundColor: Colors.grey.shade200,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            shop.name,
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '₹${product.price.toStringAsFixed(0)}',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                                fontSize: 16,
                              ),
                            ),
                            if (product.originalPrice != null)
                              Text(
                                '₹${product.originalPrice!.toStringAsFixed(0)}',
                                style: GoogleFonts.outfit(
                                  color: AppColors.textLight,
                                  fontSize: 12,
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                          ],
                        ),
                        if (quantity > 0)
                          Container(
                            height: 32,
                            width: 80,
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
                                    context.read<CartProvider>().addItem(product, shop);
                                  },
                                  child: const Icon(Icons.add, size: 16, color: Colors.white),
                                ),
                              ],
                            ),
                          )
                        else
                          GestureDetector(
                            onTap: () {
                              context.read<CartProvider>().addItem(product, shop);
                              _showAddedToast(context, product.name);
                            },
                            child: Container(
                              height: 32,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
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
                  ],
                ),
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
