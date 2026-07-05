import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product_model.dart';
import '../models/shop_model.dart';
import '../providers/cart_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/recently_viewed_provider.dart';
import '../providers/location_provider.dart';
import 'common/sheet_skeleton_loader.dart';
import '../utils/delivery_calculator.dart';
import '../theme/app_colors.dart';
import '../theme/premium_effects.dart';

import '../config/app_categories.dart';
import '../config/routes.dart';
import '../widgets/shop_detail_sheet.dart';
import '../widgets/restaurant_dashboard_sheet.dart';
import 'common/premium_product_image.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Public helper — call this instead of Navigator.pushNamed for productDetails
// ─────────────────────────────────────────────────────────────────────────────
void showProductDetailSheet(BuildContext context, String productId,
    {bool highlightVariants = false}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    useRootNavigator: true,
    clipBehavior: Clip.antiAliasWithSaveLayer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => ProductDetailSheet(
        productId: productId, highlightVariants: highlightVariants),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Sheet widget
// ─────────────────────────────────────────────────────────────────────────────
class ProductDetailSheet extends StatefulWidget {
  final String productId;
  final bool highlightVariants;
  const ProductDetailSheet(
      {super.key, required this.productId, this.highlightVariants = false});

  @override
  State<ProductDetailSheet> createState() => _ProductDetailSheetState();
}

class _ProductDetailSheetState extends State<ProductDetailSheet> {
  SupabaseClient get _supabase => Supabase.instance.client;
  ProductModel? _product;
  ShopModel? _shop;
  bool _isLoading = true;
  int _currentImageIndex = 0;
  ProductVariant? _selectedVariant;
  final GlobalKey _variantKey = GlobalKey();

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

        if (widget.highlightVariants && product.variants.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_variantKey.currentContext != null) {
              Scrollable.ensureVisible(_variantKey.currentContext!,
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeInOut,
                  alignment: 0.3);
            }
          });
        }
        // Track recently viewed (non-blocking, fire-and-forget)
        context.read<RecentlyViewedProvider>().addProduct(product.id);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 1.0,
      snap: true,
      snapSizes: const [0.65, 1.0],
      builder: (context, scrollController) {
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF12121A) : const Color(0xFFF8F9FA),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
                      isDark: isDark,
                      selectedVariant: _selectedVariant,
                      onVariantChanged: (v) =>
                          setState(() => _selectedVariant = v),
                      highlightVariants: widget.highlightVariants,
                      variantKey: _variantKey,
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
  final bool isDark;
  final ProductVariant? selectedVariant;
  final ValueChanged<ProductVariant?> onVariantChanged;
  final bool highlightVariants;
  final GlobalKey? variantKey;

  const _SheetContent({
    required this.product,
    required this.shop,
    required this.scrollController,
    required this.currentImageIndex,
    required this.onImageChanged,
    required this.isDark,
    this.selectedVariant,
    required this.onVariantChanged,
    this.highlightVariants = false,
    this.variantKey,
  });

  static Widget _trustItem(String emoji, String label, bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white54 : AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final favs = context.watch<FavoritesProvider>();
    final auth = context.watch<AuthProvider>();
    final location = context.watch<LocationProvider>();
    final quantity =
        cart.getItemQuantity(product.id, variantName: selectedVariant?.name);
    final isFav = favs.isProductFavorite(product.id);

    final distanceKm = shop != null ? location.distanceTo(shop!.location) : 0.0;
    final deliveryLabel =
        DeliveryCalculator.deliveryChargeLabel(distanceKm, product.price);

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
                              : (i == 0
                                  ? product.displayImage
                                  : product.images[i]);
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
                                        (idx) => idx == 0
                                            ? product.displayImage
                                            : product.images[idx],
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
                                  child: PremiumProductImage(
                                    imageUrl: url,
                                    isDark: isDark,
                                  ),
                                )
                              : _ImageFallback();
                        },
                      ),

                      // Image background tint (top only for icons)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: 80,
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

                      // Premium pill-style dot indicators
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
                                duration: PremiumAnimations.normal,
                                curve: PremiumAnimations.defaultCurve,
                                width: i == currentImageIndex ? 22 : 6,
                                height: 6,
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 2),
                                decoration: BoxDecoration(
                                  gradient: i == currentImageIndex
                                      ? const LinearGradient(
                                          colors: [
                                            Color(0xFF0A2A9E),
                                            Color(0xFF1E40AF)
                                          ],
                                        )
                                      : null,
                                  color: i == currentImageIndex
                                      ? null
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

              // ── Product info card ────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkSurface : Colors.white,
                    borderRadius: PremiumRadius.largeBorder,
                    border: isDark
                        ? Border.all(
                            color: Colors.white.withValues(alpha: 0.07))
                        : null,
                    boxShadow: PremiumShadows.cardLight,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Shop name link
                      if (shop != null) ...[
                        GestureDetector(
                          onTap: () {
                            Navigator.pop(context);
                            final isFood =
                                AppCategories.groupFor(shop!.category) ==
                                    CategoryGroup.food;
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

                      Builder(
                        builder: (context) {
                          final currentPrice =
                              selectedVariant?.price ?? product.price;
                          final currentOriginalPrice =
                              selectedVariant?.originalPrice ??
                                  product.originalPrice;
                          final currentDiscountPercent =
                              selectedVariant?.discountPercent ??
                                  product.discountPercent;
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Discount label
                                    if (currentDiscountPercent != null)
                                      Container(
                                        margin:
                                            const EdgeInsets.only(bottom: 4),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: AppColors.success
                                              .withValues(alpha: 0.10),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          '${currentDiscountPercent.toInt()}% OFF',
                                          style: GoogleFonts.outfit(
                                            color: AppColors.success,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    // Price
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '₹',
                                          style: GoogleFonts.outfit(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                        Text(
                                          currentPrice.toStringAsFixed(0),
                                          style: GoogleFonts.outfit(
                                            fontSize: 28,
                                            fontWeight: FontWeight.w900,
                                            color: AppColors.primary,
                                            letterSpacing: -0.5,
                                          ),
                                        ),
                                        if (currentDiscountPercent != null &&
                                            currentOriginalPrice != null) ...[
                                          const SizedBox(width: 10),
                                          Padding(
                                            padding: const EdgeInsets.only(
                                                bottom: 4),
                                            child: Text(
                                              '₹${currentOriginalPrice.toStringAsFixed(0)}',
                                              style: GoogleFonts.outfit(
                                                fontSize: 15,
                                                color: isDark
                                                    ? Colors.white38
                                                    : AppColors.textLight,
                                                decoration:
                                                    TextDecoration.lineThrough,
                                                decorationColor: isDark
                                                    ? Colors.white38
                                                    : AppColors.textLight,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),

                      if (product.variants.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        TweenAnimationBuilder<double>(
                            key: variantKey,
                            tween: Tween<double>(
                                begin: highlightVariants ? 0.0 : 1.0, end: 1.0),
                            duration: const Duration(milliseconds: 1500),
                            curve: Curves.elasticOut,
                            builder: (context, value, child) {
                              return Container(
                                padding: highlightVariants
                                    ? const EdgeInsets.all(12)
                                    : EdgeInsets.zero,
                                decoration: BoxDecoration(
                                  color: highlightVariants
                                      ? AppColors.primary
                                          .withValues(alpha: 0.1 * (2 - value))
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(16),
                                  border: highlightVariants
                                      ? Border.all(
                                          color: AppColors.primary.withValues(
                                              alpha: 0.5 * (2 - value)),
                                          width: 2)
                                      : null,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          'Select Variation',
                                          style: GoogleFonts.outfit(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: isDark
                                                ? Colors.white
                                                : AppColors.textPrimary,
                                          ),
                                        ),
                                        if (highlightVariants) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppColors.primary,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Text('Required',
                                                style: GoogleFonts.outfit(
                                                    color: Colors.white,
                                                    fontSize: 10,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: product.variants.map((v) {
                                        final isSelected =
                                            selectedVariant?.name == v.name;
                                        return GestureDetector(
                                          onTap: () => onVariantChanged(v),
                                          child: Transform.scale(
                                            scale:
                                                highlightVariants && !isSelected
                                                    ? value
                                                    : 1.0,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 14,
                                                      vertical: 8),
                                              decoration: BoxDecoration(
                                                color: isSelected
                                                    ? AppColors.primary
                                                        .withValues(alpha: 0.1)
                                                    : (isDark
                                                        ? Colors.white
                                                            .withValues(
                                                                alpha: 0.05)
                                                        : Colors.grey.shade100),
                                                borderRadius:
                                                    BorderRadius.circular(100),
                                                border: Border.all(
                                                  color: isSelected
                                                      ? AppColors.primary
                                                      : (highlightVariants
                                                          ? AppColors.primary
                                                              .withValues(
                                                                  alpha: 0.3)
                                                          : Colors.transparent),
                                                ),
                                              ),
                                              child: Text(
                                                '${v.name} - ₹${v.price.toStringAsFixed(0)}',
                                                style: GoogleFonts.outfit(
                                                  fontSize: 13,
                                                  fontWeight: isSelected
                                                      ? FontWeight.w700
                                                      : FontWeight.w500,
                                                  color: isSelected
                                                      ? AppColors.primary
                                                      : (isDark
                                                          ? Colors.white70
                                                          : AppColors
                                                              .textSecondary),
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                ),
                              );
                            }),
                      ],

                      const SizedBox(height: 14),

                      // Trust indicators
                      Row(
                        children: [
                          _trustItem('🔒', 'Secure', isDark),
                          const SizedBox(width: 16),
                          _trustItem('✓', 'Quality', isDark),
                        ],
                      ),

                      // Delivery & Distance Info
                      if (shop != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.03)
                                : const Color(0xFFF4F6FB),
                            borderRadius:
                                BorderRadius.circular(PremiumRadius.medium),
                            border: Border.all(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.05)
                                    : Colors.grey.shade200),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.location_on_rounded,
                                      size: 16, color: AppColors.primary),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${distanceKm.toStringAsFixed(1)} km away',
                                    style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: isDark
                                          ? Colors.white70
                                          : AppColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  const Icon(Icons.delivery_dining_rounded,
                                      size: 16, color: AppColors.success),
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
                    ],
                  ),
                ),
              ),

              // ── Expanded detail sections ──────────────────────────────────────────
              if (product.specialTags.isNotEmpty)
                SliverToBoxAdapter(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurface : Colors.white,
                      borderRadius: PremiumRadius.largeBorder,
                      boxShadow: PremiumShadows.cardLight,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Highlights',
                            style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary)),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: product.specialTags
                              .map((tag) => Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary
                                          .withValues(alpha: 0.07),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(tag,
                                        style: GoogleFonts.outfit(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.primary)),
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
                      color: isDark ? AppColors.darkSurface : Colors.white,
                      borderRadius: PremiumRadius.largeBorder,
                      boxShadow: PremiumShadows.cardLight,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Product Details',
                            style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary)),
                        const SizedBox(height: 10),
                        Text(product.description!,
                            style: GoogleFonts.outfit(
                                fontSize: 14,
                                color: AppColors.textSecondary,
                                height: 1.6)),
                      ],
                    ),
                  ),
                ),

              // Bottom spacing
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),
        ),
        _buildBottomBar(context, quantity, cart, isDark),
      ],
    );
  }

  Widget _buildBottomBar(
      BuildContext context, int quantity, CartProvider cart, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1A1A2E).withValues(alpha: 0.97)
            : Colors.white.withValues(alpha: 0.97),
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.07)
                : Colors.grey.shade100,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.40)
                : Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: (shop != null && !shop!.isActive)
          ? Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: PremiumRadius.smallBorder,
              ),
              child: Center(
                child: Text(
                  'Shop Currently Closed',
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            )
          : quantity > 0
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _qtyBtn(Icons.remove, () {
                      if (shop != null) {
                        cart.updateQuantity(product.id, quantity - 1,
                            variantName: selectedVariant?.name);
                      }
                    }, isDark),
                    const SizedBox(width: 28),
                    AnimatedSwitcher(
                      duration: PremiumAnimations.fast,
                      transitionBuilder: (child, anim) =>
                          ScaleTransition(scale: anim, child: child),
                      child: Text(
                        '$quantity',
                        key: ValueKey(quantity),
                        style: GoogleFonts.outfit(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 28),
                    _qtyBtn(Icons.add, () {
                      if (shop != null) {
                        if (product.variants.isNotEmpty &&
                            selectedVariant == null) {
                          _showVariantWarning(context);
                          return;
                        }
                        cart.addItemWithFeedback(context, product, shop!,
                            selectedVariant: selectedVariant);
                      }
                    }, isDark),
                    const SizedBox(width: 20),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          ScaffoldMessenger.of(context).clearSnackBars();
                          Navigator.pushNamed(context, AppRoutes.cart);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            gradient: AppColors.ctaGradient,
                            borderRadius: PremiumRadius.smallBorder,
                            boxShadow: PremiumShadows.floatingButtonLight,
                          ),
                          child: Center(
                            child: Text(
                              'View Cart',
                              style: GoogleFonts.outfit(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          if (shop != null) {
                            if (product.variants.isNotEmpty &&
                                selectedVariant == null) {
                              _showVariantWarning(context);
                              return;
                            }
                            cart.addItemWithFeedback(context, product, shop!,
                                selectedVariant: selectedVariant);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: Colors.transparent,
                            borderRadius: PremiumRadius.smallBorder,
                            border: Border.all(
                              color: AppColors.secondary
                                  .withValues(alpha: isDark ? 0.6 : 0.8),
                              width: 2,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              'ADD TO CART',
                              style: GoogleFonts.outfit(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? AppColors.secondaryLight
                                    : AppColors.secondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          if (shop != null) {
                            if (product.variants.isNotEmpty &&
                                selectedVariant == null) {
                              _showVariantWarning(context);
                              return;
                            }
                            cart.addItemWithFeedback(context, product, shop!,
                                selectedVariant: selectedVariant);
                            Navigator.pushNamed(context, AppRoutes.cart);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            gradient: AppColors.ctaGradient,
                            borderRadius: PremiumRadius.smallBorder,
                            boxShadow: PremiumShadows.floatingButtonLight,
                          ),
                          child: Center(
                            child: Text(
                              'BUY NOW',
                              style: GoogleFonts.outfit(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  void _showVariantWarning(BuildContext context) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) => Positioned(
        bottom: 110, // Floats right above the bottom bar
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutBack,
            builder: (context, value, child) {
              return Transform.scale(
                scale: value,
                child: Opacity(
                  opacity: value.clamp(0.0, 1.0),
                  child: child,
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFE85050), // Premium Coral/Red
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black26,
                      blurRadius: 16,
                      offset: Offset(0, 6)),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.touch_app_rounded,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Almost there!',
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.3,
                          ),
                        ),
                        Text(
                          'Please select a variation to continue.',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(entry);

    // Auto-remove after 2.5 seconds
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (entry.mounted) {
        entry.remove();
      }
    });

    if (variantKey?.currentContext != null) {
      Scrollable.ensureVisible(variantKey!.currentContext!,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
          alignment: 0.3);
    }
  }

  Widget _qtyBtn(IconData icon, VoidCallback onTap, bool isDark) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(50),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(
            color: AppColors.primary.withValues(alpha: isDark ? 0.6 : 0.8),
            width: 2,
          ),
          shape: BoxShape.circle,
        ),
        child: Icon(icon,
            color: isDark ? AppColors.primaryLight : AppColors.primary,
            size: 18),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SheetSkeletonLoader(isDark: isDark);
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

  const _FullScreenImageViewer(
      {required this.images, required this.initialIndex});

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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: AnimatedBuilder(
                    animation: _pageController,
                    builder: (context, child) {
                      int currentPage = widget.initialIndex;
                      if (_pageController.hasClients) {
                        currentPage = _pageController.page?.round() ??
                            widget.initialIndex;
                      }
                      return Text(
                        '${currentPage + 1} / ${widget.images.length}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
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
