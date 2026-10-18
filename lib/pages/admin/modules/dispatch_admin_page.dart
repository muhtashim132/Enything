import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../providers/rbac_provider.dart';
import '../../../providers/notification_provider.dart';
import '../../../services/bell_alert_service.dart';
import '../../../theme/admin_theme.dart';
import '../../../utils/time_utils.dart';
import '../../../widgets/order_countdown_timer.dart';
import '../rbac/forbidden_page.dart';

class DispatchAdminPage extends StatefulWidget {
  const DispatchAdminPage({super.key});

  @override
  State<DispatchAdminPage> createState() => _DispatchAdminPageState();
}

class _DispatchAdminPageState extends State<DispatchAdminPage>
    with SingleTickerProviderStateMixin {
  final SupabaseClient _supabase = Supabase.instance.client;

  // ── Master Controls ──────────────────────────────────────────────
  bool _isProxyModeActive = true;
  bool _isBuzzEnabled = true;
  bool _includeRiders = true;
  bool _includeSellers = true;
  double? _radiusKm = 15.0; // null = Unlimited

  // ── Location State ───────────────────────────────────────────────
  double? _adminLat;
  double? _adminLng;
  bool _locationLoading = false;
  String _locationStatus = 'Detecting GPS...';

  // ── Data & Feeds ─────────────────────────────────────────────────
  List<Map<String, dynamic>> _feedOrders = [];
  bool _isLoading = true;
  String _activeTab = 'All'; // 'All', 'Rider', 'Seller', 'Dual'
  final Set<String> _trackedBuzzIds = {};

  // ── Realtime & Timers ────────────────────────────────────────────
  RealtimeChannel? _realtimeChannel;
  Timer? _pollingTimer;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _activeTab = switch (_tabController.index) {
            1 => 'Rider',
            2 => 'Seller',
            3 => 'Dual',
            _ => 'All',
          };
        });
      }
    });

    _initGps();
    _fetchFeed();
    _setupRealtime();
    _startPeriodicRefresh();

    // Keep screen awake while monitoring if buzz is on
    WakelockPlus.enable().catchError((_) {});
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pollingTimer?.cancel();
    _realtimeChannel?.unsubscribe();
    // Safety cleanup: silence all buzz loops
    _silenceAllBuzz();
    WakelockPlus.disable().catchError((_) {});
    super.dispose();
  }

  // ── Location Resolution ──────────────────────────────────────────
  Future<void> _initGps() async {
    setState(() => _locationLoading = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _locationStatus = 'GPS Disabled (Remote Mode)';
          _locationLoading = false;
          _radiusKm = null; // Default to unlimited if no GPS
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() {
          _locationStatus = 'No GPS (Remote Mode)';
          _locationLoading = false;
          _radiusKm = null;
        });
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 5),
        ),
      );

      if (mounted) {
        setState(() {
          _adminLat = pos.latitude;
          _adminLng = pos.longitude;
          _locationStatus = 'GPS Locked';
          _locationLoading = false;
        });
        _fetchFeed();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _locationStatus = 'Remote Mode (All Cities)';
          _locationLoading = false;
          _radiusKm = null;
        });
      }
    }
  }

  // ── Data Ingestion & Radar Fetch ─────────────────────────────────
  Future<void> _fetchFeed({bool silent = false}) async {
    if (!_isProxyModeActive) {
      if (mounted) {
        setState(() {
          _feedOrders = [];
          _isLoading = false;
        });
      }
      _silenceAllBuzz();
      return;
    }

    if (!silent && mounted) setState(() => _isLoading = true);

    try {
      final res = await _supabase.rpc('admin_get_dispatch_feed', params: {
        'p_admin_lat': _adminLat,
        'p_admin_lng': _adminLng,
        'p_radius_km': _radiusKm,
        'p_include_riders': _includeRiders,
        'p_include_sellers': _includeSellers,
      });

      if (!mounted) return;

      final List<Map<String, dynamic>> orders =
          List<Map<String, dynamic>>.from(res as List);

      setState(() {
        _feedOrders = orders;
        _isLoading = false;
      });

      _syncAudioBuzz(orders);
    } catch (e) {
      debugPrint('Error fetching dispatch feed: $e');
      if (mounted && !silent) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ── Realtime Ingestion ───────────────────────────────────────────
  void _setupRealtime() {
    _realtimeChannel = _supabase
        .channel('dispatch-hub-orders-stream')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (payload) {
            // Trigger seamless background update
            _fetchFeed(silent: true);
          },
        )
        .subscribe();
  }

  void _startPeriodicRefresh() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (mounted && _isProxyModeActive) {
        _fetchFeed(silent: true);
      }
    });
  }

  // ── Audio Buzz Synchronization ───────────────────────────────────
  void _syncAudioBuzz(List<Map<String, dynamic>> orders) {
    if (!_isBuzzEnabled || !_isProxyModeActive) {
      _silenceAllBuzz();
      return;
    }

    final currentOrderIds =
        orders.map((o) => 'dispatch_${o['order_id']}').toSet();

    // Remove resolved buzzers
    final resolvedIds = _trackedBuzzIds.difference(currentOrderIds);
    for (final id in resolvedIds) {
      BellAlertService.instance.removePendingOrder(id);
      _trackedBuzzIds.remove(id);
    }

    // Add new buzzers
    for (final o in orders) {
      final buzzKey = 'dispatch_${o['order_id']}';
      if (!_trackedBuzzIds.contains(buzzKey)) {
        _trackedBuzzIds.add(buzzKey);
        DateTime? deadline;
        if (o['acceptance_deadline'] != null) {
          deadline = DateTime.tryParse(o['acceptance_deadline'].toString());
        }
        BellAlertService.instance
            .addPendingOrder(buzzKey, expiration: deadline);
      }
    }
  }

  void _silenceAllBuzz() {
    for (final id in _trackedBuzzIds) {
      BellAlertService.instance.removePendingOrder(id);
    }
    _trackedBuzzIds.clear();
  }

  // ── Filtering Logic ──────────────────────────────────────────────
  List<Map<String, dynamic>> get _filteredOrders {
    if (!_isProxyModeActive) return [];

    return _feedOrders.where((o) {
      final bool riderNeedsAccept =
          o['partner_accepted'] != true || o['delivery_partner_id'] == null;
      final bool sellerNeedsAccept = o['seller_accepted'] != true;

      switch (_activeTab) {
        case 'Rider':
          return riderNeedsAccept;
        case 'Seller':
          return sellerNeedsAccept;
        case 'Dual':
          return riderNeedsAccept && sellerNeedsAccept;
        case 'All':
        default:
          return true;
      }
    }).toList();
  }

  // ── Action Handlers ──────────────────────────────────────────────

  /// Accept on Rider's Behalf (Direct or Assign Rider)
  Future<void> _handleRiderAccept(Map<String, dynamic> order) async {
    final orderId = order['order_id'] as String;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _RiderAssignmentModal(
        order: order,
        onDirectAccept: () async {
          Navigator.pop(ctx);
          await _executeRiderAccept(orderId, null);
        },
        onAssignRider: (riderId, phone) async {
          Navigator.pop(ctx);
          await _executeRiderAccept(orderId, riderId, riderPhone: phone);
        },
      ),
    );
  }

  Future<void> _executeRiderAccept(String orderId, String? riderId,
      {String? riderPhone}) async {
    try {
      HapticFeedback.mediumImpact();
      final bool bothAccepted =
          await _supabase.rpc('admin_proxy_accept_rider', params: {
        'p_order_id': orderId,
        'p_rider_id': riderId,
        'p_rider_phone': riderPhone,
      });

      // Clear local buzz
      BellAlertService.instance.removePendingOrder('dispatch_$orderId');
      _trackedBuzzIds.remove('dispatch_$orderId');

      if (!mounted) return;
      _showSnack(
        bothAccepted
            ? '✅ Rider accepted! Order ready for customer payment/prep.'
            : '✅ Rider accepted on proxy! Waiting for store confirmation.',
        isError: false,
      );

      _fetchFeed(silent: true);
    } catch (e) {
      _handleRpcError('Rider Proxy Accept', e);
    }
  }

  /// Accept on Store's Behalf
  Future<void> _handleSellerAccept(Map<String, dynamic> order) async {
    final orderId = order['order_id'] as String;
    final shopName = order['shop_name'] ?? 'Store';

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _SellerAcceptModal(
        shopName: shopName,
        onConfirm: (prepTime) async {
          Navigator.pop(ctx);
          await _executeSellerAccept(orderId, prepTime, order);
        },
      ),
    );
  }

  Future<void> _executeSellerAccept(
      String orderId, int prepTimeMinutes, Map<String, dynamic> order) async {
    try {
      HapticFeedback.mediumImpact();
      final bool riderAccepted =
          await _supabase.rpc('admin_proxy_accept_seller', params: {
        'p_order_id': orderId,
        'p_prep_time_minutes': prepTimeMinutes,
      });

      // Silence local buzz
      BellAlertService.instance.removePendingOrder('dispatch_$orderId');
      _trackedBuzzIds.remove('dispatch_$orderId');

      if (!mounted) return;

      // Dispatch push notification to merchant
      final notifProv = context.read<NotificationProvider>();
      try {
        final shopId = order['shop_id'] as String?;
        if (shopId != null) {
          final shopData = await _supabase
              .from('shops')
              .select('seller_id')
              .eq('id', shopId)
              .maybeSingle();
          if (shopData != null && shopData['seller_id'] != null) {
            notifProv.sendBackgroundPush(
              targetUserId: shopData['seller_id'] as String,
              title: '🏪 Operations Accepted Order',
              body:
                  'Operations accepted Order #${orderId.substring(0, 6)} on your behalf. Please begin packing ($prepTimeMinutes min prep).',
              data: {'order_id': orderId, 'role': 'seller'},
            );
          }
        }
      } catch (_) {}

      _showSnack(
        riderAccepted
            ? '✅ Store accepted! Both sides confirmed.'
            : '✅ Store accepted! Waiting for delivery partner confirmation.',
        isError: false,
      );

      _fetchFeed(silent: true);
    } catch (e) {
      _handleRpcError('Store Proxy Accept', e);
    }
  }

  /// 1-Tap Dual Accept
  Future<void> _handleDualAccept(Map<String, dynamic> order) async {
    final orderId = order['order_id'] as String;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text('Dual Proxy Accept',
            style: GoogleFonts.outfit(
                color: Colors.white, fontWeight: FontWeight.w700)),
        content: Text(
          'Confirm acceptance for BOTH the merchant and delivery rider simultaneously?\n\nThe order will advance directly to payment/preparation.',
          style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8B2FC9),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Accept Both',
                style: GoogleFonts.outfit(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      HapticFeedback.heavyImpact();
      await _supabase.rpc('admin_proxy_accept_both', params: {
        'p_order_id': orderId,
        'p_prep_time_minutes': 15,
      });

      BellAlertService.instance.removePendingOrder('dispatch_$orderId');
      _trackedBuzzIds.remove('dispatch_$orderId');

      if (!mounted) return;
      _showSnack('⚡ Dual Accept Complete! Order confirmed for shop & rider.',
          isError: false);
      _fetchFeed(silent: true);
    } catch (e) {
      _handleRpcError('Dual Accept', e);
    }
  }

  void _handleRpcError(String action, Object e) {
    debugPrint('$action error: $e');
    final errStr = e.toString();
    String msg;
    if (errStr.contains('ORDER_ACCEPTED_BY_OTHER_RIDER')) {
      msg = '⚠️ Order was just accepted by another courier.';
    } else if (errStr.contains('ORDER_CANCELLED')) {
      msg = '⚠️ Order was cancelled by the customer.';
    } else if (errStr.contains('ORDER_ALREADY_REJECTED')) {
      msg = '⚠️ Store owner already declined this order.';
    } else if (errStr.contains('UNAUTHORIZED')) {
      msg = 'Access denied: You do not have dispatch permissions.';
    } else {
      msg = 'Error performing $action: $e';
    }
    if (mounted) _showSnack(msg, isError: true);
    _fetchFeed(silent: true);
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg,
            style: GoogleFonts.outfit(
                color: Colors.white, fontWeight: FontWeight.w600)),
        backgroundColor: isError ? AdminColors.danger : AdminColors.success,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ── Build UI ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final rbac = context.watch<RbacProvider>();

    if (!rbac.isSuperAdmin && !rbac.can('dispatch.view')) {
      return const ForbiddenPage(fullPage: false);
    }

    final filtered = _filteredOrders;

    final riderPendingCount = _feedOrders
        .where((o) =>
            o['partner_accepted'] != true || o['delivery_partner_id'] == null)
        .length;
    final sellerPendingCount =
        _feedOrders.where((o) => o['seller_accepted'] != true).length;
    final dualPendingCount = _feedOrders
        .where((o) =>
            (o['partner_accepted'] != true ||
                o['delivery_partner_id'] == null) &&
            o['seller_accepted'] != true)
        .length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // ── Top Radar Command Header ─────────────────────────────
          _buildCommandHeader(
              riderPendingCount, sellerPendingCount, dualPendingCount),

          // ── Navigation Filter Tabs ───────────────────────────────
          _buildFilterTabs(
              riderPendingCount, sellerPendingCount, dualPendingCount),

          // ── Orders Feed List ─────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF8B2FC9),
                    ),
                  )
                : filtered.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: () => _fetchFeed(),
                        color: const Color(0xFF8B2FC9),
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final o = filtered[index];
                            return _DispatchOrderCard(
                              order: o,
                              onRiderAccept: () => _handleRiderAccept(o),
                              onSellerAccept: () => _handleSellerAccept(o),
                              onDualAccept: () => _handleDualAccept(o),
                              onExpire: () => _fetchFeed(silent: true),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommandHeader(
      int riderCount, int sellerCount, int dualCount) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminColors.cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AdminColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Row 1: Master Mode + Buzz Toggle
          Row(
            children: [
              // Pulse Indicator
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isProxyModeActive
                      ? AdminColors.success
                      : AdminColors.textMuted,
                  boxShadow: _isProxyModeActive
                      ? [
                          BoxShadow(
                            color: AdminColors.success.withValues(alpha: 0.6),
                            blurRadius: 8,
                            spreadRadius: 2,
                          )
                        ]
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'DISPATCH RADAR',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
              const Spacer(),
              // Master Switch
              Row(
                children: [
                  Text(
                    _isProxyModeActive ? 'ACTIVE' : 'OFF',
                    style: GoogleFonts.outfit(
                      color: _isProxyModeActive
                          ? AdminColors.success
                          : AdminColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Transform.scale(
                    scale: 0.8,
                    child: Switch(
                      value: _isProxyModeActive,
                      activeThumbColor: AdminColors.success,
                      onChanged: (val) {
                        setState(() => _isProxyModeActive = val);
                        _fetchFeed();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              // Buzz Toggle
              IconButton(
                icon: Icon(
                  _isBuzzEnabled
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_off_rounded,
                  color: _isBuzzEnabled ? Colors.amber : Colors.white38,
                  size: 22,
                ),
                tooltip: _isBuzzEnabled ? 'Mute Buzzer' : 'Enable Buzzer',
                onPressed: () {
                  setState(() => _isBuzzEnabled = !_isBuzzEnabled);
                  if (!_isBuzzEnabled) {
                    _silenceAllBuzz();
                    _showSnack('Audio buzz muted');
                  } else {
                    _syncAudioBuzz(_feedOrders);
                    _showSnack('Audio buzz enabled');
                  }
                },
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Sub-feed Toggles: Rider & Seller Channels
          Row(
            children: [
              FilterChip(
                label: const Text('🛵 Rider Channel'),
                selected: _includeRiders,
                selectedColor: const Color(0xFF2563EB).withValues(alpha: 0.25),
                checkmarkColor: Colors.white,
                backgroundColor: Colors.white.withValues(alpha: 0.05),
                side: BorderSide(
                  color: _includeRiders
                      ? const Color(0xFF2563EB)
                      : Colors.transparent,
                ),
                labelStyle: GoogleFonts.outfit(
                  color: _includeRiders ? Colors.white : Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
                onSelected: (val) {
                  setState(() => _includeRiders = val);
                  _fetchFeed();
                },
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('🏪 Store Channel'),
                selected: _includeSellers,
                selectedColor: const Color(0xFFD97706).withValues(alpha: 0.25),
                checkmarkColor: Colors.white,
                backgroundColor: Colors.white.withValues(alpha: 0.05),
                side: BorderSide(
                  color: _includeSellers
                      ? const Color(0xFFD97706)
                      : Colors.transparent,
                ),
                labelStyle: GoogleFonts.outfit(
                  color: _includeSellers ? Colors.white : Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
                onSelected: (val) {
                  setState(() => _includeSellers = val);
                  _fetchFeed();
                },
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Row 2: Range Slider & GPS Status
          Row(
            children: [
              const Icon(
                Icons.radar_rounded,
                size: 16,
                color: AdminColors.primary,
              ),
              const SizedBox(width: 6),
              Text(
                _radiusKm != null
                    ? 'Radius: ${_radiusKm!.toInt()} km'
                    : 'Radius: Unlimited (All Cities)',
                style: GoogleFonts.outfit(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_locationLoading) ...[
                      const SizedBox(
                        width: 9,
                        height: 9,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: Color(0xFF8B2FC9),
                        ),
                      ),
                      const SizedBox(width: 5),
                    ],
                    Text(
                      _locationStatus,
                      style: GoogleFonts.outfit(
                        color: Colors.white54,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: const Color(0xFF8B2FC9),
              inactiveTrackColor: Colors.white12,
              thumbColor: Colors.white,
              overlayColor: const Color(0xFF8B2FC9).withValues(alpha: 0.2),
              trackHeight: 3,
            ),
            child: Slider(
              value: (_radiusKm ?? 60.0).clamp(5.0, 60.0),
              min: 5.0,
              max: 60.0,
              divisions: 11,
              label: _radiusKm != null ? '${_radiusKm!.toInt()} km' : 'Unlimited',
              onChanged: (v) {
                setState(() {
                  _radiusKm = v >= 55.0 ? null : v;
                });
                _fetchFeed();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTabs(
      int riderCount, int sellerCount, int dualCount) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: TabBar(
        controller: _tabController,
        isScrollable: false,
        indicatorColor: const Color(0xFF8B2FC9),
        indicatorWeight: 3,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white38,
        labelStyle: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700),
        unselectedLabelStyle: GoogleFonts.outfit(fontSize: 12),
        tabs: [
          Tab(text: 'All (${_feedOrders.length})'),
          Tab(text: 'Rider ($riderCount)'),
          Tab(text: 'Shop ($sellerCount)'),
          Tab(text: 'Dual ($dualCount)'),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            size: 56,
            color: AdminColors.success.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 12),
          Text(
            _isProxyModeActive ? 'Dispatch Radar Clear' : 'Proxy Mode Inactive',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _isProxyModeActive
                ? 'No unaccepted orders currently within range.'
                : 'Turn ON Dispatch Radar to monitor live orders.',
            style: GoogleFonts.outfit(color: Colors.white54, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ── Order Card Widget ─────────────────────────────────────────────
class _DispatchOrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final VoidCallback onRiderAccept;
  final VoidCallback onSellerAccept;
  final VoidCallback onDualAccept;
  final VoidCallback? onExpire;

  const _DispatchOrderCard({
    required this.order,
    required this.onRiderAccept,
    required this.onSellerAccept,
    required this.onDualAccept,
    this.onExpire,
  });

  @override
  Widget build(BuildContext context) {
    final orderId = (order['order_id'] ?? '').toString();
    final shopName = (order['shop_name'] ?? 'Shop').toString();
    final customerName = (order['customer_name'] ?? 'Customer').toString();
    final totalAmount = (order['total_amount'] ?? 0.0).toDouble();
    final distanceKm = (order['distance_km'] ?? 0.0).toDouble();
    final itemCount = (order['item_count'] ?? 1).toInt();
    final bool riderAccepted = order['partner_accepted'] == true;
    final bool sellerAccepted = order['seller_accepted'] == true;
    final bool isPaid = order['payment_status'] == 'captured';

    final createdAtStr = order['created_at']?.toString();
    final createdAt =
        createdAtStr != null ? DateTime.tryParse(createdAtStr) : null;
    final relativeTime = createdAt != null
        ? DateTimeUtils.formatRelative(createdAt)
        : 'Recently';

    final acceptanceDeadlineStr = order['acceptance_deadline']?.toString();
    final acceptanceDeadline = acceptanceDeadlineStr != null
        ? DateTime.tryParse(acceptanceDeadlineStr)
        : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (!riderAccepted && !sellerAccepted)
              ? const Color(0xFF8B2FC9).withValues(alpha: 0.4)
              : AdminColors.cardBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: ID + Time + Amount
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '#${orderId.length > 8 ? orderId.substring(0, 8) : orderId}',
                  style: GoogleFonts.outfit(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '· $relativeTime',
                style: GoogleFonts.outfit(color: Colors.white38, fontSize: 11),
              ),
              const Spacer(),
              Text(
                '₹${totalAmount.toStringAsFixed(0)}',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Details: Shop & Customer
          Row(
            children: [
              const Icon(Icons.store_rounded, size: 16, color: Colors.amber),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  shopName,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (distanceKm > 0)
                Text(
                  '${distanceKm.toStringAsFixed(1)} km away',
                  style:
                      GoogleFonts.outfit(color: Colors.white54, fontSize: 11),
                ),
            ],
          ),

          const SizedBox(height: 6),

          Row(
            children: [
              const Icon(Icons.person_rounded, size: 16, color: Colors.white38),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  customerName,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ),
              Text(
                '$itemCount items · ${isPaid ? "💳 Paid" : "⏳ Unpaid"}',
                style: GoogleFonts.outfit(
                  color: isPaid ? AdminColors.success : Colors.amber,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Status Badges
          Row(
            children: [
              _StatusPill(
                icon: Icons.delivery_dining_rounded,
                label: riderAccepted ? 'Rider Confirmed' : 'Needs Rider',
                isAccepted: riderAccepted,
              ),
              const SizedBox(width: 8),
              _StatusPill(
                icon: Icons.kitchen_rounded,
                label: sellerAccepted ? 'Store Confirmed' : 'Needs Store',
                isAccepted: sellerAccepted,
              ),
            ],
          ),

          if (acceptanceDeadline != null && (!riderAccepted || !sellerAccepted)) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.timer_outlined,
                          size: 14, color: Colors.redAccent),
                      const SizedBox(width: 6),
                      Text(
                        'Acceptance Window',
                        style: GoogleFonts.outfit(
                          color: Colors.redAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  OrderCountdownTimer(
                    acceptanceDeadline: acceptanceDeadline,
                    fontSize: 12,
                    color: Colors.redAccent,
                    onExpire: onExpire,
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),

          // Action Buttons
          Row(
            children: [
              if (!riderAccepted)
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.delivery_dining_rounded,
                        size: 16, color: Colors.white),
                    label: Text(
                      'Accept Rider',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: onRiderAccept,
                  ),
                ),
              if (!riderAccepted && !sellerAccepted) const SizedBox(width: 8),
              if (!sellerAccepted)
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD97706),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.store_rounded,
                        size: 16, color: Colors.white),
                    label: Text(
                      'Accept Store',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: onSellerAccept,
                  ),
                ),
              if (!riderAccepted && !sellerAccepted) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '1-Tap Dual Accept Both',
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF8B2FC9),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.bolt_rounded,
                      color: Colors.white, size: 20),
                  onPressed: onDualAccept,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isAccepted;

  const _StatusPill({
    required this.icon,
    required this.label,
    required this.isAccepted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isAccepted
            ? AdminColors.success.withValues(alpha: 0.15)
            : AdminColors.danger.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: isAccepted ? AdminColors.success : AdminColors.danger,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.outfit(
              color: isAccepted ? AdminColors.success : AdminColors.danger,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Rider Assignment Modal ─────────────────────────────────────────
class _RiderAssignmentModal extends StatefulWidget {
  final Map<String, dynamic> order;
  final VoidCallback onDirectAccept;
  final void Function(String riderId, String? phone) onAssignRider;

  const _RiderAssignmentModal({
    required this.order,
    required this.onDirectAccept,
    required this.onAssignRider,
  });

  @override
  State<_RiderAssignmentModal> createState() => _RiderAssignmentModalState();
}

class _RiderAssignmentModalState extends State<_RiderAssignmentModal> {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _riders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchOnlineRiders();
  }

  Future<void> _fetchOnlineRiders() async {
    try {
      final res = await _supabase.rpc('admin_get_online_riders');
      if (mounted) {
        setState(() {
          _riders = List<Map<String, dynamic>>.from(res as List);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Accept on Rider Behalf',
            style: GoogleFonts.outfit(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Choose direct admin proxy (unlimited capacity) or assign to an active courier:',
            style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 16),

          // Option 1: Direct Admin Hold (Unlimited)
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFF2563EB)),
            ),
            tileColor: const Color(0xFF2563EB).withValues(alpha: 0.15),
            leading:
                const Icon(Icons.flash_on_rounded, color: Color(0xFF2563EB)),
            title: Text('Direct Proxy Hold (Unlimited)',
                style: GoogleFonts.outfit(
                    color: Colors.white, fontWeight: FontWeight.w700)),
            subtitle: Text('Accept delivery responsibility on admin fleet pool',
                style: GoogleFonts.outfit(color: Colors.white54, fontSize: 11)),
            trailing: const Icon(Icons.arrow_forward_ios_rounded,
                size: 14, color: Colors.white54),
            onTap: widget.onDirectAccept,
          ),

          const SizedBox(height: 16),
          Text(
            'Or Select Active Delivery Partner:',
            style: GoogleFonts.outfit(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),

          // Option 2: Active Riders List
          _loading
              ? const Center(
                  child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(
                    color: Color(0xFF8B2FC9),
                  ),
                ))
              : _riders.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No other couriers currently active.',
                        style: GoogleFonts.outfit(
                            color: Colors.white38, fontSize: 12),
                      ),
                    )
                  : SizedBox(
                      height: 160,
                      child: ListView.separated(
                        itemCount: _riders.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (ctx, i) {
                          final r = _riders[i];
                          final name = r['full_name'] ?? 'Courier';
                          final phone = r['phone'] ?? '';
                          final load = (r['active_orders_count'] ?? 0).toInt();

                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            tileColor: Colors.white.withValues(alpha: 0.05),
                            leading: const Icon(Icons.sports_motorsports_rounded,
                                color: Colors.white70, size: 20),
                            title: Text(name,
                                style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              'Load: $load orders active · $phone',
                              style: GoogleFonts.outfit(
                                  color: Colors.white38, fontSize: 11),
                            ),
                            trailing: TextButton(
                              child: Text('Assign',
                                  style: GoogleFonts.outfit(
                                      color: const Color(0xFF8B2FC9),
                                      fontWeight: FontWeight.w700)),
                              onPressed: () => widget.onAssignRider(
                                  r['rider_id'], phone),
                            ),
                          );
                        },
                      ),
                    ),
        ],
      ),
    );
  }
}

// ── Seller Accept Modal ───────────────────────────────────────────
class _SellerAcceptModal extends StatefulWidget {
  final String shopName;
  final void Function(int prepTimeMinutes) onConfirm;

  const _SellerAcceptModal({
    required this.shopName,
    required this.onConfirm,
  });

  @override
  State<_SellerAcceptModal> createState() => _SellerAcceptModalState();
}

class _SellerAcceptModalState extends State<_SellerAcceptModal> {
  int _prepTime = 15;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Accept on Store Behalf',
            style: GoogleFonts.outfit(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Accept order on behalf of "${widget.shopName}". Specify preparation time for the kitchen:',
            style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [10, 15, 25, 40].map((t) {
              final isSelected = _prepTime == t;
              return ChoiceChip(
                label: Text('$t mins'),
                selected: isSelected,
                selectedColor: const Color(0xFFD97706),
                backgroundColor: Colors.white.withValues(alpha: 0.05),
                labelStyle: GoogleFonts.outfit(
                  color: isSelected ? Colors.white : Colors.white60,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
                onSelected: (_) => setState(() => _prepTime = t),
              );
            }).toList(),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD97706),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => widget.onConfirm(_prepTime),
              child: Text(
                'Confirm Store Acceptance ($_prepTime mins)',
                style: GoogleFonts.outfit(
                    color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
