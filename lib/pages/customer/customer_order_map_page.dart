import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/order_model.dart';
import '../../theme/app_colors.dart';
import '../../utils/geo_utils.dart';
import '../../widgets/common/animated_moving_marker.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Colour palette (customer perspective)
// ─────────────────────────────────────────────────────────────────────────────
const _kPickupColor = Color(0xFF2ECC71); // green  — rider → shop
const _kDeliveryColor = Color(0xFFFF8C42); // orange — shop → customer
const _kShopMarkerColor = Color(0xFFFF8C42);
const _kShopCancelledColor = Color(0xFF95A5A6); // grey — cancelled / rejected shop
const _kShopPickedUpColor = Color(0xFF3498DB); // blue — picked up
const _kCustomerMarkerColor = Color(0xFF00B4D8); // cyan — customer home
const _kRiderMarkerColor = Color(0xFF2ECC71); // green — live rider

// ─────────────────────────────────────────────────────────────────────────────
// CustomerOrderMapPage
// Full-screen geospatial live tracking map for the customer. Shows:
//   • Live Rider → Shop pickup leg (green) when rider is en route to shop
//   • Shop → Customer delivery polyline (orange)
//   • Live animated moving rider marker with dynamic heading orientation
//   • Distance + Estimated arrival chips (calculated along true road curves)
//   • Direct Call Shop & Call Rider action buttons
//   • Live GPS freshness ticker ("Updated X seconds ago")
//   • Instant partial order rejection recalculations
// ─────────────────────────────────────────────────────────────────────────────
class CustomerOrderMapPage extends StatefulWidget {
  final OrderModel order;
  final List<OrderModel>? groupOrders;

  const CustomerOrderMapPage({
    super.key,
    required this.order,
    this.groupOrders,
  });

  @override
  State<CustomerOrderMapPage> createState() => _CustomerOrderMapPageState();
}

class _CustomerOrderMapPageState extends State<CustomerOrderMapPage>
    with WidgetsBindingObserver {
  final MapController _mapCtrl = MapController();
  SupabaseClient get _supabase => Supabase.instance.client;

  late OrderModel _currentOrder;
  late List<OrderModel> _currentGroupOrders;

  // Route data
  List<List<LatLng>> _deliveryRoutes = [];
  List<LatLng> _pickupRoute = [];
  bool _loadingRoutes = true;
  double? _deliveryKm;
  LatLng? _lastPickupFetchPos;

  // Live rider position (isolated via ValueNotifier to prevent map re-renders)
  final ValueNotifier<Map<String, LatLng>> _riderLocationsNotifier =
      ValueNotifier({});
  final ValueNotifier<Map<String, DateTime>> _riderUpdatedAtsNotifier =
      ValueNotifier({});
  RealtimeChannel? _channel;
  bool _isIntentionalDisconnect = false;
  Timer? _updateTickerTimer;
  final ValueNotifier<int> _timeTicker = ValueNotifier(0);
  final Map<String, String> _orderToRiderMap = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _currentOrder = widget.order;
    _currentGroupOrders = (widget.groupOrders != null &&
            widget.groupOrders!.isNotEmpty)
        ? List<OrderModel>.from(widget.groupOrders!)
        : [_currentOrder];

    _updateTickerTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _timeTicker.value++;
    });

    final initialLocs = <String, LatLng>{};
    final initialAts = <String, DateTime>{};
    for (final o in _currentGroupOrders) {
      if (o.deliveryPartnerId != null) {
        _orderToRiderMap[o.id] = o.deliveryPartnerId!;
        if (o.riderLat != null && o.riderLng != null && o.riderLat != 0.0) {
          initialLocs[o.deliveryPartnerId!] = LatLng(o.riderLat!, o.riderLng!);
          if (o.riderLocationUpdatedAt != null) {
            initialAts[o.deliveryPartnerId!] = o.riderLocationUpdatedAt!;
          }
        }
      }
    }
    _riderLocationsNotifier.value = initialLocs;
    _riderUpdatedAtsNotifier.value = initialAts;

    _fetchRoutes();
    _subscribeToRider();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _updateTickerTimer?.cancel();
    _timeTicker.dispose();
    _riderLocationsNotifier.dispose();
    _riderUpdatedAtsNotifier.dispose();
    if (_channel != null) {
      _isIntentionalDisconnect = true;
      _supabase.removeChannel(_channel!);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (mounted) {
        _subscribeToRider();
      }
    }
  }

  // ── Supabase Realtime Subscription ─────────────────────────────────────────

  void _subscribeToRider() {
    if (_channel != null) {
      _isIntentionalDisconnect = true;
      _supabase.removeChannel(_channel!);
      _channel = null;
    }
    _isIntentionalDisconnect = false;

    final cartGroupId = _currentOrder.cartGroupId;
    final channelName = cartGroupId != null
        ? 'customer-map-group-$cartGroupId'
        : 'customer-map-${_currentOrder.id}';

    _channel = _supabase
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: cartGroupId != null ? 'cart_group_id' : 'id',
            value: cartGroupId ?? _currentOrder.id,
          ),
          callback: (payload) {
            if (!mounted || payload.newRecord.isEmpty) return;
            final r = payload.newRecord;
            final updatedOrder = OrderModel.fromMap(r);

            final newStatus = r['status'] as String?;
            final pid = r['delivery_partner_id'] as String?;
            final orderId = r['id'] as String;

            // 1. Update local order cache
            final idx = _currentGroupOrders.indexWhere((o) => o.id == orderId);
            if (idx != -1) {
              updatedOrder.items = _currentGroupOrders[idx].items;
              setState(() {
                _currentGroupOrders[idx] = updatedOrder;
                if (_currentOrder.id == orderId) {
                  _currentOrder = updatedOrder;
                }
              });
            } else {
              setState(() {
                _currentGroupOrders.add(updatedOrder);
              });
            }

            final activeOrders = _currentGroupOrders
                .where((o) =>
                    o.status != 'rejected' &&
                    o.status != 'cancelled' &&
                    o.status != 'seller_rejected')
                .toList();

            // 2. Handle complete order termination
            if (activeOrders.isEmpty) {
              if (pid != null) {
                _removeRiderLocation(pid);
              }
              if (mounted && Navigator.canPop(context)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Order was cancelled or rejected.'),
                    backgroundColor: AppColors.danger,
                  ),
                );
                Navigator.of(context).pop();
              }
              return;
            }

            // 3. Handle Partial Rejection or Status Change -> Recompute Routes
            if (newStatus == 'rejected' ||
                newStatus == 'cancelled' ||
                newStatus == 'seller_rejected' ||
                newStatus == 'picked_up' ||
                newStatus == 'out_for_delivery') {
              _fetchRoutes(silent: true);
            }

            // 4. Handle Reassignments & Unassignments
            final oldPid = _orderToRiderMap[orderId];
            if (oldPid != null && oldPid != pid) {
              _removeRiderLocation(oldPid);
            }

            if (pid != null) {
              _orderToRiderMap[orderId] = pid;
            } else {
              _orderToRiderMap.remove(orderId);
            }

            // 5. Handle Rider GPS Coordinates
            final lat = (r['rider_lat'] as num?)?.toDouble();
            final lng = (r['rider_lng'] as num?)?.toDouble();

            if (lat != null && lng != null && pid != null && lat != 0.0) {
              final oldLoc = _riderLocationsNotifier.value[pid];
              final newLoc = LatLng(lat, lng);
              final bool locChanged = oldLoc == null ||
                  oldLoc.latitude != newLoc.latitude ||
                  oldLoc.longitude != newLoc.longitude;

              if (locChanged) {
                final currentLocs =
                    Map<String, LatLng>.from(_riderLocationsNotifier.value);
                currentLocs[pid] = newLoc;
                _riderLocationsNotifier.value = currentLocs;

                // Dynamically refresh pickup route if rider moved > 50m
                if (_currentOrder.status != 'out_for_delivery' &&
                    (_lastPickupFetchPos == null ||
                        const Distance().as(
                                LengthUnit.Meter, _lastPickupFetchPos!, newLoc) >
                            50)) {
                  _lastPickupFetchPos = newLoc;
                  _refreshPickupRoute(newLoc);
                }
              }

              final updatedStr = r['rider_location_updated_at'] as String?;
              final updated = updatedStr != null
                  ? DateTime.tryParse(updatedStr)
                  : DateTime.now();

              if (updated != null) {
                final currentAts =
                    Map<String, DateTime>.from(_riderUpdatedAtsNotifier.value);
                currentAts[pid] = updated;
                _riderUpdatedAtsNotifier.value = currentAts;
              }
            }
          },
        )
        .subscribe((status, [error]) {
      if ((status == RealtimeSubscribeStatus.closed ||
              status == RealtimeSubscribeStatus.channelError) &&
          !_isIntentionalDisconnect) {
        debugPrint('Realtime channel disconnected. Reconnecting in 4s...');
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted) _subscribeToRider();
        });
      }
    });
  }

  void _removeRiderLocation(String pid) {
    if (_riderLocationsNotifier.value.containsKey(pid)) {
      final currentLocs =
          Map<String, LatLng>.from(_riderLocationsNotifier.value);
      currentLocs.remove(pid);
      _riderLocationsNotifier.value = currentLocs;
    }
    if (_riderUpdatedAtsNotifier.value.containsKey(pid)) {
      final currentAts =
          Map<String, DateTime>.from(_riderUpdatedAtsNotifier.value);
      currentAts.remove(pid);
      _riderUpdatedAtsNotifier.value = currentAts;
    }
  }

  // ── Route Computation ──────────────────────────────────────────────────────

  Future<void> _fetchRoutes({bool silent = false}) async {
    if (!silent) {
      setState(() => _loadingRoutes = true);
    }

    final custLat = _currentOrder.deliveryLat;
    final custLng = _currentOrder.deliveryLng;

    if (custLat == null || custLng == null || custLat == 0.0) {
      if (mounted) setState(() => _loadingRoutes = false);
      return;
    }
    final custPt = LatLng(custLat, custLng);

    final activeShops = _currentGroupOrders
        .where((s) =>
            s.status != 'rejected' &&
            s.status != 'cancelled' &&
            s.status != 'seller_rejected')
        .toList();
    final shops =
        activeShops.isNotEmpty ? activeShops : _currentGroupOrders;

    List<List<LatLng>> deliveryRoutes = [];
    double totalDeliveryKm = 0;

    // 1. Fetch Delivery Legs (Shop -> Customer or Multi-Shop -> Customer)
    if (shops.length > 1) {
      final shopPts = shops
          .where((s) =>
              s.shopLat != null && s.shopLng != null && s.shopLat != 0.0)
          .map((s) => LatLng(s.shopLat!, s.shopLng!))
          .toList();

      if (shopPts.isNotEmpty) {
        final multiRoute =
            await GeoUtils.fetchMultiStopRoute([...shopPts, custPt]);
        deliveryRoutes.add(multiRoute);
        totalDeliveryKm = GeoUtils.calculateRouteDistanceKm(multiRoute);
      }
    } else if (shops.isNotEmpty &&
        shops.first.shopLat != null &&
        shops.first.shopLng != null &&
        shops.first.shopLat != 0.0) {
      final shopPt = LatLng(shops.first.shopLat!, shops.first.shopLng!);
      final singleRoute = await GeoUtils.fetchRoadRoute(shopPt, custPt);
      deliveryRoutes.add(singleRoute);
      totalDeliveryKm = GeoUtils.calculateRouteDistanceKm(singleRoute);
    }

    // 2. Fetch Pickup Leg (Rider -> First Shop) if rider location is known
    List<LatLng> pickupRoute = [];
    final riderLocs = _riderLocationsNotifier.value;
    if (riderLocs.isNotEmpty &&
        shops.isNotEmpty &&
        shops.first.shopLat != null) {
      final riderPt = riderLocs.values.first;
      final firstShopPt = LatLng(shops.first.shopLat!, shops.first.shopLng!);
      pickupRoute = await GeoUtils.fetchRoadRoute(riderPt, firstShopPt);
    }

    if (mounted) {
      setState(() {
        _deliveryRoutes = deliveryRoutes;
        _pickupRoute = pickupRoute;
        _deliveryKm = totalDeliveryKm > 0 ? totalDeliveryKm : null;
        _loadingRoutes = false;
      });
      if (!silent) {
        _fitMapBounds();
      }
    }
  }

  Future<void> _refreshPickupRoute(LatLng riderPos) async {
    final activeShops = _currentGroupOrders
        .where((s) =>
            s.status != 'rejected' &&
            s.status != 'cancelled' &&
            s.status != 'seller_rejected')
        .toList();
    if (activeShops.isEmpty) return;

    final firstShop = activeShops.first;
    if (firstShop.shopLat == null ||
        firstShop.shopLng == null ||
        firstShop.shopLat == 0.0) {
      return;
    }

    final firstShopPt = LatLng(firstShop.shopLat!, firstShop.shopLng!);
    final newPickupRoute =
        await GeoUtils.fetchRoadRoute(riderPos, firstShopPt);

    if (mounted) {
      setState(() {
        _pickupRoute = newPickupRoute;
      });
    }
  }

  void _fitMapBounds() {
    final pts = <LatLng>[
      if (_currentOrder.deliveryLat != null &&
          _currentOrder.deliveryLng != null &&
          _currentOrder.deliveryLat != 0.0)
        LatLng(_currentOrder.deliveryLat!, _currentOrder.deliveryLng!),
      for (final loc in _riderLocationsNotifier.value.values)
        if (loc.latitude != 0.0) loc,
    ];

    final activeShops = _currentGroupOrders
        .where((s) =>
            s.status != 'rejected' &&
            s.status != 'cancelled' &&
            s.status != 'seller_rejected')
        .toList();
    final shops =
        activeShops.isNotEmpty ? activeShops : _currentGroupOrders;

    for (final shop in shops) {
      if (shop.shopLat != null && shop.shopLng != null && shop.shopLat != 0.0) {
        pts.add(LatLng(shop.shopLat!, shop.shopLng!));
      }
    }

    final bounds = GeoUtils.computeBounds(pts, paddingFactor: 0.006);
    if (bounds != null) {
      try {
        _mapCtrl.fitCamera(
          CameraFit.bounds(
            bounds: bounds,
            padding: const EdgeInsets.fromLTRB(48, 100, 48, 220),
          ),
        );
      } catch (_) {}
    }
  }

  // ── Marker Builders ────────────────────────────────────────────────────────

  Widget _mapMarker(Color color, IconData icon, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.45),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(color: Colors.white, width: 2.5),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            label,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoChip({
    required Color color,
    required IconData icon,
    required String label,
    required String value,
    bool loading = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: GoogleFonts.outfit(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
                if (loading)
                  SizedBox(
                    height: 10,
                    width: 50,
                    child: LinearProgressIndicator(
                      color: color,
                      backgroundColor: color.withValues(alpha: 0.2),
                      minHeight: 2,
                    ),
                  )
                else
                  Text(
                    value,
                    style: GoogleFonts.outfit(
                        color: color,
                        fontSize: 14,
                        fontWeight: FontWeight.w800),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _call(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final order = _currentOrder;
    final isOutForDelivery = order.status == 'out_for_delivery';
    final isRiderActiveStatus = [
      'awaiting_payment',
      'confirmed',
      'preparing',
      'ready_for_pickup',
      'picked_up',
      'out_for_delivery'
    ].contains(order.status);

    final custLat = order.deliveryLat;
    final custLng = order.deliveryLng;

    final allShops = _currentGroupOrders;
    final activeShops = allShops
        .where((s) =>
            s.status != 'rejected' &&
            s.status != 'cancelled' &&
            s.status != 'seller_rejected')
        .toList();
    final effectiveShops =
        activeShops.isNotEmpty ? activeShops : allShops;

    final isMulti = allShops.length > 1;
    final rejectedCount = allShops
        .where((s) =>
            s.status == 'rejected' ||
            s.status == 'cancelled' ||
            s.status == 'seller_rejected')
        .length;
    final hasPartialRejection =
        isMulti && rejectedCount > 0 && activeShops.isNotEmpty;

    final seenCoords = <String>{};
    LatLng applyJitter(double lat, double lng) {
      double jLat = lat;
      double jLng = lng;
      int attempts = 0;
      while (seenCoords.contains(
              '${jLat.toStringAsFixed(5)}_${jLng.toStringAsFixed(5)}') &&
          attempts < 5) {
        jLat += 0.00015;
        jLng += 0.00015;
        attempts++;
      }
      seenCoords.add('${jLat.toStringAsFixed(5)}_${jLng.toStringAsFixed(5)}');
      return LatLng(jLat, jLng);
    }

    final markers = <Marker>[
      // Shop markers
      for (int i = 0; i < allShops.length; i++)
        if (allShops[i].shopLat != null &&
            allShops[i].shopLng != null &&
            allShops[i].shopLat != 0.0)
          Marker(
            point: applyJitter(allShops[i].shopLat!, allShops[i].shopLng!),
            width: 80,
            height: 70,
            child: _mapMarker(
              (allShops[i].status == 'rejected' ||
                      allShops[i].status == 'cancelled' ||
                      allShops[i].status == 'seller_rejected')
                  ? _kShopCancelledColor
                  : (allShops[i].status == 'picked_up'
                      ? _kShopPickedUpColor
                      : _kShopMarkerColor),
              allShops[i].status == 'picked_up'
                  ? Icons.check_circle_rounded
                  : Icons.storefront_rounded,
              isMulti ? 'Shop ${i + 1}' : 'Shop',
            ),
          ),
      // Customer home marker
      if (custLat != null && custLng != null && custLat != 0.0)
        Marker(
          point: applyJitter(custLat, custLng),
          width: 80,
          height: 70,
          child: _mapMarker(_kCustomerMarkerColor, Icons.home_rounded, 'You'),
        ),
    ];

    // Initial map camera centre
    final mapCenter = (custLat != null && custLng != null && custLat != 0.0)
        ? LatLng(custLat, custLng)
        : (effectiveShops.isNotEmpty &&
                effectiveShops.first.shopLat != null &&
                effectiveShops.first.shopLng != null &&
                effectiveShops.first.shopLat != 0.0)
            ? LatLng(
                effectiveShops.first.shopLat!, effectiveShops.first.shopLng!)
            : const LatLng(28.6139, 77.2090);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF080812) : const Color(0xFFF0F4FF),
        body: Stack(
          children: [
            // ── Full-Screen Live Map ───────────────────────────────────────
            FlutterMap(
              mapController: _mapCtrl,
              options: MapOptions(
                initialCenter: mapCenter,
                initialZoom: 13.5,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.enything.app',
                ),

                // Pickup route (Rider -> Shop) when rider is heading to store
                if (_pickupRoute.isNotEmpty && !isOutForDelivery)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _pickupRoute,
                        color: _kPickupColor,
                        strokeWidth: 4.5,
                        borderStrokeWidth: 1.5,
                        borderColor: Colors.white.withValues(alpha: 0.6),
                      ),
                    ],
                  ),

                // Delivery routes (Shop -> Customer)
                if (_deliveryRoutes.isNotEmpty)
                  PolylineLayer(
                    polylines: _deliveryRoutes
                        .map((route) => Polyline(
                              points: route,
                              color: _kDeliveryColor,
                              strokeWidth: 5.0,
                              borderStrokeWidth: 1.5,
                              borderColor: Colors.white.withValues(alpha: 0.6),
                            ))
                        .toList(),
                  ),

                MarkerLayer(markers: markers),

                // Live Rider Layer with smooth coordinate gliding & heading rotation
                if (isRiderActiveStatus)
                  ValueListenableBuilder<Map<String, LatLng>>(
                    valueListenable: _riderLocationsNotifier,
                    builder: (context, riderLocs, child) {
                      if (riderLocs.isEmpty) return const SizedBox.shrink();
                      return SmoothMovingRiderMarkerLayer(
                        riderLocations: riderLocs,
                        label: 'Rider',
                        color: _kRiderMarkerColor,
                        icon: Icons.navigation_rounded,
                        rotateWithHeading: true,
                      );
                    },
                  ),
              ],
            ),

            // ── Top Navigation Bar ─────────────────────────────────────────
            SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    // Back button
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color:
                              isDark ? const Color(0xFF1E1E2E) : Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 18,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Title Header
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color:
                              isDark ? const Color(0xFF1E1E2E) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              isMulti
                                  ? 'Multi-Shop Order (${activeShops.length} active)'
                                  : 'Order #${order.id.substring(0, 8).toUpperCase()}',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            Text(
                              hasPartialRejection
                                  ? '${activeShops.length} of ${allShops.length} shops active ($rejectedCount cancelled)'
                                  : isOutForDelivery
                                      ? 'Rider is on the way! 🚴'
                                      : order.statusDisplay,
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                color: hasPartialRejection
                                    ? AppColors.warning
                                    : isDark
                                        ? Colors.white54
                                        : Colors.grey.shade600,
                                fontWeight: hasPartialRejection
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Re-centre Camera Button
                    GestureDetector(
                      onTap: _fitMapBounds,
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color:
                              isDark ? const Color(0xFF1E1E2E) : Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.my_location_rounded,
                          size: 20,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Route Loading Indicator ────────────────────────────────────
            if (_loadingRoutes)
              Positioned(
                top: 100,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text('Computing road route…',
                            style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black87)),
                      ],
                    ),
                  ),
                ),
              ),

            // ── Bottom Information Panel ───────────────────────────────────
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1A1A2E).withValues(alpha: 0.97)
                      : Colors.white.withValues(alpha: 0.97),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(28)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 24,
                      offset: const Offset(0, -6),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Route legend + Live Freshness Ticker
                        Row(
                          children: [
                            Container(
                              width: 14,
                              height: 4,
                              decoration: BoxDecoration(
                                color: _kDeliveryColor,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Delivery route',
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                color: _kDeliveryColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (isRiderActiveStatus)
                              ValueListenableBuilder<Map<String, LatLng>>(
                                valueListenable: _riderLocationsNotifier,
                                builder: (context, riderLocs, child) {
                                  if (riderLocs.isEmpty) {
                                    return const SizedBox.shrink();
                                  }
                                  return Expanded(
                                    child: Row(
                                      children: [
                                        const SizedBox(width: 14),
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: const BoxDecoration(
                                            color: _kRiderMarkerColor,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          'Live rider',
                                          style: GoogleFonts.outfit(
                                            fontSize: 12,
                                            color: _kRiderMarkerColor,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const Spacer(),
                                        ValueListenableBuilder<
                                            Map<String, DateTime>>(
                                          valueListenable:
                                              _riderUpdatedAtsNotifier,
                                          builder:
                                              (context, riderUpdatedAts, child) {
                                            if (riderUpdatedAts.isEmpty) {
                                              return const SizedBox.shrink();
                                            }
                                            return ValueListenableBuilder<int>(
                                              valueListenable: _timeTicker,
                                              builder: (context, _, child) {
                                                final latest = riderUpdatedAts
                                                    .values
                                                    .reduce((a, b) =>
                                                        a.isAfter(b) ? a : b);
                                                return Text(
                                                  'Updated ${_secondsAgo(latest)}s ago',
                                                  style: GoogleFonts.outfit(
                                                    fontSize: 11,
                                                    color: Colors.grey.shade500,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                );
                                              },
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Distance + ETA Chips
                        Row(
                          children: [
                            Expanded(
                              child: _infoChip(
                                color: _kDeliveryColor,
                                icon: Icons.route_rounded,
                                label: 'Distance',
                                value: _deliveryKm != null
                                    ? GeoUtils.formatDistance(_deliveryKm!)
                                    : '— km',
                                loading: _loadingRoutes,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _infoChip(
                                color: AppColors.primary,
                                icon: Icons.timer_outlined,
                                label: 'Est. Arrival',
                                value: _loadingRoutes
                                    ? '…'
                                    : _deliveryKm != null
                                        ? GeoUtils.estimateTravelTime(
                                            _deliveryKm!)
                                        : '—',
                                loading: _loadingRoutes,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Direct Call buttons
                        if ((order.shopPhone != null &&
                                order.shopPhone!.isNotEmpty) ||
                            (order.riderPhone != null &&
                                order.riderPhone!.isNotEmpty)) ...[
                          Row(
                            children: [
                              if (order.shopPhone != null &&
                                  order.shopPhone!.isNotEmpty)
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _call(order.shopPhone!),
                                    icon: const Icon(Icons.store_outlined,
                                        size: 16),
                                    label: Text('Call Shop',
                                        style: GoogleFonts.outfit(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700)),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.primary,
                                      side: const BorderSide(
                                          color: AppColors.primary),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(14)),
                                    ),
                                  ),
                                ),
                              if ((order.shopPhone != null &&
                                      order.shopPhone!.isNotEmpty) &&
                                  (order.riderPhone != null &&
                                      order.riderPhone!.isNotEmpty))
                                const SizedBox(width: 10),
                              if (order.riderPhone != null &&
                                  order.riderPhone!.isNotEmpty)
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _call(order.riderPhone!),
                                    icon: const Icon(
                                        Icons.delivery_dining_outlined,
                                        size: 16),
                                    label: Text('Call Rider',
                                        style: GoogleFonts.outfit(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700)),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.accent,
                                      side: const BorderSide(
                                          color: AppColors.accent),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(14)),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _secondsAgo(DateTime dt) =>
      DateTime.now().toUtc().difference(dt.toUtc()).inSeconds.abs();
}
