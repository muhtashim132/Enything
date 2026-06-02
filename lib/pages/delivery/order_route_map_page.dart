import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../../models/order_model.dart';
import '../../theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Color palette for the two route legs
// ─────────────────────────────────────────────────────────────────────────────
const _kPickupColor = Color(0xFF2ECC71); // green  — rider → shop
const _kDeliveryColor = Color(0xFFFF8C42); // orange — shop  → customer
const _kRiderMarker = Color(0xFF2ECC71);
const _kShopMarker = Color(0xFFFF8C42);
const _kCustomerMarker = Color(0xFF00B4D8); // cyan

class OrderRouteMapPage extends StatefulWidget {
  final OrderModel order;
  final double? riderLat;
  final double? riderLng;
  final double shopLat;
  final double shopLng;
  final String shopName;
  final double customerLat;
  final double customerLng;
  final VoidCallback onAccept;

  const OrderRouteMapPage({
    super.key,
    required this.order,
    required this.riderLat,
    required this.riderLng,
    required this.shopLat,
    required this.shopLng,
    required this.shopName,
    required this.customerLat,
    required this.customerLng,
    required this.onAccept,
  });

  @override
  State<OrderRouteMapPage> createState() => _OrderRouteMapPageState();
}

class _OrderRouteMapPageState extends State<OrderRouteMapPage> {
  final MapController _mapCtrl = MapController();

  // Route polylines — populated after ORS calls
  List<LatLng> _pickupRoute = [];
  List<LatLng> _deliveryRoute = [];
  bool _loadingRoutes = true;

  // Road distances in km (null = not yet computed)
  double? _pickupKm;
  double? _deliveryKm;

  @override
  void initState() {
    super.initState();
    _fetchRoutes();
  }

  // ── ORS Route Fetching ──────────────────────────────────────────────────

  Future<List<LatLng>> _fetchORSRoute(LatLng from, LatLng to) async {
    try {
      final key = dotenv.maybeGet('ORS_API_KEY') ?? '';
      if (key.isEmpty) throw Exception('ORS_API_KEY not set');

      final url = Uri.parse(
        'https://api.openrouteservice.org/v2/directions/driving-car'
        '?api_key=$key'
        '&start=${from.longitude},${from.latitude}'
        '&end=${to.longitude},${to.latitude}',
      );

      final resp = await http.get(url).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) throw Exception('ORS ${resp.statusCode}');

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final features = data['features'] as List?;
      if (features == null || features.isEmpty) throw Exception('No features');

      final geometry = features.first['geometry'] as Map<String, dynamic>;
      final coords = geometry['coordinates'] as List;

      return coords
          .map((c) => LatLng(
                (c[1] as num).toDouble(),
                (c[0] as num).toDouble(),
              ))
          .toList();
    } catch (e) {
      debugPrint('ORS route error: $e — falling back to straight line');
      // Fallback: straight-line (2-point polyline)
      return [from, to];
    }
  }

  Future<void> _fetchRoutes() async {
    setState(() => _loadingRoutes = true);

    final shopPt = LatLng(widget.shopLat, widget.shopLng);
    final customerPt = LatLng(widget.customerLat, widget.customerLng);

    List<LatLng> pickupRoute = [];
    List<LatLng> deliveryRoute = [];

    // Always fetch shop→customer route
    deliveryRoute = await _fetchORSRoute(shopPt, customerPt);

    // Fetch rider→shop only if we have rider coords
    if (widget.riderLat != null && widget.riderLng != null) {
      final riderPt = LatLng(widget.riderLat!, widget.riderLng!);
      pickupRoute = await _fetchORSRoute(riderPt, shopPt);
    }

    // Compute road distances from polyline segment lengths
    double pickupKm = 0;
    for (int i = 1; i < pickupRoute.length; i++) {
      pickupKm += Geolocator.distanceBetween(
            pickupRoute[i - 1].latitude,
            pickupRoute[i - 1].longitude,
            pickupRoute[i].latitude,
            pickupRoute[i].longitude,
          ) /
          1000;
    }

    double deliveryKm = 0;
    for (int i = 1; i < deliveryRoute.length; i++) {
      deliveryKm += Geolocator.distanceBetween(
            deliveryRoute[i - 1].latitude,
            deliveryRoute[i - 1].longitude,
            deliveryRoute[i].latitude,
            deliveryRoute[i].longitude,
          ) /
          1000;
    }

    if (mounted) {
      setState(() {
        _pickupRoute = pickupRoute;
        _deliveryRoute = deliveryRoute;
        _pickupKm = pickupKm > 0 ? pickupKm : null;
        _deliveryKm = deliveryKm > 0 ? deliveryKm : null;
        _loadingRoutes = false;
      });

      // Fit map to show all points
      _fitMapBounds();
    }
  }

  void _fitMapBounds() {
    final allPoints = [
      if (widget.riderLat != null && widget.riderLng != null)
        LatLng(widget.riderLat!, widget.riderLng!),
      LatLng(widget.shopLat, widget.shopLng),
      LatLng(widget.customerLat, widget.customerLng),
    ];
    if (allPoints.isEmpty) return;

    double minLat = allPoints.first.latitude;
    double maxLat = allPoints.first.latitude;
    double minLng = allPoints.first.longitude;
    double maxLng = allPoints.first.longitude;

    for (final p in allPoints) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }

    final bounds = LatLngBounds(
      LatLng(minLat - 0.005, minLng - 0.005),
      LatLng(maxLat + 0.005, maxLng + 0.005),
    );

    try {
      _mapCtrl.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48)),
      );
    } catch (_) {}
  }

  // ── Marker Builders ─────────────────────────────────────────────────────

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
              )
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

  // ── Distance Chip ────────────────────────────────────────────────────────

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
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1.2),
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: GoogleFonts.outfit(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
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
                  km != null ? '${km.toStringAsFixed(1)} km' : '— km',
                  style: GoogleFonts.outfit(
                    color: km != null ? color : Colors.grey,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final markers = <Marker>[
      // Shop marker
      Marker(
        point: LatLng(widget.shopLat, widget.shopLng),
        width: 80,
        height: 70,
        child: _mapMarker(
            _kShopMarker, Icons.storefront_rounded, widget.shopName),
      ),
      // Customer marker
      Marker(
        point: LatLng(widget.customerLat, widget.customerLng),
        width: 80,
        height: 70,
        child: _mapMarker(
            _kCustomerMarker, Icons.location_on_rounded, 'Customer'),
      ),
      // Rider marker (only if GPS available)
      if (widget.riderLat != null && widget.riderLng != null)
        Marker(
          point: LatLng(widget.riderLat!, widget.riderLng!),
          width: 80,
          height: 70,
          child: _mapMarker(_kRiderMarker, Icons.navigation_rounded, 'You'),
        ),
    ];

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
                initialCenter:
                    LatLng(widget.shopLat, widget.shopLng),
                initialZoom: 13,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.enything.app',
                ),

                // Rider → Shop polyline (green)
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

                // Shop → Customer polyline (orange)
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
              ],
            ),

            // ── Top bar ──────────────────────────────────────────────────
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
                          color: isDark
                              ? const Color(0xFF1E1E2E)
                              : Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            )
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
                          color: isDark
                              ? const Color(0xFF1E1E2E)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            )
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Order #${widget.order.id.substring(0, 8).toUpperCase()}',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            Text(
                              widget.shopName,
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
                    // Re-centre button
                    GestureDetector(
                      onTap: _fitMapBounds,
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1E1E2E)
                              : Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            )
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
                    )
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Route legend header
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
                            Text(
                              'Pickup route',
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                color: _kPickupColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
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
                            Text(
                              'Delivery route',
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                color: _kDeliveryColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Distance chips row
                        Row(
                          children: [
                            if (widget.riderLat != null &&
                                widget.riderLng != null)
                              Expanded(
                                child: _distanceChip(
                                  color: _kPickupColor,
                                  icon: Icons.storefront_rounded,
                                  label: 'Pickup',
                                  km: _pickupKm,
                                  loading: _loadingRoutes,
                                ),
                              ),
                            if (widget.riderLat != null &&
                                widget.riderLng != null)
                              const SizedBox(width: 10),
                            Expanded(
                              child: _distanceChip(
                                color: _kDeliveryColor,
                                icon: Icons.location_on_rounded,
                                label: 'Delivery',
                                km: _deliveryKm,
                                loading: _loadingRoutes,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Earnings row
                        Row(
                          children: [
                            Text(
                              '₹${widget.order.grandTotal.toStringAsFixed(0)} order',
                              style: GoogleFonts.outfit(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color:
                                    isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.success.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: AppColors.success
                                        .withValues(alpha: 0.4)),
                              ),
                              child: Text(
                                '₹${widget.order.riderEarnings.toStringAsFixed(0)} earn',
                                style: GoogleFonts.outfit(
                                  color: AppColors.success,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Accept button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: widget.onAccept,
                            icon: const Icon(Icons.check_circle_outline_rounded,
                                size: 20),
                            label: Text(
                              'Accept Order',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success,
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                              elevation: 4,
                              shadowColor:
                                  AppColors.success.withValues(alpha: 0.4),
                            ),
                          ),
                        ),
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
