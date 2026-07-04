import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/order_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/cart_provider.dart';
import '../../providers/theme_provider.dart';
import '../../models/product_model.dart';
import '../../models/shop_model.dart';
import '../../theme/app_colors.dart';
import '../../theme/premium_effects.dart';
import '../../config/routes.dart';
import '../../utils/responsive_layout.dart';

class OrderHistoryPage extends StatefulWidget {
  const OrderHistoryPage({super.key});

  @override
  State<OrderHistoryPage> createState() => _OrderHistoryPageState();
}

class _OrderHistoryPageState extends State<OrderHistoryPage> {
  final _supabase = Supabase.instance.client;
  List<OrderModel> _orders = [];
  bool _isLoading = true;
  final Set<String> _cancellingIds = {}; // track which orders are being cancelled
  final Set<String> _reorderingIds = {};  // track reorder in progress

  // ── Reorder: fetch items from a past order, add valid ones to cart ──────
  Future<void> _reorder(OrderModel order) async {
    if (_reorderingIds.contains(order.id)) return;
    setState(() => _reorderingIds.add(order.id));
    try {
      final itemsData = await _supabase
          .from('order_items')
          .select('product_id, quantity')
          .eq('order_id', order.id);

      if (!mounted) return;

      // Fetch current product availability for each item
      final productIds = (itemsData as List)
          .map((i) => i['product_id'] as String)
          .toList();

      if (productIds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No items found in this order.')),
        );
        return;
      }

      final productsData = await _supabase
          .from('products')
          .select('*, shops(*)')
          .inFilter('id', productIds)
          .eq('is_available', true);

      if (!mounted) return;
      final cart = context.read<CartProvider>();
      final products = (productsData as List)
          .map((p) => ProductModel.fromMap(p))
          .toList();
      // Build shopId → ShopModel lookup from the joined shop data
      final Map<String, ShopModel> shopMap = {};
      for (final p in productsData as List) {
        if (p['shops'] != null) {
          final shop = ShopModel.fromMap(p['shops']);
          shopMap[shop.id] = shop;
        }
      }

      int added = 0;
      int skipped = 0;

      for (final item in itemsData) {
        final productId = item['product_id'] as String;
        final quantity = item['quantity'] as int? ?? 1;
        final product = products.cast<ProductModel?>().firstWhere(
          (p) => p?.id == productId,
          orElse: () => null,
        );
        if (product != null) {
          final shop = shopMap[product.shopId];
          if (shop != null) {
            for (int i = 0; i < quantity; i++) {
              cart.addItem(product, shop);
            }
            added++;
          } else {
            skipped++; // shop data unavailable
          }
        } else {
          skipped++;
        }
      }

      if (!mounted) return;

      final msg = skipped > 0
          ? '$added items added to cart ($skipped no longer available)'
          : '$added items added to cart!';

      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            msg,
            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          backgroundColor: const Color(0xFF10B981), // Modern green
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 10,
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'VIEW CART',
            textColor: Colors.white,
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              Navigator.pushNamed(context, AppRoutes.cart);
            },
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to reorder: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _reorderingIds.remove(order.id));
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchOrders();
  }

  Future<void> _fetchOrders() async {
    final auth = context.read<AuthProvider>();
    try {
      final response = await _supabase
          .from('orders')
          .select()
          .eq('customer_id', auth.currentUserId ?? '')
          .order('created_at', ascending: false);

      setState(() {
        _orders =
            (response as List).map((o) => OrderModel.fromMap(o)).toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching customer orders: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load orders: $e')),
        );
      }
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'delivered': return AppColors.success;
      case 'cancelled': case 'seller_rejected': return AppColors.danger;
      case 'out_for_delivery': return AppColors.info;
      default: return AppColors.primary;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'delivered': return Icons.check_circle_outline;
      case 'cancelled': case 'seller_rejected': return Icons.cancel_outlined;
      case 'out_for_delivery': return Icons.delivery_dining;
      case 'pending': return Icons.access_time;
      default: return Icons.receipt_long_outlined;
    }
  }

  Future<void> _cancelOrder(OrderModel order, bool isDark) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Cancel Order?',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w800, color: isDark ? Colors.white : AppColors.textPrimary)),
        content: Text(
            'Are you sure you want to cancel this order?',
            style: GoogleFonts.outfit(fontSize: 14, color: isDark ? Colors.white70 : AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Keep Order', style: GoogleFonts.outfit(color: isDark ? Colors.white70 : AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Yes, Cancel',
                style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _cancellingIds.add(order.id));
    try {
      await _supabase
          .from('orders')
          .update({'status': 'cancelled', 'cancelled_reason': 'customer'})
          .eq('id', order.id);

      // BUG-4 FIX: Notify seller and rider that the customer cancelled
      if (mounted) {
        final notifProv = context.read<NotificationProvider>();

        // Notify seller (lookup seller_id via shop_id)
        if (order.shopId != null) {
          _supabase
              .from('shops')
              .select('seller_id')
              .eq('id', order.shopId!)
              .maybeSingle()
              .then((shopData) {
            if (shopData != null && shopData['seller_id'] != null) {
              notifProv.sendBackgroundPush(
                targetUserId: shopData['seller_id'] as String,
                title: '❌ Order Cancelled by Customer',
                body: 'The customer cancelled their order. No further action needed.',
                data: {'order_id': order.id, 'role': 'seller'},
              );
            }
          });
        }

        // Notify assigned rider (if any)
        if (order.deliveryPartnerId != null) {
          notifProv.sendBackgroundPush(
            targetUserId: order.deliveryPartnerId!,
            title: '❌ Order Cancelled by Customer',
            body: 'The customer cancelled their order. You are free for new deliveries.',
            data: {'order_id': order.id, 'role': 'rider'},
          );
        }
      }

      if (mounted) {
        setState(() {
          final idx = _orders.indexWhere((o) => o.id == order.id);
          if (idx != -1) _orders[idx].status = 'cancelled';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Order cancelled.'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to cancel. Please try again.'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _cancellingIds.remove(order.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDarkMode;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0E0E1A) : const Color(0xFFF4F6FB),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF12121A) : Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: Navigator.canPop(context) ? GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.07) : const Color(0xFFF0F0F8),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.arrow_back_ios_new_rounded,
                size: 16, color: isDark ? Colors.white70 : AppColors.textPrimary),
          ),
        ) : null,
        title: Text(
          'My Orders',
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ),
      body: MaxWidthContainer(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _orders.isEmpty
              ? _buildEmptyState(isDark)
              : RefreshIndicator(
                  onRefresh: _fetchOrders,
                  color: AppColors.primary,
                  backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                    itemCount: _orders.length,
                    itemBuilder: (context, index) {
                      return _buildOrderCard(_orders[index], isDark);
                    },
                  ),
                ),
      ),
    );
  }

  Widget _buildOrderCard(OrderModel order, bool isDark) {
    final statusColor = _getStatusColor(order.status);
    
    return GestureDetector(
      onTap: () => Navigator.pushNamed(
        context,
        AppRoutes.trackOrder,
        arguments: {'orderId': order.id},
      ),
      child: AnimatedContainer(
        duration: PremiumAnimations.normal,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: PremiumRadius.largeBorder,
          border: isDark ? Border.all(color: Colors.white.withValues(alpha: 0.07)) : null,
          boxShadow: PremiumShadows.cardLight,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_getStatusIcon(order.status),
                      color: statusColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Order #${order.id.substring(0, 8).toUpperCase()}',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: isDark ? Colors.white : AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        DateFormat('dd MMM yyyy, hh:mm a')
                            .format(order.createdAt),
                        style: GoogleFonts.outfit(
                          color: isDark ? Colors.white54 : AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    order.statusDisplay,
                    style: GoogleFonts.outfit(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Divider(
                height: 1, 
                color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade100,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '₹${order.grandTotal.toStringAsFixed(0)}',
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
                ),
                Row(
                  children: [
                    // Reorder button — for delivered or cancelled orders
                    if (order.status == 'delivered' ||
                        order.status == 'cancelled' ||
                        order.status == 'seller_rejected') ...[
                      _reorderingIds.contains(order.id)
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.primary),
                            )
                          : GestureDetector(
                              onTap: () => _reorder(order),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: AppColors.primary.withValues(alpha: 0.2)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.replay_rounded,
                                        size: 14, color: AppColors.primary),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Reorder',
                                      style: GoogleFonts.outfit(
                                        color: AppColors.primary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                      const SizedBox(width: 8),
                    ],
                    // Cancel chip — only for pending orders
                    // BUG-5 FIX: show cancel for awaiting_acceptance too (new order flow)
                    if (order.status == 'awaiting_acceptance' || order.status == 'pending') ...[
                      _cancellingIds.contains(order.id)
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.danger),
                            )
                          : GestureDetector(
                              onTap: () => _cancelOrder(order, isDark),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppColors.danger.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: AppColors.danger.withValues(alpha: 0.2)),
                                ),
                                child: Text(
                                  'Cancel',
                                  style: GoogleFonts.outfit(
                                    color: AppColors.danger,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      'Details',
                      style: GoogleFonts.outfit(
                        color: AppColors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_forward_ios_rounded,
                        size: 12, color: AppColors.primary),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: isDark ? 0.2 : 0.1),
                  AppColors.primaryLight.withValues(alpha: isDark ? 0.12 : 0.06),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.receipt_long_outlined,
              size: 56, 
              color: isDark ? AppColors.primaryLight : AppColors.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No orders yet',
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start ordering from nearby shops!',
            style: GoogleFonts.outfit(
              color: isDark ? Colors.white54 : AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 28),
          GestureDetector(
            onTap: () => Navigator.pushReplacementNamed(context, AppRoutes.customerHome),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              decoration: BoxDecoration(
                gradient: AppColors.ctaGradient,
                borderRadius: PremiumRadius.mediumBorder,
                boxShadow: PremiumShadows.floatingButtonLight,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.shopping_bag_outlined, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Order Now',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
