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
        size.height / 2,               // Middle of screen
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
        max(padding.top, min(_position!.dy + details.delta.dy, size.height - padding.bottom - _bubbleSize)),
      );
    });
  }

  bool _isCartInteracting = false;

  void _handleTap(List<ShopModel> shops) {
    if (_isCartInteracting || shops.isEmpty) return;
    _isCartInteracting = true;

    final contextForNav = navigatorKey.currentState?.context;
    if (contextForNav == null) {
      _isCartInteracting = false;
      return;
    }

    if (shops.length == 1) {
      // Instant navigation for 1 shop
      navigatorKey.currentState?.pushNamed(
        AppRoutes.restaurant,
        arguments: {'shopId': shops.first.id},
      ).then((_) {
        _isCartInteracting = false;
      });
    } else {
      // Show Bottom Sheet for multiple shops
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
                    padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                    child: Text(
                      'Active Shops in Cart',
                      style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24.0),
                    child: Text(
                      'Tap a shop to quickly add more items and save on delivery fees.',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...shops.map((shop) => ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(ctx).primaryColor.withValues(alpha: 0.1),
                          child: const Icon(Icons.storefront, color: Colors.green), // Assuming green is primary
                        ),
                        title: Text(shop.name, style: const TextStyle(fontWeight: FontWeight.w600)),
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
                      )),
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
            final shops = cartProvider.shops;
            
            // Only show if there are items in the cart
            if (shops.isEmpty) {
              return const SizedBox.shrink();
            }

            return Positioned(
              left: _position?.dx ?? 0,
              top: _position?.dy ?? 0,
              child: GestureDetector(
                onPanUpdate: _onPanUpdate,
                onTap: () => _handleTap(shops),
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
                      if (shops.length > 1)
                        Positioned(
                          right: -4,
                          top: -4,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${shops.length}',
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
