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
import '../../models/order_group.dart';
import '../../theme/app_colors.dart';

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

  const OrderRouteMapPage({
    super.key,
    required this.group,
    required this.riderLat,
    required this.riderLng,
    required this.shops,
    required this.onAccept,
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

  @override
  void initState() {
    super.initState();
    _fetchRoutes();
  }

  Future<List<LatLng>> _fetchORSRoute(LatLng from, LatLng to) async {
    try {
      final key = dotenv.maybeGet('ORS_API_KEY') ?? '';
      if (key.isEmpty) return [from, to];

      final url = Uri.parse(
        'https://api.openrouteservice.org/v2/directions/driving-car'
        '?api_key=$key'
        '&start=${from.longitude},${from.latitude}'
        '&end=${to.longitude},${to.latitude}',
      );

      final resp = await http.get(url).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return [from, to];

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final features = data['features'] as List?;
      if (features == null || features.isEmpty) return [from, to];

      final geometry = features.first['geometry'] as Map<String, dynamic>;
      final coords = geometry['coordinates'] as List;

      return coords
          .map((c) => LatLng(
                (c[1] as num).toDouble(),
                (c[0] as num).toDouble(),
              ))
          .toList();
    } catch (e) {
      return [from, to];
    }
  }

  double _calcKm(List<LatLng> pts) {
    double km = 0;
    for (int i = 1; i < pts.length; i++) {
      km += Geolocator.distanceBetween(
            pts[i - 1].latitude,
            pts[i - 1].longitude,
            pts[i].latitude,
            pts[i].longitude,
          ) / 1000;
    }
    return km;
  }

  Future<void> _fetchRoutes() async {
    setState(() => _loadingRoutes = true);

    List<LatLng> pickupRoute = [];
    List<LatLng> deliveryRoute = [];
    double totalKm = 0;

    final shopPts = widget.shops.map((s) => LatLng(s.lat, s.lng)).toList();
    final customerPt = LatLng(widget.group.deliveryLat ?? 0.0, widget.group.deliveryLng ?? 0.0);
    final riderPt = (widget.riderLat != null && widget.riderLng != null)
        ? LatLng(widget.riderLat!, widget.riderLng!)
        : null;

    if (riderPt != null && shopPts.isNotEmpty) {
      final r = await _fetchORSRoute(riderPt, shopPts.first);
      pickupRoute.addAll(r);
      totalKm += _calcKm(r);
    }

    if (shopPts.isNotEmpty) {
      for (int i = 0; i < shopPts.length - 1; i++) {
        final r = await _fetchORSRoute(shopPts[i], shopPts[i + 1]);
        deliveryRoute.addAll(r);
        totalKm += _calcKm(r);
      }
      final lastR = await _fetchORSRoute(shopPts.last, customerPt);
      deliveryRoute.addAll(lastR);
      totalKm += _calcKm(lastR);
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
    final allPoints = [
      if (widget.riderLat != null && widget.riderLng != null) LatLng(widget.riderLat!, widget.riderLng!),
      ...widget.shops.map((s) => LatLng(s.lat, s.lng)),
      LatLng(widget.group.deliveryLat ?? 0.0, widget.group.deliveryLng ?? 0.0),
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
      _mapCtrl.fitCamera(CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48)));
    } catch (_) {}
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
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 12, offset: const Offset(0, 4))],
            border: Border.all(color: Colors.white, width: 2.5),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
          child: Text(label, style: GoogleFonts.outfit(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final markers = <Marker>[
      for (int i = 0; i < widget.shops.length; i++)
        Marker(
          point: LatLng(widget.shops[i].lat, widget.shops[i].lng),
          width: 80,
          height: 70,
          child: _mapMarker(_kShopMarker, Icons.storefront_rounded, widget.shops[i].name),
        ),
      Marker(
        point: LatLng(widget.group.deliveryLat ?? 0.0, widget.group.deliveryLng ?? 0.0),
        width: 80,
        height: 70,
        child: _mapMarker(_kCustomerMarker, Icons.location_on_rounded, 'Customer'),
      ),
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
        backgroundColor: isDark ? const Color(0xFF080812) : const Color(0xFFF0F4FF),
        body: Stack(
          children: [
            FlutterMap(
              mapController: _mapCtrl,
              options: MapOptions(
                initialCenter: widget.shops.isNotEmpty ? LatLng(widget.shops.first.lat, widget.shops.first.lng) : const LatLng(0,0),
                initialZoom: 13,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
              ),
              children: [
                TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.enything.app'),
                if (_pickupRoute.isNotEmpty) PolylineLayer(polylines: [Polyline(points: _pickupRoute, color: _kPickupColor, strokeWidth: 4.5, borderStrokeWidth: 1.5, borderColor: Colors.white.withValues(alpha: 0.6))]),
                if (_deliveryRoute.isNotEmpty) PolylineLayer(polylines: [Polyline(points: _deliveryRoute, color: _kDeliveryColor, strokeWidth: 4.5, borderStrokeWidth: 1.5, borderColor: Colors.white.withValues(alpha: 0.6))]),
                MarkerLayer(markers: markers),
              ],
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 42, height: 42,
                        decoration: BoxDecoration(color: isDark ? const Color(0xFF1E1E2E) : Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 10, offset: const Offset(0, 3))]),
                        child: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: isDark ? Colors.white : Colors.black87),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(color: isDark ? const Color(0xFF1E1E2E) : Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 3))]),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(widget.group.isMultiShop ? 'Multi-Shop Order (${widget.shops.length} Shops)' : 'Order #${widget.group.orders.first.id.substring(0, 8).toUpperCase()}',
                                style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 14, color: isDark ? Colors.white : Colors.black87)),
                            Text(widget.group.isMultiShop ? 'Various Shops' : widget.shops.first.name,
                                style: GoogleFonts.outfit(fontSize: 12, color: isDark ? Colors.white54 : Colors.grey.shade600), overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: _fitMapBounds,
                      child: Container(
                        width: 42, height: 42,
                        decoration: BoxDecoration(color: isDark ? const Color(0xFF1E1E2E) : Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 10, offset: const Offset(0, 3))]),
                        child: const Icon(Icons.my_location_rounded, size: 20, color: AppColors.primary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1A1A2E).withValues(alpha: 0.97) : Colors.white.withValues(alpha: 0.97),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 24, offset: const Offset(0, -6))],
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Container(width: 14, height: 4, decoration: BoxDecoration(color: _kPickupColor, borderRadius: BorderRadius.circular(2))),
                            const SizedBox(width: 6),
                            Text('Pickup', style: GoogleFonts.outfit(fontSize: 12, color: _kPickupColor, fontWeight: FontWeight.w600)),
                            const SizedBox(width: 20),
                            Container(width: 14, height: 4, decoration: BoxDecoration(color: _kDeliveryColor, borderRadius: BorderRadius.circular(2))),
                            const SizedBox(width: 6),
                            Text('Delivery', style: GoogleFonts.outfit(fontSize: 12, color: _kDeliveryColor, fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(color: const Color(0xFF00B4D8).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF00B4D8).withValues(alpha: 0.35), width: 1.2)),
                                child: Row(
                                  children: [
                                    Container(width: 30, height: 30, decoration: const BoxDecoration(color: Color(0xFF00B4D8), shape: BoxShape.circle), child: const Icon(Icons.route_rounded, color: Colors.white, size: 16)),
                                    const SizedBox(width: 10),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Total Distance', style: GoogleFonts.outfit(color: const Color(0xFF00B4D8), fontSize: 11, fontWeight: FontWeight.w600)),
                                        if (_loadingRoutes) SizedBox(height: 10, width: 40, child: const LinearProgressIndicator(color: Color(0xFF00B4D8)))
                                        else Text(_totalKm != null ? '${_totalKm!.toStringAsFixed(1)} km' : '— km', style: GoogleFonts.outfit(color: _totalKm != null ? const Color(0xFF00B4D8) : Colors.grey, fontSize: 15, fontWeight: FontWeight.w800)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Text('₹${widget.group.totalGrand.toStringAsFixed(0)} order', style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: isDark ? Colors.white : Colors.black87)),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.success.withValues(alpha: 0.4))),
                              child: Text('₹${widget.group.totalEarnings.toStringAsFixed(0)} earn', style: GoogleFonts.outfit(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: widget.onAccept,
                            icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
                            label: Text('Accept Order', style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 15)),
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 4, shadowColor: AppColors.success.withValues(alpha: 0.4)),
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
