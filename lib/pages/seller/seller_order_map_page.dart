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
// Colour palette (seller perspective — both legs visible)
// ─────────────────────────────────────────────────────────────────────────────
const _kPickupColor = Color(0xFF2ECC71); // green  — rider → shop
const _kDeliveryColor = Color(0xFFFF8C42); // orange — shop  → customer
const _kRiderMarkerColor = Color(0xFF2ECC71);
const _kShopMarkerColor = Color(0xFFFF8C42);
const _kCustomerMarkerColor = Color(0xFF00B4D8);

// ─────────────────────────────────────────────────────────────────────────────
// SellerOrderMapPage
// Full-screen live tracking map for the seller. Shows:
//   • Rider → Shop   pickup polyline   (green)
//   • Shop → Customer delivery polyline (orange)
//   • Live animated moving rider marker with heading orientation
//   • Distance and ETA chips for both legs
//   • Direct Call Customer / Call Rider buttons
// ─────────────────────────────────────────────────────────────────────────────
class SellerOrderMapPage extends StatefulWidget {
  final OrderModel order;
  final String shopName;

  const SellerOrderMapPage({
    super.key,
    required this.order,
    required this.shopName,
  });

  @override
  State<SellerOrderMapPage> createState() => _SellerOrderMapPageState();
}

class _SellerOrderMapPageState extends State<SellerOrderMapPage> {
  final MapController _mapCtrl = MapController();
  SupabaseClient get _supabase => Supabase.instance.client;

  // Route polylines
  List<LatLng> _pickupRoute = [];
  List<LatLng> _deliveryRoute = [];
  bool _loadingRoutes = true;
  double? _pickupKm;
  double? _deliveryKm;

  // Live rider position (isolated via ValueNotifier to prevent map re-renders)
  final ValueNotifier<LatLng?> _riderLatLngNotifier = ValueNotifier(null);
  final ValueNotifier<DateTime?> _riderUpdatedAtNotifier = ValueNotifier(null);
  final ValueNotifier<int> _timeTicker = ValueNotifier(0);
  Timer? _tickerTimer;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();

    if (widget.order.riderLat != null &&
        widget.order.riderLng != null &&
        widget.order.riderLat != 0.0) {
      _riderLatLngNotifier.value =
          LatLng(widget.order.riderLat!, widget.order.riderLng!);
      _riderUpdatedAtNotifier.value = widget.order.riderLocationUpdatedAt;
    }

    _tickerTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _timeTicker.value++;
    });

    _fetchRoutes();
    _subscribeToRider();
  }

  @override
  void dispose() {
    _tickerTimer?.cancel();
    _timeTicker.dispose();
    _riderLatLngNotifier.dispose();
    _riderUpdatedAtNotifier.dispose();
    if (_channel != null) {
      _supabase.removeChannel(_channel!);
    }
    super.dispose();
  }

  // ── Supabase Realtime ────────────────────────────────────────────────────

  void _subscribeToRider() {
    _channel = _supabase
        .channel('seller-map-${widget.order.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.order.id,
          ),
          callback: (payload) {
            if (!mounted || payload.newRecord.isEmpty) return;
            final r = payload.newRecord;
            final lat = (r['rider_lat'] as num?)?.toDouble();
            final lng = (r['rider_lng'] as num?)?.toDouble();

            if (lat != null && lng != null && lat != 0.0) {
              final newPos = LatLng(lat, lng);
              final prevPos = _riderLatLngNotifier.value;

              if (prevPos == null ||
                  prevPos.latitude != newPos.latitude ||
                  prevPos.longitude != newPos.longitude) {
                _riderLatLngNotifier.value = newPos;

                // Dynamically refresh pickup route if rider moved > 60 meters
                if (prevPos == null ||
                    const Distance().as(
                            LengthUnit.Meter, prevPos, newPos) >
                        60) {
                  _refreshPickupRoute(newPos);
                }
              }

              _riderUpdatedAtNotifier.value =
                  r['rider_location_updated_at'] != null
                      ? DateTime.tryParse(r['rider_location_updated_at'])
                      : DateTime.now();
            }
          },
        )
        .subscribe();
  }

  // ── Route Fetching ───────────────────────────────────────────────────────

  Future<void> _fetchRoutes() async {
    setState(() => _loadingRoutes = true);

    final order = widget.order;
    final shopLat = order.shopLat;
    final shopLng = order.shopLng;
    final custLat = order.deliveryLat;
    final custLng = order.deliveryLng;

    if (shopLat == null ||
        shopLng == null ||
        custLat == null ||
        custLng == null ||
        shopLat == 0.0) {
      if (mounted) setState(() => _loadingRoutes = false);
      return;
    }

    final shopPt = LatLng(shopLat, shopLng);
    final custPt = LatLng(custLat, custLng);

    // 1. Fetch shop → customer delivery route
    final deliveryRoute = await GeoUtils.fetchRoadRoute(shopPt, custPt);
    final deliveryKm = GeoUtils.calculateRouteDistanceKm(deliveryRoute);

    // 2. Fetch rider → shop pickup route (if rider coords available)
    List<LatLng> pickupRoute = [];
    double? pickupKm;
    final riderPos = _riderLatLngNotifier.value;
    if (riderPos != null && riderPos.latitude != 0.0) {
      pickupRoute = await GeoUtils.fetchRoadRoute(riderPos, shopPt);
      pickupKm = GeoUtils.calculateRouteDistanceKm(pickupRoute);
    }

    if (mounted) {
      setState(() {
        _deliveryRoute = deliveryRoute;
        _pickupRoute = pickupRoute;
        _deliveryKm = deliveryKm > 0 ? deliveryKm : null;
        _pickupKm = pickupKm != null && pickupKm > 0 ? pickupKm : null;
        _loadingRoutes = false;
      });
      _fitMapBounds();
    }
  }

  Future<void> _refreshPickupRoute(LatLng riderPos) async {
    final shopLat = widget.order.shopLat;
    final shopLng = widget.order.shopLng;
    if (shopLat == null || shopLng == null || shopLat == 0.0) return;

    final shopPt = LatLng(shopLat, shopLng);
    final pickupRoute = await GeoUtils.fetchRoadRoute(riderPos, shopPt);
    final pickupKm = GeoUtils.calculateRouteDistanceKm(pickupRoute);

    if (mounted) {
      setState(() {
        _pickupRoute = pickupRoute;
        _pickupKm = pickupKm > 0 ? pickupKm : null;
      });
    }
  }

  void _fitMapBounds() {
    final order = widget.order;
    final riderPos = _riderLatLngNotifier.value;
    final pts = <LatLng>[
      if (order.shopLat != null &&
          order.shopLng != null &&
          order.shopLat != 0.0)
        LatLng(order.shopLat!, order.shopLng!),
      if (order.deliveryLat != null &&
          order.deliveryLng != null &&
          order.deliveryLat != 0.0)
        LatLng(order.deliveryLat!, order.deliveryLng!),
      if (riderPos != null && riderPos.latitude != 0.0) riderPos,
    ];
    if (pts.isEmpty) return;

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

  // ── Marker builders ──────────────────────────────────────────────────────

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
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _distanceChip({
    required Color color,
    required IconData icon,
    required String label,
    required double? km,
    required bool loading,
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
                        color: color, fontSize: 11, fontWeight: FontWeight.w600)),
                if (loading)
                  SizedBox(
                    height: 10,
                    width: 40,
                    child: LinearProgressIndicator(
                      color: color,
                      backgroundColor: color.withValues(alpha: 0.2),
                      minHeight: 2,
                    ),
                  )
                else
                  Text(
                    km != null ? GeoUtils.formatDistance(km) : '— km',
                    style: GoogleFonts.outfit(
                        color: km != null ? color : Colors.grey,
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
    final order = widget.order;

    final shopLat = order.shopLat;
    final shopLng = order.shopLng;
    final custLat = order.deliveryLat;
    final custLng = order.deliveryLng;

    final markers = <Marker>[
      // Shop marker
      if (shopLat != null && shopLng != null && shopLat != 0.0)
        Marker(
          point: LatLng(shopLat, shopLng),
          width: 90,
          height: 70,
          child: _mapMarker(
              _kShopMarkerColor,
              Icons.storefront_rounded,
              widget.shopName.length > 10
                  ? '${widget.shopName.substring(0, 10)}…'
                  : widget.shopName),
        ),
      // Customer marker
      if (custLat != null && custLng != null && custLat != 0.0)
        Marker(
          point: LatLng(custLat, custLng),
          width: 80,
          height: 70,
          child: _mapMarker(
              _kCustomerMarkerColor, Icons.location_on_rounded, 'Customer'),
        ),
    ];

    // Map initial centre — shop location
    final mapCenter = (shopLat != null && shopLng != null && shopLat != 0.0)
        ? LatLng(shopLat, shopLng)
        : const LatLng(28.6139, 77.2090);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF080812) : const Color(0xFFF0F4FF),
        body: Stack(
          children: [
            // ── Full-screen map ──────────────────────────────────────────
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

                // Rider → Shop pickup route (green)
                if (_pickupRoute.isNotEmpty)
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

                // Shop → Customer delivery route (orange)
                if (_deliveryRoute.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _deliveryRoute,
                        color: _kDeliveryColor,
                        strokeWidth: 4.5,
                        borderStrokeWidth: 1.5,
                        borderColor: Colors.white.withValues(alpha: 0.6),
                      ),
                    ],
                  ),

                MarkerLayer(markers: markers),

                // Live Rider Moving Marker with dynamic heading orientation
                ValueListenableBuilder<LatLng?>(
                  valueListenable: _riderLatLngNotifier,
                  builder: (context, riderLoc, child) {
                    if (riderLoc == null) return const SizedBox.shrink();
                    return SmoothSingleRiderMarkerLayer(
                      riderLocation: riderLoc,
                      label: 'Rider',
                      color: _kRiderMarkerColor,
                      icon: Icons.delivery_dining_rounded,
                      rotateWithHeading: true,
                    );
                  },
                ),
              ],
            ),

            // ── Top Navigation Bar ───────────────────────────────────────
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
                              'Order #${order.id.substring(0, 8).toUpperCase()}',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            Text(
                              order.statusDisplay,
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

            // ── Loading overlay ──────────────────────────────────────────
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
                        Text('Computing routes…',
                            style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black87)),
                      ],
                    ),
                  ),
                ),
              ),

            // ── Bottom info panel ────────────────────────────────────────
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
                        // Route legend + last-updated ticker
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
                            const SizedBox(width: 16),
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
                            ValueListenableBuilder<DateTime?>(
                              valueListenable: _riderUpdatedAtNotifier,
                              builder: (context, riderUpdatedAt, child) {
                                if (riderUpdatedAt == null) {
                                  return const SizedBox.shrink();
                                }
                                return ValueListenableBuilder<int>(
                                  valueListenable: _timeTicker,
                                  builder: (context, _, child) {
                                    return Text(
                                      'Rider updated ${_secondsAgo(riderUpdatedAt)}s ago',
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
                        const SizedBox(height: 14),

                        // Distance chips
                        Row(
                          children: [
                            ValueListenableBuilder<LatLng?>(
                              valueListenable: _riderLatLngNotifier,
                              builder: (context, riderPos, child) {
                                if (riderPos == null) {
                                  return const SizedBox.shrink();
                                }
                                return Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _distanceChip(
                                      color: _kPickupColor,
                                      icon: Icons.storefront_rounded,
                                      label: 'To Shop',
                                      km: _pickupKm,
                                      loading: _loadingRoutes,
                                    ),
                                    const SizedBox(width: 10),
                                  ],
                                );
                              },
                            ),
                            Expanded(
                              child: _distanceChip(
                                color: _kDeliveryColor,
                                icon: Icons.location_on_rounded,
                                label: 'To Customer',
                                km: _deliveryKm,
                                loading: _loadingRoutes,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Call buttons
                        if ((order.customerPhone != null &&
                                order.customerPhone!.isNotEmpty) ||
                            (order.riderPhone != null &&
                                order.riderPhone!.isNotEmpty)) ...[
                          Row(
                            children: [
                              if (order.customerPhone != null &&
                                  order.customerPhone!.isNotEmpty)
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () =>
                                        _call(order.customerPhone!),
                                    icon: const Icon(Icons.phone_outlined,
                                        size: 16),
                                    label: Text('Customer',
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
                              if ((order.customerPhone != null &&
                                      order.customerPhone!.isNotEmpty) &&
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
                                    label: Text('Rider',
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
