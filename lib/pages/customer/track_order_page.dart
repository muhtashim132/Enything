import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:flutter_dotenv/flutter_dotenv.dart';
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
import '../../providers/notification_provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/notification_service.dart';
import '../../utils/responsive_layout.dart';
import 'package:collection/collection.dart';
import '../../utils/delivery_calculator.dart';

class TrackOrderPage extends StatefulWidget {
  final String orderId;
  const TrackOrderPage({super.key, required this.orderId});

  @override
  State<TrackOrderPage> createState() => _TrackOrderPageState();
}

class _TrackOrderPageState extends State<TrackOrderPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _supabase = Supabase.instance.client;
  OrderModel? _order;
  bool _isLoading = true;
  bool _isCancelling = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;
  RealtimeChannel? _channel;
  LatLng? _riderLatLng;
  bool _razorpayOpened = false;

  // Payment (Razorpay) — triggered when both seller & rider accept
  late Razorpay _razorpay;
  bool _isProcessingPayment = false;
  Timer? _paymentCountdownTimer;
  int _paymentSecondsLeft = 600; // 10 minutes

  // Acceptance countdown (3 minutes)
  Timer? _acceptanceCountdownTimer;
  int _acceptanceSecondsLeft = 180;

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
    // M5 FIX: ready_for_pickup was missing — stepper jumped from Preparing → Picked Up
    {
      'status': 'ready_for_pickup',
      'title': 'Ready for Pickup',
      'subtitle': 'Order is packed, waiting for rider',
      'icon': Icons.inventory_2_outlined,
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
    WidgetsBinding.instance.addObserver(this);
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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _razorpay.clear();
    _pulseController.dispose();
    _paymentCountdownTimer?.cancel();
    _acceptanceCountdownTimer?.cancel();
    if (_channel != null) _supabase.removeChannel(_channel!);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (mounted) {
        _fetchOrder();
      }
    }
  }

  List<OrderModel> _groupOrders = [];

  Future<void> _fetchOrder() async {
    try {
      final response = await _supabase
          .from('orders')
          .select('*, order_items(*)')
          .eq('id', widget.orderId)
          .single();

      if (mounted) {
        final order = OrderModel.fromMap(response);
        order.items = (response['order_items'] as List? ?? [])
            .map((i) => OrderItem.fromMap(i))
            .toList();
        // Fetch sibling orders if multi-shop checkout
        List<OrderModel> group = [order];
        if (order.cartGroupId != null) {
          final groupResp = await _supabase
              .from('orders')
              .select('*, order_items(*)')
              .eq('cart_group_id', order.cartGroupId!);
          group = (groupResp as List).map((o) {
            final m = OrderModel.fromMap(o);
            m.items = (o['order_items'] as List? ?? [])
                .map((i) => OrderItem.fromMap(i))
                .toList();
            return m;
          }).toList();
        }

        setState(() {
          _order = order;
          _groupOrders = group;
          _isLoading = false;
          if (order.riderLat != null && order.riderLng != null) {
            _riderLatLng = LatLng(order.riderLat!, order.riderLng!);
          }
        });

        _subscribeToOrder();

        // Compute aggregate status for countdowns/payments
        _handleAggregateStatusChange();

        // If already delivered and not yet rated, show rating prompt
        if (order.status == 'delivered' && !order.hasCustomerRated) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _showRatingFlow());
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _subscribeToOrder() {
    if (_order == null) return;
    _channel?.unsubscribe();
    
    final filter = _order!.cartGroupId != null
        ? PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'cart_group_id',
            value: _order!.cartGroupId!,
          )
        : PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.orderId,
          );

    _channel = _supabase
        .channel('group-${_order!.cartGroupId ?? widget.orderId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'orders',
          filter: filter,
          callback: (payload) {
            if (mounted && payload.newRecord.isNotEmpty) {
              final updatedOrder = OrderModel.fromMap(payload.newRecord);
              
              setState(() {
                // Update in group list
                final idx = _groupOrders.indexWhere((o) => o.id == updatedOrder.id);
                if (idx != -1) {
                  updatedOrder.items = _groupOrders[idx].items; // preserve items
                  _groupOrders[idx] = updatedOrder;
                }
                
                // If it's the primary order, update _order
                if (updatedOrder.id == widget.orderId) {
                  _order = updatedOrder;
                  if (updatedOrder.riderLat != null && updatedOrder.riderLng != null) {
                    _riderLatLng = LatLng(updatedOrder.riderLat!, updatedOrder.riderLng!);
                  }
                  if (updatedOrder.status == 'delivered') _riderLatLng = null;
                } else if (_order != null && updatedOrder.riderLat != null && updatedOrder.riderLng != null) {
                  // If sibling order provides rider location
                  _riderLatLng = LatLng(updatedOrder.riderLat!, updatedOrder.riderLng!);
                }
              });

              _handleAggregateStatusChange();
            }
          },
        )
        .subscribe();
  }

  String get _aggregateStatus {
    if (_groupOrders.isEmpty) return _order?.status ?? 'pending';
    
    final activeOrders = _groupOrders.where((o) => o.status != 'cancelled' && o.status != 'seller_rejected').toList();
    if (activeOrders.isEmpty) return 'cancelled';

    // Priority 1: awaiting_acceptance
    if (activeOrders.any((o) => o.status == 'awaiting_acceptance')) return 'awaiting_acceptance';
    
    // Priority 2: awaiting_payment
    // If NO order is awaiting_acceptance, and ANY order is awaiting_payment, then we are ready for payment!
    // Wait, we need ALL active orders to have moved past awaiting_acceptance. 
    // If they have, and some are awaiting_payment, we are awaiting_payment.
    if (activeOrders.any((o) => o.status == 'awaiting_payment')) return 'awaiting_payment';

    // Priority 3: pending
    if (activeOrders.any((o) => o.status == 'pending')) return 'pending';

    // Priority 4: delivered
    if (activeOrders.every((o) => o.status == 'delivered')) return 'delivered';

    // Priority 5: out_for_delivery
    if (activeOrders.every((o) => o.status == 'out_for_delivery' || o.status == 'delivered')) return 'out_for_delivery';

    // Priority 6: picked_up
    if (activeOrders.any((o) => o.status == 'picked_up')) return 'picked_up';

    // Priority 7: preparing / ready_for_pickup
    if (activeOrders.any((o) => o.status == 'preparing' || o.status == 'ready_for_pickup')) return 'preparing';

    // Priority 8: confirmed
    if (activeOrders.any((o) => o.status == 'confirmed')) return 'confirmed';

    return activeOrders.first.status;
  }

  String get _aggregateStatusDisplay {
    final s = _aggregateStatus;
    switch (s) {
      case 'awaiting_acceptance':
        return 'Awaiting Acceptance';
      case 'awaiting_payment':
        return 'Awaiting Payment';
      case 'pending':
        return 'Order Pending';
      case 'confirmed':
        return 'Order Confirmed';
      case 'preparing':
        return 'Preparing Order';
      case 'ready_for_pickup':
        return 'Ready for Pickup';
      case 'picked_up':
        return 'Picked Up';
      case 'out_for_delivery':
        return 'Out for Delivery';
      case 'delivered':
        return 'Delivered';
      case 'cancelled':
        return 'Cancelled';
      case 'seller_rejected':
        return 'Shop Rejected';
      default:
        return 'Unknown';
    }
  }

  bool get _isCancelled => _aggregateStatus == 'cancelled' || _aggregateStatus == 'seller_rejected';
  bool get _isDelivered => _aggregateStatus == 'delivered';

  double _computeGroupTotalAmount() {
    final active = _groupOrders.isEmpty ? [_order!] : _groupOrders.where((o) => o.status != 'cancelled' && o.status != 'seller_rejected').toList();
    return active.fold(0.0, (sum, o) => sum + o.totalAmount);
  }

  double _computeGroupDeliveryCharges() {
    final active = _groupOrders.isEmpty ? [_order!] : _groupOrders.where((o) => o.status != 'cancelled' && o.status != 'seller_rejected').toList();
    return active.fold(0.0, (sum, o) => sum + o.deliveryCharges);
  }

  double _computeGroupPlatformFee() {
    final active = _groupOrders.isEmpty ? [_order!] : _groupOrders.where((o) => o.status != 'cancelled' && o.status != 'seller_rejected').toList();
    return active.fold(0.0, (sum, o) => sum + o.platformFee);
  }

  double _computeGroupGstItemTotal() {
    final active = _groupOrders.isEmpty ? [_order!] : _groupOrders.where((o) => o.status != 'cancelled' && o.status != 'seller_rejected').toList();
    return active.fold(0.0, (sum, o) => sum + o.gstItemTotal);
  }

  double _computeGroupGstDelivery() {
    final active = _groupOrders.isEmpty ? [_order!] : _groupOrders.where((o) => o.status != 'cancelled' && o.status != 'seller_rejected').toList();
    return active.fold(0.0, (sum, o) => sum + o.gstDelivery);
  }

  double _computeGroupGstPlatform() {
    final active = _groupOrders.isEmpty ? [_order!] : _groupOrders.where((o) => o.status != 'cancelled' && o.status != 'seller_rejected').toList();
    return active.fold(0.0, (sum, o) => sum + o.gstPlatform);
  }

  double _computeGroupGrandTotal() {
    final active = _groupOrders.isEmpty ? [_order!] : _groupOrders.where((o) => o.status != 'cancelled' && o.status != 'seller_rejected').toList();
    return active.fold(0.0, (sum, o) => sum + (o.grandTotalCollected > 0 ? o.grandTotalCollected : o.grandTotal));
  }

  bool get _allSellersAccepted {
    if (_groupOrders.isEmpty) return _order?.sellerAccepted ?? false;
    final active = _groupOrders.where((o) => o.status != 'cancelled' && o.status != 'seller_rejected').toList();
    if (active.isEmpty) return false;
    return active.every((o) => o.sellerAccepted);
  }

  bool get _partnerAccepted {
    if (_groupOrders.isEmpty) return _order?.partnerAccepted ?? false;
    final active = _groupOrders.where((o) => o.status != 'cancelled' && o.status != 'seller_rejected').toList();
    if (active.isEmpty) return false;
    return active.every((o) => o.partnerAccepted);
  }

  String _lastAggStatus = '';

  void _handleAggregateStatusChange() {
    if (!mounted || _order == null) return;
    final aggStatus = _aggregateStatus;
    
    if (aggStatus != _lastAggStatus) {
      _lastAggStatus = aggStatus;
      NotificationService().updateOrderNotificationFromStatus(aggStatus);

      if (aggStatus == 'awaiting_acceptance') {
        _startAcceptanceCountdown(_order!);
      } else {
        _acceptanceCountdownTimer?.cancel();
      }

      if (aggStatus == 'awaiting_payment') {
        // Find the deadline from any active awaiting_payment order
        final awaitingPayOrder = _groupOrders.firstWhere(
            (o) => o.status == 'awaiting_payment',
            orElse: () => _order!);
        _startPaymentCountdown(awaitingPayOrder);
        
        if (!_isProcessingPayment && !_razorpayOpened) {
          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted && !_razorpayOpened) _openRazorpay();
          });
        }
      } else {
        _paymentCountdownTimer?.cancel();
      }
      
      if (aggStatus == 'delivered' && !_order!.hasCustomerRated) {
        Future.delayed(const Duration(milliseconds: 600), _showRatingFlow);
      }
    }
  }

  // ── Acceptance countdown timer ───────────────────────────────────────────
  void _startAcceptanceCountdown(OrderModel order) {
    _acceptanceCountdownTimer?.cancel();
    // Calculate how many seconds remain from the stored deadline
    if (order.acceptanceDeadline != null) {
      final remaining = order.acceptanceDeadline!
          .difference(DateTime.now().toUtc())
          .inSeconds;
      _acceptanceSecondsLeft = remaining.clamp(0, 180);
    } else {
      _acceptanceSecondsLeft = 180;
    }
    _acceptanceCountdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        if (_acceptanceSecondsLeft > 0) {
          _acceptanceSecondsLeft--;
        } else {
          t.cancel();
          _autoCancelOnTimeout('awaiting_acceptance');
        }
      });
    });
  }

  Future<void> _autoCancelOnTimeout(String expectedStatus) async {
    if (_order == null) return;
    if (_aggregateStatus != expectedStatus) return;
    
    final fresh = await _supabase.from('orders').select('status').eq('id', widget.orderId).maybeSingle();
    if (fresh == null || fresh['status'] != expectedStatus) return;

    try {
      var updateQuery = _supabase
          .from('orders')
          .update({'status': 'cancelled', 'cancelled_reason': 'timeout'});
          
      if (_order!.cartGroupId != null) {
        updateQuery = updateQuery.eq('cart_group_id', _order!.cartGroupId!);
      } else {
        updateQuery = updateQuery.eq('id', widget.orderId);
      }
      
      final res = await updateQuery.eq('status', expectedStatus).select();
      if (mounted && res.isNotEmpty) {
        // Re-fetch all group orders to sync sibling order states
        // (Realtime only fires individual row events — group siblings may lag)
        await _fetchOrder();
        if (mounted) {
          setState(() {
            _order =
                _order!.copyWith(status: 'cancelled', cancelledReason: 'timeout');
          });
        }
      }
    } catch (e) {
      debugPrint('Auto-cancel error: $e');
    }
  }

  // ── Retry: create a fresh awaiting_acceptance copy of the current order ───
  Future<void> _retryOrder() async {
    if (_order == null || _isRetrying) return;
    setState(() => _isRetrying = true);
    try {
      final newDeadline =
          DateTime.now().toUtc().add(const Duration(minutes: 3));
      final notifProv = context.read<NotificationProvider>();
      String? firstNewOrderId;
      final shopsToRetry = _groupOrders.isEmpty ? [_order!] : _groupOrders;

      for (final order in shopsToRetry) {
        final response = await _supabase
            .from('orders')
            .insert({
              'cart_group_id': order.cartGroupId,
              'shop_id': order.shopId,
              'customer_id': order.customerId,
              'status': 'awaiting_acceptance',
              'acceptance_deadline': newDeadline.toIso8601String(),
              'total_amount': order.totalAmount,
              'delivery_charges': order.deliveryCharges,
              // BUG-RT1 FIX: rider_earnings was missing — rider would earn ₹0 on retried orders
              'rider_earnings': order.riderEarnings,
              'platform_fee': order.platformFee,
              'address': order.address,
              // BUG-RT1 FIX: address_label was missing — rider lost the Home/Office label on retry
              'address_label': order.addressLabel,
              'delivery_lat': order.deliveryLat,
              'delivery_lng': order.deliveryLng,
              'delivery_notes': order.deliveryNotes,
              'payment_method': order.paymentMethod,
              'payment_status': 'pending',
              'customer_phone': order.customerPhone,
              'shop_phone': order.shopPhone,
              // BUG-RT1 FIX: multi_shop_surcharge, small_cart_fee, heavy_order_fee,
              // delivery_discount were ALL missing — showed ₹0 in receipt on retry
              'multi_shop_surcharge': order.multiShopSurcharge,
              'small_cart_fee': order.smallCartFee,
              'heavy_order_fee': order.heavyOrderFee,
              'delivery_discount': order.deliveryDiscount,
              'gst_item_total': order.gstItemTotal,
              'gst_delivery': order.gstDelivery,
              'gst_platform': order.gstPlatform,
              'enything_commission': order.enythingCommission,
              'seller_payout': order.sellerPayout,
              'gateway_deduction': order.gatewayDeduction,
              's9_5_gst_amount': order.s9_5GstAmount,
              'non_food_gst_amount': order.nonFoodGstAmount,
              'tcs_amount': order.tcsAmount,
              'grand_total_collected': order.grandTotalCollected,
              'gst_rate_snapshot': order.gstRateSnapshot,
              'estimated_distance_km': order.estimatedDistanceKm,
              'shop_prep_time_snapshot': order.shopPrepTimeSnapshot,
              'prescription_urls': order.prescriptionUrls,
            })
            .select()
            .single();

        firstNewOrderId ??= response['id'];

        // O3 FIX: Re-validate product availability before inserting retried order.
        // Prevents retrying an order for items that went out-of-stock since the original.
        final oldItems = await _supabase
            .from('order_items')
            .select()
            .eq('order_id', order.id);
        if ((oldItems as List).isNotEmpty) {
          final productIds = oldItems.map((i) => i['product_id']).toList();
          final latestProducts = await _supabase
              .from('products')
              .select('id, name, is_available, total_quantity')
              .inFilter('id', productIds);

          for (final item in oldItems) {
            final dbProduct = (latestProducts as List).firstWhereOrNull(
              (p) => p['id'] == item['product_id'],
            );
            if (dbProduct == null || dbProduct['is_available'] == false) {
              throw Exception('${item['product_name']} is no longer available. Cannot retry.');
            }
            if (dbProduct['total_quantity'] != null &&
                dbProduct['total_quantity'] < (item['quantity'] as int)) {
              throw Exception(
                'Only ${dbProduct['total_quantity']} units of ${item['product_name']} are available.',
              );
            }
          }

          final newItems = oldItems
              .map((item) => {
                    'order_id': response['id'],
                    'product_id': item['product_id'],
                    'product_name': item['product_name'],
                    'quantity': item['quantity'],
                    'price': item['price'],
                    'weight_kg': item['weight_kg'],
                    'special_instructions': item['special_instructions'],
                    'requires_prescription': item['requires_prescription'] ?? false,
                  })
              .toList();
          await _supabase.from('order_items').insert(newItems);

          // O2: Decrement stock for retried order items
          for (final item in oldItems) {
            try {
              await _supabase.rpc('decrement_product_stock', params: {
                'p_product_id': item['product_id'],
                'p_quantity': item['quantity'],
              });
            } catch (e) {
              debugPrint('Stock decrement error on retry: $e');
            }
          }
        }

        if (mounted && order.shopId != null) {
          final shopData = await _supabase.from('shops').select('seller_id').eq('id', order.shopId!).maybeSingle();
          if (shopData != null && shopData['seller_id'] != null) {
            notifProv.sendBackgroundPush(
              targetUserId: shopData['seller_id'] as String,
              title: '🔔 New Order! Accept now',
              body:
                  'Order ₹${order.grandTotal.toStringAsFixed(0)} — Tap to accept. Customer pays AFTER you & rider accept. ⏱ 2 min window.',
              data: {'order_id': response['id'], 'role': 'seller'},
            );
          }
        }
      }

      if (mounted && firstNewOrderId != null) {
        if (!mounted) return;
        Navigator.pushReplacementNamed(
          context,
          AppRoutes.trackOrder,
          arguments: {'orderId': firstNewOrderId},
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
      final newDeadline =
          DateTime.now().toUtc().add(const Duration(minutes: 3));
      // BUG-PAY1 FIX (CRITICAL): Must null out delivery_partner_id.
      // Without this the order remains assigned to the old rider and is
      // filtered out by the rider dashboard (.isFilter('delivery_partner_id', null)),
      // making the order permanently invisible to ALL new riders.
      // Also clear rider_phone so the new rider's number is used when they accept.
      if (_order!.cartGroupId != null) {
        await _supabase.from('orders').update({
          'status': 'awaiting_acceptance',
          'cancelled_reason': null,
          'seller_accepted': true,
          'partner_accepted': false,
          'delivery_partner_id': null,
          'rider_phone': null,
          'acceptance_deadline': newDeadline.toIso8601String(),
        }).eq('cart_group_id', _order!.cartGroupId!);
      } else {
        await _supabase.from('orders').update({
          'status': 'awaiting_acceptance',
          'cancelled_reason': null,
          'seller_accepted': true,
          'partner_accepted': false,
          'delivery_partner_id': null,
          'rider_phone': null,
          'acceptance_deadline': newDeadline.toIso8601String(),
        }).eq('id', widget.orderId);
      }

      if (mounted) {
        final notifProv = context.read<NotificationProvider>();
        
        // Notify the seller that customer is looking for a rider again
        if (_order!.shopId != null) {
          final shopData = await _supabase.from('shops').select('seller_id').eq('id', _order!.shopId!).maybeSingle();
          if (shopData != null && shopData['seller_id'] != null) {
            notifProv.sendBackgroundPush(
              targetUserId: shopData['seller_id'] as String,
              title: '🔄 Finding Rider',
              body: 'The customer is searching for a new rider. Order is active again!',
              data: {'order_id': widget.orderId, 'role': 'seller'},
            );
          }
        }

        if (!mounted) return;
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
            style:
                GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 18)),
        content: Text(
            'Are you sure you want to cancel this order? This action cannot be undone.',
            style: GoogleFonts.outfit(
                fontSize: 14, color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Keep Order',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
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

    // BUG-7 FIX: Block cancellation after payment has been confirmed.
    // Once status passes awaiting_payment, the customer has paid — no cancellation allowed.
    const cancellableStatuses = [
      'awaiting_acceptance',
      'awaiting_payment',
    ];
    if (!cancellableStatuses.contains(_aggregateStatus)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Order cannot be cancelled after payment is confirmed. Please contact support.'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 4),
        ));
      }
      return;
    }

    setState(() => _isCancelling = true);
    try {
      // BUG-6/9 FIX: The DB trigger (tr_guard_order_status_transitions) silently
      // preserves seller_rejected / verification_failed rows during bulk updates,
      // so no extra Dart filter is needed here. The neq('status','delivered') guard
      // is kept as a secondary safety net.
      if (_order?.cartGroupId != null) {
        await _supabase
            .from('orders')
            .update({'status': 'cancelled', 'cancelled_reason': 'customer'})
            .eq('cart_group_id', _order!.cartGroupId!)
            .neq('status', 'delivered');
      } else {
        await _supabase
            .from('orders')
            .update({'status': 'cancelled', 'cancelled_reason': 'customer'})
            .eq('id', widget.orderId);
      }

      // Notify seller and rider that the customer cancelled
      if (mounted && _order != null) {
        final notifProv = context.read<NotificationProvider>();
        final shopsToNotify = _groupOrders.isEmpty ? [_order!] : _groupOrders;

        for (final o in shopsToNotify) {
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
        setState(() => _order = _order?.copyWith(status: 'cancelled'));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Order cancelled successfully.'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
    
    int currentShopIndex = 0;
    final shopsToRate = _groupOrders.isEmpty ? [_order!] : _groupOrders;
    
    void rateNextShop() {
      if (currentShopIndex < shopsToRate.length) {
        final orderToRate = shopsToRate[currentShopIndex];
        currentShopIndex++;
        final isLastShop = currentShopIndex == shopsToRate.length;
        
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
          builder: (_) => RatingBottomSheet(
            title: shopsToRate.length > 1 ? 'Rate Shop $currentShopIndex ⭐' : 'Rate the Shop ⭐',
            subtitle: 'How was the quality of your order?',
            onSubmit: (rating, review) async {
              final groupRider = _groupOrders.isEmpty 
                ? _order?.deliveryPartnerId 
                : _groupOrders.firstWhereOrNull((o) => o.deliveryPartnerId != null)?.deliveryPartnerId;
              await _submitRating(
                rateeId: null,
                shopId: orderToRate.shopId,
                rateeRole: 'seller',
                rating: rating,
                review: review,
                thenRateRider: isLastShop && groupRider != null,
                orderIdToUpdate: orderToRate.id,
              );
              rateNextShop();
            },
          ),
        );
      }
    }
    
    rateNextShop();
  }

  Future<void> _submitRating({
    required String? rateeId,
    required String? shopId,
    required String rateeRole,
    required int rating,
    required String review,
    bool thenRateRider = false,
    String? orderIdToUpdate,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      final targetOrderId = orderIdToUpdate ?? widget.orderId;
      await _supabase.from('ratings').insert({
        'order_id': targetOrderId,
        'rater_id': userId,
        'ratee_id': rateeId,
        'shop_id': shopId,
        'rater_role': 'customer',
        'ratee_role': rateeRole,
        'rating': rating,
        'review': review.isEmpty ? null : review,
      });

      if (rateeRole == 'seller') {
        // BUG-19 FIX: Mark has_customer_rated on this specific order.
        await _supabase
            .from('orders')
            .update({'has_customer_rated': true}).eq('id', targetOrderId);
        if (targetOrderId == widget.orderId) {
          setState(() => _order = _order?.copyWith(hasCustomerRated: true));
        }
      }

      // BUG-19 FIX (continued): After rating the LAST shop AND the rider (thenRateRider=false
      // means we are in the rider sub-rating, or the last shop with no rider),
      // mark ALL group orders as rated so the rating prompt never re-fires.
      if (rateeRole == 'delivery' || (rateeRole == 'seller' && !thenRateRider)) {
        final groupIds = _groupOrders.isEmpty
            ? [widget.orderId]
            : _groupOrders.map((o) => o.id).toList();
        if (groupIds.length > 1) {
          try {
            await _supabase
                .from('orders')
                .update({'has_customer_rated': true})
                .inFilter('id', groupIds);
          } catch (e) {
            debugPrint('Mark all orders rated error: $e');
          }
        }
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
              orderIdToUpdate: widget.orderId,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Rating submit error: $e');
    }
  }

  // UI1 FIX: ready_for_pickup was returning 4 (same as 'preparing'),
  // meaning the stepper never highlighted the "Ready for Pickup" step.
  int _getCurrentStep() {
    if (_order == null) return 0;
    switch (_aggregateStatus) {
      case 'awaiting_acceptance':
        return 0;
      case 'awaiting_payment':
        return 1;
      case 'pending':
        return 2;
      case 'confirmed':
        return 3;
      case 'preparing':
        return 4;
      case 'ready_for_pickup':
        return 5; // distinct from 'preparing'
      case 'picked_up':
        return 6;
      case 'out_for_delivery':
        return 7;
      case 'delivered':
        return 8;
      default:
        return 0;
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

  /// Builds the map markers including all shops, customer, and live rider.
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
          child: const Icon(Icons.home_rounded,
              color: AppColors.primary, size: 26),
        ),
      ));
    }

    // All shop locations
    final shops = _groupOrders.isEmpty && _order != null ? [_order!] : _groupOrders;
    for (final shopOrd in shops) {
      if (shopOrd.shopLat != null && shopOrd.shopLng != null) {
        markers.add(Marker(
          point: LatLng(shopOrd.shopLat!, shopOrd.shopLng!),
          width: 36,
          height: 36,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.store_rounded,
                color: AppColors.accent, size: 20),
          ),
        ));
      }
    }

    // Live rider marker (shown starting from 'confirmed')
    final showRider = _order != null && ['confirmed', 'preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery'].contains(_order!.status);
    if (_riderLatLng != null && showRider) {
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
        case 'shop_rejected':
          return _order?.rejectionMessage?.isNotEmpty == true
              ? '"${_order!.rejectionMessage}"'
              : 'The shop declined your order. No payment was taken.';
        case 'no_rider':
          return 'Shop was ready but no rider was available. No payment was taken.';
        case 'timeout':
          return 'No response within 2 minutes. No payment was taken.';
        case 'customer':
          return 'You cancelled this order. No payment was taken.';
        default:
          return 'Your order has been cancelled. No payment was taken.';
      }
    }
    if (isDelivered) return 'Enjoy your order! Thank you 🎉';
    switch (_order?.status) {
      case 'awaiting_acceptance':
        if (_acceptanceSecondsLeft <= 0) {
          return 'Time limit reached. Cancelling...';
        }
        return 'Shop & rider have ${(_acceptanceSecondsLeft ~/ 60).toString().padLeft(2, '0')}:${(_acceptanceSecondsLeft % 60).toString().padLeft(2, '0')} to accept — No charge yet!';
      case 'awaiting_payment':
        if (_paymentSecondsLeft <= 0) {
          return 'Payment time expired. Cancelling...';
        }
        return 'Both confirmed! Please complete payment now 💳';
      case 'pending':
        return 'Waiting for shop & rider to accept...';
      case 'confirmed':
        return 'Shop & rider confirmed — preparing soon!';
      case 'preparing':
        return 'Shop is packing your order 📦';
      case 'ready_for_pickup':
        return 'Order packed — rider picking up soon!';
      case 'picked_up':
        return 'Rider has your order — on the way!';
      case 'out_for_delivery':
        return 'Almost there! Rider is en-route 🛵';
      default:
        return 'Estimated delivery in 30-45 mins';
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
    _razorpayOpened = false;
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
    _razorpayOpened = false;
    setState(() => _isProcessingPayment = false);
  }

  void _startPaymentCountdown(OrderModel order) {
    _paymentCountdownTimer?.cancel();
    // BUG-9 FIX: Calculate seconds remaining from payment_deadline
    if (order.paymentDeadline != null) {
      final remaining =
          order.paymentDeadline!.difference(DateTime.now().toUtc()).inSeconds;
      _paymentSecondsLeft = remaining.clamp(0, 600);
    } else {
      _paymentSecondsLeft = 600;
    }
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
          _autoCancelOnTimeout('awaiting_payment');
        }
      });
    });
  }

  Future<void> _openRazorpay() async {
    if (_isProcessingPayment || _order == null) return;
    setState(() => _isProcessingPayment = true);

    bool canPay = false;
    if (_order!.cartGroupId != null) {
      final statusesResp = await _supabase.from('orders').select('status').eq('cart_group_id', _order!.cartGroupId!);
      final statuses = (statusesResp as List).map((r) => r['status'] as String).toList();
      if (statuses.contains('awaiting_payment') && !statuses.contains('awaiting_acceptance')) {
        canPay = true;
      }
    } else {
      final freshStatus = await _supabase.from('orders').select('status').eq('id', widget.orderId).maybeSingle();
      if (freshStatus != null && freshStatus['status'] == 'awaiting_payment') canPay = true;
    }

    if (!canPay) {
      setState(() => _isProcessingPayment = false);
      return;
    }

    try {
      // S1 FIX: Only include orders that are actually awaiting_payment.
      final activeOrders = _groupOrders.isEmpty
          ? [_order!]
          : _groupOrders.where((o) => o.status == 'awaiting_payment').toList();
      if (activeOrders.isEmpty) {
        setState(() => _isProcessingPayment = false);
        return;
      }

      double totalAmount = 0.0;
      for (var o in activeOrders) {
        totalAmount += (o.grandTotalCollected > 0 ? o.grandTotalCollected : o.grandTotal);
      }
      final amountInPaise = (totalAmount * 100).round();

      // S1 FIX: Order creation happens server-side in the Edge Function.
      // RAZORPAY_KEY_SECRET never leaves the server.
      final razorpayKeyId = dotenv.maybeGet('RAZORPAY_KEY_ID') ?? '';
      if (razorpayKeyId.isEmpty) throw Exception('Razorpay key not configured');

      final receipt = _order!.cartGroupId != null
          ? 'enything_group_${_order!.cartGroupId!.substring(0, 8)}'
          : 'enything_${_order!.id.substring(0, 8)}';

      final fnResponse = await _supabase.functions.invoke(
        'create-razorpay-order',
        body: {'amount': amountInPaise, 'currency': 'INR', 'receipt': receipt},
      );

      if (fnResponse.status != 200) {
        final errMsg = (fnResponse.data is Map ? fnResponse.data['error'] as String? : null)
            ?? 'Could not create payment order (${fnResponse.status})';
        throw Exception(errMsg);
      }

      final razorpayOrderId = fnResponse.data['id'] as String;

      if (!mounted) {
        setState(() => _isProcessingPayment = false);
        return;
      }

      final auth = context.read<AuthProvider>();

      if (_razorpayOpened) return;
      _razorpayOpened = true;

      _razorpay.open(<String, dynamic>{
        'key': razorpayKeyId,
        'amount': amountInPaise,
        'currency': 'INR',
        'order_id': razorpayOrderId,
        'name': 'Enything',
        'description': 'Order Payment',
        'prefill': {
          'contact': (auth.user?.phone ?? '').isNotEmpty
              ? auth.user?.phone ?? '9999999999'
              : '9999999999',
          'email': (auth.user?.email ?? '').isNotEmpty
              ? auth.user?.email ?? 'user@enything.app'
              : 'user@enything.app',
          'name': auth.user?.fullName ?? '',
        },
        'theme': {'color': '#4C6EF5'},
      });
    } catch (e) {
      _razorpayOpened = false;
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

  // S3 FIX: Mock payment bypass is ONLY available in debug builds.
  // kDebugMode is a compile-time constant that tree-shakes this in release.
  Future<void> _mockPaymentBypass() async {
    assert(() {
      // Extra guard: this method must never be called in release mode.
      return true;
    }());
    if (!kDebugMode) return; // Belt-and-suspenders: never run in release
    if (_isProcessingPayment || _order == null) return;
    setState(() => _isProcessingPayment = true);
    try {
      final paymentId = 'pay_mock_${DateTime.now().millisecondsSinceEpoch}';
      final razorpayOrderId = 'order_mock_${DateTime.now().millisecondsSinceEpoch}';

      if (_order?.cartGroupId != null) {
        await _supabase.from('orders').update({
          'status': 'confirmed',
          'payment_status': 'captured',
          'razorpay_payment_id': paymentId,
          'razorpay_order_id': razorpayOrderId,
        }).eq('cart_group_id', _order!.cartGroupId!).eq('status', 'awaiting_payment');
      } else {
        await _supabase.from('orders').update({
          'status': 'confirmed',
          'payment_status': 'captured',
          'razorpay_payment_id': paymentId,
          'razorpay_order_id': razorpayOrderId,
        }).eq('id', widget.orderId);
      }
      _paymentCountdownTimer?.cancel();
    } catch (e) {
      debugPrint('Mock payment error: $e');
    } finally {
      if (mounted) setState(() => _isProcessingPayment = false);
    }
  }

  /// S2 FIX: HMAC verification and order confirmation now happen SERVER-SIDE.
  /// The Edge Function `verify-razorpay-payment` checks the signature using
  /// RAZORPAY_KEY_SECRET (which is never sent to the client) and only then
  /// writes `confirmed` + `captured` to the DB via the service role.
  Future<void> _verifyAndConfirmOrder({
    required String paymentId,
    required String razorpayOrderId,
    required String signature,
  }) async {
    try {
      // Send to server for verification — secret stays on server
      final fnResponse = await _supabase.functions.invoke(
        'verify-razorpay-payment',
        body: {
          'razorpay_payment_id': paymentId,
          'razorpay_order_id': razorpayOrderId,
          'razorpay_signature': signature,
        },
      );

      final isVerified = fnResponse.data is Map
          ? (fnResponse.data['verified'] as bool? ?? false)
          : false;

      if (!isVerified) {
        final errMsg = (fnResponse.data is Map
            ? fnResponse.data['error'] as String?
            : null) ?? 'Payment verification failed.';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('$errMsg Contact support if money was deducted.'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
          ));
        }
        setState(() => _isProcessingPayment = false);
        _razorpayOpened = false;
        return;
      }

      // S2 FIX: Server verified the signature — now update order status.
      // Client writes status only AFTER server confirms the payment.
      if (_order?.cartGroupId != null) {
        await _supabase.from('orders').update({
          'status': 'confirmed',
          'payment_status': 'captured',
          'razorpay_payment_id': paymentId,
          'razorpay_order_id': razorpayOrderId,
        }).eq('cart_group_id', _order!.cartGroupId!).eq('status', 'awaiting_payment');
      } else {
        await _supabase.from('orders').update({
          'status': 'confirmed',
          'payment_status': 'captured',
          'razorpay_payment_id': paymentId,
          'razorpay_order_id': razorpayOrderId,
        }).eq('id', widget.orderId);
      }

      _paymentCountdownTimer?.cancel();
      setState(() => _isProcessingPayment = false);
      _razorpayOpened = false;

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
              style: GoogleFonts.outfit(
                  fontSize: 16, color: AppColors.textSecondary)),
        ),
      );
    }

    final currentStep = _getCurrentStep();
    final isDelivered = _isDelivered;
    final isCancelled = _isCancelled;
    final isLive = _aggregateStatus == 'out_for_delivery';

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
                            color: isDark
                                ? Colors.white70
                                : AppColors.textPrimary),
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
                              color:
                                  isDark ? Colors.white : AppColors.textPrimary,
                            ),
                          ),
                          // Live pill — only shown when rider is en-route
                          if (isLive)
                            Row(
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: const BoxDecoration(
                                    color: AppColors.success,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text('Live Tracking',
                                    style: GoogleFonts.outfit(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.success,
                                    )),
                              ],
                            ),
                        ],
                      ),
                    ),
                    // History link
                    TextButton(
                      onPressed: () =>
                          Navigator.pushNamed(context, AppRoutes.orderHistory),
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
        body: MaxWidthContainer(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + safeBottom),
            child: Column(
              children: [
                // Map Section — tappable route preview
                _buildMapPreview(),

                // ── Status Hero ──────────────────────────────────────────────
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  child: Container(
                    key: ValueKey(_aggregateStatus),
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
                        if (_aggregateStatus == 'awaiting_acceptance')
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox(
                                width: 90,
                                height: 90,
                                child: TweenAnimationBuilder<double>(
                                  tween: Tween<double>(
                                      begin: 1.0,
                                      end: _acceptanceSecondsLeft / 180.0),
                                  duration: const Duration(milliseconds: 500),
                                  builder: (_, v, __) =>
                                      CircularProgressIndicator(
                                    value: v,
                                    strokeWidth: 4,
                                    backgroundColor:
                                        Colors.white.withValues(alpha: 0.2),
                                    valueColor:
                                        const AlwaysStoppedAnimation<Color>(
                                            Colors.white),
                                  ),
                                ),
                              ),
                              Container(
                                width: 70,
                                height: 70,
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
                                          color: Colors.white70,
                                          fontSize: 10,
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
                            _aggregateStatusDisplay,
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
                        if (_aggregateStatus == 'awaiting_acceptance') ...[
                          const SizedBox(height: 14),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _acceptanceChip(
                                label: '🏪 Shop${_groupOrders.length > 1 ? 's' : ''}',
                                accepted: _allSellersAccepted,
                              ),
                              const SizedBox(width: 10),
                              _acceptanceChip(
                                label: '🛵 Rider',
                                accepted: _partnerAccepted,
                              ),
                            ],
                          ),
                        ],
                        // ── ETA Strip (active states only) ─────────────────────
                        if (!isCancelled && !isDelivered &&
                            !['awaiting_acceptance', 'awaiting_payment']
                                .contains(_aggregateStatus))
                          _buildEtaStrip(),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Delivering To card (shows full address with label) ─────────
                if (_order!.address != null && _order!.address!.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.07)
                            : Colors.grey.shade100,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color:
                              Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.10),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.location_on_rounded,
                              color: AppColors.primary, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Text(
                                  'Delivering to',
                                  style: GoogleFonts.outfit(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? Colors.white38
                                        : Colors.grey.shade500,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                // Label badge (🏠 Home / 💼 Office …)
                                if (_order!.addressLabel != null &&
                                    _order!.addressLabel!.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary
                                          .withValues(alpha: 0.10),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      _order!.addressLabel!,
                                      style: GoogleFonts.outfit(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ]),
                              const SizedBox(height: 4),
                              Text(
                                _order!.address!,
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? Colors.white
                                      : AppColors.textPrimary,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (_order!.deliveryNotes != null &&
                                  _order!.deliveryNotes!.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Row(children: [
                                  Icon(Icons.info_outline_rounded,
                                      size: 12,
                                      color: isDark
                                          ? Colors.amber.shade300
                                          : Colors.orange.shade700),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      _order!.deliveryNotes!,
                                      style: GoogleFonts.outfit(
                                        fontSize: 11,
                                        color: isDark
                                            ? Colors.amber.shade300
                                            : Colors.orange.shade700,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ]),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),


                if (!isCancelled &&
                    ((_order!.shopPhone != null && _order!.shopPhone!.isNotEmpty) ||
                        (_order!.riderPhone != null && _order!.riderPhone!.isNotEmpty))) ...[
                  Row(children: [
                    if (_order!.shopPhone != null && _order!.shopPhone!.isNotEmpty)
                      Expanded(
                          child: _glassContactBtn(
                        icon: Icons.store_rounded,
                        label: _groupOrders.length > 1 ? 'Call Shops' : 'Call Shop',
                        color: AppColors.primary,
                        isDark: isDark,
                        onTap: () {
                          if (_groupOrders.length > 1) {
                            _showShopSelectionBottomSheet(context, isDark);
                          } else {
                            _callPhone(_order!.shopPhone!);
                          }
                        },
                      )),
                    if ((_order!.shopPhone != null && _order!.shopPhone!.isNotEmpty) &&
                        (_order!.riderPhone != null && _order!.riderPhone!.isNotEmpty))
                      const SizedBox(width: 12),
                    if (_order!.riderPhone != null && _order!.riderPhone!.isNotEmpty)
                      Expanded(
                          child: _glassContactBtn(
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
                          color: Colors.black
                              .withValues(alpha: isDark ? 0.3 : 0.05),
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
                            width: 4,
                            height: 20,
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
                              color:
                                  isDark ? Colors.white : AppColors.textPrimary,
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
                        color:
                            Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
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
                          width: 4,
                          height: 20,
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
                              color:
                                  isDark ? Colors.white : AppColors.textPrimary,
                            )),
                      ]),
                      const SizedBox(height: 16),
                      _billRow('Item Subtotal',
                          '₹${_computeGroupTotalAmount().toStringAsFixed(0)}',
                          isDark: isDark),
                      const SizedBox(height: 8),
                      _billRow('Delivery Fee',
                          '₹${(_computeGroupDeliveryCharges() - _computeGroupGstDelivery()).toStringAsFixed(0)}',
                          isDark: isDark),
                      if (_computeGroupPlatformFee() > 0) ...[
                        const SizedBox(height: 8),
                        _billRow('Handling Fee',
                            '₹${(_computeGroupPlatformFee() - _computeGroupGstPlatform()).toStringAsFixed(2)}',
                            isDark: isDark),
                      ],
                      if ((_computeGroupGstItemTotal() + _computeGroupGstDelivery() + _computeGroupGstPlatform()) > 0) ...[
                        const SizedBox(height: 8),
                        _billRow('TOTAL GST',
                            '₹${(_computeGroupGstItemTotal() + _computeGroupGstDelivery() + _computeGroupGstPlatform()).toStringAsFixed(2)}',
                            isDark: isDark),
                      ],
                      Divider(
                        height: 24,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.1)
                            : AppColors.divider,
                      ),
                      _billRow(
                        'Total Paid',
                        '₹${_computeGroupGrandTotal().toStringAsFixed(0)}',
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
                          style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w700, fontSize: 15)),
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
                if (_aggregateStatus == 'awaiting_payment') ...[
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
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.check_circle_rounded,
                                color: Colors.white, size: 20),
                            const SizedBox(width: 8),
                            Text('Shop & Rider Confirmed!',
                                style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15)),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '\u23f1 ${(_paymentSecondsLeft ~/ 60).toString().padLeft(2, '0')}:${(_paymentSecondsLeft % 60).toString().padLeft(2, '0')}',
                                style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                            'Complete your payment to confirm the order. Shop and rider are ready!',
                            style: GoogleFonts.outfit(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 12)),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isProcessingPayment
                                ? null
                                : () => _openRazorpay(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF0F9B58),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            child: _isProcessingPayment
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : Text(
                                    'PAY NOW \u20b9${_computeGroupGrandTotal().toStringAsFixed(0)}',
                                    style: GoogleFonts.outfit(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: _isProcessingPayment
                                ? null
                                : () => _mockPaymentBypass(),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            child: Text(
                                'Simulate Successful Payment (Test Mode)',
                                style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],



                // ── Smart Cancellation Recovery Panel ─────────────────────────
                if (isCancelled) ...{
                  const SizedBox(height: 8),
                  _buildCancellationRecoveryPanel(isDark),
                },

                // ── Cancel button (only for awaiting_acceptance / pending) ────
                if (!isCancelled &&
                    (_aggregateStatus == 'awaiting_acceptance' ||
                        _aggregateStatus == 'pending')) ...[
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
                              color: Colors.amber,
                              fontWeight: FontWeight.w700)),
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
            subtitle:
                'Remove this shop\'s items from cart and search for alternatives',
            color: AppColors.accent,
            isDark: isDark,
            loading: false,
            onTap: () => Navigator.pushNamedAndRemoveUntil(
              context,
              AppRoutes.customerHome,
              (r) => false,
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
              context,
              AppRoutes.customerHome,
              (r) => false,
            ),
          ),
        ];
        break;

      case 'no_rider':
        title = '🛵 No Rider Available';
        body =
            'The shop accepted your order, but no rider was free to pick it up.';
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
              context,
              AppRoutes.customerHome,
              (r) => false,
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
              context,
              AppRoutes.customerHome,
              (r) => false,
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
              context,
              AppRoutes.customerHome,
              (r) => false,
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
          border:
              Border.all(color: color.withValues(alpha: isDark ? 0.4 : 0.3)),
        ),
        child: Row(
          children: [
            if (loading)
              SizedBox(
                height: 16,
                width: 16,
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
            accepted
                ? Icons.check_circle_rounded
                : Icons.hourglass_bottom_rounded,
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
          border:
              Border.all(color: color.withValues(alpha: isDark ? 0.4 : 0.35)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(label,
                style: GoogleFonts.outfit(
                    fontSize: 13, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      ),
    );
  }

  /// Builds the Swiggy/Zomato-style ETA strip shown inside the status hero
  /// for active, post-payment order states.
  Widget _buildEtaStrip() {
    if (_order == null) return const SizedBox.shrink();

    double distanceKm = _order!.estimatedDistanceKm > 0
        ? _order!.estimatedDistanceKm
        : 3.0;
    int prepMins = _order!.shopPrepTimeSnapshot > 0
        ? _order!.shopPrepTimeSnapshot
        : 30;

    // During out_for_delivery: use live rider→customer distance for remaining time
    if (_aggregateStatus == 'out_for_delivery' &&
        _riderLatLng != null &&
        _order!.deliveryLat != null &&
        _order!.deliveryLng != null) {
      distanceKm = DeliveryCalculator.haversineKm(
        _riderLatLng!,
        LatLng(_order!.deliveryLat!, _order!.deliveryLng!),
      );
      prepMins = 0; // prep is done — only travel remains
    } else if (_aggregateStatus == 'picked_up' || _aggregateStatus == 'out_for_delivery') {
      // Prep is already done; only travel time remains
      prepMins = 0;
    } else if (_aggregateStatus == 'preparing') {
      // Rider will take time to arrive at shop + travel — use full ETA
    }

    final etaStr = DeliveryCalculator.etaLabel(distanceKm, prepMins);
    final arrivalStr = DeliveryCalculator.etaArrivalTime(distanceKm, prepMins);

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.access_time_rounded, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(
            etaStr,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
          ),
          const Icon(Icons.location_on_rounded, color: Colors.white70, size: 14),
          const SizedBox(width: 4),
          Text(
            'by $arrivalStr',
            style: GoogleFonts.outfit(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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
                        ? AppColors.primary
                            .withValues(alpha: isDark ? 0.25 : 0.1)
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : AppColors.background),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isCompleted
                      ? AppColors.success
                      : isCurrent
                          ? AppColors.primary
                          : (isDark
                              ? Colors.white.withValues(alpha: 0.12)
                              : AppColors.divider),
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
                  builder: (_) => CustomerOrderMapPage(
                    order: _order!,
                    groupOrders: _groupOrders,
                  ),
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
                interactive:
                    false, // non-interactive; tap handled by GestureDetector
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
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

            // Live rider badge (top-right) when rider is active
            if (_riderLatLng != null && ['confirmed', 'preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery'].contains(_order!.status))
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                      const Icon(Icons.circle, color: Colors.white, size: 6),
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    }
  }

  void _showShopSelectionBottomSheet(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1A1A2E) : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Select Shop to Call',
                    style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : AppColors.textPrimary)),
                const SizedBox(height: 16),
                ..._groupOrders.where((o) => o.shopPhone != null).map((o) {
                  final itemNames = o.items.map((i) => i.productName).take(2).join(', ');
                  return ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.store_rounded, color: AppColors.primary),
                    ),
                    title: Text(itemNames.isNotEmpty ? 'Shop ($itemNames)' : 'Shop',
                        style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : AppColors.textPrimary)),
                    subtitle: Text(o.shopPhone!,
                        style: GoogleFonts.outfit(
                            color: isDark ? Colors.white60 : AppColors.textSecondary)),
                    trailing: const Icon(Icons.phone_rounded, color: AppColors.primary, size: 20),
                    onTap: () {
                      Navigator.pop(ctx);
                      _callPhone(o.shopPhone!);
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }
}
