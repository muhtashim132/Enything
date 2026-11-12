import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:math';

import '../../providers/cart_provider.dart';
import '../../config/route_observer.dart';
import '../../config/routes.dart';
import '../../models/shop_model.dart';
import '../../theme/sensory_haptics.dart';
import '../../main.dart' show navigatorKey;

class MultiShopCartBubbleOverlay extends StatelessWidget {
  final Widget child;

  const MultiShopCartBubbleOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        textDirection: TextDirection.ltr,
        children: [
          child,
          const DraggableCartBubble(),
        ],
      ),
    );
  }
}

class DraggableCartBubble extends StatefulWidget {
  const DraggableCartBubble({super.key});

  @override
  State<DraggableCartBubble> createState() => _DraggableCartBubbleState();
}

class _DraggableCartBubbleState extends State<DraggableCartBubble>
    with SingleTickerProviderStateMixin {
  Offset? _position;
  final double _bubbleSize = 58.0;
  bool _isDragging = false;

  AnimationController? _snapController;
  Animation<Offset>? _snapAnimation;

  // Define allowed routes for the bubble to appear on across customer discovery and browsing.
  static const List<String> _allowedRoutes = [
    AppRoutes.customerHome,
    AppRoutes.restaurant,
    AppRoutes.restaurantDashboard,
    AppRoutes.productDetails,
    AppRoutes.favorites,
    AppRoutes.categoryProducts,
    AppRoutes.allListings,
    AppRoutes.allCategories,
    AppRoutes.bulkOrderDiscovery,
    AppRoutes.bulkOrderMenu,
  ];

  @override
  void initState() {
    super.initState();
    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
  }

  @override
  void dispose() {
    _snapController?.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Initialize position once when context is available with safe boundary clamping
    if (_position == null) {
      final size = MediaQuery.of(context).size;
      final padding = MediaQuery.of(context).padding;
      final minTop = padding.top + 60.0;
      final maxTop = size.height - padding.bottom - 110.0 - _bubbleSize;

      _position = Offset(
        size.width - _bubbleSize - 16, // 16px from right edge
        (size.height / 2).clamp(minTop, maxTop),
      );
    }
  }

  void _onPanStart(DragStartDetails details) {
    if (_snapController != null && _snapController!.isAnimating) {
      _snapController!.stop();
    }
    SensoryHaptics.light();
    setState(() => _isDragging = true);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_position == null) return;

    final size = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;
    final minTop = padding.top + 60.0;
    final maxTop = size.height - padding.bottom - 110.0 - _bubbleSize;

    setState(() {
      _position = Offset(
        (_position!.dx + details.delta.dx).clamp(0.0, size.width - _bubbleSize),
        (_position!.dy + details.delta.dy).clamp(minTop, maxTop),
      );
    });
  }

  void _onPanEnd(DragEndDetails details) {
    setState(() => _isDragging = false);
    if (_position == null || !mounted) return;

    final size = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;
    final minTop = padding.top + 60.0;
    final maxTop = size.height - padding.bottom - 110.0 - _bubbleSize;

    final double startX = _position!.dx;
    final double startY = _position!.dy.clamp(minTop, maxTop);

    // Spring edge-docking: dock smoothly to nearest screen edge (left or right)
    final double targetX = (startX + _bubbleSize / 2 < size.width / 2)
        ? 16.0
        : (size.width - _bubbleSize - 16.0);
    final double targetY = startY;

    _snapAnimation = Tween<Offset>(
      begin: Offset(startX, startY),
      end: Offset(targetX, targetY),
    ).animate(CurvedAnimation(
      parent: _snapController!,
      curve: Curves.easeOutBack,
    ));

    _snapController!.reset();
    _snapAnimation!.addListener(() {
      if (mounted) {
        setState(() {
          _position = _snapAnimation!.value;
        });
      }
    });
    _snapController!.forward();
  }

  bool _isCartInteracting = false;

  void _handleTap(List<ShopModel> allShops, {List<ShopModel> pendingShops = const []}) {
    if (_isCartInteracting || allShops.isEmpty) return;
    _isCartInteracting = true;
    SensoryHaptics.selection();

    final contextForNav = navigatorKey.currentState?.context;
    if (contextForNav == null) {
      _isCartInteracting = false;
      return;
    }

    if (allShops.length == 1 && pendingShops.isEmpty) {
      // Instant navigation for 1 regular cart shop
      navigatorKey.currentState?.pushNamed(
        AppRoutes.restaurant,
        arguments: {'shopId': allShops.first.id},
      ).then((_) {
        _isCartInteracting = false;
      });
    } else {
      // Show modern elevated Bottom Sheet for multiple shops or replacement mode
      final pendingShopIds = pendingShops.map((s) => s.id).toSet();
      bool isNavigating = false;
      showModalBottomSheet(
        context: contextForNav,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (ctx) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          return Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF141420) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.15),
                  blurRadius: 24,
                  offset: const Offset(0, -6),
                ),
              ],
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Modern sheet drag handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 18),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white24 : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          pendingShops.isNotEmpty
                              ? 'Active Order (${allShops.length}/3)'
                              : 'Active Shops in Cart',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                            color: isDark ? Colors.white : const Color(0xFF1E293B),
                          ),
                        ),
                        if (allShops.length < 3)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFF10B981).withValues(alpha: 0.3),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              '${3 - allShops.length} slot${3 - allShops.length > 1 ? 's' : ''} left',
                              style: const TextStyle(
                                color: Color(0xFF10B981),
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      pendingShops.isNotEmpty
                          ? 'Your active order includes items from up to 3 shops. Tap a shop to view its menu.'
                          : 'Order items from up to 3 shops in a single combined delivery fee.',
                      style: TextStyle(
                        color: isDark ? Colors.white60 : Colors.grey.shade600,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 18),
                    ...allShops.map((shop) {
                      final isPending = pendingShopIds.contains(shop.id);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1E1E2D)
                              : const Color(0xFFF8F9FA),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.grey.shade200,
                            width: 1,
                          ),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              if (isNavigating) return;
                              isNavigating = true;
                              SensoryHaptics.selection();
                              Navigator.pop(ctx);
                              navigatorKey.currentState?.pushNamed(
                                AppRoutes.restaurant,
                                arguments: {'shopId': shop.id},
                              ).then((_) => isNavigating = false);
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: isPending
                                          ? const Color(0xFFF59E0B)
                                              .withValues(alpha: 0.15)
                                          : const Color(0xFF6366F1)
                                              .withValues(alpha: 0.12),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.storefront_rounded,
                                      color: isPending
                                          ? const Color(0xFFD97706)
                                          : const Color(0xFF6366F1),
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          shop.name,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                            color: isDark
                                                ? Colors.white
                                                : const Color(0xFF1E293B),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          shop.category,
                                          style: TextStyle(
                                            color: isDark
                                                ? Colors.white54
                                                : Colors.grey.shade500,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isPending
                                          ? const Color(0xFFF59E0B)
                                              .withValues(alpha: 0.15)
                                          : const Color(0xFF3B82F6)
                                              .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      isPending ? 'In Order' : 'In Cart',
                                      style: TextStyle(
                                        color: isPending
                                            ? const Color(0xFFD97706)
                                            : const Color(0xFF2563EB),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    color: isDark
                                        ? Colors.white38
                                        : Colors.grey.shade400,
                                    size: 20,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          );
        },
      ).then((_) {
        _isCartInteracting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: currentRouteNotifier,
      builder: (context, currentRoute, _) {
        // Only show on allowed customer discovery routes
        if (!_allowedRoutes.contains(currentRoute)) {
          return const SizedBox.shrink();
        }

        return Consumer<CartProvider>(
          builder: (context, cartProvider, _) {
            final pendingShops = cartProvider.isPendingReplacementActive
                ? cartProvider.activePendingShops
                : <ShopModel>[];
            final cartShops = cartProvider.shops;

            final seenIds = <String>{};
            final allShops = <ShopModel>[];
            for (final s in pendingShops) {
              if (seenIds.add(s.id)) allShops.add(s);
            }
            for (final s in cartShops) {
              if (seenIds.add(s.id)) allShops.add(s);
            }

            // Only show if there are items in the cart OR active shops in pending replacement
            if (allShops.isEmpty) {
              return const SizedBox.shrink();
            }

            return Positioned(
              left: _position?.dx ?? 0,
              top: _position?.dy ?? 0,
              child: GestureDetector(
                onPanStart: _onPanStart,
                onPanUpdate: _onPanUpdate,
                onPanEnd: _onPanEnd,
                onTap: () => _handleTap(allShops, pendingShops: pendingShops),
                child: AnimatedScale(
                  scale: _isDragging ? 0.92 : 1.0,
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  child: Container(
                    width: _bubbleSize,
                    height: _bubbleSize,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF6366F1), // Premium Modern Indigo
                          Color(0xFF4F46E5),
                          Color(0xFF4338CA),
                        ],
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.35),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6366F1).withValues(alpha: 0.42),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                          spreadRadius: 1,
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.22),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(
                          Icons.shopping_bag_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                        if (allShops.length > 1 || pendingShops.isNotEmpty)
                          Positioned(
                            right: -4,
                            top: -4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFFF3366),
                                    Color(0xFFFF5E3A),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2.0,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFFF3366)
                                        .withValues(alpha: 0.45),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Text(
                                '${allShops.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  height: 1.0,
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
          },
        );
      },
    );
  }
}
