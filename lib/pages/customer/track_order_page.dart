import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/order_model.dart';
import '../../theme/app_colors.dart';
import '../../config/routes.dart';
import '../../widgets/common/enything_map.dart';
import '../../widgets/common/rating_bottom_sheet.dart';
import '../../pages/customer/customer_order_map_page.dart';
import '../../providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/notification_service.dart';

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
  LatLng? _riderLatLng;

  // Payment (Razorpay) — triggered when both seller & rider accept
  late Razorpay _razorpay;
  bool _isProcessingPayment = false;
  Timer? _paymentCountdownTimer;
  int _paymentSecondsLeft = 600; // 10 minutes

  // Acceptance countdown (2 minutes)
  Timer? _acceptanceCountdownTimer;
  int _acceptanceSecondsLeft = 120;

  // Sibling orders (same cart_group_id) for multi-shop display (up to 3 shops)
  List<Map<String, dynamic>> _siblingOrders = [];
  bool _isRetrying = false;

  final List<Map<String, dynamic>> _steps = [
    {
      'status': 'awaiting_acceptance',
      'title': 'Order Sent',
      'subtitle': 'Waiting for shop & rider to accept',
      'icon': Icons.hourglass_top_rounded,
    },
    {
      'status': 'awaiting_payment',
      'title': 'Ready — Pay Now!',
      'subtitle': 'Shop & rider confirmed. Complete payment',
      'icon': Icons.payment_rounded,
    },
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
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
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
    _razorpay.clear();
    _pulseController.dispose();
    _paymentCountdownTimer?.cancel();
    _acceptanceCountdownTimer?.cancel();
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
          if (order.riderLat != null && order.riderLng != null) {
            _riderLatLng = LatLng(order.riderLat!, order.riderLng!);
          }
        });
        
        NotificationService().updateOrderNotificationFromStatus(order.status);

        // Start acceptance countdown if still waiting
        if (order.status == 'awaiting_acceptance') {
          _startAcceptanceCountdown(order);
        }
        
        // Fetch sibling orders if multi-shop checkout
        if (order.cartGroupId != null) {
          _fetchSiblingOrders(order.cartGroupId!);
        }
        
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
              final justReadyToPay = _order?.status != 'awaiting_payment' &&
                  updatedOrder.status == 'awaiting_payment';
              final justAccepting = _order?.status != 'awaiting_acceptance' &&
                  updatedOrder.status == 'awaiting_acceptance';

              setState(() {
                _order = updatedOrder;
                if (updatedOrder.riderLat != null && updatedOrder.riderLng != null) {
                  _riderLatLng = LatLng(updatedOrder.riderLat!, updatedOrder.riderLng!);
                }
                if (updatedOrder.status == 'delivered') _riderLatLng = null;
              });
              
              NotificationService().updateOrderNotificationFromStatus(updatedOrder.status);

              // Start/stop acceptance countdown
              if (justAccepting) {
                _startAcceptanceCountdown(updatedOrder);
              } else if (updatedOrder.status != 'awaiting_acceptance') {
                _acceptanceCountdownTimer?.cancel();
              }

              // Auto-open Razorpay when both seller & rider have accepted
              if (justReadyToPay) {
                _startPaymentCountdown(updatedOrder);
                Future.delayed(const Duration(milliseconds: 800), () {
                  if (mounted) _openRazorpay(updatedOrder);
                });
              }

              if (wasDelivered && !updatedOrder.hasCustomerRated) {
                Future.delayed(
                    const Duration(milliseconds: 600), _showRatingFlow);
              }
            }
          },
        )
        .subscribe();
  }

  // ── Acceptance countdown timer ───────────────────────────────────────────
  void _startAcceptanceCountdown(OrderModel order) {
    _acceptanceCountdownTimer?.cancel();
    // Calculate how many seconds remain from the stored deadline
    if (order.acceptanceDeadline != null) {
      final remaining = order.acceptanceDeadline!.difference(DateTime.now().toUtc()).inSeconds;
      _acceptanceSecondsLeft = remaining.clamp(0, 120);
    } else {
      _acceptanceSecondsLeft = 120;
    }
    _acceptanceCountdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        if (_acceptanceSecondsLeft > 0) {
          _acceptanceSecondsLeft--;
        } else {
          t.cancel();
        }
      });
    });
  }

  // ── Fetch sibling orders (same cart_group_id, up to 3 shops) ─────────────
  Future<void> _fetchSiblingOrders(String cartGroupId) async {
    try {
      final data = await _supabase
          .from('orders')
          .select('id, status, shop_id, cancelled_reason, rejection_message')
          .eq('cart_group_id', cartGroupId)
          .neq('id', widget.orderId);
      if (mounted) {
        setState(() => _siblingOrders = List<Map<String, dynamic>>.from(data as List));
      }
    } catch (_) {}
  }

  // ── Retry: create a fresh awaiting_acceptance copy of the current order ───
  Future<void> _retryOrder() async {
    if (_order == null || _isRetrying) return;
    setState(() => _isRetrying = true);
    try {
      final newDeadline = DateTime.now().toUtc().add(const Duration(minutes: 2));
      final response = await _supabase.from('orders').insert({
        'cart_group_id': _order!.cartGroupId,
        'shop_id': _order!.shopId,
        'customer_id': _order!.customerId,
        'status': 'awaiting_acceptance',
        'acceptance_deadline': newDeadline.toIso8601String(),
        'total_amount': _order!.totalAmount,
        'delivery_charges': _order!.deliveryCharges,
        'rider_earnings': _order!.riderEarnings,
        'platform_fee': _order!.platformFee,
        'address': _order!.address,
        'delivery_lat': _order!.deliveryLat,
        'delivery_lng': _order!.deliveryLng,
        'delivery_notes': _order!.deliveryNotes,
        'payment_method': _order!.paymentMethod,
        'payment_status': 'pending',
        'customer_phone': _order!.customerPhone,
        'shop_phone': _order!.shopPhone,
        'gst_item_total': _order!.gstItemTotal,
        'gst_delivery': _order!.gstDelivery,
        'gst_platform': _order!.gstPlatform,
        'enything_commission': _order!.enythingCommission,
        'seller_payout': _order!.sellerPayout,
        'gateway_deduction': _order!.gatewayDeduction,
        's9_5_gst_amount': _order!.s9_5GstAmount,
        'non_food_gst_amount': _order!.nonFoodGstAmount,
        'tcs_amount': _order!.tcsAmount,
        'grand_total_collected': _order!.grandTotalCollected,
        'gst_rate_snapshot': _order!.gstRateSnapshot,
        'estimated_distance_km': _order!.estimatedDistanceKm,
        'shop_prep_time_snapshot': _order!.shopPrepTimeSnapshot,
      }).select().single();

      // Copy order items
      final oldItems = await _supabase.from('order_items').select().eq('order_id', widget.orderId);
      if ((oldItems as List).isNotEmpty) {
        final newItems = oldItems.map((item) => {
          'order_id': response['id'],
          'product_id': item['product_id'],
          'product_name': item['product_name'],
          'quantity': item['quantity'],
          'price': item['price'],
          'weight_kg': item['weight_kg'],
        }).toList();
        await _supabase.from('order_items').insert(newItems);
      }

      if (mounted) {
        Navigator.pushReplacementNamed(
          context, AppRoutes.trackOrder,
          arguments: {'orderId': response['id']},
        );
      }
    } catch (e) {
      debugPrint('Retry order error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not retry: $e'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ));
        setState(() => _isRetrying = false);
      }
    }
  }

  // ── Retry: re-broadcast to riders (shop already accepted) ─────────────────
  Future<void> _retryFindRider() async {
    if (_order == null || _isRetrying) return;
    setState(() => _isRetrying = true);
    try {
      final newDeadline = DateTime.now().toUtc().add(const Duration(minutes: 2));
      await _supabase.from('orders').update({
        'status': 'awaiting_acceptance',
        'cancelled_reason': null,
        'seller_accepted': true,
        'partner_accepted': false,
        'acceptance_deadline': newDeadline.toIso8601String(),
      }).eq('id', widget.orderId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('🛵 Looking for a rider again…'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ));
        setState(() => _isRetrying = false);
      }
    } catch (e) {
      debugPrint('Retry rider error: $e');
      if (mounted) setState(() => _isRetrying = false);
    }
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
          .update({'status': 'cancelled', 'cancelled_reason': 'customer'})
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
      case 'awaiting_acceptance': return 0;
      case 'awaiting_payment':    return 1;
      case 'pending':             return 2;
      case 'confirmed':           return 3;
      case 'preparing':           return 4;
      case 'ready_for_pickup':    return 4;
      case 'picked_up':           return 5;
      case 'out_for_delivery':    return 6;
      case 'delivered':           return 7;
      default:                    return 0;
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

  String _statusSubtitle(bool isDelivered, bool isCancelled) {
    if (isCancelled) {
      switch (_order?.cancelledReason) {
        case 'shop_rejected':  return _order?.rejectionMessage?.isNotEmpty == true
            ? '"${_order!.rejectionMessage}"'
            : 'The shop declined your order. No payment was taken.';
        case 'no_rider':       return 'Shop was ready but no rider was available. No payment was taken.';
        case 'timeout':        return 'No response within 2 minutes. No payment was taken.';
        case 'customer':       return 'You cancelled this order. No payment was taken.';
        default:               return 'Your order has been cancelled. No payment was taken.';
      }
    }
    if (isDelivered) return 'Enjoy your order! Thank you 🎉';
    switch (_order?.status) {
      case 'awaiting_acceptance': return 'Shop & rider have ${(_acceptanceSecondsLeft ~/ 60).toString().padLeft(2, '0')}:${(_acceptanceSecondsLeft % 60).toString().padLeft(2, '0')} to accept — No charge yet!';
      case 'awaiting_payment':    return 'Both confirmed! Please complete payment now 💳';
      case 'pending':             return 'Waiting for shop & rider to accept...';
      case 'confirmed':           return 'Shop & rider confirmed — preparing soon!';
      case 'preparing':           return 'Shop is packing your order 📦';
      case 'ready_for_pickup':    return 'Order packed — rider picking up soon!';
      case 'picked_up':           return 'Rider has your order — on the way!';
      case 'out_for_delivery':    return 'Almost there! Rider is en-route 🛵';
      default:                    return 'Estimated delivery in 30-45 mins';
    }
  }

  // ── Razorpay Payment on TrackOrder page ──────────────────────────────────

  void _onPaymentSuccess(PaymentSuccessResponse response) {
    _verifyAndConfirmOrder(
      paymentId: response.paymentId ?? '',
      razorpayOrderId: response.orderId ?? '',
      signature: response.signature ?? '',
    );
  }

  void _onPaymentError(PaymentFailureResponse response) {
    setState(() => _isProcessingPayment = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Payment failed: ${response.message ?? "Unknown error"}'),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    setState(() => _isProcessingPayment = false);
  }

  void _startPaymentCountdown(OrderModel order) {
    _paymentCountdownTimer?.cancel();
    // Calculate seconds remaining from payment_deadline if available
    _paymentSecondsLeft = 600;
    _paymentCountdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        if (_paymentSecondsLeft > 0) {
          _paymentSecondsLeft--;
        } else {
          t.cancel();
        }
      });
    });
  }

  Future<void> _openRazorpay(OrderModel order) async {
    if (_isProcessingPayment) return;
    setState(() => _isProcessingPayment = true);
    try {
      final grandTotal = order.grandTotalCollected > 0
          ? order.grandTotalCollected
          : order.grandTotal;
      final amountInPaise = (grandTotal * 100).toInt();

      final razorpayKeyId = dotenv.maybeGet('RAZORPAY_KEY_ID') ?? '';
      final razorpayKeySecret = dotenv.maybeGet('RAZORPAY_KEY_SECRET') ?? '';

      if (razorpayKeyId.isEmpty || razorpayKeySecret.isEmpty) {
        throw Exception('Razorpay keys not configured');
      }

      final authString =
          base64Encode(utf8.encode('$razorpayKeyId:$razorpayKeySecret'));
      final response = await http.post(
        Uri.parse('https://api.razorpay.com/v1/orders'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Basic $authString',
        },
        body: jsonEncode({
          'amount': amountInPaise,
          'currency': 'INR',
          'receipt': 'enything_${order.id.substring(0, 8)}',
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Could not create payment order');
      }

      final data = jsonDecode(response.body);
      final razorpayOrderId = data['id'] as String;

      if (!mounted) {
        setState(() => _isProcessingPayment = false);
        return;
      }

      final auth = context.read<AuthProvider>();
      final razorpayKey = dotenv.maybeGet('RAZORPAY_KEY') ?? '';
      _razorpay.open(<String, dynamic>{
        'key': razorpayKey,
        'amount': amountInPaise,
        'currency': 'INR',
        'order_id': razorpayOrderId,
        'name': 'Enything',
        'description': 'Order Payment',
        'prefill': {
          'contact': (auth.user?.phone ?? '').isNotEmpty ? auth.user?.phone ?? '9999999999' : '9999999999',
          'email': (auth.user?.email ?? '').isNotEmpty ? auth.user?.email ?? 'user@enything.app' : 'user@enything.app',
          'name': auth.user?.fullName ?? '',
        },
        'theme': {'color': '#4C6EF5'},
      });
    } catch (e) {
      setState(() => _isProcessingPayment = false);
      debugPrint('Open Razorpay error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not open payment: $e'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<void> _verifyAndConfirmOrder({
    required String paymentId,
    required String razorpayOrderId,
    required String signature,
  }) async {
    try {
      final razorpayKeySecret = dotenv.maybeGet('RAZORPAY_KEY_SECRET') ?? '';
      final key = utf8.encode(razorpayKeySecret);
      final bytes = utf8.encode('$razorpayOrderId|$paymentId');
      final hmacSha256 = Hmac(sha256, key);
      final digest = hmacSha256.convert(bytes);
      final generatedSignature = digest.toString();

      if (generatedSignature != signature) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Payment verification failed. Contact support if money was deducted.'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 6),
          ));
        }
        setState(() => _isProcessingPayment = false);
        return;
      }

      // Signature verified — mark order as confirmed
      await _supabase.from('orders').update({
        'status': 'confirmed',
        'payment_status': 'captured',
        'razorpay_payment_id': paymentId,
        'razorpay_order_id': razorpayOrderId,
      }).eq('id', widget.orderId);

      _paymentCountdownTimer?.cancel();
      setState(() => _isProcessingPayment = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('💳 Payment confirmed! Shop is now preparing your order.'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      debugPrint('Verify payment error: $e');
      setState(() => _isProcessingPayment = false);
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
                      // Countdown ring for awaiting_acceptance

                      if (_order!.status == 'awaiting_acceptance')
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 90, height: 90,
                              child: TweenAnimationBuilder<double>(
                                tween: Tween<double>(begin: 1.0, end: _acceptanceSecondsLeft / 120.0),
                                duration: const Duration(milliseconds: 500),
                                builder: (_, v, __) => CircularProgressIndicator(
                                  value: v,
                                  strokeWidth: 4,
                                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              ),
                            ),
                            Container(
                              width: 70, height: 70,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '${(_acceptanceSecondsLeft ~/ 60).toString().padLeft(2, '0')}:${(_acceptanceSecondsLeft % 60).toString().padLeft(2, '0')}',
                                    style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text('left',
                                    style: GoogleFonts.outfit(
                                      color: Colors.white70, fontSize: 10,
                                    )),
                                ],
                              ),
                            ),
                          ],
                        )
                      else
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
                      // Per-party acceptance chips (awaiting_acceptance only)
                      if (_order!.status == 'awaiting_acceptance') ...[
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _acceptanceChip(
                              label: '🏪 Shop',
                              accepted: _order!.sellerAccepted,
                            ),
                            const SizedBox(width: 10),
                            _acceptanceChip(
                              label: '🛵 Rider',
                              accepted: _order!.partnerAccepted,
                            ),
                          ],
                        ),
                      ],
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

              // ── Back to Home (only for active orders) ─────────────────────
              if (!isCancelled)
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

              // ── PAY NOW BUTTON (when both seller & rider accepted) ────────
              if (_order!.status == 'awaiting_payment') ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0F9B58), Color(0xFF1DB954)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0F9B58).withValues(alpha: 0.4),
                        blurRadius: 16, offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Text('Shop & Rider Confirmed!', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '\u23f1 ${(_paymentSecondsLeft ~/ 60).toString().padLeft(2, '0')}:${(_paymentSecondsLeft % 60).toString().padLeft(2, '0')}',
                              style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('Complete your payment to confirm the order. Shop and rider are ready!', style: GoogleFonts.outfit(color: Colors.white.withValues(alpha: 0.9), fontSize: 12)),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isProcessingPayment ? null : () => _openRazorpay(_order!),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF0F9B58),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: _isProcessingPayment
                              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : Text('PAY NOW \u20b9${(_order!.grandTotalCollected > 0 ? _order!.grandTotalCollected : _order!.grandTotal).toStringAsFixed(0)}', style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 16)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // ── Sibling orders banner (multi-shop checkout, up to 3 shops) ─
              if (_siblingOrders.isNotEmpty) ...{
                const SizedBox(height: 16),
                ..._siblingOrders.map((sibling) {
                  final sibStatus = sibling['status'] as String? ?? '';
                  final isActive = sibStatus != 'cancelled' &&
                      sibStatus != 'seller_rejected' &&
                      sibStatus != 'partner_rejected';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GestureDetector(
                      onTap: () => Navigator.pushNamed(
                        context, AppRoutes.trackOrder,
                        arguments: {'orderId': sibling['id']},
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: isActive
                              ? AppColors.primary.withValues(alpha: isDark ? 0.18 : 0.08)
                              : AppColors.danger.withValues(alpha: isDark ? 0.12 : 0.06),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isActive
                                ? AppColors.primary.withValues(alpha: 0.35)
                                : AppColors.danger.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isActive ? Icons.store_rounded : Icons.store_mall_directory_outlined,
                              color: isActive ? AppColors.primary : AppColors.danger,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                isActive
                                    ? 'Your other shop order is active → tap to track'
                                    : 'Another shop order was also cancelled',
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isActive ? AppColors.primary : AppColors.danger,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: isActive ? AppColors.primary : AppColors.danger,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              },

              // ── Smart Cancellation Recovery Panel ─────────────────────────
              if (isCancelled) ...{
                const SizedBox(height: 8),
                _buildCancellationRecoveryPanel(isDark),
              },

              // ── Cancel button (only for awaiting_acceptance / pending) ────
              if (!isCancelled && (_order!.status == 'awaiting_acceptance' || _order!.status == 'pending')) ...[
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

  // ── Smart Cancellation Recovery Panel ───────────────────────────────────
  Widget _buildCancellationRecoveryPanel(bool isDark) {
    final reason = _order?.cancelledReason ?? 
        (_order?.status == 'seller_rejected' ? 'shop_rejected' : 'customer');

    String title;
    String body;
    List<Widget> actions;

    switch (reason) {
      case 'shop_rejected':
        title = '💬 What would you like to do?';
        body = _order?.rejectionMessage?.isNotEmpty == true
            ? 'The shop sent a message: "${_order!.rejectionMessage}"'
            : 'The shop was unable to accept your order.';
        actions = [
          _recoveryBtn(
            label: '🔄 Retry Same Shop',
            subtitle: 'Place the same order again with this shop',
            color: AppColors.primary,
            isDark: isDark,
            loading: _isRetrying,
            onTap: _retryOrder,
          ),
          const SizedBox(height: 10),
          _recoveryBtn(
            label: '🏪 Choose Different Shop',
            subtitle: 'Remove this shop\'s items from cart and search for alternatives',
            color: AppColors.accent,
            isDark: isDark,
            loading: false,
            onTap: () => Navigator.pushNamedAndRemoveUntil(
              context, AppRoutes.customerHome, (r) => false,
            ),
          ),
          const SizedBox(height: 10),
          _recoveryBtn(
            label: '🏠 Back to Home',
            subtitle: '',
            color: Colors.grey,
            isDark: isDark,
            loading: false,
            onTap: () => Navigator.pushNamedAndRemoveUntil(
              context, AppRoutes.customerHome, (r) => false,
            ),
          ),
        ];
        break;

      case 'no_rider':
        title = '🛵 No Rider Available';
        body = 'The shop accepted your order, but no rider was free to pick it up.';
        actions = [
          _recoveryBtn(
            label: '🔍 Find a Rider Again',
            subtitle: 'Re-broadcast to all nearby riders for 2 more minutes',
            color: AppColors.success,
            isDark: isDark,
            loading: _isRetrying,
            onTap: _retryFindRider,
          ),
          const SizedBox(height: 10),
          _recoveryBtn(
            label: '🔄 Retry Full Order',
            subtitle: 'Notify both shop & rider again',
            color: AppColors.primary,
            isDark: isDark,
            loading: false,
            onTap: _retryOrder,
          ),
          const SizedBox(height: 10),
          _recoveryBtn(
            label: '🏠 Back to Home',
            subtitle: '',
            color: Colors.grey,
            isDark: isDark,
            loading: false,
            onTap: () => Navigator.pushNamedAndRemoveUntil(
              context, AppRoutes.customerHome, (r) => false,
            ),
          ),
        ];
        break;

      case 'timeout':
        title = '⏱ Order Expired';
        body = 'Neither the shop nor a rider responded within 2 minutes.';
        actions = [
          _recoveryBtn(
            label: '🔄 Try Again',
            subtitle: 'Re-send the same order — no extra charge',
            color: AppColors.primary,
            isDark: isDark,
            loading: _isRetrying,
            onTap: _retryOrder,
          ),
          const SizedBox(height: 10),
          _recoveryBtn(
            label: '🏠 Back to Home',
            subtitle: '',
            color: Colors.grey,
            isDark: isDark,
            loading: false,
            onTap: () => Navigator.pushNamedAndRemoveUntil(
              context, AppRoutes.customerHome, (r) => false,
            ),
          ),
        ];
        break;

      default: // 'customer' or unknown
        title = '✅ Order Cancelled';
        body = 'You cancelled this order. No payment was taken.';
        actions = [
          _recoveryBtn(
            label: '🔄 Retry Full Order',
            subtitle: 'Place this order again',
            color: AppColors.primary,
            isDark: isDark,
            loading: _isRetrying,
            onTap: _retryOrder,
          ),
          const SizedBox(height: 10),
          _recoveryBtn(
            label: '🏠 Back to Home',
            subtitle: '',
            color: Colors.grey,
            isDark: isDark,
            loading: false,
            onTap: () => Navigator.pushNamedAndRemoveUntil(
              context, AppRoutes.customerHome, (r) => false,
            ),
          ),
        ];
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.black.withValues(alpha: 0.06),
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
          Text(title,
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : AppColors.textPrimary,
              )),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(body,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  color: isDark ? Colors.white60 : AppColors.textSecondary,
                )),
          ],
          const SizedBox(height: 16),
          ...actions,
        ],
      ),
    );
  }

  Widget _recoveryBtn({
    required String label,
    required String subtitle,
    required Color color,
    required bool isDark,
    required bool loading,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.15 : 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: isDark ? 0.4 : 0.3)),
        ),
        child: Row(
          children: [
            if (loading)
              SizedBox(
                height: 16, width: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: color,
                ),
              )
            else
              Icon(Icons.arrow_forward_ios_rounded, color: color, size: 14),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: color,
                      )),
                  if (subtitle.isNotEmpty)
                    Text(subtitle,
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          color: color.withValues(alpha: 0.7),
                        )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Acceptance status chip ────────────────────────────────────────────────
  Widget _acceptanceChip({required String label, required bool accepted}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: accepted
            ? Colors.white.withValues(alpha: 0.25)
            : Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: accepted ? Colors.white : Colors.white30,
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            accepted ? Icons.check_circle_rounded : Icons.hourglass_bottom_rounded,
            color: accepted ? Colors.white : Colors.white54,
            size: 13,
          ),
          const SizedBox(width: 5),
          Text(
            '$label ${accepted ? "✓" : "…"}',
            style: GoogleFonts.outfit(
              color: accepted ? Colors.white : Colors.white60,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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
                zoom: _order?.status == 'awaiting_acceptance' ? 15.5 : 16.5,
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
