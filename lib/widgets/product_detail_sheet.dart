import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product_model.dart';
import '../models/shop_model.dart';
import '../providers/cart_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/auth_provider.dart';
import '../theme/app_colors.dart';

import '../config/app_categories.dart';
import '../config/routes.dart';
import 'shop_detail_sheet.dart';
import 'restaurant_dashboard_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Public helper — call this instead of Navigator.pushNamed for productDetails
// ─────────────────────────────────────────────────────────────────────────────
void showProductDetailSheet(BuildContext context, String productId) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    useRootNavigator: true,
    builder: (_) => ProductDetailSheet(productId: productId),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Sheet widget
// ─────────────────────────────────────────────────────────────────────────────
class ProductDetailSheet extends StatefulWidget {
  final String productId;
  const ProductDetailSheet({super.key, required this.productId});

  @override
  State<ProductDetailSheet> createState() => _ProductDetailSheetState();
}

class _ProductDetailSheetState extends State<ProductDetailSheet> {
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

      if (mounted) {
        setState(() {
          _product = product;
          _shop = ShopModel.fromMap(shopData);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 1.0,
      snap: true,
      snapSizes: const [0.65, 1.0],
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF8F9FA),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: _isLoading
              ? const _LoadingSheet()
              : _product == null
                  ? const _ErrorSheet()
                  : _SheetContent(
                      product: _product!,
                      shop: _shop,
                      scrollController: scrollController,
                      currentImageIndex: _currentImageIndex,
                      onImageChanged: (i) =>
                          setState(() => _currentImageIndex = i),
                    ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main scrollable content
// ─────────────────────────────────────────────────────────────────────────────
class _SheetContent extends StatelessWidget {
  final ProductModel product;
  final ShopModel? shop;
  final ScrollController scrollController;
  final int currentImageIndex;
  final ValueChanged<int> onImageChanged;

  const _SheetContent({
    required this.product,
    required this.shop,
    required this.scrollController,
    required this.currentImageIndex,
    required this.onImageChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final favs = context.watch<FavoritesProvider>();
    final auth = context.watch<AuthProvider>();
    final quantity = cart.getItemQuantity(product.id);
    final isFav = favs.isProductFavorite(product.id);

    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            controller: scrollController,
      slivers: [
        // ── Drag handle ──────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),

        // ── Hero image area ───────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: SizedBox(
            height: 260,
            child: Stack(
              children: [
                // Image carousel
                PageView.builder(
                  itemCount:
                      product.images.isEmpty ? 1 : product.images.length,
                  onPageChanged: onImageChanged,
                  itemBuilder: (ctx, i) {
                    final url = product.images.isEmpty
                        ? ''
                        : (i == 0 ? product.displayImage : product.images[i]);
                    return url.isNotEmpty
                        ? GestureDetector(
                            onTap: () {
                              List<String> allImages = [];
                              if (product.images.isEmpty) {
                                if (product.displayImage.isNotEmpty) {
                                  allImages = [product.displayImage];
                                }
                              } else {
                                allImages = List<String>.generate(
                                  product.images.length,
                                  (idx) => idx == 0 ? product.displayImage : product.images[idx],
                                );
                              }
                              
                              if (allImages.isNotEmpty) {
                                showDialog(
                                  context: context,
                                  builder: (_) => _FullScreenImageViewer(
                                    images: allImages,
                                    initialIndex: i,
                                  ),
                                );
                              }
                            },
                            child: CachedNetworkImage(
                              imageUrl: url,
                              fit: BoxFit.contain,
                              width: double.infinity,
                              fadeInDuration: const Duration(milliseconds: 300),
                              placeholder: (c, _) => Shimmer.fromColors(
                                baseColor: const Color(0xFFE9ECEF),
                                highlightColor: const Color(0xFFF8F9FA),
                                child: Container(color: Colors.white),
                              ),
                              errorWidget: (c, e, s) => _ImageFallback(),
                            ),
                          )
                        : _ImageFallback();
                  },
                ),

                // Image background tint (top only for icons)
                Positioned(
                  top: 0, left: 0, right: 0, height: 80,
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.3),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Close (chevron-down) button — top left
                Positioned(
                  top: 12,
                  left: 16,
                  child: _OverlayCircleButton(
                    icon: Icons.keyboard_arrow_down_rounded,
                    iconSize: 26,
                    onTap: () => Navigator.pop(context),
                  ),
                ),

                // Favorite button — top right
                Positioned(
                  top: 12,
                  right: 16,
                  child: _OverlayCircleButton(
                    icon: isFav
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                    iconColor: isFav ? AppColors.primary : null,
                    onTap: () {
                      if (auth.currentUserId != null) {
                        favs.toggleProductFavorite(
                            auth.currentUserId!, product.id);
                      }
                    },
                  ),
                ),

                // Dot indicators
                if (product.images.length > 1)
                  Positioned(
                    bottom: 12,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        product.images.length,
                        (i) => AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: i == currentImageIndex ? 20 : 6,
                          height: 6,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: i == currentImageIndex
                                ? AppColors.primary
                                : Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ),

                // Veg / Non-veg indicator — bottom-left
                if (product.isVeg != null)
                  Positioned(
                    bottom: 12,
                    left: 16,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: const [
                          BoxShadow(color: Colors.black12, blurRadius: 4)
                        ],
                      ),
                      child: Icon(
                        Icons.circle,
                        size: 12,
                        color: product.isVeg!
                            ? AppColors.vegGreen
                            : AppColors.nonVegRed,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // ── White product info card ───────────────────────────────────────────
        SliverToBoxAdapter(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Shop name link
                if (shop != null) ...[
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      final isFood = AppCategories.groupFor(shop!.category) == CategoryGroup.food;
                      if (isFood) {
                        showRestaurantDashboardSheet(context, shop!.id);
                      } else {
                        showShopDetailSheet(context, shop!.id);
                      }
                    },
                    child: Text(
                      'Explore all ${shop!.name} items  ›',
                      style: GoogleFonts.outfit(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // Product name
                Text(
                  product.name,
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),

                // Short description
                if (product.description != null &&
                    product.description!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    product.description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                // Weight badge
                if (product.weightPerUnit != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Text(
                      '${product.weightPerUnit!.toStringAsFixed(product.weightPerUnit! % 1 == 0 ? 0 : 1)} ${product.unitType}',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Price row + ADD button
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Discount label
                          if (product.discountPercent != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                '${product.discountPercent!.toInt()}% OFF',
                                style: GoogleFonts.outfit(
                                  color: AppColors.success,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          // Price
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                '₹${product.price.toStringAsFixed(0)}',
                                style: GoogleFonts.outfit(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              if (product.discountPercent != null) ...[
                                const SizedBox(width: 8),
                                Text(
                                  '₹${product.originalPrice!.toStringAsFixed(0)}',
                                  style: GoogleFonts.outfit(
                                    fontSize: 15,
                                    color: AppColors.textLight,
                                    decoration: TextDecoration.lineThrough,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          // Unit price
                          if (product.weightPerUnit != null &&
                              product.weightPerUnit! > 0)
                            Text(
                              '₹${(product.price / (product.weightPerUnit! / 100)).toStringAsFixed(0)}/100${product.unitType}',
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                color: AppColors.textLight,
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
        ),

        // ── Expanded detail sections ──────────────────────────────────────────
        // Special tags / highlights
        if (product.specialTags.isNotEmpty)
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Highlights',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: product.specialTags
                        .map((tag) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.07),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.2)),
                              ),
                              child: Text(
                                tag,
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                ],
              ),
            ),
          ),

        // Full description
        if (product.description != null &&
            product.description!.isNotEmpty)
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Product Details',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    product.description!,
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Shop info card (expanded only)
        if (shop != null)
          SliverToBoxAdapter(
            child: GestureDetector(
              onTap: () {
                Navigator.pop(context);
                final isFood = AppCategories.groupFor(shop!.category) == CategoryGroup.food;
                if (isFood) {
                  showRestaurantDashboardSheet(context, shop!.id);
                } else {
                  showShopDetailSheet(context, shop!.id);
                }
              },
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.store_outlined,
                          color: AppColors.primary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            shop!.name,
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          if (shop!.address.isNotEmpty)
                            Text(
                              shop!.address,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded,
                        size: 14, color: AppColors.textLight),
                  ],
                ),
              ),
            ),
          ),

        // Bottom spacing
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ),
        ),
        _buildBottomBar(context, quantity, cart),
      ],
    );
  }

  Widget _buildBottomBar(BuildContext context, int quantity, CartProvider cart) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1A1A2E) : Colors.white,
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
                  if (shop != null) cart.updateQuantity(product.id, quantity - 1);
                }),
                const SizedBox(width: 28),
                Text('$quantity', style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(width: 28),
                _qtyBtn(Icons.add, () {
                  if (shop != null) cart.addItem(product, shop!);
                }),
                const SizedBox(width: 20),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).clearSnackBars();
                      Navigator.pushNamed(context, AppRoutes.cart);
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('View Cart', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      if (shop != null) {
                        cart.addItem(product, shop!);
                        ScaffoldMessenger.of(context).clearSnackBars();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('${product.name} added to cart! 🛒'),
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
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: AppColors.primary, width: 2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('ADD TO CART', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primary)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      if (shop != null) {
                        cart.addItem(product, shop!);
                        ScaffoldMessenger.of(context).clearSnackBars();
                        Navigator.pushNamed(context, AppRoutes.cart);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('BUY NOW', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _qtyBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(50),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(border: Border.all(color: AppColors.primary, width: 2), shape: BoxShape.circle),
        child: Icon(icon, color: AppColors.primary, size: 18),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Overlay circular button (close, share, etc.)
// ─────────────────────────────────────────────────────────────────────────────
class _OverlayCircleButton extends StatelessWidget {
  final IconData icon;
  final double iconSize;
  final Color? iconColor;
  final VoidCallback onTap;

  const _OverlayCircleButton({
    required this.icon,
    this.iconSize = 20,
    this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 8,
            ),
          ],
        ),
        child: Icon(
          icon,
          size: iconSize,
          color: iconColor ?? AppColors.textPrimary,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Loading / error states
// ─────────────────────────────────────────────────────────────────────────────
class _LoadingSheet extends StatelessWidget {
  const _LoadingSheet();
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(top: 12),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const Expanded(
          child: Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        ),
      ],
    );
  }
}

class _ErrorSheet extends StatelessWidget {
  const _ErrorSheet();
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(top: 12),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline,
                    size: 48, color: AppColors.textLight),
                const SizedBox(height: 12),
                Text(
                  'Product not found',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ImageFallback extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primary.withValues(alpha: 0.05),
      child: const Center(
        child: Icon(Icons.shopping_bag_outlined,
            size: 80, color: AppColors.primary),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Full Screen Image Viewer
// ─────────────────────────────────────────────────────────────────────────────
class _FullScreenImageViewer extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const _FullScreenImageViewer({required this.images, required this.initialIndex});

  @override
  State<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<_FullScreenImageViewer> {
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.images.length,
            itemBuilder: (context, index) {
              return InteractiveViewer(
                child: CachedNetworkImage(
                  imageUrl: widget.images[index],
                  fit: BoxFit.contain,
                  placeholder: (c, _) => const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),
              );
            },
          ),
          Positioned(
            top: 40,
            right: 20,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          if (widget.images.length > 1)
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: AnimatedBuilder(
                    animation: _pageController,
                    builder: (context, child) {
                      int currentPage = widget.initialIndex;
                      if (_pageController.hasClients) {
                        currentPage = _pageController.page?.round() ?? widget.initialIndex;
                      }
                      return Text(
                        '${currentPage + 1} / ${widget.images.length}',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      );
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

