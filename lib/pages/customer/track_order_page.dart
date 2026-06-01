import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/order_model.dart';
import '../../theme/app_colors.dart';
import '../../config/routes.dart';
import '../../widgets/common/enything_map.dart';
import '../../widgets/common/rating_bottom_sheet.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

class TrackOrderPage extends StatefulWidget {
  final String orderId;
  const TrackOrderPage({super.key, required this.orderId});

  @override
  State<TrackOrderPage> createState() => _TrackOrderPageState();
}

class _TrackOrderPageState extends State<TrackOrderPage>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  OrderModel? _order;
  bool _isLoading = true;
  bool _isCancelling = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;
  RealtimeChannel? _channel;
  // Live rider GPS position (updated by delivery partner every 15s)
  LatLng? _riderLatLng;

  final List<Map<String, dynamic>> _steps = [
    {
      'status': 'pending',
      'title': 'Order Placed',
      'subtitle': 'Waiting for shop & rider to accept',
      'icon': Icons.receipt_long,
    },
    {
      'status': 'confirmed',
      'title': 'Order Confirmed',
      'subtitle': 'Both shop & rider accepted!',
      'icon': Icons.verified_outlined,
    },
    {
      'status': 'preparing',
      'title': 'Preparing',
      'subtitle': 'Shop is preparing your order',
      'icon': Icons.restaurant,
    },
    {
      'status': 'picked_up',
      'title': 'Picked Up',
      'subtitle': 'Rider collected your order',
      'icon': Icons.delivery_dining,
    },
    {
      'status': 'out_for_delivery',
      'title': 'Out for Delivery',
      'subtitle': 'Your order is almost here!',
      'icon': Icons.local_shipping_outlined,
    },
    {
      'status': 'delivered',
      'title': 'Delivered!',
      'subtitle': 'Enjoy your order! 🎉',
      'icon': Icons.check_circle,
    },
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _fetchOrder();
    _subscribeToOrder();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _fetchOrder() async {
    try {
      final response = await _supabase
          .from('orders')
          .select()
          .eq('id', widget.orderId)
          .single();

      if (mounted) {
        final order = OrderModel.fromMap(response);
        setState(() {
          _order = order;
          _isLoading = false;
          // Set initial rider location if available
          if (order.riderLat != null && order.riderLng != null) {
            _riderLatLng = LatLng(order.riderLat!, order.riderLng!);
          }
        });
        // If already delivered and not yet rated, show rating prompt
        if (order.status == 'delivered' && !order.hasCustomerRated) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _showRatingFlow());
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _subscribeToOrder() {
    _channel = _supabase
        .channel('order-${widget.orderId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.orderId,
          ),
          callback: (payload) {
            if (mounted && payload.newRecord.isNotEmpty) {
              final updatedOrder = OrderModel.fromMap(payload.newRecord);
              final wasDelivered = _order?.status != 'delivered' &&
                  updatedOrder.status == 'delivered';
              setState(() {
                _order = updatedOrder;
                // Update live rider marker position
                if (updatedOrder.riderLat != null && updatedOrder.riderLng != null) {
                  _riderLatLng = LatLng(updatedOrder.riderLat!, updatedOrder.riderLng!);
                }
                // Clear rider marker once delivered
                if (updatedOrder.status == 'delivered') _riderLatLng = null;
              });
              // Trigger rating prompt the moment delivery is confirmed
              if (wasDelivered && !updatedOrder.hasCustomerRated) {
                Future.delayed(
                    const Duration(milliseconds: 600), _showRatingFlow);
              }
            }
          },
        )
        .subscribe();
  }

  /// Shows a confirmation dialog then cancels the order in Supabase.
  Future<void> _cancelOrder() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Cancel Order?',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        content: const Text(
            'Are you sure you want to cancel this order? This action cannot be undone.',
            style: TextStyle(fontFamily: 'Poppins', fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Order'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Yes, Cancel', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isCancelling = true);
    try {
      await _supabase
          .from('orders')
          .update({'status': 'cancelled'})
          .eq('id', widget.orderId);
      if (mounted) {
        setState(() => _order = _order?.copyWith(status: 'cancelled'));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Order cancelled successfully.'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      debugPrint('Cancel order error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to cancel order. Please try again.'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }

  /// Step 1: Rate the Shop. Step 2 (if partner assigned): Rate the Rider.
  void _showRatingFlow() {
    if (!mounted || _order == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => RatingBottomSheet(
        title: 'Rate the Shop ⭐',
        subtitle: 'How was the quality of your order?',
        onSubmit: (rating, review) => _submitRating(
          rateeId: null,
          shopId: _order!.shopId, // Pass the actual shop ID
          rateeRole: 'seller',
          rating: rating,
          review: review,
          thenRateRider: _order!.deliveryPartnerId != null,
        ),
      ),
    );
  }

  Future<void> _submitRating({
    required String? rateeId,
    required String? shopId,
    required String rateeRole,
    required int rating,
    required String review,
    bool thenRateRider = false,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      await _supabase.from('ratings').insert({
        'order_id': widget.orderId,
        'rater_id': userId,
        'ratee_id': rateeId,
        'shop_id': shopId,
        'rater_role': 'customer',
        'ratee_role': rateeRole,
        'rating': rating,
        'review': review.isEmpty ? null : review,
      });

      if (rateeRole == 'seller') {
        // Mark customer rated on the order
        await _supabase.from('orders')
            .update({'has_customer_rated': true}).eq('id', widget.orderId);
        setState(() => _order = _order?.copyWith(hasCustomerRated: true));
      }

      if (thenRateRider && mounted) {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
          builder: (_) => RatingBottomSheet(
            title: 'Rate the Rider 🚴',
            subtitle: 'How was the delivery experience?',
            onSubmit: (r, rv) => _submitRating(
              rateeId: _order!.deliveryPartnerId,
              shopId: null,
              rateeRole: 'delivery',
              rating: r,
              review: rv,
              thenRateRider: false,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Rating submit error: $e');
    }
  }

  int _getCurrentStep() {
    if (_order == null) return 0;
    switch (_order!.status) {
      case 'pending':          return 0;
      case 'confirmed':        return 1;
      case 'preparing':        return 2;
      case 'ready_for_pickup': return 2;
      case 'picked_up':        return 3;
      case 'out_for_delivery': return 4;
      case 'delivered':        return 5;
      default:                 return 0;
    }
  }

  /// Returns the best available map centre for this order.
  /// Priority: rider live position → customer delivery address → Delhi fallback.
  LatLng _mapCenter() {
    if (_riderLatLng != null && _order?.status == 'out_for_delivery') {
      return _riderLatLng!;
    }
    if (_order?.deliveryLat != null && _order?.deliveryLng != null) {
      return LatLng(_order!.deliveryLat!, _order!.deliveryLng!);
    }
    return const LatLng(28.6139, 77.2090);
  }

  /// Builds the rider motorcycle marker when live location is available.
  List<Marker> _buildMapMarkers() {
    final markers = <Marker>[];

    // Customer delivery address pin (always shown)
    if (_order?.deliveryLat != null && _order?.deliveryLng != null) {
      markers.add(Marker(
        point: LatLng(_order!.deliveryLat!, _order!.deliveryLng!),
        width: 44,
        height: 44,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.home_rounded, color: AppColors.primary, size: 26),
        ),
      ));
    }

    // Live rider marker (only when out_for_delivery)
    if (_riderLatLng != null && _order?.status == 'out_for_delivery') {
      markers.add(Marker(
        point: _riderLatLng!,
        width: 52,
        height: 52,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.2),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.success, width: 2),
          ),
          child: const Icon(Icons.delivery_dining_rounded,
              color: AppColors.success, size: 28),
        ),
      ));
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_order == null) {
      return const Scaffold(body: Center(child: Text('Order not found')));
    }

    final currentStep = _getCurrentStep();
    final isDelivered = _order!.status == 'delivered';
    final isCancelled = _order!.status == 'cancelled' ||
        _order!.status == 'seller_rejected';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Order #${_order!.id.substring(0, 8).toUpperCase()}'),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pushNamed(context, AppRoutes.orderHistory),
            icon: const Icon(Icons.history, size: 16),
            label: const Text('History'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Map Section
            Container(
              height: 250,
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: EnythingMap(
                  center: _mapCenter(),
                  zoom: 14,
                  interactive: true,
                  markers: _buildMapMarkers(),
                ),
              ),
            ),
            // Status Hero
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: isCancelled
                    ? LinearGradient(colors: [
                        AppColors.danger.withValues(alpha: 0.8),
                        AppColors.danger,
                      ])
                    : isDelivered
                        ? LinearGradient(colors: [
                            AppColors.success.withValues(alpha: 0.8),
                            AppColors.success,
                          ])
                        : AppColors.splashGradient,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                children: [
                  ScaleTransition(
                    scale: isDelivered || isCancelled
                        ? const AlwaysStoppedAnimation(1.0)
                        : _pulseAnim,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isCancelled
                            ? Icons.cancel_outlined
                            : isDelivered
                                ? Icons.check_circle_outline
                                : Icons.delivery_dining,
                        color: Colors.white,
                        size: 44,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _order!.statusDisplay,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'Poppins',
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isDelivered
                        ? 'Enjoy your order! Thank you 🎉'
                        : isCancelled
                            ? 'Your order has been cancelled'
                            : 'Estimated delivery in 30-45 mins',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 13,
                      fontFamily: 'Poppins',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            const SizedBox(height: 20),

            // Contact Buttons
            if (!isCancelled && (_order!.shopPhone != null || _order!.riderPhone != null)) ...[
              Row(children: [
                if (_order!.shopPhone != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _callPhone(_order!.shopPhone!),
                      icon: const Icon(Icons.store_outlined, size: 16),
                      label: const Text('Call Shop', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                if (_order!.shopPhone != null && _order!.riderPhone != null)
                  const SizedBox(width: 12),
                if (_order!.riderPhone != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _callPhone(_order!.riderPhone!),
                      icon: const Icon(Icons.delivery_dining_outlined, size: 16),
                      label: const Text('Call Rider', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.accent,
                        side: const BorderSide(color: AppColors.accent),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 20),
            ],

            // Tracking Steps
            if (!isCancelled)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Order Tracking',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Poppins',
                      ),
                    ),
                    const SizedBox(height: 20),
                    ...List.generate(_steps.length, (index) {
                      final isCompleted = index <= currentStep;
                      final isCurrent = index == currentStep;
                      return _buildStep(
                        _steps[index]['title']!,
                        _steps[index]['subtitle']!,
                        _steps[index]['icon'] as IconData,
                        isCompleted,
                        isCurrent,
                        index < _steps.length - 1,
                      );
                    }),
                  ],
                ),
              ),
            const SizedBox(height: 20),

            // Order Bill
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Bill Summary',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Poppins')),
                  const SizedBox(height: 16),
                  _billRow('Item Subtotal',
                      '₹${_order!.totalAmount.toStringAsFixed(0)}'),
                  const SizedBox(height: 8),
                  _billRow('Delivery Fee',
                      '₹${_order!.deliveryCharges.toStringAsFixed(0)}'),
                  if (_order!.platformFee > 0) ...[
                    const SizedBox(height: 8),
                    _billRow('Handling Fee',
                        '₹${_order!.platformFee.toStringAsFixed(0)}'),
                  ],
                  if (_order!.gstItemTotal > 0) ...[
                    const SizedBox(height: 8),
                    _billRow('GST on Items',
                        '₹${_order!.gstItemTotal.toStringAsFixed(0)}'),
                  ],
                  const Divider(height: 20),
                  _billRow(
                    'Total Paid',
                    '₹${(_order!.grandTotalCollected > 0 ? _order!.grandTotalCollected : _order!.grandTotal).toStringAsFixed(0)}',
                    isBold: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            ElevatedButton.icon(
              onPressed: () => Navigator.pushNamedAndRemoveUntil(
                  context, AppRoutes.customerHome, (route) => false),
              icon: const Icon(Icons.home_outlined),
              label: const Text('Back to Home'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
              ),
            ),
            // Cancel button — only for pending orders
            if (_order!.status == 'pending') ...[
              const SizedBox(height: 12),
              _isCancelling
                  ? const SizedBox(
                      height: 52,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : OutlinedButton.icon(
                      onPressed: _cancelOrder,
                      icon: const Icon(Icons.cancel_outlined,
                          color: AppColors.danger),
                      label: const Text('Cancel Order',
                          style: TextStyle(
                              color: AppColors.danger,
                              fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 52),
                        side: const BorderSide(color: AppColors.danger),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
            ],
            if (isDelivered && !(_order!.hasCustomerRated)) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _showRatingFlow,
                icon: const Icon(Icons.star_outline_rounded, color: Colors.amber),
                label: const Text('Rate Your Order',
                    style: TextStyle(color: Colors.amber, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  side: const BorderSide(color: Colors.amber),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ] else if (isDelivered && _order!.hasCustomerRated) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_outline, color: AppColors.success, size: 18),
                    SizedBox(width: 8),
                    Text('Thanks for your rating!',
                        style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(String title, String subtitle, IconData icon,
      bool isCompleted, bool isCurrent, bool hasLine) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isCompleted
                    ? AppColors.success
                    : isCurrent
                        ? AppColors.primary.withValues(alpha: 0.1)
                        : AppColors.background,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isCompleted
                      ? AppColors.success
                      : isCurrent
                          ? AppColors.primary
                          : AppColors.divider,
                  width: 2,
                ),
              ),
              child: Icon(
                isCompleted ? Icons.check : icon,
                color: isCompleted
                    ? Colors.white
                    : isCurrent
                        ? AppColors.primary
                        : AppColors.textLight,
                size: 18,
              ),
            ),
            if (hasLine)
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                width: 2,
                height: 36,
                color: isCompleted ? AppColors.success : AppColors.divider,
              ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: isCompleted || isCurrent
                        ? AppColors.textPrimary
                        : AppColors.textLight,
                    fontFamily: 'Poppins',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: isCompleted || isCurrent
                        ? AppColors.textSecondary
                        : AppColors.textLight,
                    fontFamily: 'Poppins',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _billRow(String label, String value, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
              color: isBold ? AppColors.textPrimary : AppColors.textSecondary,
              fontSize: isBold ? 15 : 13,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
            )),
        Text(value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
              fontSize: isBold ? 16 : 13,
              color: isBold ? AppColors.primary : AppColors.textPrimary,
            )),
      ],
    );
  }

  Future<void> _callPhone(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Could not launch dialer'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    }
  }
}
