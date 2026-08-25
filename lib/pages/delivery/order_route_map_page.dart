import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/order_group.dart';
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

  List<LatLng> _pickupRoute = [];
  List<LatLng> _deliveryRoute = [];
  bool _loadingRoutes = true;
  double? _totalKm;

  // ValueNotifier prevents parent widget and map re-renders on GPS stream ticks
  final ValueNotifier<LatLng?> _riderPositionNotifier = ValueNotifier(null);
  StreamSubscription<Position>? _positionStreamSub;

  int _selectedStopIndex = 0;

  @override
  void initState() {
    super.initState();
    if (widget.riderLat != null &&
        widget.riderLng != null &&
        widget.riderLat != 0.0) {
      _riderPositionNotifier.value = LatLng(widget.riderLat!, widget.riderLng!);
    }
    _fetchRoutes();

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
      }
    }, onError: (e) {
      debugPrint('Geolocator stream error: $e');
    });
  }

  @override
  void dispose() {
    _positionStreamSub?.cancel();
    _riderPositionNotifier.dispose();
    super.dispose();
  }

  Future<void> _fetchRoutes() async {
    setState(() => _loadingRoutes = true);

    List<LatLng> pickupRoute = [];
    List<LatLng> deliveryRoute = [];
    double totalKm = 0;

    List<LatLng> shopPts = [];
    if (widget.shops.isNotEmpty) {
      final unvisited = widget.shops
          .where((s) => s.lat != 0.0 && s.lng != 0.0)
          .map((s) => LatLng(s.lat, s.lng))
          .toList();
      final riderPos = _riderPositionNotifier.value;
      LatLng currentPos = riderPos ?? (unvisited.isNotEmpty ? unvisited.first : const LatLng(0, 0));

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

    // 1. Pickup Route: Rider -> First Shop
    if (riderPt != null && shopPts.isNotEmpty) {
      final r = await GeoUtils.fetchRoadRoute(riderPt, shopPts.first);
      pickupRoute.addAll(r);
      totalKm += GeoUtils.calculateRouteDistanceKm(r);
    }

    // 2. Delivery Route: Shop 1 -> Shop 2 -> ... -> Customer
    if (shopPts.isNotEmpty) {
      final allWaypoints = [...shopPts];
      if (customerPt != null) {
        allWaypoints.add(customerPt);
      }
      final r = await GeoUtils.fetchMultiStopRoute(allWaypoints);
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
      _fitMapBounds();
    }
  }

  void _fitMapBounds() {
    final riderPos = _riderPositionNotifier.value;
    final allPoints = [
      if (riderPos != null && riderPos.latitude != 0.0) riderPos,
      ...widget.shops
          .where((s) => s.lat != 0.0)
          .map((s) => LatLng(s.lat, s.lng)),
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
    final origin = (riderPos != null && riderPos.latitude != 0.0)
        ? '${riderPos.latitude},${riderPos.longitude}'
        : widget.shops.isNotEmpty
            ? '${widget.shops.first.lat},${widget.shops.first.lng}'
            : '';

    final destination =
        (widget.group.deliveryLat != null && widget.group.deliveryLat != 0.0)
            ? '${widget.group.deliveryLat},${widget.group.deliveryLng}'
            : widget.shops.isNotEmpty
                ? '${widget.shops.last.lat},${widget.shops.last.lng}'
                : '';

    if (origin.isEmpty || destination.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Cannot open map: Missing location coordinates.')));
      }
      return;
    }

    final waypoints = widget.shops.map((s) => '${s.lat},${s.lng}').toList();

    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&origin=$origin&destination=$destination&waypoints=${waypoints.join('|')}');

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not launch external map.')));
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
    final isMulti = widget.shops.length > 1;
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
      for (int i = 0; i < widget.shops.length; i++)
        Marker(
          point: applyJitter(widget.shops[i].lat, widget.shops[i].lng),
          width: 80,
          height: 70,
          child: _mapMarker(
            _kShopMarker,
            Icons.storefront_rounded,
            isMulti ? '${i + 1}. ${widget.shops[i].name}' : widget.shops[i].name,
          ),
        ),
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
                initialCenter: widget.shops.isNotEmpty
                    ? LatLng(widget.shops.first.lat, widget.shops.first.lng)
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

                // Delivery legs (Shop -> Customer)
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
                              widget.group.isMultiShop
                                  ? 'Multi-Shop Order (${widget.shops.length} Shops)'
                                  : 'Order #${widget.group.orders.first.id.substring(0, 8).toUpperCase()}',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            Text(
                              widget.group.isMultiShop
                                  ? widget.shops.map((s) => s.name).join(', ')
                                  : (widget.shops.isNotEmpty ? widget.shops.first.name : 'Store'),
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
                                                ? GeoUtils.formatDistance(_totalKm!)
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
                                  color: AppColors.success.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: AppColors.success.withValues(alpha: 0.35),
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
                            for (int i = 0; i < widget.shops.length; i++) ...[
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => setState(() => _selectedStopIndex = i),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    decoration: BoxDecoration(
                                      color: _selectedStopIndex == i
                                          ? _kPickupColor.withValues(alpha: 0.15)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: _selectedStopIndex == i
                                            ? _kPickupColor
                                            : Colors.grey.withValues(alpha: 0.3),
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
                                              : (isDark ? Colors.white70 : Colors.black87),
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
                                onTap: () => setState(() =>
                                    _selectedStopIndex = widget.shops.length),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: _selectedStopIndex == widget.shops.length
                                        ? _kCustomerMarker.withValues(alpha: 0.15)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: _selectedStopIndex == widget.shops.length
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
                                        color: _selectedStopIndex == widget.shops.length
                                            ? _kCustomerMarker
                                            : (isDark ? Colors.white70 : Colors.black87),
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
                        if (_selectedStopIndex < widget.shops.length) ...[
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
                                    color: _kShopMarker.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.storefront_rounded,
                                      color: _kShopMarker, size: 20),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.shops[_selectedStopIndex].name,
                                        style: GoogleFonts.outfit(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: isDark ? Colors.white : Colors.black87,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        'Pick up items here',
                                        style: GoogleFonts.outfit(
                                          fontSize: 11,
                                          color: isDark ? Colors.white54 : Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (widget.group.orders[_selectedStopIndex].shopPhone != null)
                                  IconButton(
                                    onPressed: () => _call(widget
                                        .group.orders[_selectedStopIndex].shopPhone),
                                    icon: const Icon(Icons.phone_rounded,
                                        color: AppColors.primary, size: 20),
                                    style: IconButton.styleFrom(
                                      backgroundColor:
                                          AppColors.primary.withValues(alpha: 0.1),
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
                                    color: _kCustomerMarker.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.home_rounded,
                                      color: _kCustomerMarker, size: 20),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.group.customerAddress,
                                        style: GoogleFonts.outfit(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: isDark ? Colors.white : Colors.black87,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (primaryOrder.deliveryNotes != null &&
                                          primaryOrder.deliveryNotes!.isNotEmpty)
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
                                    onPressed: () => _call(widget.group.customerPhone),
                                    icon: const Icon(Icons.phone_rounded,
                                        color: AppColors.primary, size: 20),
                                    style: IconButton.styleFrom(
                                      backgroundColor:
                                          AppColors.primary.withValues(alpha: 0.1),
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
                                  shadowColor:
                                      AppColors.success.withValues(alpha: 0.4)),
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
