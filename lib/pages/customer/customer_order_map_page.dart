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
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/order_model.dart';
import '../../theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Colour palette (customer perspective — no pickup leg)
// ─────────────────────────────────────────────────────────────────────────────
const _kDeliveryColor = Color(0xFFFF8C42); // orange — shop → customer
const _kShopMarkerColor = Color(0xFFFF8C42);
const _kCustomerMarkerColor = Color(0xFF00B4D8); // cyan — customer home
const _kRiderMarkerColor = Color(0xFF2ECC71); // green — live rider dot

// ─────────────────────────────────────────────────────────────────────────────
// CustomerOrderMapPage
// Full-screen ORS map for the customer. Shows:
//   • Shop → Customer delivery polyline (orange)
//   • Live rider marker (when out_for_delivery), updated via Supabase Realtime
//   • Chips: delivery distance + estimated arrival
//   • Call Shop / Call Rider action buttons
// ─────────────────────────────────────────────────────────────────────────────
class CustomerOrderMapPage extends StatefulWidget {
  final OrderModel order;

  const CustomerOrderMapPage({super.key, required this.order});

  @override
  State<CustomerOrderMapPage> createState() => _CustomerOrderMapPageState();
}

class _CustomerOrderMapPageState extends State<CustomerOrderMapPage>
    with TickerProviderStateMixin {
  final MapController _mapCtrl = MapController();
  final _supabase = Supabase.instance.client;

  // Route data
  List<LatLng> _deliveryRoute = [];
  bool _loadingRoutes = true;
  double? _deliveryKm;

  // Live rider position (updated via Realtime)
  LatLng? _riderLatLng;
  DateTime? _riderUpdatedAt;
  RealtimeChannel? _channel;

  // Pulse animation for the rider dot
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();

    // Seed rider position from current order snapshot
    if (widget.order.riderLat != null && widget.order.riderLng != null) {
      _riderLatLng = LatLng(widget.order.riderLat!, widget.order.riderLng!);
      _riderUpdatedAt = widget.order.riderLocationUpdatedAt;
    }

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _fetchRoutes();
    _subscribeToRider();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _channel?.unsubscribe();
    super.dispose();
  }

  // ── Supabase Realtime ────────────────────────────────────────────────────

  void _subscribeToRider() {
    _channel = _supabase
        .channel('customer-map-${widget.order.id}')
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
            if (lat != null && lng != null) {
              setState(() {
                _riderLatLng = LatLng(lat, lng);
                _riderUpdatedAt = r['rider_location_updated_at'] != null
                    ? DateTime.tryParse(r['rider_location_updated_at'])
                    : null;
              });
            }
          },
        )
        .subscribe();
  }

  // ── ORS Route Fetching ───────────────────────────────────────────────────

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
      return [from, to];
    }
  }

  Future<void> _fetchRoutes() async {
    setState(() => _loadingRoutes = true);

    final shopLat = widget.order.shopLat;
    final shopLng = widget.order.shopLng;
    final custLat = widget.order.deliveryLat;
    final custLng = widget.order.deliveryLng;

    if (shopLat == null || shopLng == null || custLat == null || custLng == null) {
      if (mounted) setState(() => _loadingRoutes = false);
      return;
    }

    final shopPt = LatLng(shopLat, shopLng);
    final custPt = LatLng(custLat, custLng);

    final route = await _fetchORSRoute(shopPt, custPt);

    double km = 0;
    for (int i = 1; i < route.length; i++) {
      km += Geolocator.distanceBetween(
            route[i - 1].latitude,
            route[i - 1].longitude,
            route[i].latitude,
            route[i].longitude,
          ) /
          1000;
    }

    if (mounted) {
      setState(() {
        _deliveryRoute = route;
        _deliveryKm = km > 0 ? km : null;
        _loadingRoutes = false;
      });
      _fitMapBounds();
    }
  }

  void _fitMapBounds() {
    final pts = <LatLng>[
      if (widget.order.shopLat != null && widget.order.shopLng != null)
        LatLng(widget.order.shopLat!, widget.order.shopLng!),
      if (widget.order.deliveryLat != null && widget.order.deliveryLng != null)
        LatLng(widget.order.deliveryLat!, widget.order.deliveryLng!),
      if (_riderLatLng != null) _riderLatLng!,
    ];
    if (pts.isEmpty) return;

    double minLat = pts.first.latitude, maxLat = pts.first.latitude;
    double minLng = pts.first.longitude, maxLng = pts.first.longitude;

    for (final p in pts) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }

    try {
      _mapCtrl.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds(
            LatLng(minLat - 0.005, minLng - 0.005),
            LatLng(maxLat + 0.005, maxLng + 0.005),
          ),
          padding: const EdgeInsets.all(56),
        ),
      );
    } catch (_) {}
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

  Widget _riderMarker() {
    return ScaleTransition(
      scale: _pulseAnim,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _kRiderMarkerColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _kRiderMarkerColor.withValues(alpha: 0.5),
                  blurRadius: 16,
                  spreadRadius: 2,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(color: Colors.white, width: 2.5),
            ),
            child: const Icon(Icons.delivery_dining_rounded,
                color: Colors.white, size: 26),
          ),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _kRiderMarkerColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Rider',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom chip ──────────────────────────────────────────────────────────

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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: GoogleFonts.outfit(
                      color: color, fontSize: 11, fontWeight: FontWeight.w600)),
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
                Text(value,
                    style: GoogleFonts.outfit(
                        color: color,
                        fontSize: 15,
                        fontWeight: FontWeight.w800)),
            ],
          ),
        ],
      ),
    );
  }

  // ── Phone helper ─────────────────────────────────────────────────────────

  Future<void> _call(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  // ── ETA estimate ─────────────────────────────────────────────────────────

  String _etaString() {
    if (_deliveryKm == null) return '—';
    // Assume avg 20 km/h in city traffic
    final mins = ((_deliveryKm! / 20) * 60).round();
    if (mins < 1) return '< 1 min';
    return '$mins min';
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final order = widget.order;
    final isOutForDelivery = order.status == 'out_for_delivery';

    final shopLat = order.shopLat;
    final shopLng = order.shopLng;
    final custLat = order.deliveryLat;
    final custLng = order.deliveryLng;

    final markers = <Marker>[
      // Shop pin
      if (shopLat != null && shopLng != null)
        Marker(
          point: LatLng(shopLat, shopLng),
          width: 80,
          height: 70,
          child: _mapMarker(_kShopMarkerColor, Icons.storefront_rounded, 'Shop'),
        ),
      // Customer home pin
      if (custLat != null && custLng != null)
        Marker(
          point: LatLng(custLat, custLng),
          width: 80,
          height: 70,
          child: _mapMarker(
              _kCustomerMarkerColor, Icons.home_rounded, 'You'),
        ),
      // Live rider marker (only when out_for_delivery and position is known)
      if (isOutForDelivery && _riderLatLng != null)
        Marker(
          point: _riderLatLng!,
          width: 80,
          height: 72,
          child: _riderMarker(),
        ),
    ];

    // Map initial centre — prefer customer address
    final mapCenter = (custLat != null && custLng != null)
        ? LatLng(custLat, custLng)
        : (shopLat != null && shopLng != null)
            ? LatLng(shopLat, shopLng)
            : const LatLng(28.6139, 77.2090);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF080812) : const Color(0xFFF0F4FF),
        body: Stack(
          children: [
            // ── Full-screen map ────────────────────────────────────────────
            FlutterMap(
              mapController: _mapCtrl,
              options: MapOptions(
                initialCenter: mapCenter,
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

                // Shop → Customer delivery route (orange)
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
              ],
            ),

            // ── Top bar ────────────────────────────────────────────────────
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
                          color: isDark
                              ? const Color(0xFF1E1E2E)
                              : Colors.white,
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

                    // Title card
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
                              isOutForDelivery
                                  ? 'Rider is on the way! 🚴'
                                  : order.statusDisplay,
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

            // ── Loading overlay ────────────────────────────────────────────
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
                      color: isDark
                          ? const Color(0xFF1E1E2E)
                          : Colors.white,
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
                        Text('Loading route…',
                            style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black87)),
                      ],
                    ),
                  ),
                ),
              ),

            // ── Bottom info panel ──────────────────────────────────────────
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
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Route legend
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
                            if (isOutForDelivery && _riderLatLng != null) ...[
                              const SizedBox(width: 16),
                              Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  color: _kRiderMarkerColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Live rider',
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  color: _kRiderMarkerColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (_riderUpdatedAt != null) ...[
                                const Spacer(),
                                Text(
                                  'Updated ${_secondsAgo(_riderUpdatedAt!)}s ago',
                                  style: GoogleFonts.outfit(
                                    fontSize: 10,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Distance + ETA chips
                        Row(
                          children: [
                            Expanded(
                              child: _infoChip(
                                color: _kDeliveryColor,
                                icon: Icons.route_rounded,
                                label: 'Distance',
                                value: _deliveryKm != null
                                    ? '${_deliveryKm!.toStringAsFixed(1)} km'
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
                                value: _loadingRoutes ? '…' : _etaString(),
                                loading: _loadingRoutes,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Call buttons
                        if (order.shopPhone != null ||
                            order.riderPhone != null) ...[
                          Row(children: [
                            if (order.shopPhone != null)
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
                            if (order.shopPhone != null &&
                                order.riderPhone != null)
                              const SizedBox(width: 10),
                            if (order.riderPhone != null)
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
                                    side:
                                        const BorderSide(color: AppColors.accent),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(14)),
                                  ),
                                ),
                              ),
                          ]),
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
      DateTime.now().difference(dt).inSeconds.abs();
}
