import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../providers/rbac_provider.dart';
import '../../../providers/notification_provider.dart';
import '../../../services/bell_alert_service.dart';
import '../../../services/admin_dispatch_settings_service.dart';
import '../../../config/routes.dart';
import '../../../theme/admin_theme.dart';
import '../../../utils/time_utils.dart';
import '../../../widgets/order_countdown_timer.dart';
import '../../../widgets/admin/practice_order_simulator_modal.dart';
import '../rbac/forbidden_page.dart';

class DispatchAdminPage extends StatefulWidget {
  const DispatchAdminPage({super.key});

  @override
  State<DispatchAdminPage> createState() => _DispatchAdminPageState();
}

class _DispatchAdminPageState extends State<DispatchAdminPage>
    with SingleTickerProviderStateMixin {
  final SupabaseClient _supabase = Supabase.instance.client;

  String? get _adminId => _supabase.auth.currentUser?.id;

  // ── Master Controls ──────────────────────────────────────────────
  bool _isProxyModeActive = false; // Loaded from AdminDispatchSettingsService per admin
  bool _isBuzzEnabled = true;
  bool _includeRiders = true;
  bool _includeSellers = true;
  double? _radiusKm = 15.0; // null = Unlimited
  bool _isSettingsLoaded = false;

  // ── Location State ───────────────────────────────────────────────
  double? _adminLat;
  double? _adminLng;
  bool _locationLoading = false;
  String _locationStatus = 'Detecting GPS...';

  // ── Data & Feeds ─────────────────────────────────────────────────
  List<Map<String, dynamic>> _feedOrders = [];
  List<Map<String, dynamic>> _bulkOrders = [];
  bool _isLoading = true;
  String _activeTab = 'All'; // 'All', 'Rider', 'Seller', 'Dual', 'Bulk'
  final Set<String> _trackedBuzzIds = {};

  // ── Realtime & Timers ────────────────────────────────────────────
  RealtimeChannel? _realtimeChannel;
  Timer? _pollingTimer;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _activeTab = switch (_tabController.index) {
            1 => 'Rider',
            2 => 'Seller',
            3 => 'Dual',
            4 => 'Bulk',
            _ => 'All',
          };
        });
      }
    });

    _loadAdminSettingsAndStart();
  }

  /// Hydrate persistent settings scoped to the currently authenticated admin
  Future<void> _loadAdminSettingsAndStart() async {
    final uid = _adminId;
    if (uid != null) {
      final active =
          await AdminDispatchSettingsService.instance.isRadarActive(uid);
      final buzz =
          await AdminDispatchSettingsService.instance.isBuzzEnabled(uid);
      final radius =
          await AdminDispatchSettingsService.instance.getRadiusKm(uid);
      if (mounted) {
        setState(() {
          _isProxyModeActive = active;
          _isBuzzEnabled = buzz;
          _radiusKm = radius;
          _isSettingsLoaded = true;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isSettingsLoaded = true;
        });
      }
    }

    if (_isProxyModeActive) {
      _startMonitoring();
    } else {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _startMonitoring() {
    _initGps();
    _fetchFeed();
    _setupRealtime();
    _startPeriodicRefresh();
    // Keep screen awake while actively monitoring radar
    WakelockPlus.enable().catchError((_) {});
  }

  void _stopMonitoring() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _realtimeChannel?.unsubscribe();
    _realtimeChannel = null;
    _silenceAllBuzz();
    WakelockPlus.disable().catchError((_) {});
    if (mounted) {
      setState(() {
        _feedOrders = [];
        _bulkOrders = [];
        _isLoading = false;
      });
    }
    AdminDispatchSettingsService.instance.updatePendingCount(0);
  }

  Future<void> _toggleProxyMode(bool val) async {
    final uid = _adminId;
    setState(() => _isProxyModeActive = val);
    if (uid != null) {
      await AdminDispatchSettingsService.instance
          .setRadarActive(uid, active: val);
    }
    if (val) {
      _startMonitoring();
      _showSnack('📡 Dispatch Radar Activated');
    } else {
      _stopMonitoring();
      _showSnack('Dispatch Radar Turned OFF');
    }
  }

  Future<void> _toggleBuzz() async {
    final newBuzz = !_isBuzzEnabled;
    setState(() => _isBuzzEnabled = newBuzz);
    final uid = _adminId;
    if (uid != null) {
      await AdminDispatchSettingsService.instance
          .setBuzzEnabled(uid, enabled: newBuzz);
    }
    if (!newBuzz) {
      _silenceAllBuzz();
      _showSnack('Audio buzz muted');
    } else {
      _syncAudioBuzz(_feedOrders);
      _showSnack('Audio buzz enabled');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _stopMonitoring();
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

      // Fetch active bulk orders
      List<Map<String, dynamic>> bulkList = [];
      try {
        final bulkData = await _supabase
            .from('orders')
            .select('''
              id, created_at, status, total_amount, payment_status,
              customer_notes, delivery_address, grand_total_collected,
              profiles:customer_id ( full_name, phone ),
              shops:shop_id ( id, name, phone ),
              bulk_orders (
                event_name, event_date, delivery_slot, total_guests,
                total_packages_estimate, delivery_method,
                seller_response_status, total_batches, batches_packed,
                bulk_dispatch_group_id
              )
            ''')
            .eq('order_type', 'bulk')
            .inFilter('status', [
              'bulk_pending',
              'bulk_confirmed',
              'bulk_preparing',
              'bulk_ready',
              'bulk_dispatched'
            ])
            .order('created_at', ascending: false);
        bulkList = List<Map<String, dynamic>>.from(bulkData as List);
      } catch (be) {
        debugPrint('Error fetching bulk orders in dispatch hub: $be');
      }

      setState(() {
        _feedOrders = orders;
        _bulkOrders = bulkList;
        _isLoading = false;
      });

      _syncAudioBuzz(orders);
      AdminDispatchSettingsService.instance.updatePendingCount(orders.length);
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF334155), width: 1.2),
        ),
        title: Text('Dual Proxy Accept',
            style: GoogleFonts.outfit(
                color: Colors.white, fontWeight: FontWeight.w700)),
        content: Text(
          'Confirm acceptance for BOTH the merchant and delivery rider simultaneously?\n\nThe order will advance directly to payment/preparation.',
          style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: const BorderSide(color: Color(0xFF475569)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: GoogleFonts.outfit(
                    color: Colors.white70, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
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

  void _showFleetAssignmentModal(Map<String, dynamic> order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _BulkFleetAssignmentModal(
        order: order,
        onDispatch: (dispatchType, riderAssignments, vehicleDetails) async {
          Navigator.pop(ctx);
          await _executeBulkFleetDispatch(
            order['id'] as String,
            dispatchType,
            riderAssignments: riderAssignments,
            vehicleDetails: vehicleDetails,
          );
        },
      ),
    );
  }

  Future<void> _executeBulkFleetDispatch(
    String orderId,
    String dispatchType, {
    List<Map<String, dynamic>>? riderAssignments,
    Map<String, dynamic>? vehicleDetails,
  }) async {
    try {
      HapticFeedback.mediumImpact();
      await _supabase.rpc('bulk_assign_fleet', params: {
        'p_order_id': orderId,
        'p_dispatch_type': dispatchType,
        'p_rider_assignments': riderAssignments ?? [],
        'p_vehicle_details': vehicleDetails,
      });

      if (!mounted) return;
      _showSnack(
        '🚀 Fleet dispatched successfully for bulk order!',
        isError: false,
      );
      _fetchFeed(silent: true);
    } catch (e) {
      _handleRpcError('Bulk Fleet Dispatch', e);
    }
  }

  // ── Build UI ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final rbac = context.watch<RbacProvider>();

    if (!rbac.isSuperAdmin && !rbac.can('dispatch.view')) {
      return const ForbiddenPage(fullPage: false);
    }

    if (!_isSettingsLoaded) {
      return const Center(
        child: CircularProgressIndicator(color: AdminColors.primary),
      );
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
    final bulkCount = _bulkOrders.length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // ── Top Radar Command Header ─────────────────────────────
          _buildCommandHeader(
              riderPendingCount, sellerPendingCount, dualPendingCount),

          // ── Navigation Filter Tabs ───────────────────────────────
          _buildFilterTabs(
              riderPendingCount, sellerPendingCount, dualPendingCount, bulkCount),

          // ── Orders Feed List ─────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF8B2FC9),
                    ),
                  )
                : _activeTab == 'Bulk'
                    ? _bulkOrders.isEmpty
                        ? _buildBulkEmptyState()
                        : RefreshIndicator(
                            onRefresh: () => _fetchFeed(),
                            color: const Color(0xFF8B2FC9),
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                              itemCount: _bulkOrders.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final bo = _bulkOrders[index];
                                return _DispatchBulkOrderCard(
                                  order: bo,
                                  onAssignFleet: () =>
                                      _showFleetAssignmentModal(bo),
                                );
                              },
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
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF334155), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Row 1: Master Mode + Buzz Toggle + Action Shortcuts (Compact, Responsive, Zero Overflow)
          Row(
            children: [
              // Pulse Indicator + Title (Flexible so it never overflows)
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isProxyModeActive
                            ? AdminColors.success
                            : AdminColors.textMuted,
                        boxShadow: _isProxyModeActive
                            ? [
                                BoxShadow(
                                  color: AdminColors.success.withValues(alpha: 0.6),
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                )
                              ]
                            : null,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'DISPATCH RADAR',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              // Master Switch
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _isProxyModeActive ? 'ACTIVE' : 'OFF',
                    style: GoogleFonts.outfit(
                      color: _isProxyModeActive
                          ? AdminColors.success
                          : AdminColors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Transform.scale(
                    scale: 0.75,
                    child: Switch(
                      value: _isProxyModeActive,
                      activeThumbColor: AdminColors.success,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: (val) => _toggleProxyMode(val),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              // Buzz Toggle
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  _isBuzzEnabled
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_off_rounded,
                  color: _isBuzzEnabled ? Colors.amber : Colors.white38,
                  size: 20,
                ),
                tooltip: _isBuzzEnabled ? 'Mute Buzzer' : 'Enable Buzzer',
                onPressed: _toggleBuzz,
              ),
              const SizedBox(width: 2),
              // Quotes Shortcut
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.receipt_long_rounded,
                  color: Colors.cyanAccent,
                  size: 20,
                ),
                tooltip: 'Event Quotes',
                onPressed: () {
                  Navigator.pushNamed(context, AppRoutes.adminQuoteReview);
                },
              ),
              const SizedBox(width: 2),
              // Practice Order Simulator Shortcut
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.science_rounded,
                  color: Color(0xFF38BDF8),
                  size: 20,
                ),
                tooltip: 'Practice Order Simulator',
                onPressed: () {
                  PracticeOrderSimulatorModal.show(context);
                },
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Sub-feed Toggles: Rider & Seller Channels (Solid high-contrast buttons)
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _includeRiders = !_includeRiders);
                    _fetchFeed();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: _includeRiders
                          ? const Color(0xFF2563EB)
                          : const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _includeRiders
                            ? const Color(0xFF3B82F6)
                            : const Color(0xFF334155),
                        width: 1.2,
                      ),
                      boxShadow: _includeRiders
                          ? [
                              BoxShadow(
                                color: const Color(0xFF2563EB)
                                    .withValues(alpha: 0.35),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              )
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.delivery_dining_rounded,
                          size: 18,
                          color: _includeRiders
                              ? Colors.white
                              : const Color(0xFF94A3B8),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Rider Channel',
                          style: GoogleFonts.outfit(
                            color: _includeRiders
                                ? Colors.white
                                : const Color(0xFF94A3B8),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _includeSellers = !_includeSellers);
                    _fetchFeed();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: _includeSellers
                          ? const Color(0xFFD97706)
                          : const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _includeSellers
                            ? const Color(0xFFF59E0B)
                            : const Color(0xFF334155),
                        width: 1.2,
                      ),
                      boxShadow: _includeSellers
                          ? [
                              BoxShadow(
                                color: const Color(0xFFD97706)
                                    .withValues(alpha: 0.35),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              )
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.store_rounded,
                          size: 18,
                          color: _includeSellers
                              ? Colors.white
                              : const Color(0xFF94A3B8),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Store Channel',
                          style: GoogleFonts.outfit(
                            color: _includeSellers
                                ? Colors.white
                                : const Color(0xFF94A3B8),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
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
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF334155)),
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
                        color: const Color(0xFF94A3B8),
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
                final newRadius = v >= 55.0 ? null : v;
                setState(() {
                  _radiusKm = newRadius;
                });
                final uid = _adminId;
                if (uid != null) {
                  AdminDispatchSettingsService.instance
                      .setRadiusKm(uid, newRadius);
                }
                _fetchFeed();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTabs(
      int riderCount, int sellerCount, int dualCount, int bulkCount) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
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
          Tab(text: 'Bulk 🎉 ($bulkCount)'),
        ],
      ),
    );
  }

  Widget _buildBulkEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.celebration_outlined,
            size: 56,
            color: Colors.purple.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 12),
          Text(
            'No Bulk Catering Orders',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Large event orders awaiting dispatch or preparation will appear here.',
            style: GoogleFonts.outfit(color: Colors.white54, fontSize: 13),
          ),
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
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (!riderAccepted && !sellerAccepted)
              ? const Color(0xFF8B2FC9)
              : const Color(0xFF334155),
          width: (!riderAccepted && !sellerAccepted) ? 1.5 : 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
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
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Text(
                  '#${orderId.length > 8 ? orderId.substring(0, 8) : orderId}',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '· $relativeTime',
                style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 11),
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
              const Icon(Icons.store_rounded, size: 16, color: Color(0xFFF59E0B)),
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
                      GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 11),
                ),
            ],
          ),

          const SizedBox(height: 6),

          Row(
            children: [
              const Icon(Icons.person_rounded, size: 16, color: Color(0xFF64748B)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  customerName,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: const Color(0xFFCBD5E1),
                    fontSize: 12,
                  ),
                ),
              ),
              Text(
                '$itemCount items · ${isPaid ? "💳 Paid" : "⏳ Unpaid"}',
                style: GoogleFonts.outfit(
                  color: isPaid ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
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
                color: const Color(0xFF2D1515),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFDC2626).withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.timer_outlined,
                          size: 14, color: Color(0xFFF87171)),
                      const SizedBox(width: 6),
                      Text(
                        'Acceptance Window',
                        style: GoogleFonts.outfit(
                          color: const Color(0xFFF87171),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  OrderCountdownTimer(
                    acceptanceDeadline: acceptanceDeadline,
                    fontSize: 12,
                    color: const Color(0xFFF87171),
                    onExpire: onExpire,
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),

          // Action Buttons: Even, High-Contrast, Balanced Layout
          if (!riderAccepted && !sellerAccepted) ...[
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.delivery_dining_rounded,
                          size: 18, color: Colors.white),
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
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD97706),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.store_rounded,
                          size: 18, color: Colors.white),
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
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.bolt_rounded,
                    color: Color(0xFFFDE047), size: 20),
                label: Text(
                  '⚡ 1-Tap Dual Accept (Rider + Store)',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                onPressed: onDualAccept,
              ),
            ),
          ] else if (!riderAccepted) ...[
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.delivery_dining_rounded,
                    size: 18, color: Colors.white),
                label: Text(
                  'Accept on Rider Behalf',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onPressed: onRiderAccept,
              ),
            ),
          ] else if (!sellerAccepted) ...[
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD97706),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.store_rounded,
                    size: 18, color: Colors.white),
                label: Text(
                  'Accept on Store Behalf',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onPressed: onSellerAccept,
              ),
            ),
          ],
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isAccepted
            ? const Color(0xFF064E3B)
            : const Color(0xFF450A0A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isAccepted ? const Color(0xFF059669) : const Color(0xFFDC2626),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: isAccepted ? const Color(0xFF6EE7B7) : const Color(0xFFFCA5A5),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.outfit(
              color: isAccepted ? const Color(0xFF6EE7B7) : const Color(0xFFFCA5A5),
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
            style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 12),
          ),
          const SizedBox(height: 16),

          // Option 1: Direct Admin Hold (Unlimited)
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2563EB), width: 1.5),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: widget.onDirectAccept,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.flash_on_rounded, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Direct Proxy Hold (Unlimited)',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Accept delivery responsibility on admin fleet pool',
                              style: GoogleFonts.outfit(
                                color: const Color(0xFF94A3B8),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios_rounded,
                          size: 14, color: Color(0xFF94A3B8)),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),
          Text(
            'Or Select Active Delivery Partner:',
            style: GoogleFonts.outfit(
                color: const Color(0xFFCBD5E1),
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
                            color: const Color(0xFF94A3B8), fontSize: 12),
                      ),
                    )
                  : SizedBox(
                      height: 180,
                      child: ListView.separated(
                        itemCount: _riders.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (ctx, i) {
                          final r = _riders[i];
                          final name = r['full_name'] ?? 'Courier';
                          final phone = r['phone'] ?? '';
                          final load = (r['active_orders_count'] ?? 0).toInt();

                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFF334155)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1E293B),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.sports_motorsports_rounded,
                                    color: Color(0xFF38BDF8),
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: GoogleFonts.outfit(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Load: $load active · $phone',
                                        style: GoogleFonts.outfit(
                                          color: const Color(0xFF94A3B8),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF8B2FC9),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 8),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    elevation: 0,
                                  ),
                                  onPressed: () => widget.onAssignRider(
                                      r['rider_id'], phone),
                                  child: Text(
                                    'Assign',
                                    style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
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
            style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 12),
          ),
          const SizedBox(height: 18),
          Row(
            children: [10, 15, 25, 40].map((t) {
              final isSelected = _prepTime == t;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _prepTime = t);
                    },
                    child: Container(
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFD97706)
                            : const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFFF59E0B)
                              : const Color(0xFF334155),
                          width: isSelected ? 1.5 : 1.0,
                        ),
                      ),
                      child: Text(
                        '$t mins',
                        style: GoogleFonts.outfit(
                          color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
                          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD97706),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              onPressed: () => widget.onConfirm(_prepTime),
              child: Text(
                'Confirm Store Acceptance ($_prepTime mins)',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bulk Order Card Widget ─────────────────────────────────────────────
class _DispatchBulkOrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final VoidCallback onAssignFleet;

  const _DispatchBulkOrderCard({
    required this.order,
    required this.onAssignFleet,
  });

  @override
  Widget build(BuildContext context) {
    final orderId = (order['id'] ?? '').toString();
    final status = (order['status'] ?? 'bulk_pending').toString();
    final totalAmount = (order['total_amount'] as num?)?.toDouble() ?? 0.0;
    final grandTotal =
        (order['grand_total_collected'] as num?)?.toDouble() ?? totalAmount;
    final isPaid = order['payment_status'] == 'captured';
    final deliveryAddress =
        (order['delivery_address'] ?? 'No address').toString();
    final notes = (order['customer_notes'] ?? '').toString();

    final shop = (order['shops'] is Map)
        ? order['shops'] as Map<String, dynamic>
        : (order['shops'] is List && (order['shops'] as List).isNotEmpty
            ? (order['shops'] as List).first as Map<String, dynamic>
            : null);
    final profile = (order['profiles'] is Map)
        ? order['profiles'] as Map<String, dynamic>
        : (order['profiles'] is List && (order['profiles'] as List).isNotEmpty
            ? (order['profiles'] as List).first as Map<String, dynamic>
            : null);

    final bulk = (order['bulk_orders'] is List &&
            (order['bulk_orders'] as List).isNotEmpty)
        ? (order['bulk_orders'] as List).first as Map<String, dynamic>
        : (order['bulk_orders'] is Map
            ? order['bulk_orders'] as Map<String, dynamic>
            : <String, dynamic>{});

    final eventName = (bulk['event_name'] ?? 'Event Catering').toString();
    final eventDateStr = (bulk['event_date'] ?? '').toString();
    final deliverySlot = (bulk['delivery_slot'] ?? 'Flexible Slot').toString();
    final totalGuests = (bulk['total_guests'] as num?)?.toInt() ?? 0;
    final totalPackages =
        (bulk['total_packages_estimate'] as num?)?.toInt() ?? 1;
    final totalBatches = (bulk['total_batches'] as num?)?.toInt() ?? 1;
    final batchesPacked = (bulk['batches_packed'] as num?)?.toInt() ?? 0;
    final deliveryMethod =
        (bulk['delivery_method'] ?? 'platform_fleet').toString();

    String formattedDate = eventDateStr;
    try {
      if (eventDateStr.isNotEmpty) {
        final d = DateTime.parse(eventDateStr);
        formattedDate = DateFormat('EEE, dd MMM yyyy').format(d);
      }
    } catch (_) {}

    final (statusColor, statusLabel, statusIcon) = switch (status) {
      'bulk_pending' => (
          const Color(0xFFF59E0B),
          'Pending Store',
          Icons.hourglass_top_rounded
        ),
      'bulk_confirmed' => (
          const Color(0xFF3B82F6),
          'Store Confirmed',
          Icons.thumb_up_alt_rounded
        ),
      'bulk_preparing' => (
          const Color(0xFF8B2FC9),
          'Kitchen Prep',
          Icons.soup_kitchen_rounded
        ),
      'bulk_ready' => (
          const Color(0xFF10B981),
          'Ready for Fleet',
          Icons.inventory_2_rounded
        ),
      'bulk_dispatched' => (
          const Color(0xFF06B6D4),
          'Fleet Dispatched',
          Icons.local_shipping_rounded
        ),
      'delivered' || 'bulk_delivered' => (
          const Color(0xFF10B981),
          'Delivered',
          Icons.check_circle_rounded
        ),
      'bulk_cancelled' || 'cancelled' => (
          const Color(0xFFEF4444),
          'Cancelled',
          Icons.cancel_rounded
        ),
      _ => (const Color(0xFF94A3B8), status, Icons.info_outline_rounded),
    };

    final bool canAssignFleet = status == 'bulk_ready' ||
        status == 'bulk_preparing' ||
        status == 'bulk_confirmed';
    final bool isDispatched = status == 'bulk_dispatched';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: status == 'bulk_ready'
              ? const Color(0xFF10B981)
              : const Color(0xFF334155),
          width: status == 'bulk_ready' ? 1.5 : 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: ID, Bulk Chip, Status Pill, Amount
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Text(
                  '#${orderId.length > 8 ? orderId.substring(0, 8).toUpperCase() : orderId}',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border:
                      Border.all(color: Colors.purple.withValues(alpha: 0.4)),
                ),
                child: const Text(
                  '🎉 BULK CATERING',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.purpleAccent,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '₹${grandTotal.toStringAsFixed(0)}',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Row 2: Event Name & Status Badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  eventName,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: statusColor.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, color: statusColor, size: 13),
                    const SizedBox(width: 4),
                    Text(
                      statusLabel,
                      style: GoogleFonts.outfit(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Row 3: Event Info Chips (Date, Slot, Guests, Packages)
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (formattedDate.isNotEmpty)
                _InfoChip(
                    icon: Icons.calendar_today_rounded, label: formattedDate),
              if (deliverySlot.isNotEmpty)
                _InfoChip(icon: Icons.access_time_rounded, label: deliverySlot),
              if (totalGuests > 0)
                _InfoChip(
                    icon: Icons.people_alt_rounded,
                    label: '$totalGuests guests'),
              _InfoChip(
                  icon: Icons.inventory_2_outlined,
                  label: '~$totalPackages pkgs'),
              _InfoChip(
                icon: Icons.payment_rounded,
                label: isPaid ? 'Paid Online 💳' : 'Payment Pending',
                color: isPaid
                    ? const Color(0xFF10B981)
                    : const Color(0xFFF59E0B),
              ),
            ],
          ),

          const SizedBox(height: 12),
          const Divider(color: Color(0xFF334155), height: 1),
          const SizedBox(height: 10),

          // Row 4: Shop & Customer Details
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.storefront_rounded,
                            size: 14, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            shop?['name'] ?? 'Restaurant',
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.person_rounded,
                            size: 14, color: Color(0xFF94A3B8)),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            '${profile?['full_name'] ?? 'Customer'}${profile?['phone'] != null ? " • ${profile!['phone']}" : ""}',
                            style: GoogleFonts.outfit(
                              color: const Color(0xFFCBD5E1),
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.location_on_rounded,
                  size: 14, color: Color(0xFFE2E8F0)),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  deliveryAddress,
                  style: GoogleFonts.outfit(
                    color: const Color(0xFF94A3B8),
                    fontSize: 11,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          if (notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.note_rounded,
                    size: 13, color: Color(0xFFF59E0B)),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'Notes: $notes',
                    style: GoogleFonts.outfit(
                      color: const Color(0xFFF59E0B),
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],

          // Batch Packaging Progress (if preparing or batches packed)
          if (totalBatches > 1 || batchesPacked > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Kitchen Batch Packaging',
                        style: GoogleFonts.outfit(
                          color: const Color(0xFF94A3B8),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '$batchesPacked / $totalBatches batches packed',
                        style: GoogleFonts.outfit(
                          color: batchesPacked >= totalBatches
                              ? const Color(0xFF10B981)
                              : const Color(0xFFA855F7),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: totalBatches > 0
                          ? (batchesPacked / totalBatches).clamp(0.0, 1.0)
                          : 0.0,
                      backgroundColor: const Color(0xFF334155),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        batchesPacked >= totalBatches
                            ? const Color(0xFF10B981)
                            : const Color(0xFFA855F7),
                      ),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),

          // Row 5: Action Button (Assign Fleet / Reassign)
          if (canAssignFleet || isDispatched)
            Row(
              children: [
                if (isDispatched) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF06B6D4).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: const Color(0xFF06B6D4)
                              .withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded,
                            color: Color(0xFF06B6D4), size: 14),
                        const SizedBox(width: 5),
                        Text(
                          deliveryMethod == 'merchant_delivery'
                              ? 'Merchant Transport Assigned'
                              : 'Fleet Assigned & Active',
                          style: GoogleFonts.outfit(
                            color: const Color(0xFF06B6D4),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF475569)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: onAssignFleet,
                    child: Text('Reassign',
                        style: GoogleFonts.outfit(fontSize: 12)),
                  ),
                ] else ...[
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: status == 'bulk_ready'
                              ? const Color(0xFF10B981)
                              : const Color(0xFF8B2FC9),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                        ),
                        onPressed: onAssignFleet,
                        icon: Icon(
                          status == 'bulk_ready'
                              ? Icons.local_shipping_rounded
                              : Icons.schedule_send_rounded,
                          size: 18,
                        ),
                        label: Text(
                          status == 'bulk_ready'
                              ? 'Assign Fleet Now 🚀'
                              : 'Pre-Assign Fleet (Prep in Progress)',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _InfoChip({
    required this.icon,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFF94A3B8);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: c),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.outfit(
              color: c,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bulk Fleet Assignment Modal ──────────────────────────────────────────
class _BulkFleetAssignmentModal extends StatefulWidget {
  final Map<String, dynamic> order;
  final void Function(
    String dispatchType,
    List<Map<String, dynamic>>? riderAssignments,
    Map<String, dynamic>? vehicleDetails,
  ) onDispatch;

  const _BulkFleetAssignmentModal({
    required this.order,
    required this.onDispatch,
  });

  @override
  State<_BulkFleetAssignmentModal> createState() =>
      _BulkFleetAssignmentModalState();
}

class _BulkFleetAssignmentModalState extends State<_BulkFleetAssignmentModal> {
  final SupabaseClient _supabase = Supabase.instance.client;

  String _dispatchType =
      'multi_rider'; // 'multi_rider', 'dedicated_vehicle', 'merchant_delivery'
  List<Map<String, dynamic>> _riders = [];
  bool _loadingRiders = true;

  // Multi-rider state: Map of rider_id -> packages_assigned
  final Map<String, int> _riderPackages = {};

  // Dedicated vehicle state
  String _vehicleType = 'Mini-Truck (Tata Ace)';
  final TextEditingController _driverNameController = TextEditingController();
  final TextEditingController _driverPhoneController = TextEditingController();
  final TextEditingController _plateNumberController = TextEditingController();

  static const List<String> _vehicleTypes = [
    'Mini-Truck (Tata Ace)',
    'Delivery Van (Eeco / Omni)',
    '3-Wheeler Auto Cargo',
    'Large SUV / Utility Car',
  ];

  @override
  void initState() {
    super.initState();
    _fetchOnlineRiders();
  }

  @override
  void dispose() {
    _driverNameController.dispose();
    _driverPhoneController.dispose();
    _plateNumberController.dispose();
    super.dispose();
  }

  Future<void> _fetchOnlineRiders() async {
    try {
      final res = await _supabase.rpc('admin_get_online_riders');
      if (mounted) {
        setState(() {
          _riders = List<Map<String, dynamic>>.from(res as List);
          _loadingRiders = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingRiders = false);
    }
  }

  int get _totalPackagesEstimate {
    final bulk = (widget.order['bulk_orders'] is List &&
            (widget.order['bulk_orders'] as List).isNotEmpty)
        ? (widget.order['bulk_orders'] as List).first as Map<String, dynamic>
        : (widget.order['bulk_orders'] is Map
            ? widget.order['bulk_orders'] as Map<String, dynamic>
            : <String, dynamic>{});
    return (bulk['total_packages_estimate'] as num?)?.toInt() ?? 1;
  }

  int get _allocatedPackages {
    return _riderPackages.values.fold(0, (sum, val) => sum + val);
  }

  void _onConfirm() {
    HapticFeedback.mediumImpact();
    if (_dispatchType == 'multi_rider') {
      if (_riderPackages.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Please select at least 1 courier.',
              style: GoogleFonts.outfit(color: Colors.white),
            ),
            backgroundColor: AdminColors.danger,
          ),
        );
        return;
      }

      final riderAssignments = _riderPackages.entries.map((e) {
        return {
          'rider_id': e.key,
          'packages': e.value,
        };
      }).toList();

      widget.onDispatch('multi_rider', riderAssignments, null);
    } else if (_dispatchType == 'dedicated_vehicle') {
      final driverName = _driverNameController.text.trim();
      final driverPhone = _driverPhoneController.text.trim();
      final plateNumber = _plateNumberController.text.trim();

      if (driverName.isEmpty || driverPhone.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Please provide driver name and contact number.',
              style: GoogleFonts.outfit(color: Colors.white),
            ),
            backgroundColor: AdminColors.danger,
          ),
        );
        return;
      }

      final vehicleDetails = {
        'vehicle_type': _vehicleType,
        'driver_name': driverName,
        'driver_phone': driverPhone,
        'vehicle_plate_number': plateNumber,
      };

      widget.onDispatch('dedicated_vehicle', null, vehicleDetails);
    } else {
      // merchant_delivery
      widget.onDispatch('merchant_delivery', null, null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final orderId = (widget.order['id'] ?? '').toString();
    final targetPackages = _totalPackagesEstimate;
    final allocated = _allocatedPackages;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B2FC9).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.local_shipping_rounded,
                  color: Color(0xFFC084FC),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bulk Fleet Coordination',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Order #${orderId.length > 8 ? orderId.substring(0, 8).toUpperCase() : orderId} · ~$targetPackages packages',
                      style: GoogleFonts.outfit(
                        color: const Color(0xFF94A3B8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white54),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Dispatch Type Selector
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Row(
              children: [
                _TypeTab(
                  label: 'Multi-Rider 🛵',
                  selected: _dispatchType == 'multi_rider',
                  onTap: () => setState(() => _dispatchType = 'multi_rider'),
                ),
                _TypeTab(
                  label: 'Vehicle 🚚',
                  selected: _dispatchType == 'dedicated_vehicle',
                  onTap: () =>
                      setState(() => _dispatchType = 'dedicated_vehicle'),
                ),
                _TypeTab(
                  label: 'Store Direct 🏪',
                  selected: _dispatchType == 'merchant_delivery',
                  onTap: () =>
                      setState(() => _dispatchType = 'merchant_delivery'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Dynamic Body
          Flexible(
            child: SingleChildScrollView(
              child: switch (_dispatchType) {
                'multi_rider' =>
                  _buildMultiRiderSection(targetPackages, allocated),
                'dedicated_vehicle' => _buildDedicatedVehicleSection(),
                'merchant_delivery' => _buildMerchantDeliverySection(),
                _ => const SizedBox.shrink(),
              },
            ),
          ),

          const SizedBox(height: 16),

          // Action Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8B2FC9),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              onPressed: _onConfirm,
              child: Text(
                _dispatchType == 'multi_rider'
                    ? 'Dispatch ${_riderPackages.length} Rider(s) ($allocated pkgs)'
                    : _dispatchType == 'dedicated_vehicle'
                        ? 'Dispatch Vehicle & Driver'
                        : 'Confirm Store Direct Delivery',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMultiRiderSection(int targetPackages, int allocated) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Allocation summary pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: allocated >= targetPackages
                ? const Color(0xFF10B981).withValues(alpha: 0.15)
                : const Color(0xFFF59E0B).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: allocated >= targetPackages
                  ? const Color(0xFF10B981)
                  : const Color(0xFFF59E0B),
              width: 1.2,
            ),
          ),
          child: Row(
            children: [
              Icon(
                allocated >= targetPackages
                    ? Icons.check_circle_rounded
                    : Icons.info_outline_rounded,
                size: 16,
                color: allocated >= targetPackages
                    ? const Color(0xFF10B981)
                    : const Color(0xFFF59E0B),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Packages Assigned: $allocated of $targetPackages estimated',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),
        Text(
          'Select Active Couriers:',
          style: GoogleFonts.outfit(
            color: const Color(0xFF94A3B8),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),

        if (_loadingRiders)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(color: Color(0xFF8B2FC9)),
            ),
          )
        else if (_riders.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                'No delivery partners currently active/online.',
                style: GoogleFonts.outfit(color: Colors.white54, fontSize: 13),
              ),
            ),
          )
        else
          ..._riders.map((r) {
            final riderId = (r['rider_id'] ?? '').toString();
            final name = (r['full_name'] ?? 'Rider').toString();
            final phone = (r['phone'] ?? '').toString();
            final isSelected = _riderPackages.containsKey(riderId);
            final packagesCount = _riderPackages[riderId] ?? 1;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF8B2FC9).withValues(alpha: 0.15)
                    : const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF8B2FC9)
                      : const Color(0xFF334155),
                  width: isSelected ? 1.5 : 1.0,
                ),
              ),
              child: Row(
                children: [
                  Checkbox(
                    value: isSelected,
                    activeColor: const Color(0xFF8B2FC9),
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _riderPackages[riderId] = 1;
                        } else {
                          _riderPackages.remove(riderId);
                        }
                      });
                    },
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (phone.isNotEmpty)
                          Text(
                            phone,
                            style: GoogleFonts.outfit(
                              color: const Color(0xFF94A3B8),
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (isSelected)
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline_rounded,
                              color: Colors.white70, size: 20),
                          onPressed: () {
                            if (packagesCount > 1) {
                              setState(() {
                                _riderPackages[riderId] = packagesCount - 1;
                              });
                            }
                          },
                        ),
                        Text(
                          '$packagesCount pkg',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline_rounded,
                              color: Colors.white70, size: 20),
                          onPressed: () {
                            setState(() {
                              _riderPackages[riderId] = packagesCount + 1;
                            });
                          },
                        ),
                      ],
                    ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildDedicatedVehicleSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Vehicle Type',
          style: GoogleFonts.outfit(
            color: const Color(0xFF94A3B8),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _vehicleType,
              isExpanded: true,
              dropdownColor: const Color(0xFF0F172A),
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
              icon: const Icon(Icons.arrow_drop_down_rounded,
                  color: Colors.white70),
              items: _vehicleTypes.map((v) {
                return DropdownMenuItem<String>(
                  value: v,
                  child: Text(v),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _vehicleType = val);
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildTextField(
            'Driver Full Name', _driverNameController, 'e.g. Ramesh Kumar'),
        const SizedBox(height: 12),
        _buildTextField(
            'Driver Phone Number', _driverPhoneController, 'e.g. 9876543210',
            keyboardType: TextInputType.phone),
        const SizedBox(height: 12),
        _buildTextField('Vehicle Number Plate (Optional)',
            _plateNumberController, 'e.g. DL 01 AB 1234'),
      ],
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller,
    String hint, {
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.outfit(
            color: const Color(0xFF94A3B8),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.outfit(
                color: const Color(0xFF64748B), fontSize: 13),
            filled: true,
            fillColor: const Color(0xFF0F172A),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF334155)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF334155)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  const BorderSide(color: Color(0xFF8B2FC9), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMerchantDeliverySection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storefront_rounded,
                  color: Color(0xFFF59E0B), size: 20),
              const SizedBox(width: 8),
              Text(
                'Store Self-Delivery Mode',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'The restaurant / store has arranged their own dedicated staff or vehicle for delivering this large catering order. No platform delivery partners will be assigned.',
            style: GoogleFonts.outfit(
              color: const Color(0xFF94A3B8),
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TypeTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF8B2FC9) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: GoogleFonts.outfit(
              color: selected ? Colors.white : const Color(0xFF94A3B8),
              fontSize: 12,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

