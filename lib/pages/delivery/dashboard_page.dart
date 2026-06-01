import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/notification_provider.dart';
import '../../models/order_model.dart';
import '../../theme/app_colors.dart';
import '../../config/payment_config.dart';
import '../../config/routes.dart';
import '../../widgets/common/rating_bottom_sheet.dart';
import '../../widgets/common/notification_bell.dart';
import 'package:url_launcher/url_launcher.dart';

class DeliveryDashboardPage extends StatefulWidget {
  const DeliveryDashboardPage({super.key});
  @override
  State<DeliveryDashboardPage> createState() => _DeliveryDashboardPageState();
}

class _DeliveryDashboardPageState extends State<DeliveryDashboardPage>
    with TickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  bool _isOnline = false;
  List<OrderModel> _availableOrders = [];
  List<OrderModel> _myOrders = [];
  bool _isLoading = false;
  // Bug #19: rider's current GPS position for geographic filtering
  double? _riderLat;
  double? _riderLng;
  bool _locationUnavailable = false;

  // Location broadcast timer — updates rider_lat/rider_lng every 15s
  Timer? _locationBroadcastTimer;

  late AnimationController _bgCtrl;
  late Animation<double> _bgAnim;

  bool _autoAccept = false;
  String _navApp = 'Google Maps';

  @override
  void initState() {
    super.initState();
    _bgCtrl =
        AnimationController(duration: const Duration(seconds: 5), vsync: this)
          ..repeat(reverse: true);
    _bgAnim = CurvedAnimation(parent: _bgCtrl, curve: Curves.easeInOut);

    _loadOrders();
    _initNotifications();
  }

  void _initNotifications() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      final userId = auth.currentUserId;
      if (userId != null) {
        final notifProvider = context.read<NotificationProvider>();
        notifProvider.listenAsDelivery(userId);
        notifProvider.registerFcmToken(userId, 'delivery'); // Register push token
      }
    });
  }

  @override
  void dispose() {
    _locationBroadcastTimer?.cancel();
    _bgCtrl.dispose();
    super.dispose();
  }

  // Starts pushing GPS location to DB every 15s while out_for_delivery.
  void _startLocationBroadcast() {
    _locationBroadcastTimer?.cancel();
    _locationBroadcastTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      final outOrders = _myOrders.where((o) => o.status == 'out_for_delivery').toList();
      if (outOrders.isEmpty) {
        _stopLocationBroadcast();
        return;
      }
      await _fetchRiderLocation();
      if (_riderLat == null || _riderLng == null) return;
      for (final order in outOrders) {
        try {
          await _supabase.from('orders').update({
            'rider_lat': _riderLat,
            'rider_lng': _riderLng,
            'rider_location_updated_at': DateTime.now().toIso8601String(),
          }).eq('id', order.id);
        } catch (e) {
          debugPrint('Location broadcast error: $e');
        }
      }
    });
  }

  void _stopLocationBroadcast() {
    _locationBroadcastTimer?.cancel();
    _locationBroadcastTimer = null;
  }

  /// Attempt to get the rider's current GPS position.
  /// Returns true if location was obtained, false otherwise.
  Future<bool> _fetchRiderLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return false;

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) return false;

      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 10),
          ),
        );
      } catch (_) {
        pos = await Geolocator.getLastKnownPosition();
      }

      if (pos != null) {
        _riderLat = pos.latitude;
        _riderLng = pos.longitude;
        return true;
      }
    } catch (e) {
      debugPrint('Rider location error: $e');
    }
    return false;
  }

  Future<void> _loadOrders() async {
    setState(() => _isLoading = true);
    final auth = context.read<AuthProvider>();
    try {
      // Bug #19: fetch rider location before querying orders
      final hasLocation = await _fetchRiderLocation();
      setState(() => _locationUnavailable = !hasLocation);

      if (auth.currentUserId != null) {
        final partnerResp = await _supabase
            .from('delivery_partners')
            .select('is_active')
            .eq('id', auth.currentUserId!)
            .maybeSingle();
        if (partnerResp != null && partnerResp['is_active'] != null) {
          _isOnline = partnerResp['is_active'] as bool;
        }
      }


      final available = await _supabase
          .from('orders')
          .select('*, order_items(*)')
          .eq('seller_accepted', true)
          .isFilter('delivery_partner_id', null)
          .inFilter('status', ['pending', 'confirmed']);

      final myOrders = await _supabase
          .from('orders')
          .select('*, order_items(*)')
          .eq('delivery_partner_id', auth.currentUserId ?? '')
          .neq('status', 'delivered')
          .neq('status', 'cancelled')
          .neq('status', 'seller_rejected')
          .neq('status', 'partner_rejected');

      final allAvailable = (available as List).map((o) {
        final model = OrderModel.fromMap(o);
        model.items = (o['order_items'] as List? ?? [])
            .map((i) => OrderItem.fromMap(i))
            .toList();
        return model;
      }).toList();

      // Bug #19: filter by distance — only show orders within maxDeliveryRadiusKm
      final filtered = hasLocation
          ? allAvailable.where((order) {
              final lat = order.deliveryLat;
              final lng = order.deliveryLng;
              if (lat == null || lng == null) {
                return true; // no coords → include (legacy order)
              }
              final distM =
                  Geolocator.distanceBetween(_riderLat!, _riderLng!, lat, lng);
              return distM / 1000 <= PaymentConfig.maxDeliveryRadiusKm;
            }).toList()
          : allAvailable; // no location → show all with a warning banner

      setState(() {
        _availableOrders = filtered;
        _myOrders = (myOrders as List).map((o) {
          final model = OrderModel.fromMap(o);
          model.items = (o['order_items'] as List? ?? [])
              .map((i) => OrderItem.fromMap(i))
              .toList();
          return model;
        }).toList();
        _isLoading = false;
      });

      // Auto-start broadcast if rider already has an out_for_delivery order
      final hasOutForDelivery =
          _myOrders.any((o) => o.status == 'out_for_delivery');
      if (hasOutForDelivery && _locationBroadcastTimer == null) {
        _startLocationBroadcast();
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _acceptOrder(OrderModel order) async {
    final auth = context.read<AuthProvider>();
    try {
      final newStatus = order.sellerAccepted ? 'confirmed' : 'pending';
      await _supabase.from('orders').update({
        'delivery_partner_id': auth.currentUserId,
        'partner_accepted': true,
        'status': newStatus,
      }).eq('id', order.id);

      if (mounted) {
        final msg = order.sellerAccepted
            ? '✅ Order confirmed! Both shop & rider accepted.'
            : '✅ Saved. Waiting for shop to confirm.';
        _showSnack(msg);
      }
      _loadOrders();
    } catch (e) {
      debugPrint('Accept error: $e');
    }
  }

  Future<void> _updateStatus(OrderModel order, String status) async {
    try {
      if (status == 'arrived') {
        await _supabase.from('orders').update({
          'arrived_at_shop_time': DateTime.now().toIso8601String(),
        }).eq('id', order.id);
      } else if (status == 'reassign' || status == 'reassign_disputed') {
        double penalty = 0.0;
        if (order.arrivedAtShopTime != null) {
          final waitMinutes =
              DateTime.now().difference(order.arrivedAtShopTime!).inMinutes;
          final paidMinutes = math.max(0, math.min(10, waitMinutes - 10));
          penalty = paidMinutes * 1.5;
        }
        await _supabase.from('orders').update({
          'delivery_partner_id': null,
          'partner_accepted': false,
          'status': 'pending',
          'wait_time_penalty': penalty,
          'wait_time_disputed': status == 'reassign_disputed',
        }).eq('id', order.id);
      } else if (status == 'delivered') {
        await _supabase.from('orders').update({
          'status': status,
        }).eq('id', order.id);
        _stopLocationBroadcast();
        _loadOrders();
        // Show rating prompt after delivering
        if (mounted && !order.hasDeliveryRated) {
          Future.delayed(const Duration(milliseconds: 500),
              () => _showDeliveryRatingFlow(order));
        }
        return;
      } else {
        await _supabase
            .from('orders')
            .update({'status': status}).eq('id', order.id);
      }
      // Start broadcasting location when rider is out for delivery
      if (status == 'out_for_delivery') {
        _startLocationBroadcast();
      }
      _loadOrders();
    } catch (e) {
      debugPrint('Status update error: $e');
    }
  }

  void _showDeliveryRatingFlow(OrderModel order) {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => RatingBottomSheet(
        title: 'Rate the Customer 👤',
        subtitle: 'How was the pickup/drop experience?',
        onSubmit: (rating, review) async {
          await _submitDeliveryRating(
            orderId: order.id,
            rateeId: order.customerId,
            rateeRole: 'customer',
            rating: rating,
            review: review,
          );
          // Then rate the shop
          if (mounted) {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.white,
              shape: const RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(28))),
              builder: (_) => RatingBottomSheet(
                title: 'Rate the Shop 🏪',
                subtitle: 'How was your wait time and experience at the shop?',
                onSubmit: (r, rv) => _submitDeliveryRating(
                  orderId: order.id,
                  rateeId: null,
                  shopId: order.shopId, // link to the actual shop
                  rateeRole: 'seller',
                  rating: r,
                  review: rv,
                  markRated: true,
                ),
              ),
            );
          }
        },
      ),
    );
  }

  Future<void> _submitDeliveryRating({
    required String orderId,
    required String? rateeId,
    String? shopId,
    required String rateeRole,
    required int rating,
    required String review,
    bool markRated = false,
  }) async {
    try {
      final auth = context.read<AuthProvider>();
      await _supabase.from('ratings').insert({
        'order_id': orderId,
        'rater_id': auth.currentUserId,
        'ratee_id': rateeId,
        'shop_id': shopId,
        'rater_role': 'delivery',
        'ratee_role': rateeRole,
        'rating': rating,
        'review': review.isEmpty ? null : review,
      });
      if (markRated) {
        await _supabase
            .from('orders')
            .update({'has_delivery_rated': true}).eq('id', orderId);
      }
    } catch (e) {
      debugPrint('Delivery rating error: $e');
    }
  }

  void _showDisputeDialog(OrderModel order) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Dispute Order',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text(
            'Report shop delay or missing items. You will keep your wait penalty pay and the order will be reassigned.',
            style: GoogleFonts.outfit()),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _updateStatus(order, 'reassign_disputed');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Dispute & Reassign'),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.outfit()),
      backgroundColor: AppColors.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = themeProvider.isDarkMode;
    final size = MediaQuery.of(context).size;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF080812) : const Color(0xFFF0F4FF),
        body: CustomScrollView(
          slivers: [
            // ── Animated Header ───────────────────────────────────────────
            SliverAppBar(
              expandedHeight: 240,
              pinned: true,
              elevation: 0,
              backgroundColor: const Color(0xFF0D2137),
              surfaceTintColor: Colors.transparent,
              leading: const SizedBox.shrink(),
              flexibleSpace: FlexibleSpaceBar(
                background: AnimatedBuilder(
                  animation: _bgCtrl,
                  builder: (_, __) => Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color.lerp(const Color(0xFF0D2137),
                              const Color(0xFF0A3260), _bgAnim.value)!,
                          Color.lerp(const Color(0xFF061222),
                              const Color(0xFF061A36), _bgAnim.value)!,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Stack(
                      children: [
                        // Blobs
                        Positioned(
                            top: -50,
                            right: -50,
                            child: _blob(220, const Color(0xFF00B4D8),
                                0.12 + _bgAnim.value * 0.06)),
                        Positioned(
                            bottom: -40,
                            left: -40,
                            child: _blob(180, const Color(0xFF51CF66), 0.10)),
                        // Stars
                        CustomPaint(
                            size: Size(size.width, 240),
                            painter: _MiniStarPainter(_bgCtrl.value)),
                        // Content
                        SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Top bar
                                Row(children: [
                                  _glassAvatar(auth.user?.initials ?? 'D',
                                      const Color(0xFF00B4D8)),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                              'Hi, ${auth.user?.fullName.split(' ').first ?? 'Partner'}! 🚴',
                                              style: GoogleFonts.outfit(
                                                  color: Colors.white,
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.w800)),
                                          const SizedBox(height: 4),
                                          _badge('🛵  Delivery Partner',
                                              const Color(0xFF00B4D8)),
                                        ]),
                                  ),
                                  _iconBtn(
                                      isDark
                                          ? Icons.light_mode_outlined
                                          : Icons.dark_mode_outlined,
                                      () => themeProvider.toggleTheme()),
                                  const NotificationBell(
                                    iconColor: Colors.white70,
                                    containerColor: Colors.transparent,
                                    badgeColor: Color(0xFFFF6B6B),
                                  ),
                                  _iconBtn(
                                      Icons.settings_outlined,
                                      () => Navigator.pushNamed(
                                          context, AppRoutes.settings)),
                                ]),
                                const SizedBox(height: 24),

                                // Stats row
                                Row(children: [
                                  const Spacer(),
                                  GestureDetector(
                                    onTap: () => Navigator.pushNamed(
                                        context, AppRoutes.earnings),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                            color:
                                                Colors.white.withValues(alpha: 0.2)),
                                      ),
                                      child: Row(children: [
                                        const Icon(
                                            Icons
                                                .account_balance_wallet_outlined,
                                            color: Colors.white70,
                                            size: 16),
                                        const SizedBox(width: 6),
                                        Text('Earnings',
                                            style: GoogleFonts.outfit(
                                                color: Colors.white70,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600)),
                                      ]),
                                    ),
                                  ),
                                ]),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── Content ────────────────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // Quick Actions
                  _sectionHeader(
                      '⚡ Quick Actions', '', const Color(0xFF00B4D8), isDark),
                  const SizedBox(height: 14),
                  _actionTile(
                    icon: Icons.work_outline_rounded,
                    gradient: const [Color(0xFF2ECC71), Color(0xFF27AE60)],
                    title: 'Work Management',
                    subtitle: _isOnline
                        ? 'You are Online. Tap to go Offline or edit settings.'
                        : 'You are Offline. Tap to go Online.',
                    badge: _isOnline ? 'Online' : 'Offline',
                    isDark: isDark,
                    onTap: _showWorkManagementSheet,
                  ),
                  const SizedBox(height: 24),

                  // Active deliveries
                  if (_myOrders.isNotEmpty) ...[
                    _sectionHeader('🚗 My Active Deliveries',
                        '${_myOrders.length}', const Color(0xFF4C6EF5), isDark),
                    const SizedBox(height: 14),
                    ..._myOrders.map((o) => _activeOrderCard(o, isDark)),
                    const SizedBox(height: 24),
                  ],

                  // Available orders
                  _sectionHeader(
                      '📦 Available Orders',
                      '${_availableOrders.length}',
                      const Color(0xFFFF8C42),
                      isDark),
                  const SizedBox(height: 14),

                  // Bug #19: warn rider if location is unavailable (showing unfiltered orders)
                  if (_locationUnavailable && _isOnline)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.location_off_outlined,
                            color: Colors.orange, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Location unavailable — showing all nearby orders. Enable GPS for distance-based filtering.',
                            style: GoogleFonts.outfit(
                                color: Colors.orange, fontSize: 12),
                          ),
                        ),
                      ]),
                    ),

                  if (_isLoading)
                    const Center(
                        child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(),
                    ))
                  else if (!_isOnline)
                    _offlineState(isDark)
                  else if (_availableOrders.isEmpty)
                    _emptyState(isDark)
                  else
                    ..._availableOrders
                        .map((o) => _availableOrderCard(o, isDark)),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Card Builders ─────────────────────────────────────────────────────────

  Widget _availableOrderCard(OrderModel order, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF121222) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
              blurRadius: 16,
              offset: const Offset(0, 6))
        ],
        border: Border.all(
            color:
                isDark ? Colors.white.withValues(alpha: 0.06) : Colors.transparent),
      ),
      child: Column(children: [
        // Header strip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: const BoxDecoration(
            gradient:
                LinearGradient(colors: [Color(0xFF0D2137), Color(0xFF1A3A5C)]),
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Row(children: [
            const Icon(Icons.storefront_outlined,
                color: Colors.white70, size: 16),
            const SizedBox(width: 8),
            Text('Order #${order.id.substring(0, 8).toUpperCase()}',
                style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: AppColors.success.withValues(alpha: 0.5))),
              child: Text('₹${order.riderEarnings.toStringAsFixed(0)} earn',
                  style: GoogleFonts.outfit(
                      color: AppColors.success,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
        // Body
        Padding(
          padding: const EdgeInsets.all(18),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.location_on_outlined,
                  size: 16, color: AppColors.danger),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(order.address ?? 'Address not set',
                      style: GoogleFonts.outfit(
                          color: isDark ? Colors.white60 : Colors.grey.shade600,
                          fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis)),
            ]),
            // Order items
            if (order.items.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color:
                      (isDark ? Colors.white : Colors.black).withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Items (${order.items.length})',
                        style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? Colors.white54
                                : Colors.grey.shade600)),
                    const SizedBox(height: 4),
                    ...order.items.map((item) => Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text('${item.quantity}x ${item.productName}',
                              style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  color:
                                      isDark ? Colors.white70 : Colors.black87),
                              overflow: TextOverflow.ellipsis),
                        )),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(children: [
              Text('₹${order.grandTotal.toStringAsFixed(0)}',
                  style: GoogleFonts.outfit(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : const Color(0xFF0A0A14))),
              const Spacer(),
              ElevatedButton(
                onPressed: () => _acceptOrder(order),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 4,
                  shadowColor: AppColors.success.withValues(alpha: 0.4),
                ),
                child: Text('Accept',
                    style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w800, fontSize: 14)),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _activeOrderCard(OrderModel order, bool isDark) {
    String? nextStatus;
    String? nextLabel;

    // Wait-time variables
    final now = DateTime.now();
    bool showWaitTimer = false;
    int waitMinutes = 0;
    double waitPenalty = 0.0;
    bool canReassign = false;

    if (order.arrivedAtShopTime != null) {
      if (order.status == 'confirmed' ||
          order.status == 'preparing' ||
          order.status == 'ready_for_pickup') {
        showWaitTimer = true;
        // If shop marked ready, calculate wait time up to orderReadyTime. Else up to now.
        final endTime = order.orderReadyTime ?? now;
        waitMinutes = endTime.difference(order.arrivedAtShopTime!).inMinutes;
        final paidMinutes = math.max(0, math.min(10, waitMinutes - 10));
        waitPenalty = paidMinutes * 1.5;
        canReassign = now.difference(order.arrivedAtShopTime!).inMinutes >= 20;
      }
    }

    if (order.status == 'confirmed' || order.status == 'preparing') {
      if (order.arrivedAtShopTime == null) {
        nextStatus = 'arrived';
        nextLabel = '📍 Mark Arrived at Shop';
      } else {
        if (canReassign) {
          nextStatus = 'reassign';
          nextLabel = '⚠️ Wait Time Exceeded - Reassign';
        } else {
          nextLabel = 'Waiting for Shop to Pack...';
          nextStatus = null; // disabled
        }
      }
    } else if (order.status == 'ready_for_pickup') {
      nextStatus = 'picked_up';
      nextLabel = '✅ Confirm Received (Mark Picked Up)';
    } else if (order.status == 'picked_up') {
      nextStatus = 'out_for_delivery';
      nextLabel = '🚀 Out for Delivery';
    } else if (order.status == 'out_for_delivery') {
      nextStatus = 'delivered';
      nextLabel = '✅ Mark Delivered';
    }

    final statusGradient = order.status == 'out_for_delivery'
        ? [const Color(0xFF4C6EF5), const Color(0xFF364FC7)]
        : order.status == 'picked_up'
            ? [const Color(0xFF51CF66), const Color(0xFF2F9E44)]
            : [const Color(0xFFFF8C42), const Color(0xFFE8590C)];

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF121222) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
            color: statusGradient.first.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
              color: statusGradient.first.withValues(alpha: 0.15),
              blurRadius: 16,
              offset: const Offset(0, 6))
        ],
      ),
      child: Column(children: [
        // Status strip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: statusGradient),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Row(children: [
            Text('Order #${order.id.substring(0, 8).toUpperCase()}',
                style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
            const Spacer(),
            Text(order.statusDisplay,
                style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Row(children: [
              const Icon(Icons.location_on_outlined,
                  size: 16, color: AppColors.danger),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(order.address ?? 'Address not set',
                      style: GoogleFonts.outfit(
                          color: isDark ? Colors.white60 : Colors.grey.shade600,
                          fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              if (order.customerPhone != null)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _callPhone(order.customerPhone!),
                    icon: const Icon(Icons.phone_outlined, size: 16),
                    label: Text('Customer',
                        style: GoogleFonts.outfit(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              if (order.customerPhone != null && order.shopPhone != null)
                const SizedBox(width: 8),
              if (order.shopPhone != null)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _callPhone(order.shopPhone!),
                    icon: const Icon(Icons.store_outlined, size: 16),
                    label:
                        Text('Shop', style: GoogleFonts.outfit(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.accent,
                      side: const BorderSide(color: AppColors.accent),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
            ]),
            if (showWaitTimer) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: waitMinutes >= 10
                      ? Colors.orange.withValues(alpha: 0.1)
                      : Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: waitMinutes >= 10 ? Colors.orange : Colors.blue),
                ),
                child: Row(
                  children: [
                    Icon(Icons.timer_outlined,
                        color: waitMinutes >= 10 ? Colors.orange : Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Wait Time: $waitMinutes mins',
                              style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.bold,
                                  color: waitMinutes >= 10
                                      ? Colors.orange
                                      : Colors.blue)),
                          Text(
                              order.orderReadyTime != null
                                  ? 'Timer stopped by shop'
                                  : (waitMinutes < 10
                                      ? 'Grace period (10 mins)'
                                      : 'Earning ₹1.5/min delay penalty'),
                              style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.black87)),
                        ],
                      ),
                    ),
                    Text('+₹${waitPenalty.toStringAsFixed(1)}',
                        style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: AppColors.success)),
                  ],
                ),
              ),
            ],
            if (nextLabel != null) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: nextStatus == null
                      ? null
                      : () {
                          if (nextStatus == 'arrived') {
                            // Geofence mock: within 100 meters
                            _showSnack('📍 GPS verified: At Shop');
                            _updateStatus(order, nextStatus!);
                          } else if (nextStatus == 'reassign') {
                            _showDisputeDialog(order);
                          } else {
                            _updateStatus(order, nextStatus!);
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: nextStatus == 'reassign'
                        ? AppColors.danger
                        : statusGradient.first,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        isDark ? Colors.white10 : Colors.grey.shade300,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: Text(nextLabel,
                      style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                ),
              ),
            ],
            if (showWaitTimer) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => _showDisputeDialog(order),
                icon: const Icon(Icons.report_problem_outlined,
                    color: AppColors.danger, size: 16),
                label: Text(
                    order.orderReadyTime != null
                        ? 'Shop Lied - Items Not Received'
                        : 'Shop Lied / Items Not Given',
                    style: GoogleFonts.outfit(
                        color: AppColors.danger, fontSize: 12)),
              ),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _offlineState(bool isDark) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF121222) : Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(children: [
          const Text('💤', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 16),
          Text('You\'re Offline',
              style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF0A0A14))),
          const SizedBox(height: 8),
          Text('Toggle the switch above to start accepting orders',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                  color: isDark ? Colors.white38 : Colors.grey.shade500,
                  fontSize: 13)),
        ]),
      );

  Widget _emptyState(bool isDark) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF121222) : Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(children: [
          const Text('🕐', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 16),
          Text('No orders yet',
              style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF0A0A14))),
          const SizedBox(height: 8),
          Text('Waiting for delivery requests...',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                  color: isDark ? Colors.white38 : Colors.grey.shade500,
                  fontSize: 13)),
        ]),
      );

  Widget _sectionHeader(String title, String count, Color color, bool isDark) =>
      Row(children: [
        Text(title,
            style: GoogleFonts.outfit(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : const Color(0xFF0A0A14))),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(20)),
          child: Text(count,
              style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800)),
        ),
      ]);

  Widget _glassAvatar(String initials, Color color) => Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.6)]),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
                color: color.withValues(alpha: 0.5),
                blurRadius: 14,
                offset: const Offset(0, 4))
          ],
        ),
        child: Center(
            child: Text(initials,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900))),
      );

  Widget _badge(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.5))),
        child: Text(label,
            style: GoogleFonts.outfit(
                color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      );

  Widget _iconBtn(IconData icon, VoidCallback onTap) => IconButton(
        icon: Icon(icon, color: Colors.white70, size: 22),
        onPressed: onTap,
        splashRadius: 20,
      );
  Widget _blob(double size, Color color, double opacity) => Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient:
                    RadialGradient(colors: [color, color.withValues(alpha: 0)]))),
      );

  Widget _actionTile({
    required IconData icon,
    required List<Color> gradient,
    required String title,
    required String subtitle,
    required String? badge,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF141425) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ],
        ),
        child: Row(children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: gradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                    color: gradient.first.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4))
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: isDark ? Colors.white : const Color(0xFF0A0A14))),
              Text(subtitle,
                  style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: isDark ? Colors.white38 : Colors.grey.shade600)),
            ]),
          ),
          if (badge != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color:
                      badge == 'Online' ? const Color(0xFF2ECC71) : Colors.grey,
                  borderRadius: BorderRadius.circular(20)),
              child: Text(badge,
                  style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 8),
          ],
          Icon(Icons.arrow_forward_ios_rounded,
              size: 15, color: isDark ? Colors.white24 : Colors.grey.shade400),
        ]),
      ),
    );
  }

  void _showWorkManagementSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1A1A2E)
          : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheetState) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Work Management 🛠️',
                  style: GoogleFonts.outfit(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black)),
              const SizedBox(height: 8),
              Text('Manage your shift, tools, and availability.',
                  style: GoogleFonts.outfit(
                      fontSize: 14,
                      color: isDark ? Colors.white60 : Colors.black54)),
              const SizedBox(height: 24),
              // Online/Offline Toggle
              Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SwitchListTile(
                  title: Text('Duty Status',
                      style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black)),
                  subtitle: Text(
                      _isOnline
                          ? 'Online - Receiving orders'
                          : 'Offline - Not receiving orders',
                      style: GoogleFonts.outfit(
                          color: isDark ? Colors.white70 : Colors.black54)),
                  value: _isOnline,
                  activeThumbColor: AppColors.success,
                  secondary: Icon(Icons.power_settings_new_rounded,
                      color: _isOnline ? AppColors.success : Colors.grey),
                  onChanged: (val) async {
                    setSheetState(() => _isOnline = val);
                    setState(() => _isOnline = val);
                    final auth = context.read<AuthProvider>();
                    if (auth.currentUserId != null) {
                      try {
                        await _supabase
                            .from('delivery_partners')
                            .update({'is_active': val})
                            .eq('id', auth.currentUserId!);
                      } catch (e) {
                        debugPrint('Error updating duty status: $e');
                      }
                    }
                    if (val) _loadOrders();
                  },
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SwitchListTile(
                  title: Text('Auto-Accept Orders',
                      style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black)),
                  subtitle: Text(
                      'Automatically accept nearby orders (Under Dev)',
                      style: GoogleFonts.outfit(
                          color: isDark ? Colors.white70 : Colors.black54)),
                  value: _autoAccept,
                  activeThumbColor: AppColors.primary,
                  secondary: Icon(Icons.flash_on_rounded,
                      color: _autoAccept ? AppColors.primary : Colors.grey),
                  onChanged: (val) {
                    setSheetState(() => _autoAccept = val);
                    setState(() => _autoAccept = val);
                  },
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ListTile(
                  title: Text('Navigation App',
                      style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black)),
                  subtitle: Text(_navApp,
                      style: GoogleFonts.outfit(
                          color: isDark ? Colors.white70 : Colors.black54)),
                  leading: const Icon(Icons.map_outlined, color: Colors.blue),
                  trailing:
                      const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                  onTap: () {
                    setSheetState(() {
                      _navApp =
                          _navApp == 'Google Maps' ? 'Waze' : 'Google Maps';
                    });
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ListTile(
                  title: Text('Delivery Vehicle',
                      style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black)),
                  subtitle: Text('2-Wheeler (Motorcycle)',
                      style: GoogleFonts.outfit(
                          color: isDark ? Colors.white70 : Colors.black54)),
                  leading: const Icon(Icons.two_wheeler_rounded,
                      color: Colors.orange),
                  trailing:
                      const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                  onTap: () {
                    _showSnack('Vehicle change requires admin approval.');
                  },
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        );
      }),
    );
  }

  Future<void> _callPhone(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _showSnack('Could not launch dialer');
    }
  }
}

class _MiniStarPainter extends CustomPainter {
  final double t;
  _MiniStarPainter(this.t);
  static final _rnd = math.Random(42);
  static final _stars = List.generate(
      25,
      (_) => [
            _rnd.nextDouble(),
            _rnd.nextDouble(),
            _rnd.nextDouble() * 1.2 + 0.4,
            _rnd.nextDouble() * math.pi * 2,
          ]);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..style = PaintingStyle.fill;
    for (final s in _stars) {
      final tw = (math.sin(t * math.pi * 2 + s[3]) + 1) / 2;
      p.color = Colors.white.withValues(alpha: 0.02 + tw * 0.10);
      canvas.drawCircle(Offset(s[0] * size.width, s[1] * size.height), s[2], p);
    }
  }

  @override
  bool shouldRepaint(_MiniStarPainter o) => o.t != t;
}
