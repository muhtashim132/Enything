import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/order_group.dart';
import '../../models/order_model.dart';
import '../../theme/app_colors.dart';
import '../../utils/geo_utils.dart';
import '../../widgets/common/animated_moving_marker.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Colour palette (rider navigation perspective)
// ─────────────────────────────────────────────────────────────────────────────
const _kPickupColor = Color(0xFF2ECC71); // green  — rider → shop
const _kDeliveryColor = Color(0xFFFF8C42); // orange — shop  → customer
const _kRiderMarker = Color(0xFF2ECC71);
const _kShopMarker = Color(0xFFFF8C42);
const _kShopPickedUpMarker = Color(0xFF3498DB);
const _kShopCancelledMarker = Color(0xFF95A5A6);
const _kCustomerMarker = Color(0xFF00B4D8); // cyan

class OrderRouteMapPage extends StatefulWidget {
  final OrderGroup group;
  final double? riderLat;
  final double? riderLng;
  final List<({double lat, double lng, String name})> shops;
  final VoidCallback onAccept;
  final bool isViewOnly;

  const OrderRouteMapPage({
    super.key,
    required this.group,
    required this.riderLat,
    required this.riderLng,
    required this.shops,
    required this.onAccept,
    this.isViewOnly = false,
  });

  @override
  State<OrderRouteMapPage> createState() => _OrderRouteMapPageState();
}

class _OrderRouteMapPageState extends State<OrderRouteMapPage> {
  final MapController _mapCtrl = MapController();
  SupabaseClient get _supabase => Supabase.instance.client;

  List<OrderModel> _orders = [];
  List<LatLng> _pickupRoute = [];
  List<LatLng> _deliveryRoute = [];
  bool _loadingRoutes = true;
  double? _totalKm;

  // ValueNotifier prevents parent widget and map re-renders on GPS stream ticks
  final ValueNotifier<LatLng?> _riderPositionNotifier = ValueNotifier(null);
  StreamSubscription<Position>? _positionStreamSub;
  RealtimeChannel? _orderChannel;
  LatLng? _lastRouteFetchPos;

  int _selectedStopIndex = 0;

  @override
  void initState() {
    super.initState();
    _orders = List<OrderModel>.from(widget.group.orders);

    if (widget.riderLat != null &&
        widget.riderLng != null &&
        widget.riderLat != 0.0) {
      final initialPos = LatLng(widget.riderLat!, widget.riderLng!);
      _riderPositionNotifier.value = initialPos;
      _lastRouteFetchPos = initialPos;
    }
    _fetchRoutes();
    _subscribeToOrderChanges();

    _positionStreamSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
      ),
    ).listen((Position position) {
      final newPos = LatLng(position.latitude, position.longitude);
      final prevPos = _riderPositionNotifier.value;
      if (prevPos == null ||
          prevPos.latitude != newPos.latitude ||
          prevPos.longitude != newPos.longitude) {
        _riderPositionNotifier.value = newPos;

        // Dynamically re-evaluate routes if rider moved > 60m along the trip
        if (_lastRouteFetchPos == null ||
            const Distance()
                    .as(LengthUnit.Meter, _lastRouteFetchPos!, newPos) >
                60) {
          _lastRouteFetchPos = newPos;
          _fetchRoutes(silent: true);
        }
      }
    }, onError: (e) {
      debugPrint('Geolocator stream error: $e');
    });
  }

  @override
  void dispose() {
    _positionStreamSub?.cancel();
    if (_orderChannel != null) {
      _supabase.removeChannel(_orderChannel!);
    }
    _riderPositionNotifier.dispose();
    super.dispose();
  }

  // ── Supabase Realtime Subscription ─────────────────────────────────────────
  void _subscribeToOrderChanges() {
    final cartGroupId = widget.group.primaryOrder.cartGroupId;
    final primaryId = widget.group.primaryOrder.id;

    final channelName = cartGroupId != null
        ? 'rider-route-map-group-$cartGroupId'
        : 'rider-route-map-$primaryId';

    _orderChannel = _supabase
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: cartGroupId != null ? 'cart_group_id' : 'id',
            value: cartGroupId ?? primaryId,
          ),
          callback: (payload) {
            if (!mounted || payload.newRecord.isEmpty) return;
            final updatedOrder = OrderModel.fromMap(payload.newRecord);

            final idx = _orders.indexWhere((o) => o.id == updatedOrder.id);
            if (idx != -1) {
              updatedOrder.items = _orders[idx].items;
              setState(() {
                _orders[idx] = updatedOrder;
              });
            } else {
              setState(() {
                _orders.add(updatedOrder);
              });
            }

            final activeOrders = _orders
                .where((o) =>
                    o.status != 'rejected' &&
                    o.status != 'cancelled' &&
                    o.status != 'seller_rejected')
                .toList();

            // If entire order was cancelled/rejected by all shops
            if (activeOrders.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Order was cancelled or rejected by all shops.'),
                  backgroundColor: AppColors.danger,
                ),
              );
              if (mounted && Navigator.canPop(context)) {
                Navigator.pop(context);
              }
              return;
            }

            // Recalculate routes on status change
            _fetchRoutes(silent: true);
          },
        )
        .subscribe();
  }

  List<({double lat, double lng, String name, String status, String? phone})>
      get _effectiveShopStops {
    final activeOrders = _orders
        .where((o) =>
            o.status != 'rejected' &&
            o.status != 'cancelled' &&
            o.status != 'seller_rejected')
        .toList();

    final targetOrders = activeOrders.isNotEmpty ? activeOrders : _orders;

    return targetOrders.map((o) {
      final matchingShop = widget.shops.firstWhere(
        (s) => s.lat == o.shopLat && s.lng == o.shopLng,
        orElse: () => (
          lat: o.shopLat ?? 0.0,
          lng: o.shopLng ?? 0.0,
          name: o.items.isNotEmpty ? o.items.first.productName : 'Shop',
        ),
      );

      return (
        lat: matchingShop.lat,
        lng: matchingShop.lng,
        name: matchingShop.name,
        status: o.status,
        phone: o.shopPhone,
      );
    }).where((s) => s.lat != 0.0 && s.lng != 0.0).toList();
  }

  Future<void> _fetchRoutes({bool silent = false}) async {
    if (!silent) {
      setState(() => _loadingRoutes = true);
    }

    List<LatLng> pickupRoute = [];
    List<LatLng> deliveryRoute = [];
    double totalKm = 0;

    final shops = _effectiveShopStops;
    final unpickedShops = shops
        .where((s) => s.status != 'picked_up' && s.status != 'out_for_delivery')
        .toList();

    List<LatLng> shopPts = [];
    if (unpickedShops.isNotEmpty) {
      final unvisited = unpickedShops.map((s) => LatLng(s.lat, s.lng)).toList();
      final riderPos = _riderPositionNotifier.value;
      LatLng currentPos =
          riderPos ?? (unvisited.isNotEmpty ? unvisited.first : const LatLng(0, 0));

      while (unvisited.isNotEmpty) {
        unvisited.sort((a, b) {
          final distA = Geolocator.distanceBetween(
              currentPos.latitude, currentPos.longitude, a.latitude, a.longitude);
          final distB = Geolocator.distanceBetween(
              currentPos.latitude, currentPos.longitude, b.latitude, b.longitude);
          return distA.compareTo(distB);
        });
        final nearest = unvisited.removeAt(0);
        shopPts.add(nearest);
        currentPos = nearest;
      }
    }

    final customerPt =
        (widget.group.deliveryLat != null && widget.group.deliveryLat != 0.0)
            ? LatLng(widget.group.deliveryLat!, widget.group.deliveryLng!)
            : null;
    final riderPos = _riderPositionNotifier.value;
    final riderPt =
        (riderPos != null && riderPos.latitude != 0.0) ? riderPos : null;

    // 1. Pickup Route: Rider -> First Unpicked Shop
    if (riderPt != null && shopPts.isNotEmpty) {
      final r = await GeoUtils.fetchRoadRoute(riderPt, shopPts.first);
      pickupRoute.addAll(r);
      totalKm += GeoUtils.calculateRouteDistanceKm(r);
    }

    // 2. Delivery Route:
    // If there are unpicked shops: Shop 1 -> Shop 2 -> Customer
    // If ALL shops are picked up: Rider -> Customer directly!
    if (shopPts.isNotEmpty) {
      final allWaypoints = [...shopPts];
      if (customerPt != null) {
        allWaypoints.add(customerPt);
      }
      final r = await GeoUtils.fetchMultiStopRoute(allWaypoints);
      deliveryRoute.addAll(r);
      totalKm += GeoUtils.calculateRouteDistanceKm(r);
    } else if (riderPt != null && customerPt != null) {
      // All items picked up! Direct route from Rider to Customer
      final r = await GeoUtils.fetchRoadRoute(riderPt, customerPt);
      deliveryRoute.addAll(r);
      totalKm += GeoUtils.calculateRouteDistanceKm(r);
    }

    if (mounted) {
      setState(() {
        _pickupRoute = pickupRoute;
        _deliveryRoute = deliveryRoute;
        _totalKm = totalKm > 0 ? totalKm : null;
        _loadingRoutes = false;
      });
      if (!silent) {
        _fitMapBounds();
      }
    }
  }

  void _fitMapBounds() {
    final riderPos = _riderPositionNotifier.value;
    final activeShops = _effectiveShopStops;

    final allPoints = [
      if (riderPos != null && riderPos.latitude != 0.0) riderPos,
      ...activeShops.map((s) => LatLng(s.lat, s.lng)),
      if (widget.group.deliveryLat != null && widget.group.deliveryLat != 0.0)
        LatLng(widget.group.deliveryLat!, widget.group.deliveryLng!),
    ];
    if (allPoints.isEmpty) return;

    final bounds = GeoUtils.computeBounds(allPoints, paddingFactor: 0.006);
    if (bounds != null) {
      try {
        _mapCtrl.fitCamera(
          CameraFit.bounds(
            bounds: bounds,
            padding: const EdgeInsets.fromLTRB(48, 100, 48, 240),
          ),
        );
      } catch (_) {}
    }
  }

  Future<void> _openInExternalMap() async {
    final riderPos = _riderPositionNotifier.value;
    final shops = _effectiveShopStops;
    final unpickedShops = shops
        .where((s) => s.status != 'picked_up' && s.status != 'out_for_delivery')
        .toList();

    final origin = (riderPos != null && riderPos.latitude != 0.0)
        ? '${riderPos.latitude},${riderPos.longitude}'
        : shops.isNotEmpty
            ? '${shops.first.lat},${shops.first.lng}'
            : '';

    final destination =
        (widget.group.deliveryLat != null && widget.group.deliveryLat != 0.0)
            ? '${widget.group.deliveryLat},${widget.group.deliveryLng}'
            : shops.isNotEmpty
                ? '${shops.last.lat},${shops.last.lng}'
                : '';

    if (origin.isEmpty || destination.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Cannot open map: Missing location coordinates.')));
      }
      return;
    }

    final waypoints =
        unpickedShops.map((s) => '${s.lat},${s.lng}').toList();

    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&origin=$origin&destination=$destination&waypoints=${waypoints.join('|')}');

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not launch external map.')));
      }
    }
  }

  Future<void> _call(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shops = _effectiveShopStops;
    final isMulti = shops.length > 1;
    final primaryOrder = widget.group.primaryOrder;

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
      for (int i = 0; i < shops.length; i++) ...[
        Marker(
          point: applyJitter(shops[i].lat, shops[i].lng),
          width: 80,
          height: 70,
          child: _mapMarker(
            shops[i].status == 'picked_up'
                ? _kShopPickedUpMarker
                : (shops[i].status == 'rejected' ||
                        shops[i].status == 'cancelled')
                    ? _kShopCancelledMarker
                    : _kShopMarker,
            shops[i].status == 'picked_up'
                ? Icons.check_circle_rounded
                : Icons.storefront_rounded,
            isMulti ? '${i + 1}. ${shops[i].name}' : shops[i].name,
          ),
        ),
      ],
      // Customer delivery marker
      if (widget.group.deliveryLat != null && widget.group.deliveryLat != 0.0)
        Marker(
          point:
              applyJitter(widget.group.deliveryLat!, widget.group.deliveryLng!),
          width: 80,
          height: 70,
          child: _mapMarker(
              _kCustomerMarker, Icons.location_on_rounded, 'Customer'),
        ),
    ];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF080812) : const Color(0xFFF0F4FF),
        body: Stack(
          children: [
            // ── Live Navigation Map ──────────────────────────────────────
            FlutterMap(
              mapController: _mapCtrl,
              options: MapOptions(
                initialCenter: shops.isNotEmpty
                    ? LatLng(shops.first.lat, shops.first.lng)
                    : const LatLng(28.6139, 77.2090),
                initialZoom: 13.5,
                interactionOptions:
                    const InteractionOptions(flags: InteractiveFlag.all),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.enything.app',
                ),

                // Pickup leg (Rider -> Shop)
                if (_pickupRoute.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _pickupRoute,
                        color: _kPickupColor,
                        strokeWidth: 5.0,
                        borderStrokeWidth: 1.5,
                        borderColor: Colors.white.withValues(alpha: 0.6),
                      ),
                    ],
                  ),

                // Delivery legs (Shop -> Customer or Rider -> Customer)
                if (_deliveryRoute.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _deliveryRoute,
                        color: _kDeliveryColor,
                        strokeWidth: 5.0,
                        borderStrokeWidth: 1.5,
                        borderColor: Colors.white.withValues(alpha: 0.6),
                      ),
                    ],
                  ),

                MarkerLayer(markers: markers),

                // Live animated rider navigation arrow with compass orientation
                ValueListenableBuilder<LatLng?>(
                  valueListenable: _riderPositionNotifier,
                  builder: (context, riderPos, child) {
                    if (riderPos == null) return const SizedBox.shrink();
                    return SmoothSingleRiderMarkerLayer(
                      riderLocation: riderPos,
                      label: 'You',
                      color: _kRiderMarker,
                      icon: Icons.navigation_rounded,
                      rotateWithHeading: true,
                    );
                  },
                ),
              ],
            ),

            // ── Top Bar Header ───────────────────────────────────────────
            SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
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
                                  ? 'Multi-Shop Route (${shops.length} Shops)'
                                  : 'Order #${primaryOrder.id.substring(0, 8).toUpperCase()}',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            Text(
                              isMulti
                                  ? shops.map((s) => s.name).join(', ')
                                  : (shops.isNotEmpty
                                      ? shops.first.name
                                      : 'Store'),
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                color: isDark
                                    ? Colors.white54
                                    : Colors.grey.shade600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
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

            // ── Loading Route Overlay ────────────────────────────────────
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

            // ── Bottom Navigation & Order Details Sheet ──────────────────
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
                        // Route Legend & Trip Metrics
                        Row(
                          children: [
                            Container(
                              width: 14,
                              height: 4,
                              decoration: BoxDecoration(
                                color: _kPickupColor,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text('Pickup',
                                style: GoogleFonts.outfit(
                                    fontSize: 12,
                                    color: _kPickupColor,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(width: 20),
                            Container(
                              width: 14,
                              height: 4,
                              decoration: BoxDecoration(
                                color: _kDeliveryColor,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text('Delivery',
                                style: GoogleFonts.outfit(
                                    fontSize: 12,
                                    color: _kDeliveryColor,
                                    fontWeight: FontWeight.w600)),
                            const Spacer(),
                            if (_totalKm != null)
                              Text(
                                'Est. ${GeoUtils.estimateTravelTime(_totalKm!)}',
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Distance + Financial Chips
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00B4D8)
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: const Color(0xFF00B4D8)
                                          .withValues(alpha: 0.35),
                                      width: 1.2),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 30,
                                      height: 30,
                                      decoration: const BoxDecoration(
                                          color: Color(0xFF00B4D8),
                                          shape: BoxShape.circle),
                                      child: const Icon(Icons.route_rounded,
                                          color: Colors.white, size: 16),
                                    ),
                                    const SizedBox(width: 10),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('Total Distance',
                                            style: GoogleFonts.outfit(
                                                color: const Color(0xFF00B4D8),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600)),
                                        if (_loadingRoutes)
                                          const SizedBox(
                                              height: 10,
                                              width: 40,
                                              child: LinearProgressIndicator(
                                                  color: Color(0xFF00B4D8)))
                                        else
                                          Text(
                                            _totalKm != null
                                                ? GeoUtils.formatDistance(
                                                    _totalKm!)
                                                : '— km',
                                            style: GoogleFonts.outfit(
                                                color: _totalKm != null
                                                    ? const Color(0xFF00B4D8)
                                                    : Colors.grey,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w800),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.success.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: AppColors.success
                                          .withValues(alpha: 0.35),
                                      width: 1.2),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 30,
                                      height: 30,
                                      decoration: const BoxDecoration(
                                          color: AppColors.success,
                                          shape: BoxShape.circle),
                                      child: const Icon(Icons.currency_rupee,
                                          color: Colors.white, size: 16),
                                    ),
                                    const SizedBox(width: 10),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('Your Earnings',
                                            style: GoogleFonts.outfit(
                                                color: AppColors.success,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600)),
                                        Text(
                                          '₹${widget.group.totalEarnings.toStringAsFixed(0)}',
                                          style: GoogleFonts.outfit(
                                              color: AppColors.success,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w800),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Stop Selector Tabs (Pickup Stores vs Dropoff)
                        Row(
                          children: [
                            for (int i = 0; i < shops.length; i++) ...[
                              Expanded(
                                child: GestureDetector(
                                  onTap: () =>
                                      setState(() => _selectedStopIndex = i),
                                  child: Container(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 8),
                                    decoration: BoxDecoration(
                                      color: _selectedStopIndex == i
                                          ? _kPickupColor.withValues(alpha: 0.15)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: _selectedStopIndex == i
                                            ? _kPickupColor
                                            : Colors.grey
                                                .withValues(alpha: 0.3),
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        isMulti ? 'Shop ${i + 1}' : 'Shop Info',
                                        style: GoogleFonts.outfit(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: _selectedStopIndex == i
                                              ? _kPickupColor
                                              : (isDark
                                                  ? Colors.white70
                                                  : Colors.black87),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(
                                    () => _selectedStopIndex = shops.length),
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: _selectedStopIndex == shops.length
                                        ? _kCustomerMarker
                                            .withValues(alpha: 0.15)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: _selectedStopIndex == shops.length
                                          ? _kCustomerMarker
                                          : Colors.grey.withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      'Customer',
                                      style: GoogleFonts.outfit(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: _selectedStopIndex == shops.length
                                            ? _kCustomerMarker
                                            : (isDark
                                                ? Colors.white70
                                                : Colors.black87),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Active Stop Details Card
                        if (_selectedStopIndex < shops.length) ...[
                          // Shop Details Card
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF141424)
                                  : const Color(0xFFF7F9FC),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white12
                                    : Colors.grey.shade200,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: (shops[_selectedStopIndex].status ==
                                            'picked_up'
                                        ? _kShopPickedUpMarker
                                        : _kShopMarker)
                                        .withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                      shops[_selectedStopIndex].status ==
                                              'picked_up'
                                          ? Icons.check_circle_rounded
                                          : Icons.storefront_rounded,
                                      color: shops[_selectedStopIndex].status ==
                                              'picked_up'
                                          ? _kShopPickedUpMarker
                                          : _kShopMarker,
                                      size: 20),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        shops[_selectedStopIndex].name,
                                        style: GoogleFonts.outfit(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black87,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        shops[_selectedStopIndex].status ==
                                                'picked_up'
                                            ? 'Items picked up ✓'
                                            : 'Pick up items here',
                                        style: GoogleFonts.outfit(
                                          fontSize: 11,
                                          color: shops[_selectedStopIndex]
                                                      .status ==
                                                  'picked_up'
                                              ? AppColors.success
                                              : (isDark
                                                  ? Colors.white54
                                                  : Colors.grey.shade600),
                                          fontWeight: shops[_selectedStopIndex]
                                                      .status ==
                                                  'picked_up'
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (shops[_selectedStopIndex].phone != null)
                                  IconButton(
                                    onPressed: () => _call(
                                        shops[_selectedStopIndex].phone),
                                    icon: const Icon(Icons.phone_rounded,
                                        color: AppColors.primary, size: 20),
                                    style: IconButton.styleFrom(
                                      backgroundColor: AppColors.primary
                                          .withValues(alpha: 0.1),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ] else ...[
                          // Customer Details Card
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF141424)
                                  : const Color(0xFFF7F9FC),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white12
                                    : Colors.grey.shade200,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: _kCustomerMarker
                                        .withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.home_rounded,
                                      color: _kCustomerMarker, size: 20),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.group.customerAddress,
                                        style: GoogleFonts.outfit(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black87,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (primaryOrder.deliveryNotes != null &&
                                          primaryOrder
                                              .deliveryNotes!.isNotEmpty)
                                        Text(
                                          'Note: ${primaryOrder.deliveryNotes}',
                                          style: GoogleFonts.outfit(
                                            fontSize: 11,
                                            color: AppColors.warning,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),
                                if (widget.group.customerPhone != null)
                                  IconButton(
                                    onPressed: () =>
                                        _call(widget.group.customerPhone),
                                    icon: const Icon(Icons.phone_rounded,
                                        color: AppColors.primary, size: 20),
                                    style: IconButton.styleFrom(
                                      backgroundColor: AppColors.primary
                                          .withValues(alpha: 0.1),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),

                        // Navigation Button
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _openInExternalMap,
                            icon: const Icon(Icons.navigation_rounded, size: 20),
                            label: Text('Open Google Maps Navigation',
                                style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.w800, fontSize: 14)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF4C6EF5),
                              side: const BorderSide(
                                  color: Color(0xFF4C6EF5), width: 1.5),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                            ),
                          ),
                        ),

                        // Accept Order button (when not in view-only mode)
                        if (!widget.isViewOnly) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: widget.onAccept,
                              icon: const Icon(
                                  Icons.check_circle_outline_rounded,
                                  size: 20),
                              label: Text('Accept Order',
                                  style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15)),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.success,
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 13),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16)),
                                  elevation: 4,
                                  shadowColor: AppColors.success
                                      .withValues(alpha: 0.4)),
                            ),
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
}
