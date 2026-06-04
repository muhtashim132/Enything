import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notification_provider.dart';
import '../../models/order_model.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common/rating_bottom_sheet.dart';
import '../../widgets/common/notification_bell.dart';
import '../../pages/seller/seller_order_map_page.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../utils/responsive_layout.dart';
class SellerOrdersPage extends StatefulWidget {
  const SellerOrdersPage({super.key});

  @override
  State<SellerOrdersPage> createState() => _SellerOrdersPageState();
}

class _SellerOrdersPageState extends State<SellerOrdersPage>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  List<OrderModel> _orders = [];
  bool _isLoading = true;
  late TabController _tabController;
  // shopId → shop name for map page label
  final Map<String, String> _shopNames = {};
  // BUG-15 FIX: preserve expanded state
  final Set<String> _expandedOrderIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadOrders();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadOrders() async {
    try {
      if (!mounted) return;
      final auth = context.read<AuthProvider>();

      final shopsResp = await _supabase
          .from('shops')
          .select('id, name')
          .eq('seller_id', auth.currentUserId ?? '');

      if ((shopsResp as List).isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // Collect ALL shop IDs and names for this seller
      final shopIds = (shopsResp as List).map((s) => s['id'] as String).toList();
      final Map<String, String> shopNames = {
        for (final s in shopsResp as List)
          s['id'] as String: s['name'] as String? ?? 'My Shop'
      };

      final response = await _supabase
          .from('orders')
          .select('*, order_items(*)')
          .inFilter('shop_id', shopIds)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _shopNames
            ..clear()
            ..addAll(shopNames);
          _orders = (response as List).map((o) {
            final model = OrderModel.fromMap(o);
            final rawItems = o['order_items'] as List? ?? [];
            model.items = rawItems.map((i) => OrderItem.fromMap(i)).toList();
            return model;
          }).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Seller presses Accept:
  ///   - If rider already accepted (partner_accepted = true)
  ///       → set seller_accepted + advance to awaiting_payment + push customer + push rider
  ///   - If rider has NOT yet accepted
  ///       → set seller_accepted + broadcast to riders + notify customer shop accepted
  Future<void> _sellerAccept(OrderModel order) async {
    try {
      final riderAlreadyAccepted = order.partnerAccepted;
      final paymentDeadline = riderAlreadyAccepted
          ? DateTime.now().toUtc().add(const Duration(minutes: 10)).toIso8601String()
          : null;

      // Update DB
      await _supabase.from('orders').update({
        'seller_accepted': true,
        if (riderAlreadyAccepted) 'status': 'awaiting_payment',
        if (paymentDeadline != null) 'payment_deadline': paymentDeadline,
      }).eq('id', order.id);

      if (mounted) {
        final notifProv = context.read<NotificationProvider>();

        if (riderAlreadyAccepted) {
          // ── Both now accepted → push customer to pay NOW ──────────────
          _showSnack('✅ Both you & rider accepted. Waiting for customer to pay.', isError: false);

          notifProv.sendBackgroundPush(
            targetUserId: order.customerId,
            title: '✅ Shop & Rider Ready! Pay Now 💳',
            body: 'Both the shop and rider accepted your order. Complete payment within 10 minutes.',
            data: {'order_id': order.id, 'action': 'pay'},
          );

          // Notify rider: seller is in, customer is paying
          if (order.deliveryPartnerId != null) {
            notifProv.sendBackgroundPush(
              targetUserId: order.deliveryPartnerId!,
              title: '⌛ Waiting for Customer Payment',
              body: 'The shop accepted. Both of you are confirmed — customer is completing payment now.',
            );
          }
        } else {
          // ── Seller accepted first → broadcast riders + notify customer ─
          _showSnack('✅ Your acceptance saved. Waiting for a delivery partner.', isError: false);

          // Broadcast ALL riders that this order is now available
          notifProv.sendBroadcastToAudience(
            audience: 'Riders',
            title: '🛵 Order Available!',
            body: 'A shop accepted an order ₹${order.grandTotal.toStringAsFixed(0)}. Be the first rider to accept it!',
            data: {'order_id': order.id, 'role': 'rider'},
          );

          // Notify customer that shop accepted, waiting for rider
          notifProv.sendBackgroundPush(
            targetUserId: order.customerId,
            title: '🏪 Shop Accepted!',
            body: 'The shop accepted your order. Now waiting for a rider to also confirm.',
          );
        }
      }
      _loadOrders();
    } catch (e) {
      debugPrint('Seller accept error: $e');
    }
  }

  Future<void> _sellerReject(OrderModel order) async {
    final messageController = TextEditingController();
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A2E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('Decline Order',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  )),
              const SizedBox(height: 4),
              Text('Send an optional message to the customer explaining why.',
                  style: GoogleFonts.outfit(color: Colors.white54, fontSize: 13)),
              const SizedBox(height: 20),
              TextField(
                controller: messageController,
                maxLines: 3,
                style: GoogleFonts.outfit(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'e.g. "This item is currently out of stock"',
                  hintStyle: GoogleFonts.outfit(color: Colors.white30, fontSize: 13),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.07),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.all(14),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white24),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text('Go Back',
                          style: GoogleFonts.outfit(color: Colors.white70, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.danger,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text('Send & Decline',
                          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final msg = messageController.text.trim();
      await _supabase.from('orders').update({
        'status': order.prescriptionUrls.isNotEmpty ? 'verification_failed' : 'seller_rejected',
        'seller_accepted': false,
        if (msg.isNotEmpty) 'rejection_message': msg,
      }).eq('id', order.id);

      if (mounted) {
        context.read<NotificationProvider>().sendBackgroundPush(
          targetUserId: order.customerId,
          title: '🏪 Shop Declined',
          body: msg.isNotEmpty
              ? '"$msg" — You can retry or choose a different shop.'
              : 'The shop could not accept your order. You can retry or choose a different shop.',
        );
      }

      _loadOrders();
      _showSnack('Order declined.', isError: true);
    } catch (e) {
      debugPrint('Reject error: $e');
    }
  }

  void _showPrescriptionImages(List<String> urls) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          width: double.infinity,
          height: 500,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Prescription Images', style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(context)),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: urls.length,
                  itemBuilder: (context, index) {
                    return Container(
                      width: 300,
                      margin: const EdgeInsets.only(right: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
                        image: DecorationImage(image: NetworkImage(urls[index]), fit: BoxFit.contain),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _updateOrderStatus(OrderModel order, String status) async {
    try {
      final updateData = <String, dynamic>{'status': status};
      if (status == 'ready_for_pickup') {
        final readyTime = DateTime.now();
        updateData['order_ready_time'] = readyTime.toIso8601String();
        
        if (order.arrivedAtShopTime != null) {
          final waitMins = readyTime.difference(order.arrivedAtShopTime!).inMinutes;
          final prepLimit = order.shopPrepTimeSnapshot;
          if (waitMins > prepLimit) {
            updateData['wait_time_penalty'] = (waitMins - prepLimit) * 2.0;
          }
        }
      }

      await _supabase.from('orders').update(updateData).eq('id', order.id);
      
      if (mounted) {
        final notifProv = context.read<NotificationProvider>();
        if (status == 'preparing') {
          notifProv.sendBackgroundPush(
            targetUserId: order.customerId,
            title: '👨‍🍳 Order Being Prepared',
            body: 'The shop is now preparing your order.',
          );
          if (order.deliveryPartnerId != null) {
            notifProv.sendBackgroundPush(
              targetUserId: order.deliveryPartnerId!,
              title: '👨‍🍳 Shop Preparing',
              body: 'The shop has started preparing the order. Head over!',
            );
          }
        } else if (status == 'ready_for_pickup') {
          notifProv.sendBackgroundPush(
            targetUserId: order.customerId,
            title: '📦 Ready for Pickup',
            body: 'Your order is packed and waiting for the rider.',
          );
          if (order.deliveryPartnerId != null) {
            notifProv.sendBackgroundPush(
              targetUserId: order.deliveryPartnerId!,
              title: '📦 Ready for Pickup!',
              body: 'The order is ready. Go pick it up now!',
            );
          }
        }
      }
      
      _loadOrders();
      _showSnack('Status → ${status.replaceAll('_', ' ')}', isError: false);
    } catch (e) {
      debugPrint('Update error: $e');
    }
  }

  void _showSnack(String msg, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.outfit()),
      backgroundColor: isError ? AppColors.danger : AppColors.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  void _showSellerRatingFlow(OrderModel order) {
    if (!mounted || order.deliveryPartnerId == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => RatingBottomSheet(
        title: 'Rate the Rider 🚴',
        subtitle: 'How punctual was the delivery partner?',
        onSubmit: (rating, review) => _submitSellerRating(
          orderId: order.id,
          rateeId: order.deliveryPartnerId!,
          rating: rating,
          review: review,
        ),
      ),
    );
  }

  Future<void> _submitSellerRating({
    required String orderId,
    required String rateeId,
    required int rating,
    required String review,
  }) async {
    try {
      final auth = context.read<AuthProvider>();
      await _supabase.from('ratings').insert({
        'order_id': orderId,
        'rater_id': auth.currentUserId,
        'ratee_id': rateeId,
        'rater_role': 'seller',
        'ratee_role': 'delivery',
        'rating': rating,
        'review': review.isEmpty ? null : review,
      });
      await _supabase.from('orders')
          .update({'has_seller_rated': true}).eq('id', orderId);
      _loadOrders();
      _showSnack('⭐ Rider rated successfully!', isError: false);
    } catch (e) {
      debugPrint('Seller rating error: $e');
    }
  }

  // ── Tab filters ────────────────────────────────────────────────────────────
  List<OrderModel> _pendingOrders() => _orders
      .where((o) =>
          (o.status == 'awaiting_acceptance' || o.status == 'pending') &&
          !o.sellerAccepted)
      .toList();

  List<OrderModel> _activeOrders() => _orders
      .where((o) =>
          ((o.status == 'awaiting_acceptance' || o.status == 'pending') && o.sellerAccepted) ||
          [
            'awaiting_payment',
            'confirmed',
            'preparing',
            'ready_for_pickup',
            'picked_up',
            'out_for_delivery',
          ].contains(o.status))
      .toList();

  List<OrderModel> _doneOrders() => _orders
      .where((o) => [
            'delivered',
            'cancelled',
            'seller_rejected',
            'partner_rejected'
          ].contains(o.status))
      .toList();

  @override
  Widget build(BuildContext context) {
    final pendingCount = _pendingOrders().length;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: MaxWidthContainer(
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return [
            SliverAppBar(
              expandedHeight: 120,
              pinned: true,
              elevation: 0,
              backgroundColor: isDark ? const Color(0xFF141425) : Colors.white,
              surfaceTintColor: Colors.transparent,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.only(left: 20, bottom: 60),
                title: Text('Orders',
                    style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w800,
                        fontSize: 24,
                        color: isDark ? Colors.white : Colors.black)),
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF4C6EF5).withValues(alpha: 0.15),
                        Colors.transparent,
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
              actions: const [
                Padding(
                  padding: EdgeInsets.only(right: 8.0, bottom: 48.0),
                  child: NotificationBell(),
                ),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(60),
                child: Container(
                  height: 60,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E2E) : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicator: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      labelColor: Colors.white,
                      unselectedLabelColor: isDark ? Colors.white54 : Colors.black54,
                      dividerColor: Colors.transparent,
                      tabs: [
                        Tab(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('Pending', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                              if (pendingCount > 0) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                      color: AppColors.danger,
                                      borderRadius: BorderRadius.circular(10)),
                                  child: Text('$pendingCount',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800)),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Tab(child: Text('Active', style: GoogleFonts.outfit(fontWeight: FontWeight.w600))),
                        Tab(child: Text('Done', style: GoogleFonts.outfit(fontWeight: FontWeight.w600))),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ];
        },
        body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildList(_pendingOrders(), 'pending'),
                _buildList(_activeOrders(), 'active'),
                _buildList(_doneOrders(), 'done'),
              ],
            ),
        ),
      ),
    );
  }

  Widget _buildList(List<OrderModel> orders, String tab) {
    if (orders.isEmpty) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    blurRadius: 20,
                    spreadRadius: 5,
                  )
                ]
              ),
              child: Icon(
                tab == 'pending' ? Icons.inbox_outlined : 
                tab == 'active' ? Icons.local_shipping_outlined : 
                Icons.check_circle_outline,
                size: 64,
                color: AppColors.primary.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              tab == 'pending'
                  ? 'No New Orders'
                  : tab == 'active'
                      ? 'No Active Orders'
                      : 'No Completed Orders',
              style: GoogleFonts.outfit(
                  color: isDark ? Colors.white : Colors.black87, 
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              tab == 'pending'
                  ? 'When customers place orders, they will appear here.'
                  : tab == 'active'
                      ? 'Orders in progress will be tracked here.'
                      : 'Your past orders will be saved here.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                  color: AppColors.textSecondary, 
                  fontSize: 14),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadOrders,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: orders.length,
        itemBuilder: (context, index) => _buildOrderCard(orders[index], tab),
      ),
    );
  }

  Widget _buildOrderCard(OrderModel order, String tab) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusColor = _statusColor(order);

    bool isExpanded = _expandedOrderIds.contains(order.id);

    return StatefulBuilder(
      builder: (context, setState) {
        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                  color: isDark ? Colors.black26 : Colors.black.withValues(alpha: 0.05), 
                  blurRadius: 10,
                  offset: const Offset(0, 4))
            ],
            border: Border.all(
                color: isDark ? Colors.white10 : Colors.transparent,
                width: 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: statusColor,
                    width: 6,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
          // Header row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Order #${order.id.substring(0, 8).toUpperCase()}',
                style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w700, fontSize: 14),
              ),
              Text(
                DateFormat('hh:mm a').format(order.createdAt),
                style: GoogleFonts.outfit(
                    color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Amount + status badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '₹${order.grandTotal.toStringAsFixed(0)}',
                style: GoogleFonts.outfit(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary),
              ),
              _statusBadge(order, statusColor),
            ],
          ),

          // ── Order Items (Collapsible) ───────────────────────────────────
          if (order.items.isNotEmpty) ...[
            const SizedBox(height: 12),
            InkWell(
              onTap: () {
                setState(() {
                  if (isExpanded) {
                    _expandedOrderIds.remove(order.id);
                  } else {
                    _expandedOrderIds.add(order.id);
                  }
                  isExpanded = !isExpanded;
                });
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2A2A3A) : AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? Colors.white10 : Colors.grey.shade200,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Items (${order.items.length})',
                            style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white70 : AppColors.textSecondary)),
                        Icon(
                          isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                          size: 20,
                          color: isDark ? Colors.white54 : Colors.grey,
                        ),
                      ],
                    ),
                    if (isExpanded) ...[
                      const SizedBox(height: 8),
                      const Divider(height: 1),
                      const SizedBox(height: 8),
                      ...order.items.map((item) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  margin: const EdgeInsets.only(top: 4, right: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${item.quantity}x',
                                    style: GoogleFonts.outfit(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    item.productName,
                                    style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w500),
                                  ),
                                ),
                                Text(
                                  '₹${item.totalPrice.toStringAsFixed(0)}',
                                  style: GoogleFonts.outfit(
                                      fontSize: 13, fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          )),
                    ],
                  ],
                ),
              ),
            ),
          ],

          if (order.deliveryNotes != null && order.deliveryNotes!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.note_alt_outlined, size: 18, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Customer Note', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                        const SizedBox(height: 4),
                        Text(order.deliveryNotes!, style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textPrimary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Dual-acceptance progress bar (for pending-but-one-accepted)
          if (order.status == 'pending' &&
              (order.sellerAccepted || order.partnerAccepted)) ...[
            const SizedBox(height: 12),
            _buildAcceptanceProgress(order),
          ],

          // Contact Buttons
          if (order.customerPhone != null || order.riderPhone != null) ...[
            const SizedBox(height: 12),
            Row(children: [
              if (order.customerPhone != null)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _callPhone(order.customerPhone!),
                    icon: const Icon(Icons.phone_outlined, size: 16),
                    label: Text('Customer', style: GoogleFonts.outfit(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              if (order.customerPhone != null && order.riderPhone != null)
                const SizedBox(width: 8),
              if (order.riderPhone != null)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _callPhone(order.riderPhone!),
                    icon: const Icon(Icons.delivery_dining_outlined, size: 16),
                    label: Text('Rider', style: GoogleFonts.outfit(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.accent,
                      side: const BorderSide(color: AppColors.accent),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
            ]),
          ],

          // ── Track on Map button (active orders with coords) ──────────────
          if (tab == 'active' &&
              order.shopLat != null &&
              order.shopLng != null &&
              order.deliveryLat != null &&
              order.deliveryLng != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SellerOrderMapPage(
                      order: order,
                      shopName: _shopNames[order.shopId] ?? 'My Shop',
                    ),
                  ),
                ),
                icon: const Icon(Icons.map_outlined, size: 16),
                label: Text(
                  'Track on Map',
                  style: GoogleFonts.outfit(
                      fontSize: 12, fontWeight: FontWeight.w700),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],

          if (order.prescriptionUrls.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.medical_information, color: AppColors.danger, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Prescription Required',
                          style: GoogleFonts.outfit(color: AppColors.danger, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _showPrescriptionImages(order.prescriptionUrls),
                      icon: const Icon(Icons.image_outlined, size: 16),
                      label: Text('View ${order.prescriptionUrls.length} Prescription Images'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        side: const BorderSide(color: AppColors.danger),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  if (tab == 'pending') ...[
                    const SizedBox(height: 6),
                    Text(
                      'Please verify the prescription before accepting the order.',
                      style: GoogleFonts.outfit(color: AppColors.danger, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
          ],

          // Action buttons
          if (tab == 'pending') ...[
            const Divider(height: 20),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _sellerReject(order),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Reject',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _sellerAccept(order),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Accept',
                      style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
            ]),
          ] else if (tab == 'active' && order.status == 'confirmed') ...[
            const Divider(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _updateOrderStatus(order, 'preparing'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Start Preparing',
                    style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ] else if (tab == 'active' && order.status == 'preparing') ...[
            const Divider(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () =>
                    _updateOrderStatus(order, 'ready_for_pickup'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Mark Ready for Pickup',
                    style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w700, color: Colors.black)),
              ),
            ),
          ] else if (tab == 'done' &&
              order.status == 'delivered' &&
              order.deliveryPartnerId != null &&
              !order.hasSellerRated) ...[
            const Divider(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showSellerRatingFlow(order),
                icon: const Icon(Icons.star_outline_rounded, color: Colors.amber),
                label: Text('Rate Delivery Partner',
                    style: GoogleFonts.outfit(
                        color: Colors.amber, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.amber),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ] else if (tab == 'done' && order.hasSellerRated) ...[
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle_outline,
                    color: AppColors.success, size: 16),
                const SizedBox(width: 6),
                Text('Rider Rated',
                    style: GoogleFonts.outfit(
                        color: AppColors.success,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Shows a visual progress bar: [Seller ✓] ──── [Rider ?]
  Widget _buildAcceptanceProgress(OrderModel order) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Waiting for both parties to accept',
            style: GoogleFonts.outfit(
                fontSize: 12,
                color: Colors.amber.shade800,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _acceptanceStep(
                label: 'Shop',
                icon: Icons.store_outlined,
                accepted: order.sellerAccepted,
              ),
              Expanded(
                child: Container(
                  height: 2,
                  color: (order.sellerAccepted && order.partnerAccepted)
                      ? AppColors.success
                      : Colors.grey.shade300,
                ),
              ),
              _acceptanceStep(
                label: 'Rider',
                icon: Icons.delivery_dining_outlined,
                accepted: order.partnerAccepted,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _acceptanceStep(
      {required String label, required IconData icon, required bool accepted}) {
    return Column(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: accepted ? AppColors.success : Colors.grey.shade200,
            shape: BoxShape.circle,
          ),
          child: Icon(
            accepted ? Icons.check : icon,
            color: accepted ? Colors.white : Colors.grey.shade500,
            size: 18,
          ),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: GoogleFonts.outfit(
                fontSize: 11,
                color: accepted ? AppColors.success : AppColors.textSecondary,
                fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _statusBadge(OrderModel order, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        order.statusDisplay,
        style: GoogleFonts.outfit(
            color: color, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }

  Color _statusColor(OrderModel order) {
    switch (order.status) {
      case 'confirmed':
        return AppColors.success;
      case 'preparing':
        return AppColors.primary;
      case 'ready_for_pickup':
        return Colors.orange;
      case 'picked_up':
        return Colors.blue;
      case 'out_for_delivery':
        return Colors.deepPurple;
      case 'delivered':
        return AppColors.success;
      case 'seller_rejected':
      case 'partner_rejected':
      case 'cancelled':
        return AppColors.danger;
      default:
        if (order.sellerAccepted || order.partnerAccepted) {
          return Colors.amber.shade700;
        }
        return AppColors.textSecondary;
    }
  }

  Future<void> _callPhone(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _showSnack('Could not launch dialer', isError: true);
    }
  }
}
