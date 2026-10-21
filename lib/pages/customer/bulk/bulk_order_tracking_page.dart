// ============================================================================
// bulk_order_tracking_page.dart — Customer Bulk & Catering Order Tracking
// ============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../theme/app_theme.dart';
import '../../../config/routes.dart';
import '../../../models/bulk_order_model.dart';
import '../../../models/order_model.dart';
import '../../../providers/bulk_order_provider.dart';

class BulkOrderTrackingPage extends StatefulWidget {
  final String? initialOrderId;

  const BulkOrderTrackingPage({super.key, this.initialOrderId});

  @override
  State<BulkOrderTrackingPage> createState() => _BulkOrderTrackingPageState();
}

class _BulkOrderTrackingPageState extends State<BulkOrderTrackingPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  RealtimeChannel? _realtimeChannel;
  final Set<String> _revealedOtpOrderIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<BulkOrderProvider>(context, listen: false);
      provider.loadCustomerBulkOrders();
      _setupRealtime();
    });
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  void _setupRealtime() {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    _realtimeChannel = _supabase
        .channel('public:bulk_orders_tracking_${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'customer_id',
            value: user.id,
          ),
          callback: (payload) {
            if (mounted) {
              Provider.of<BulkOrderProvider>(context, listen: false)
                  .loadCustomerBulkOrders();
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'bulk_orders',
          callback: (payload) {
            if (mounted) {
              Provider.of<BulkOrderProvider>(context, listen: false)
                  .loadCustomerBulkOrders();
            }
          },
        )
        .subscribe();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = AppTheme.primaryColor;
    final bulkProvider = Provider.of<BulkOrderProvider>(context);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          'My Bulk & Event Orders 🎉',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        elevation: 0,
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black87,
      ),
      body: bulkProvider.isLoadingOrders
          ? const Center(child: CircularProgressIndicator())
          : bulkProvider.customerBulkOrders.isEmpty
              ? _buildEmptyState(isDark)
              : Builder(
                  builder: (context) {
                    final orders = List<OrderModel>.from(bulkProvider.customerBulkOrders);
                    if (widget.initialOrderId != null) {
                      orders.sort((a, b) {
                        if (a.id == widget.initialOrderId) return -1;
                        if (b.id == widget.initialOrderId) return 1;
                        return 0;
                      });
                    }

                    return RefreshIndicator(
                      onRefresh: () => bulkProvider.loadCustomerBulkOrders(),
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: orders.length,
                        itemBuilder: (context, index) {
                          final order = orders[index];
                          final bulkMeta = bulkProvider.bulkMetadataMap[order.id];
                          final isSelected = widget.initialOrderId != null &&
                              order.id == widget.initialOrderId;
                          return _buildOrderTrackingCard(
                            order,
                            bulkMeta,
                            isDark,
                            primary,
                            isSelected: isSelected,
                          );
                        },
                      ),
                    );
                  },
                ),
    );
  }

  Widget _buildOrderTrackingCard(
    OrderModel order,
    BulkOrderModel? bulkMeta,
    bool isDark,
    Color primary, {
    bool isSelected = false,
  }) {
    final isCancelled = order.status == 'cancelled' || order.status == 'seller_rejected';
    final isDelivered = order.status == 'delivered';
    final isModificationProposed = order.status == 'modification_proposed';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isSelected
              ? primary
              : (isModificationProposed
                  ? Colors.amber.withValues(alpha: 0.5)
                  : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05))),
          width: isSelected ? 2 : (isModificationProposed ? 1.5 : 1),
        ),
        boxShadow: [
          BoxShadow(
            color: isSelected
                ? primary.withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: isSelected ? 16 : 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Event Name + Status Badge
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF242424) : Colors.grey[50],
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bulkMeta?.eventName?.isNotEmpty == true
                            ? bulkMeta!.eventName!
                            : 'Event Catering',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Order #${order.id.substring(0, 8).toUpperCase()}',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white54 : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                _buildStatusPill(order.status, isDark),
              ],
            ),
          ),

          // Body: Date, Slot, Venue, Batches
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (bulkMeta != null) ...[
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded, size: 14, color: Colors.grey),
                      const SizedBox(width: 6),
                      Text(
                        bulkMeta.eventDateDisplay,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      const Icon(Icons.schedule_rounded, size: 14, color: Colors.grey),
                      const SizedBox(width: 6),
                      Text(
                        bulkMeta.slotDisplay,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (bulkMeta.venueAddress != null)
                    Row(
                      children: [
                        const Icon(Icons.location_on_rounded, size: 14, color: Colors.grey),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            bulkMeta.venueAddress!,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white70 : Colors.grey[700],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                ],

                const SizedBox(height: 12),

                // Clean Event Preparation & Delivery Status Card
                if (!isCancelled && !isDelivered) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.black26 : Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: (order.status == 'bulk_dispatched' || order.status == 'out_for_delivery')
                                ? Colors.teal.withValues(alpha: 0.15)
                                : (order.status == 'bulk_ready')
                                    ? Colors.purple.withValues(alpha: 0.15)
                                    : (order.status == 'bulk_confirmed' || order.status == 'bulk_preparing')
                                        ? Colors.blue.withValues(alpha: 0.15)
                                        : Colors.amber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            (order.status == 'bulk_dispatched' || order.status == 'out_for_delivery')
                                ? Icons.directions_car_filled_rounded
                                : (order.status == 'bulk_ready')
                                    ? Icons.done_all_rounded
                                    : (order.status == 'bulk_confirmed' || order.status == 'bulk_preparing')
                                        ? Icons.outdoor_grill_rounded
                                        : Icons.soup_kitchen_rounded,
                            color: (order.status == 'bulk_dispatched' || order.status == 'out_for_delivery')
                                ? Colors.teal
                                : (order.status == 'bulk_ready')
                                    ? Colors.purpleAccent
                                    : (order.status == 'bulk_confirmed' || order.status == 'bulk_preparing')
                                        ? Colors.blue
                                        : Colors.amber.shade800,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (order.status == 'bulk_dispatched' || order.status == 'out_for_delivery')
                                    ? 'Out for Delivery 🚗'
                                    : (order.status == 'bulk_ready')
                                        ? 'Food Prepared & Packed 🍱'
                                        : (order.status == 'bulk_confirmed' || order.status == 'bulk_preparing')
                                            ? 'Dishes Cooking in Kitchen 👨‍🍳'
                                            : 'Awaiting Kitchen Preparation',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                (order.status == 'bulk_dispatched' || order.status == 'out_for_delivery')
                                    ? 'In-house team is en route to your event venue.'
                                    : (order.status == 'bulk_ready')
                                        ? 'All dishes packed in containers, ready for dispatch.'
                                        : (order.status == 'bulk_confirmed' || order.status == 'bulk_preparing')
                                            ? 'Kitchen is freshly preparing your event menu.'
                                            : 'Catering team is scheduling prep for your event.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? Colors.white60 : Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Delivery OTP Card
                if (!isCancelled && !isDelivered)
                  Builder(
                    builder: (context) {
                      final isRevealed = _revealedOtpOrderIds.contains(order.id);
                      final hasOtp = order.deliveryOtp != null && order.deliveryOtp!.isNotEmpty;
                      final displayOtp = hasOtp
                          ? (isRevealed ? order.deliveryOtp! : '••••')
                          : '••••';

                      return InkWell(
                        onTap: hasOtp
                            ? () {
                                setState(() {
                                  if (isRevealed) {
                                    _revealedOtpOrderIds.remove(order.id);
                                  } else {
                                    _revealedOtpOrderIds.add(order.id);
                                  }
                                });
                              }
                            : null,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: primary.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.key_rounded, size: 16, color: primary),
                                  const SizedBox(width: 8),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Delivery Handover OTP:',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                      ),
                                      if (hasOtp)
                                        Text(
                                          isRevealed
                                              ? 'Share with driver at arrival'
                                              : 'Tap to reveal code',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: isDark ? Colors.white54 : Colors.grey[600],
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  Text(
                                    displayOtp,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: isRevealed ? 4 : 2,
                                      color: primary,
                                    ),
                                  ),
                                  if (hasOtp) ...[
                                    const SizedBox(width: 8),
                                    Icon(
                                      isRevealed
                                          ? Icons.visibility_off_rounded
                                          : Icons.visibility_rounded,
                                      size: 16,
                                      color: primary,
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                // Modification Proposal Notice Card
                if (isModificationProposed && bulkMeta?.sellerModificationProposal != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.edit_note_rounded, size: 18, color: Colors.amber),
                            SizedBox(width: 6),
                            Text(
                              'Kitchen Proposed Changes',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.amber,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          bulkMeta?.sellerNotes ??
                              'The kitchen proposed adjusting dish quantities or items due to prep capacity.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  Provider.of<BulkOrderProvider>(context,
                                          listen: false)
                                      .respondToModification(order.id, false);
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                  side: const BorderSide(color: Colors.red),
                                ),
                                child: const Text('Decline (Refund)'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () {
                                  Provider.of<BulkOrderProvider>(context,
                                          listen: false)
                                      .respondToModification(order.id, true);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Accept Changes'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],

                const Divider(height: 24),

                // Footer: Total & Actions (Call shop, Cancel)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total Paid',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: isDark ? Colors.white54 : Colors.grey[600],
                          ),
                        ),
                        Text(
                          '₹${order.grandTotal.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: primary,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        if (order.shopPhone != null && order.shopPhone!.isNotEmpty)
                          IconButton.filledTonal(
                            icon: const Icon(Icons.phone_rounded, size: 18),
                            tooltip: 'Call Kitchen',
                            onPressed: () {
                              final uri = Uri.parse('tel:${order.shopPhone}');
                              launchUrl(uri, mode: LaunchMode.externalApplication);
                            },
                          ),
                        if (!isCancelled && !isDelivered) ...[
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () => _confirmCancelOrder(order, bulkMeta),
                            style: TextButton.styleFrom(foregroundColor: Colors.red),
                            child: const Text('Cancel Order'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmCancelOrder(OrderModel order, BulkOrderModel? bulkMeta) {
    final startTime = bulkMeta?.deliveryTimeSlotStart ?? DateTime.now().add(const Duration(hours: 12));
    final hoursLeft = startTime.difference(DateTime.now()).inMinutes / 60.0;

    String refundPolicyText;
    if (hoursLeft > 24) {
      refundPolicyText = '100% Refund (More than 24 hours before event)';
    } else if (hoursLeft >= 6) {
      refundPolicyText = '50% Item Refund + 100% Delivery Fee Refund (6–24 hours before event)';
    } else {
      refundPolicyText = '0% Item Refund (Food prep underway). Delivery fee will be refunded.';
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Bulk Order?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Are you sure you want to cancel this bulk catering order?',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Cancellation Refund Preview:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(refundPolicyText, style: const TextStyle(fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep Order'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Provider.of<BulkOrderProvider>(context, listen: false)
                  .cancelBulkOrder(order.id);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Confirm Cancellation'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPill(String status, bool isDark) {
    Color bg;
    Color fg;
    String label;

    switch (status) {
      case 'bulk_pending':
        bg = Colors.amber.withValues(alpha: 0.15);
        fg = Colors.amber.shade800;
        label = 'Awaiting Kitchen';
        break;
      case 'bulk_confirmed':
        bg = Colors.blue.withValues(alpha: 0.15);
        fg = Colors.blue;
        label = 'Kitchen Confirmed';
        break;
      case 'bulk_preparing':
        bg = Colors.blue.withValues(alpha: 0.15);
        fg = Colors.blue;
        label = 'Cooking in Progress 🍳';
        break;
      case 'bulk_ready':
        bg = Colors.purple.withValues(alpha: 0.15);
        fg = Colors.purpleAccent;
        label = 'Food Ready 🍱';
        break;
      case 'bulk_dispatched':
      case 'out_for_delivery':
        bg = Colors.teal.withValues(alpha: 0.15);
        fg = Colors.teal;
        label = 'Out for Delivery 🚗';
        break;
      case 'delivered':
        bg = Colors.green.withValues(alpha: 0.15);
        fg = Colors.green;
        label = 'Delivered 🎉';
        break;
      case 'cancelled':
      case 'seller_rejected':
        bg = Colors.red.withValues(alpha: 0.15);
        fg = Colors.red;
        label = 'Cancelled';
        break;
      case 'modification_proposed':
        bg = Colors.amber.withValues(alpha: 0.2);
        fg = Colors.amber.shade900;
        label = 'Review Changes';
        break;
      default:
        bg = Colors.grey.withValues(alpha: 0.15);
        fg = Colors.grey;
        label = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(
        label,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🎉', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text(
              'No Catering Orders Placed Yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Looking to cater for a birthday, wedding, or team lunch? Request a custom menu quotation with zero GST surcharge.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white60 : Colors.grey[600],
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.draw_rounded, size: 18),
              label: const Text('Request a Quote ✍️'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () {
                Navigator.pushNamed(context, AppRoutes.manualQuoteRequest);
              },
            ),
          ],
        ),
      ),
    );
  }
}
