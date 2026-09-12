import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:math';

import '../../providers/cart_provider.dart';
import '../../config/route_observer.dart';
import '../../config/routes.dart';
import '../../models/shop_model.dart';
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

class _DraggableCartBubbleState extends State<DraggableCartBubble> {
  Offset? _position;
  final double _bubbleSize = 56.0;

  // Define allowed routes for the bubble to appear on.
  static const List<String> _allowedRoutes = [
    AppRoutes.customerHome,
    AppRoutes.restaurant,
    AppRoutes.restaurantDashboard,
    AppRoutes.productDetails,
    AppRoutes.favorites,
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Initialize position once when context is available
    if (_position == null) {
      final size = MediaQuery.of(context).size;
      _position = Offset(
        size.width - _bubbleSize - 16, // 16px from right edge
        size.height / 2, // Middle of screen
      );
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_position == null) return;

    final size = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;

    setState(() {
      _position = Offset(
        max(0, min(_position!.dx + details.delta.dx, size.width - _bubbleSize)),
        max(
            padding.top,
            min(_position!.dy + details.delta.dy,
                size.height - padding.bottom - _bubbleSize)),
      );
    });
  }

  bool _isCartInteracting = false;

  void _handleTap(List<ShopModel> allShops, {List<ShopModel> pendingShops = const []}) {
    if (_isCartInteracting || allShops.isEmpty) return;
    _isCartInteracting = true;

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
      // Show Bottom Sheet for multiple shops or replacement mode
      final pendingShopIds = pendingShops.map((s) => s.id).toSet();
      bool isNavigating = false;
      showModalBottomSheet(
        context: contextForNav,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24.0, vertical: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          pendingShops.isNotEmpty
                              ? 'Order Shops (${allShops.length}/3)'
                              : 'Active Shops in Cart',
                          style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        if (allShops.length < 3)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${3 - allShops.length} slot${3 - allShops.length > 1 ? 's' : ''} left',
                              style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Text(
                      pendingShops.isNotEmpty
                          ? 'Your active order includes items from up to 3 shops. Tap a shop to view its menu.'
                          : 'Tap a shop to quickly add more items and save on delivery fees.',
                      style: const TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...allShops.map((shop) {
                    final isPending = pendingShopIds.contains(shop.id);
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 24.0, vertical: 8.0),
                      leading: CircleAvatar(
                        backgroundColor: isPending
                            ? Colors.orange.withValues(alpha: 0.15)
                            : Theme.of(ctx).primaryColor.withValues(alpha: 0.1),
                        child: Icon(
                          Icons.storefront,
                          color: isPending ? Colors.orange.shade700 : Colors.green,
                        ),
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              shop.name,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (isPending)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'In Order',
                                style: TextStyle(
                                  color: Colors.orange.shade800,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'In Cart',
                                style: TextStyle(
                                  color: Colors.blue,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text(shop.category),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        if (isNavigating) return;
                        isNavigating = true;
                        Navigator.pop(ctx);
                        navigatorKey.currentState?.pushNamed(
                          AppRoutes.restaurant,
                          arguments: {'shopId': shop.id},
                        ).then((_) => isNavigating = false);
                      },
                    );
                  }),
                ],
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
        // Only show on allowed routes
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
                onPanUpdate: _onPanUpdate,
                onTap: () => _handleTap(allShops, pendingShops: pendingShops),
                child: Container(
                  width: _bubbleSize,
                  height: _bubbleSize,
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(
                        Icons.shopping_bag_outlined,
                        color: Colors.white,
                        size: 28,
                      ),
                      if (allShops.length > 1 || pendingShops.isNotEmpty)
                        Positioned(
                          right: -4,
                          top: -4,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: pendingShops.isNotEmpty
                                  ? const Color(0xFFEF4444)
                                  : Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${allShops.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                height: 1.0,
                              ),
                            ),
                          ),
                        ),
                    ],
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
