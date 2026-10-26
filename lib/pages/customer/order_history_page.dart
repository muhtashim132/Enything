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
import '../../providers/quote_request_provider.dart';
import '../../models/quote_request_model.dart';
import '../settings/faq_support_page.dart';

class OrderHistoryPage extends StatefulWidget {
  const OrderHistoryPage({super.key});

  @override
  State<OrderHistoryPage> createState() => _OrderHistoryPageState();
}

class _OrderHistoryPageState extends State<OrderHistoryPage>
    with WidgetsBindingObserver {
  SupabaseClient get _supabase => Supabase.instance.client;
  List<OrderModel> _orders = [];
  bool _isLoading = true;
  final Set<String> _cancellingIds =
      {}; // track which orders are being cancelled
  final Set<String> _reorderingIds = {}; // track reorder in progress

  // Pagination fields
  final ScrollController _scrollController = ScrollController();
  bool _isLoadingMore = false;
  bool _hasMoreOrders = true;
  static const int _pageSize = 15;

  RealtimeChannel? _customerOrdersChannel;

  // ── Reorder: fetch items from a past order, add valid ones to cart ──────
  Future<void> _reorder(OrderModel order) async {
    if (_reorderingIds.contains(order.id)) return;
    setState(() => _reorderingIds.add(order.id));
    try {
      final itemsData = await _supabase
          .from('order_items')
          .select('product_id, quantity, variant_name')
          .eq('order_id', order.id);

      if (!mounted) return;

      // Fetch current product availability for each item
      final productIds =
          (itemsData as List).map((i) => i['product_id'] as String).toList();

      if (productIds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No items found in this order.')),
        );
        return;
      }

      final productsData = await _supabase
          .from('products')
          .select('*, shops(*)')
          .eq('is_deleted', false)
          .inFilter('id', productIds)
          .eq('is_available', true);

      if (!mounted) return;
      final cart = context.read<CartProvider>();
      final products =
          (productsData as List).map((p) => ProductModel.fromMap(p)).toList();
      // Build shopId → ShopModel lookup from the joined shop data
      final Map<String, ShopModel> shopMap = {};
      for (final p in productsData) {
        if (p['shops'] != null) {
          final shop = ShopModel.fromMap(p['shops']);
          if (shop.isActive) {
            shopMap[shop.id] = shop;
          }
        }
      }

      int added = 0;
      int skipped = 0;
      String? firstError;

      for (final item in itemsData) {
        final productId = item['product_id'] as String;
        final quantity = item['quantity'] as int? ?? 1;
        final variantName = item['variant_name'] as String?;
        final product = products.cast<ProductModel?>().firstWhere(
              (p) => p?.id == productId,
              orElse: () => null,
            );
        if (product != null) {
          final shop = shopMap[product.shopId];
          if (shop != null) {
            ProductVariant? selectedVariant;
            if (variantName != null && product.variants.isNotEmpty) {
              try {
                selectedVariant =
                    product.variants.firstWhere((v) => v.name == variantName);
              } catch (_) {}
            }

            // Phase 18 Fix: Safely capture business logic rejections
            final err = cart.addItem(product, shop,
                quantity: quantity, selectedVariant: selectedVariant);

            if (err == null) {
              added++;
            } else {
              skipped++;
              firstError ??= err; // Capture the exact reason
            }
          } else {
            skipped++; // shop data unavailable
          }
        } else {
          skipped++;
        }
      }

      if (!mounted) return;

      final msg = skipped > 0
          ? '$added added, $skipped skipped${firstError != null ? ' ($firstError)' : ''}'
          : '$added items added to cart!';

      ScaffoldMessenger.of(context).clearSnackBars();
      final controller = ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            msg,
            style: GoogleFonts.outfit(
                color: Colors.white, fontWeight: FontWeight.w600),
          ),
          backgroundColor: const Color(0xFF10B981), // Modern green
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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

      // Additive fix: Force close after duration to bypass sticky SnackBar bug
      Future.delayed(const Duration(seconds: 3), () {
        try {
          controller.close();
        } catch (_) {}
      });
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
    WidgetsBinding.instance.addObserver(this);
    _fetchOrders();
    _scrollController.addListener(_onScroll);
    _setupRealtimeOrders();
    // Subscribe & load customer catering quotes
    final quoteProv = context.read<QuoteRequestProvider>();
    quoteProv.loadCustomerQuotes();
    quoteProv.subscribeToCustomerQuotes();
  }

  void _setupRealtimeOrders() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      final userId = auth.currentUserId;
      if (userId == null) return;

      _customerOrdersChannel = _supabase
          .channel('customer-orders-$userId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'orders',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'customer_id',
              value: userId,
            ),
            callback: (payload) {
              if (mounted) {
                _fetchOrders();
              }
            },
          )
          .subscribe();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (mounted) {
        _fetchOrders();
      }
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreOrders();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_customerOrdersChannel != null) {
      _supabase.removeChannel(_customerOrdersChannel!);
    }
    _scrollController.dispose();
    super.dispose();
  }

  void _handleBack() {
    final isFirst = ModalRoute.of(context)?.isFirst ?? false;
    if (isFirst) {
      Navigator.pushNamedAndRemoveUntil(
          context, AppRoutes.customerHome, (route) => false);
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _fetchOrders() async {
    final auth = context.read<AuthProvider>();
    try {
      context.read<QuoteRequestProvider>().loadCustomerQuotes();
    } catch (_) {}
    try {
      final response = await _supabase
          .from('orders')
          .select()
          .eq('customer_id', auth.currentUserId ?? '')
          .order('created_at', ascending: false)
          .range(0, _pageSize - 1);

      if (!mounted) return;
      final fetchedOrders =
          (response as List).map((o) => OrderModel.fromMap(o)).toList();

      setState(() {
        _orders = fetchedOrders;
        _hasMoreOrders = fetchedOrders.length == _pageSize;
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

  Future<void> _loadMoreOrders() async {
    if (_isLoadingMore || !_hasMoreOrders) return;

    setState(() => _isLoadingMore = true);
    final auth = context.read<AuthProvider>();

    try {
      final response = await _supabase
          .from('orders')
          .select()
          .eq('customer_id', auth.currentUserId ?? '')
          .order('created_at', ascending: false)
          .range(_orders.length, _orders.length + _pageSize - 1);

      if (!mounted) return;
      final fetchedOrders =
          (response as List).map((o) => OrderModel.fromMap(o)).toList();

      setState(() {
        _orders.addAll(fetchedOrders);
        _hasMoreOrders = fetchedOrders.length == _pageSize;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'delivered':
        return AppColors.success;
      case 'cancelled':
      case 'seller_rejected':
      case 'partner_rejected':
      case 'rider_rejected':
      case 'verification_failed':
      case 'timeout':
      case 'payment_failed':
      case 'shop_dispute_cancel':
        return AppColors.danger;
      case 'bulk_pending':
        return const Color(0xFFF59E0B);
      case 'bulk_confirmed':
      case 'bulk_preparing':
        return const Color(0xFF2563EB);
      case 'bulk_ready':
        return const Color(0xFF8B5CF6);
      case 'bulk_dispatched':
      case 'out_for_delivery':
        return const Color(0xFF059669);
      default:
        return AppColors.primary;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'delivered':
        return Icons.check_circle_outline;
      case 'cancelled':
      case 'seller_rejected':
      case 'partner_rejected':
      case 'rider_rejected':
      case 'verification_failed':
      case 'timeout':
      case 'payment_failed':
      case 'shop_dispute_cancel':
        return Icons.cancel_outlined;
      case 'bulk_pending':
        return Icons.event_available_rounded;
      case 'bulk_confirmed':
      case 'bulk_preparing':
        return Icons.restaurant_rounded;
      case 'bulk_ready':
        return Icons.inventory_2_rounded;
      case 'bulk_dispatched':
        return Icons.directions_car_filled_rounded;
      case 'out_for_delivery':
        return Icons.delivery_dining;
      case 'pending':
        return Icons.access_time;
      default:
        return Icons.receipt_long_outlined;
    }
  }

  Future<void> _cancelOrder(OrderModel order, bool isDark) async {
    final isGroup = order.cartGroupId != null &&
        (order.status == 'awaiting_acceptance' ||
            order.status == 'awaiting_payment');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(isGroup ? 'Cancel Entire Cart?' : 'Cancel Order?',
            style: GoogleFonts.outfit(
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : AppColors.textPrimary)),
        content: Text(
            isGroup
                ? 'This order is part of a combined cart. Cancelling it will cancel ALL items in the cart. Are you sure?'
                : 'Are you sure you want to cancel this order?',
            style: GoogleFonts.outfit(
                fontSize: 14,
                color: isDark ? Colors.white70 : AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Keep Order',
                style: GoogleFonts.outfit(
                    color: isDark ? Colors.white70 : AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Yes, Cancel',
                style: GoogleFonts.outfit(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _cancellingIds.add(order.id));
    List<OrderModel> ordersToCancel = [order];
    try {
      if (isGroup && order.cartGroupId != null) {
        // Phase 19 Fix: Unpaginated fetch to guarantee ALL sellers in the group
        // receive the cancellation push notification, avoiding Ghost Kitchen Orders
        final groupResponse = await _supabase
            .from('orders')
            .select()
            .eq('cart_group_id', order.cartGroupId as Object);
        ordersToCancel =
            (groupResponse as List).map((o) => OrderModel.fromMap(o)).toList();

        if (mounted) {
          setState(() {
            for (final o in ordersToCancel) {
              _cancellingIds.add(o.id);
            }
          });
        }
      }

      // Secure atomic cancellation via RPC. The RPC automatically handles
      // cancelling all orders in the cart group if this order belongs to one.
      await _supabase.rpc('cancel_order', params: {
        'p_order_id': order.id,
        'p_reason': 'customer',
      });

      // BUG-4 FIX: Notify seller and rider that the customer cancelled
      if (mounted) {
        final notifProv = context.read<NotificationProvider>();

        for (final o in ordersToCancel) {
          // Notify seller
          if (o.shopId != null) {
            _supabase
                .from('shops')
                .select('seller_id')
                .eq('id', o.shopId!)
                .maybeSingle()
                .then((shopData) {
              if (shopData != null && shopData['seller_id'] != null) {
                notifProv.sendBackgroundPush(
                  targetUserId: shopData['seller_id'] as String,
                  title: '❌ Order Cancelled by Customer',
                  body:
                      'The customer cancelled their order. No further action needed.',
                  data: {'order_id': o.id, 'role': 'seller'},
                );
              }
            });
          }

          // Notify assigned rider (if any)
          if (o.deliveryPartnerId != null) {
            notifProv.sendBackgroundPush(
              targetUserId: o.deliveryPartnerId!,
              title: '❌ Order Cancelled by Customer',
              body:
                  'The customer cancelled their order. You are free for new deliveries.',
              data: {'order_id': o.id, 'role': 'rider'},
            );
          }
        }
      }

      if (mounted) {
        setState(() {
          for (final o in ordersToCancel) {
            final idx = _orders.indexWhere((existing) => existing.id == o.id);
            if (idx != -1) _orders[idx].status = 'cancelled';
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Order cancelled.'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          for (final o in ordersToCancel) {
            _cancellingIds.remove(o.id);
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDarkMode;
    final isFirst = ModalRoute.of(context)?.isFirst ?? false;
    final quoteProv = context.watch<QuoteRequestProvider>();
    final quotes = quoteProv.customerQuotes;

    return PopScope(
        canPop: !isFirst,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) {
            Navigator.pushNamedAndRemoveUntil(
                context, AppRoutes.customerHome, (route) => false);
          }
        },
        child: Scaffold(
          backgroundColor:
              isDark ? const Color(0xFF0E0E1A) : const Color(0xFFF4F6FB),
          appBar: AppBar(
            backgroundColor: isDark ? const Color(0xFF12121A) : Colors.white,
            elevation: 0,
            surfaceTintColor: Colors.transparent,
            leading: Navigator.canPop(context)
                ? GestureDetector(
                    onTap: _handleBack,
                    child: Container(
                      margin: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.07)
                            : const Color(0xFFF0F0F8),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.arrow_back_ios_new_rounded,
                          size: 16,
                          color:
                              isDark ? Colors.white70 : AppColors.textPrimary),
                    ),
                  )
                : null,
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
                : (_orders.isEmpty && quotes.isEmpty)
                    ? _buildEmptyState(isDark)
                    : RefreshIndicator(
                        onRefresh: () async {
                          await _fetchOrders();
                          await quoteProv.loadCustomerQuotes();
                        },
                        color: AppColors.primary,
                        backgroundColor:
                            isDark ? AppColors.darkSurface : Colors.white,
                        child: ListView(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                          children: [
                            if (quotes.isNotEmpty) ...[
                              _buildQuotesSectionHeader(isDark, quotes.length),
                              ...quotes.map((q) => _buildQuoteCard(q, isDark)),
                              const SizedBox(height: 14),
                            ],
                            if (_orders.isNotEmpty) ...[
                              if (quotes.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(0, 4, 0, 10),
                                  child: Text(
                                    'FOOD & STORE ORDERS',
                                    style: GoogleFonts.outfit(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.0,
                                      color: isDark ? Colors.white38 : AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ..._orders.map((o) => _buildOrderCard(o, isDark)),
                              if (_hasMoreOrders)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 20),
                                  child: Center(
                                    child: CircularProgressIndicator(color: AppColors.primary),
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
          ),
        ));
  }

  Widget _buildOrderCard(OrderModel order, bool isDark) {
    final statusColor = _getStatusColor(order.status);

    return GestureDetector(
      onTap: () {
        if (order.orderType == 'bulk' ||
            order.orderType == 'manual_quote' ||
            order.status.startsWith('bulk_')) {
          Navigator.pushNamed(
            context,
            AppRoutes.bulkOrderTracking,
            arguments: {'order_id': order.id},
          );
        } else {
          Navigator.pushNamed(
            context,
            AppRoutes.trackOrder,
            arguments: {'orderId': order.id},
          );
        }
      },
      child: AnimatedContainer(
        duration: PremiumAnimations.normal,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: PremiumRadius.largeBorder,
          border: isDark
              ? Border.all(color: Colors.white.withValues(alpha: 0.07))
              : null,
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
                          color:
                              isDark ? Colors.white54 : AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.grey.shade100,
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
                Expanded(
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // Reorder button — for delivered or cancelled orders
                      if (order.status == 'delivered' ||
                          order.status == 'cancelled' ||
                          order.status == 'seller_rejected')
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
                                    color: AppColors.primary
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                        color: AppColors.primary
                                            .withValues(alpha: 0.2)),
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
                      // Cancel chip — only for pending orders
                      // BUG-5 FIX: show cancel for awaiting_acceptance too (new order flow)
                      if (order.status == 'awaiting_acceptance' ||
                          order.status == 'pending')
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
                                    color:
                                        AppColors.danger.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                        color: AppColors.danger
                                            .withValues(alpha: 0.2)),
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
                      // Report Issue Button (always visible for past or problematic orders)
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => FaqSupportPage(
                                initialTabIndex: 0,
                                openTicketSheet: true,
                                prefillOrderId: order.id,
                              ),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.info.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: AppColors.info.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.report_problem_outlined,
                                  size: 14, color: AppColors.info),
                              const SizedBox(width: 4),
                              Text(
                                'Report Issue',
                                style: GoogleFonts.outfit(
                                  color: AppColors.info,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
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
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuotesSectionHeader(bool isDark, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.2 : 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.celebration_rounded, color: Color(0xFF10B981), size: 14),
          ),
          const SizedBox(width: 8),
          Text(
            'EVENT & CATERING QUOTES',
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
              color: isDark ? Colors.white70 : AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: GoogleFonts.outfit(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuoteCard(QuoteRequestModel quote, bool isDark) {
    final isQuoted = quote.quoteStatus == 'quoted';
    final isPending = quote.quoteStatus == 'pending_review';
    final isAccepted = quote.quoteStatus == 'customer_accepted';
    final isPaid = quote.quoteStatus == 'paid';
    final isDeclined = quote.quoteStatus == 'declined' || quote.quoteStatus == 'customer_rejected';

    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    if (isQuoted) {
      statusColor = const Color(0xFF10B981);
      statusLabel = 'Quote Ready';
      statusIcon = Icons.check_circle_outline_rounded;
    } else if (isPending) {
      statusColor = const Color(0xFF6366F1);
      statusLabel = 'Under Review';
      statusIcon = Icons.hourglass_top_rounded;
    } else if (isAccepted) {
      statusColor = const Color(0xFFF59E0B);
      statusLabel = 'Payment Pending';
      statusIcon = Icons.payment_rounded;
    } else if (isPaid) {
      statusColor = const Color(0xFF10B981);
      statusLabel = 'Paid & Confirmed';
      statusIcon = Icons.verified_rounded;
    } else if (isDeclined) {
      statusColor = Colors.red;
      statusLabel = 'Declined';
      statusIcon = Icons.cancel_outlined;
    } else {
      statusColor = Colors.grey;
      statusLabel = quote.quoteStatus.replaceAll('_', ' ').toUpperCase();
      statusIcon = Icons.info_outline;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isQuoted
              ? const Color(0xFF10B981).withValues(alpha: 0.6)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.08)),
          width: isQuoted ? 1.5 : 1.0,
        ),
        boxShadow: isQuoted
            ? [
                BoxShadow(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            if (isPaid && quote.resultingOrderId != null && quote.resultingOrderId!.isNotEmpty) {
              Navigator.pushNamed(
                context,
                AppRoutes.bulkOrderTracking,
                arguments: {'order_id': quote.resultingOrderId},
              );
            } else {
              Navigator.pushNamed(
                context,
                AppRoutes.quoteResponse,
                arguments: {'quote_id': quote.id},
              );
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        quote.eventName.isNotEmpty ? quote.eventName : 'Catering & Event Quote',
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(statusIcon, size: 12, color: statusColor),
                          const SizedBox(width: 4),
                          Text(
                            statusLabel,
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.people_outline,
                        size: 14,
                        color: isDark ? Colors.white38 : AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      '${quote.estimatedGuestCount} guests',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(Icons.calendar_today_outlined,
                        size: 13,
                        color: isDark ? Colors.white38 : AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      '${quote.eventDate.day}/${quote.eventDate.month}/${quote.eventDate.year}',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (quote.quotedAmount != null && quote.quotedAmount! > 0)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Quoted Price',
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              color: isDark ? Colors.white38 : AppColors.textSecondary,
                            ),
                          ),
                          Text(
                            '₹${quote.quotedAmount!.toStringAsFixed(0)}',
                            style: GoogleFonts.outfit(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF10B981),
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        'Awaiting Admin Pricing',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: isDark ? Colors.white38 : AppColors.textSecondary,
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        gradient: isQuoted
                            ? const LinearGradient(
                                colors: [Color(0xFF10B981), Color(0xFF059669)])
                            : (isPaid
                                ? const LinearGradient(
                                    colors: [Color(0xFF6366F1), Color(0xFF4F46E5)])
                                : null),
                        color: (isQuoted || isPaid)
                            ? null
                            : (isDark ? Colors.white12 : Colors.grey.shade100),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            isQuoted
                                ? 'Review Quote'
                                : (isPaid ? 'Track Order 🚚' : 'View Details'),
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: (isQuoted || isPaid)
                                  ? Colors.white
                                  : (isDark ? Colors.white70 : AppColors.textPrimary),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 14,
                            color: (isQuoted || isPaid)
                                ? Colors.white
                                : (isDark ? Colors.white70 : AppColors.textPrimary),
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
                  AppColors.primaryLight
                      .withValues(alpha: isDark ? 0.12 : 0.06),
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
            onTap: () =>
                Navigator.pushReplacementNamed(context, AppRoutes.customerHome),
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
                  const Icon(Icons.shopping_bag_outlined,
                      color: Colors.white, size: 18),
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
