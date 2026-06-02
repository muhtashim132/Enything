import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/order_model.dart';
import '../../theme/app_colors.dart';
import '../../config/routes.dart';
import '../../widgets/common/enything_map.dart';
import '../../widgets/common/rating_bottom_sheet.dart';
import '../../pages/customer/customer_order_map_page.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Cancel Order?',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 18)),
        content: Text(
            'Are you sure you want to cancel this order? This action cannot be undone.',
            style: GoogleFonts.outfit(fontSize: 14, color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Keep Order', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Yes, Cancel', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w700)),
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

  // Returns the dynamic status subtitle per status
  String _statusSubtitle(bool isDelivered, bool isCancelled) {
    if (isCancelled) return 'Your order has been cancelled';
    if (isDelivered) return 'Enjoy your order! Thank you 🎉';
    switch (_order?.status) {
      case 'pending':          return 'Waiting for shop & rider to accept...';
      case 'confirmed':        return 'Shop & rider confirmed — preparing soon!';
      case 'preparing':        return 'Shop is packing your order 📦';
      case 'ready_for_pickup': return 'Order packed — rider picking up soon!';
      case 'picked_up':        return 'Rider has your order — on the way!';
      case 'out_for_delivery': return 'Almost there! Rider is en-route 🛵';
      default:                 return 'Estimated delivery in 30-45 mins';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: isDark ? AppColors.darkBg : AppColors.background,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_order == null) {
      return Scaffold(
        backgroundColor: isDark ? AppColors.darkBg : AppColors.background,
        body: Center(
          child: Text('Order not found',
              style: GoogleFonts.outfit(fontSize: 16, color: AppColors.textSecondary)),
        ),
      );
    }

    final currentStep = _getCurrentStep();
    final isDelivered = _order!.status == 'delivered';
    final isCancelled = _order!.status == 'cancelled' ||
        _order!.status == 'seller_rejected' ||
        _order!.status == 'partner_rejected';
    final isLive = _order!.status == 'out_for_delivery';

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: isDark ? AppColors.darkBg : AppColors.background,
        // ── Premium Custom AppBar ─────────────────────────────────────────
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Container(
            color: isDark ? const Color(0xFF0D0D1A) : Colors.white,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    // Glass back button
                    GestureDetector(
                      onTap: () => Navigator.maybePop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.black.withValues(alpha: 0.05),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.arrow_back_ios_new_rounded,
                            size: 18,
                            color: isDark ? Colors.white70 : AppColors.textPrimary),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Order ID title
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Order #${_order!.id.substring(0, 8).toUpperCase()}',
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: isDark ? Colors.white : AppColors.textPrimary,
                            ),
                          ),
                          // Live pill — only shown when rider is en-route
                          if (isLive)
                            Row(
                              children: [
                                Container(
                                  width: 7, height: 7,
                                  decoration: const BoxDecoration(
                                    color: AppColors.success, shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text('Live Tracking',
                                    style: GoogleFonts.outfit(
                                      fontSize: 11, fontWeight: FontWeight.w600,
                                      color: AppColors.success,
                                    )),
                              ],
                            ),
                        ],
                      ),
                    ),
                    // History link
                    TextButton(
                      onPressed: () => Navigator.pushNamed(context, AppRoutes.orderHistory),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      child: Text('History',
                          style: GoogleFonts.outfit(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + safeBottom),
          child: Column(
            children: [
              // Map Section — tappable route preview
              _buildMapPreview(),

              // ── Status Hero ──────────────────────────────────────────────
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: Container(
                  key: ValueKey(_order!.status),
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: isCancelled
                        ? LinearGradient(colors: [
                            AppColors.danger.withValues(alpha: 0.85),
                            AppColors.danger,
                          ])
                        : isDelivered
                            ? LinearGradient(colors: [
                                AppColors.success.withValues(alpha: 0.85),
                                AppColors.success,
                              ])
                            : AppColors.splashGradient,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: (isCancelled
                                ? AppColors.danger
                                : isDelivered
                                    ? AppColors.success
                                    : AppColors.primary)
                            .withValues(alpha: 0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
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
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _order!.statusDisplay,
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _statusSubtitle(isDelivered, isCancelled),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ── Glass Contact Buttons ─────────────────────────────────────
              if (!isCancelled &&
                  (_order!.shopPhone != null || _order!.riderPhone != null)) ...[
                Row(children: [
                  if (_order!.shopPhone != null)
                    Expanded(child: _glassContactBtn(
                      icon: Icons.store_rounded,
                      label: 'Call Shop',
                      color: AppColors.primary,
                      isDark: isDark,
                      onTap: () => _callPhone(_order!.shopPhone!),
                    )),
                  if (_order!.shopPhone != null && _order!.riderPhone != null)
                    const SizedBox(width: 12),
                  if (_order!.riderPhone != null)
                    Expanded(child: _glassContactBtn(
                      icon: Icons.delivery_dining_rounded,
                      label: 'Call Rider',
                      color: AppColors.accent,
                      isDark: isDark,
                      onTap: () => _callPhone(_order!.riderPhone!),
                    )),
                ]),
                const SizedBox(height: 20),
              ],

              // ── Tracking Steps ────────────────────────────────────────────
              if (!isCancelled)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.07)
                          : Colors.transparent,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(
                          width: 4, height: 20,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Order Tracking',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : AppColors.textPrimary,
                          ),
                        ),
                      ]),
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
                          isDark,
                        );
                      }),
                    ],
                  ),
                ),
              const SizedBox(height: 20),

              // ── Bill Summary ──────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.07)
                        : Colors.transparent,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
                      blurRadius: 12, offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                        width: 4, height: 20,
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text('Bill Summary',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : AppColors.textPrimary,
                          )),
                    ]),
                    const SizedBox(height: 16),
                    _billRow('Item Subtotal',
                        '₹${_order!.totalAmount.toStringAsFixed(0)}', isDark: isDark),
                    const SizedBox(height: 8),
                    _billRow('Delivery Fee',
                        '₹${_order!.deliveryCharges.toStringAsFixed(0)}', isDark: isDark),
                    if (_order!.platformFee > 0) ...[
                      const SizedBox(height: 8),
                      _billRow('Handling Fee',
                          '₹${_order!.platformFee.toStringAsFixed(0)}', isDark: isDark),
                    ],
                    if (_order!.gstItemTotal > 0) ...[
                      const SizedBox(height: 8),
                      _billRow('GST on Items',
                          '₹${_order!.gstItemTotal.toStringAsFixed(0)}', isDark: isDark),
                    ],
                    Divider(
                      height: 24,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.1)
                          : AppColors.divider,
                    ),
                    _billRow(
                      'Total Paid',
                      '₹${(_order!.grandTotalCollected > 0 ? _order!.grandTotalCollected : _order!.grandTotal).toStringAsFixed(0)}',
                      isBold: true,
                      isDark: isDark,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── Back to Home ──────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pushNamedAndRemoveUntil(
                      context, AppRoutes.customerHome, (route) => false),
                  icon: const Icon(Icons.home_outlined),
                  label: Text('Back to Home',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 15)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
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
                    : SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: OutlinedButton.icon(
                          onPressed: _cancelOrder,
                          icon: const Icon(Icons.cancel_outlined,
                              color: AppColors.danger),
                          label: Text('Cancel Order',
                              style: GoogleFonts.outfit(
                                  color: AppColors.danger,
                                  fontWeight: FontWeight.w700)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.danger),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ),
              ],

              // Rate button — delivered, not yet rated
              if (isDelivered && !(_order!.hasCustomerRated)) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: _showRatingFlow,
                    icon: const Icon(Icons.star_rounded, color: Colors.amber),
                    label: Text('Rate Your Order',
                        style: GoogleFonts.outfit(
                            color: Colors.amber, fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.amber),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              ] else if (isDelivered && _order!.hasCustomerRated) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: AppColors.success.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check_circle_outline,
                          color: AppColors.success, size: 18),
                      const SizedBox(width: 8),
                      Text('Thanks for your rating!',
                          style: GoogleFonts.outfit(
                              color: AppColors.success,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _glassContactBtn({
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.15 : 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: isDark ? 0.4 : 0.35)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(label,
                style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(String title, String subtitle, IconData icon,
      bool isCompleted, bool isCurrent, bool hasLine, bool isDark) {
    final activeColor = isCompleted ? AppColors.success : AppColors.primary;
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
                        ? AppColors.primary.withValues(alpha: isDark ? 0.25 : 0.1)
                        : (isDark ? Colors.white.withValues(alpha: 0.05) : AppColors.background),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isCompleted
                      ? AppColors.success
                      : isCurrent
                          ? AppColors.primary
                          : (isDark ? Colors.white.withValues(alpha: 0.12) : AppColors.divider),
                  width: 2,
                ),
              ),
              child: Icon(
                isCompleted ? Icons.check_rounded : icon,
                color: isCompleted
                    ? Colors.white
                    : isCurrent
                        ? AppColors.primary
                        : (isDark ? Colors.white30 : AppColors.textLight),
                size: 18,
              ),
            ),
            if (hasLine)
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                width: 2,
                height: 36,
                decoration: BoxDecoration(
                  gradient: isCompleted
                      ? const LinearGradient(
                          colors: [AppColors.success, AppColors.success],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter)
                      : LinearGradient(
                          colors: [
                            isDark
                                ? Colors.white.withValues(alpha: 0.1)
                                : AppColors.divider,
                            isDark
                                ? Colors.white.withValues(alpha: 0.1)
                                : AppColors.divider,
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter),
                ),
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
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: isCompleted || isCurrent
                        ? (isDark ? Colors.white : AppColors.textPrimary)
                        : (isDark ? Colors.white30 : AppColors.textLight),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: isCompleted || isCurrent
                        ? (isDark ? Colors.white54 : AppColors.textSecondary)
                        : (isDark ? Colors.white24 : AppColors.textLight),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (isCompleted)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Icon(Icons.check_circle_rounded,
                color: activeColor.withValues(alpha: 0.5), size: 14),
          ),
      ],
    );
  }

  Widget _billRow(String label, String value,
      {bool isBold = false, bool isDark = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: GoogleFonts.outfit(
              color: isBold
                  ? (isDark ? Colors.white : AppColors.textPrimary)
                  : (isDark ? Colors.white54 : AppColors.textSecondary),
              fontSize: isBold ? 15 : 13,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
            )),
        Text(value,
            style: GoogleFonts.outfit(
              fontWeight: isBold ? FontWeight.w900 : FontWeight.w600,
              fontSize: isBold ? 16 : 13,
              color: isBold
                  ? AppColors.primary
                  : (isDark ? Colors.white70 : AppColors.textPrimary),
            )),
      ],
    );
  }

  /// Tappable map preview — opens full-screen CustomerOrderMapPage when tapped.
  Widget _buildMapPreview() {
    if (_order == null) return const SizedBox.shrink();

    final hasCoords = _order!.shopLat != null &&
        _order!.shopLng != null &&
        _order!.deliveryLat != null &&
        _order!.deliveryLng != null;

    final isCancelled = _order!.status == 'cancelled' ||
        _order!.status == 'seller_rejected' ||
        _order!.status == 'partner_rejected';

    // Show full-screen button only for active/trackable statuses
    final canShowMap = hasCoords && !isCancelled;

    return GestureDetector(
      onTap: canShowMap
          ? () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CustomerOrderMapPage(order: _order!),
                ),
              )
          : null,
      child: Container(
        height: 240,
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
        child: Stack(
          children: [
            // Underlying map thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: EnythingMap(
                center: _mapCenter(),
                zoom: 14,
                interactive: false, // non-interactive; tap handled by GestureDetector
                markers: _buildMapMarkers(),
              ),
            ),

            // Gradient overlay for readability
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.45),
                    ],
                    stops: const [0.5, 1.0],
                  ),
                ),
              ),
            ),

            // "View Live Route" pill button at bottom centre
            if (canShowMap)
              Positioned(
                bottom: 14,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 9),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.route_rounded,
                            color: Colors.white, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'View Live Route',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Live rider badge (top-right) when out_for_delivery
            if (_riderLatLng != null &&
                _order!.status == 'out_for_delivery')
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.success.withValues(alpha: 0.4),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.circle,
                          color: Colors.white, size: 6),
                      const SizedBox(width: 5),
                      Text(
                        'Rider Live',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
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
