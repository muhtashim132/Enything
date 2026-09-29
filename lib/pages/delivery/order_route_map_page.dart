import 'dart:async';
import 'dart:math' as math;
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

/// 100x Architecture: Aggregated Physical Shop Stop.
/// Clusters multiple sub-orders (even from different customers) at the same physical store.
class UnifiedShopStop {
  final double lat;
  final double lng;
  final String name;
  final String? phone;
  final List<OrderModel> orders;

  UnifiedShopStop({
    required this.lat,
    required this.lng,
    required this.name,
    this.phone,
    required this.orders,
  });

  String get aggregateStatus {
    final active = orders.where((o) =>
        o.status != 'rejected' &&
        o.status != 'cancelled' &&
        o.status != 'seller_rejected' &&
        o.status != 'partner_rejected' &&
        o.status != 'shop_dispute_cancel').toList();
    if (active.isEmpty) return 'cancelled';
    if (active.every((o) =>
        o.status == 'picked_up' ||
        o.status == 'out_for_delivery' ||
        o.status == 'delivered')) {
      return 'picked_up';
    }
    if (active.any((o) => o.status == 'ready_for_pickup')) return 'ready_for_pickup';
    if (active.any((o) => o.status == 'preparing')) return 'preparing';
    return active.first.status;
  }

  bool get isPickedUp => aggregateStatus == 'picked_up';
  bool get isCancelled => aggregateStatus == 'cancelled';
}

class OrderRouteMapPage extends StatefulWidget {
  final OrderGroup group;
  final List<OrderGroup>? groups;
  final double? riderLat;
  final double? riderLng;
  final List<({double lat, double lng, String name})> shops;
  final VoidCallback onAccept;
  final bool isViewOnly;

  const OrderRouteMapPage({
    super.key,
    required this.group,
    this.groups,
    required this.riderLat,
    required this.riderLng,
    this.shops = const [],
    this.onAccept = _noop,
    this.isViewOnly = false,
  });

  static void _noop() {}

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
  // 100x FIX (Edge Case 6): Support multiple realtime channels for multi-customer routes
  final List<RealtimeChannel> _orderChannels = [];
  LatLng? _lastRouteFetchPos;

  int _selectedStopIndex = 0;

  @override
  void initState() {
    super.initState();
    _orders = widget.groups != null && widget.groups!.isNotEmpty
        ? widget.groups!.expand((g) => g.orders).toList()
        : List<OrderModel>.from(widget.group.orders);

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
    // 100x FIX (Edge Case 6): Clean up ALL realtime channels
    for (final ch in _orderChannels) {
      _supabase.removeChannel(ch);
    }
    _riderPositionNotifier.dispose();
    super.dispose();
  }

  // ── Supabase Realtime Subscription ─────────────────────────────────────────
  void _subscribeToOrderChanges() {
    // 100x FIX (Edge Case 6): Subscribe to ALL distinct cart groups in
    // multi-customer master route mode, not just the primary group.
    final groupsToSubscribe = (widget.groups != null && widget.groups!.isNotEmpty)
        ? widget.groups!
        : [widget.group];

    final subscribedGroupIds = <String>{};

    for (final group in groupsToSubscribe) {
      final cartGroupId = group.primaryOrder.cartGroupId;
      final primaryId = group.primaryOrder.id;
      final subscriptionKey = cartGroupId ?? primaryId;

      // Deduplicate: don't subscribe to the same cart_group_id twice
      if (subscribedGroupIds.contains(subscriptionKey)) continue;
      subscribedGroupIds.add(subscriptionKey);

      final channelName = cartGroupId != null
          ? 'rider-route-map-group-$cartGroupId'
          : 'rider-route-map-$primaryId';

      final channel = _supabase
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
                      o.status != 'seller_rejected' &&
                      o.status != 'partner_rejected' &&
                      o.status != 'shop_dispute_cancel')
                  .toList();

              // If a stop was cancelled/disputed
              if (updatedOrder.status == 'seller_rejected' ||
                  updatedOrder.status == 'shop_dispute_cancel' ||
                  updatedOrder.status == 'cancelled') {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('⚠️ A stop was cancelled or disputed. Recalculating route...'),
                    backgroundColor: Colors.orange.shade800,
                  ),
                );
              }

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

              // 100x FIX (Edge Case 3): Clamp selected stop index to prevent RangeError crash
              final totalStops =
                  _effectiveShopStops.length + _activeCustomerGroups.length;
              if (_selectedStopIndex >= totalStops) {
                setState(() {
                  _selectedStopIndex = math.max(0, totalStops - 1);
                });
              }
            },
          )
          .subscribe();

      _orderChannels.add(channel);
    }
  }

  /// 100x FIX: Active customer groups excluding completely cancelled/rejected groups.
  List<OrderGroup> get _activeCustomerGroups {
    final allGroups = (widget.groups != null && widget.groups!.isNotEmpty)
        ? widget.groups!
        : [widget.group];

    return allGroups.where((g) {
      if (g.deliveryLat == null || g.deliveryLat == 0.0) return false;
      return !_isGroupCancelled(g);
    }).toList();
  }

  /// 100x FIX: True only if all sub-orders of this group are terminal cancelled/rejected.
  bool _isGroupCancelled(OrderGroup g) {
    final groupOrders = _orders.where((o) =>
        (o.cartGroupId != null && o.cartGroupId == g.groupId) ||
        (o.cartGroupId == null && o.id == g.primaryOrder.id)).toList();
    if (groupOrders.isEmpty) return true;
    return groupOrders.every((o) =>
        o.status == 'rejected' ||
        o.status == 'cancelled' ||
        o.status == 'seller_rejected' ||
        o.status == 'partner_rejected' ||
        o.status == 'shop_dispute_cancel');
  }

  /// 100x FIX: Group is delivered ONLY if active orders are non-empty and all are 'delivered'.
  bool _isGroupDelivered(OrderGroup g) {
    final groupOrders = _orders.where((o) =>
        (o.cartGroupId != null && o.cartGroupId == g.groupId) ||
        (o.cartGroupId == null && o.id == g.primaryOrder.id)).toList();
    if (groupOrders.isEmpty) return false;
    final active = groupOrders.where((o) =>
        o.status != 'rejected' &&
        o.status != 'cancelled' &&
        o.status != 'seller_rejected' &&
        o.status != 'partner_rejected' &&
        o.status != 'shop_dispute_cancel').toList();
    if (active.isEmpty) return false; // If all were cancelled, it's NOT delivered!
    return active.every((o) => o.status == 'delivered');
  }

  /// 100x FIX (Edge Case 1): Unified Physical Shop Stops.
  /// Deduplicates co-located shops across multiple customer cart groups.
  List<UnifiedShopStop> get _effectiveShopStops {
    final activeOrders = _orders
        .where((o) =>
            o.status != 'rejected' &&
            o.status != 'cancelled' &&
            o.status != 'seller_rejected' &&
            o.status != 'partner_rejected' &&
            o.status != 'shop_dispute_cancel')
        .toList();

    final targetOrders = activeOrders.isNotEmpty ? activeOrders : _orders;
    final stops = <UnifiedShopStop>[];

    for (final o in targetOrders) {
      final sLat = o.shopLat ?? 0.0;
      final sLng = o.shopLng ?? 0.0;
      if (sLat == 0.0 && sLng == 0.0) continue;

      // Check if this shop already exists by shopId or within 25m geographic radius
      final existingIndex = stops.indexWhere((s) {
        if (o.shopId != null && s.orders.any((ord) => ord.shopId == o.shopId)) {
          return true;
        }
        return Geolocator.distanceBetween(s.lat, s.lng, sLat, sLng) < 25.0;
      });

      final matchingShop = widget.shops.firstWhere(
        (s) =>
            (sLat != 0.0 &&
                sLng != 0.0 &&
                (s.lat - sLat).abs() < 0.0001 &&
                (s.lng - sLng).abs() < 0.0001),
        orElse: () => (
          lat: sLat,
          lng: sLng,
          name: o.items.isNotEmpty ? o.items.first.productName : 'Shop',
        ),
      );

      if (existingIndex != -1) {
        stops[existingIndex].orders.add(o);
      } else {
        stops.add(UnifiedShopStop(
          lat: matchingShop.lat != 0.0 ? matchingShop.lat : sLat,
          lng: matchingShop.lng != 0.0 ? matchingShop.lng : sLng,
          name: matchingShop.name,
          phone: o.shopPhone,
          orders: [o],
        ));
      }
    }
    return stops;
  }

  Future<void> _fetchRoutes({bool silent = false}) async {
    if (!silent) {
      setState(() => _loadingRoutes = true);
    }

    List<LatLng> pickupRoute = [];
    List<LatLng> deliveryRoute = [];
    double totalKm = 0;

    final shops = _effectiveShopStops;
    // 100x FIX: Use aggregate status whitelist for unpicked shops
    final unpickedShops = shops
        .where((s) =>
            s.aggregateStatus == 'confirmed' ||
            s.aggregateStatus == 'preparing' ||
            s.aggregateStatus == 'ready_for_pickup')
        .toList();

    List<LatLng> shopPts = [];
    if (unpickedShops.isNotEmpty) {
      final unvisited = List<UnifiedShopStop>.from(unpickedShops);
      final riderPos = _riderPositionNotifier.value;
      LatLng currentPos =
          riderPos ?? LatLng(unvisited.first.lat, unvisited.first.lng);

      while (unvisited.isNotEmpty) {
        unvisited.sort((a, b) {
          final distA = Geolocator.distanceBetween(
              currentPos.latitude, currentPos.longitude, a.lat, a.lng);
          final distB = Geolocator.distanceBetween(
              currentPos.latitude, currentPos.longitude, b.lat, b.lng);
          return distA.compareTo(distB);
        });
        final nearest = unvisited.removeAt(0);
        shopPts.add(LatLng(nearest.lat, nearest.lng));
        currentPos = LatLng(nearest.lat, nearest.lng);
      }
    }

    // 100x FIX (Edge Case 2): Greedy nearest-neighbor customer drop-off TSP sequence
    final undeliveredGroups =
        _activeCustomerGroups.where((g) => !_isGroupDelivered(g)).toList();
    List<LatLng> customerPts = [];
    if (undeliveredGroups.isNotEmpty) {
      final unvisitedGroups = List<OrderGroup>.from(undeliveredGroups);
      final riderPos = _riderPositionNotifier.value;
      LatLng dropRef = shopPts.isNotEmpty
          ? shopPts.last
          : (riderPos ??
              LatLng(undeliveredGroups.first.deliveryLat!,
                  undeliveredGroups.first.deliveryLng!));

      while (unvisitedGroups.isNotEmpty) {
        unvisitedGroups.sort((a, b) {
          final distA = Geolocator.distanceBetween(
              dropRef.latitude,
              dropRef.longitude,
              a.deliveryLat!,
              a.deliveryLng!);
          final distB = Geolocator.distanceBetween(
              dropRef.latitude,
              dropRef.longitude,
              b.deliveryLat!,
              b.deliveryLng!);
          return distA.compareTo(distB);
        });
        final nearest = unvisitedGroups.removeAt(0);
        customerPts.add(LatLng(nearest.deliveryLat!, nearest.deliveryLng!));
        dropRef = LatLng(nearest.deliveryLat!, nearest.deliveryLng!);
      }
    }

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
    // If there are unpicked shops: Shop 1 -> Shop 2 -> Customer(s)
    // If ALL shops are picked up: Rider -> Customer(s) directly!
    if (shopPts.isNotEmpty) {
      final allWaypoints = [...shopPts, ...customerPts];
      final r = await GeoUtils.fetchMultiStopRoute(allWaypoints);
      deliveryRoute.addAll(r);
      totalKm += GeoUtils.calculateRouteDistanceKm(r);
    } else if (riderPt != null && customerPts.isNotEmpty) {
      final r = customerPts.length > 1
          ? await GeoUtils.fetchMultiStopRoute([riderPt, ...customerPts])
          : await GeoUtils.fetchRoadRoute(riderPt, customerPts.first);
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
    final activeGroups = _activeCustomerGroups;

    final customerPts = activeGroups
        .where((g) => g.deliveryLat != null && g.deliveryLat != 0.0)
        .map((g) => LatLng(g.deliveryLat!, g.deliveryLng!))
        .toList();

    final allPoints = [
      if (riderPos != null && riderPos.latitude != 0.0) riderPos,
      ...activeShops.map((s) => LatLng(s.lat, s.lng)),
      ...customerPts,
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
        .where((s) =>
            s.aggregateStatus == 'confirmed' ||
            s.aggregateStatus == 'preparing' ||
            s.aggregateStatus == 'ready_for_pickup')
        .toList();

    final origin = (riderPos != null && riderPos.latitude != 0.0)
        ? '${riderPos.latitude},${riderPos.longitude}'
        : shops.isNotEmpty
            ? '${shops.first.lat},${shops.first.lng}'
            : '';

    // 100x FIX: Greedy TSP customer drop-offs for external map
    final undeliveredGroups =
        _activeCustomerGroups.where((g) => !_isGroupDelivered(g)).toList();
    final orderedCustomerPts = <String>[];
    if (undeliveredGroups.isNotEmpty) {
      final unvisited = List<OrderGroup>.from(undeliveredGroups);
      LatLng ref = unpickedShops.isNotEmpty
          ? LatLng(unpickedShops.last.lat, unpickedShops.last.lng)
          : (riderPos ??
              LatLng(unvisited.first.deliveryLat!,
                  unvisited.first.deliveryLng!));

      while (unvisited.isNotEmpty) {
        unvisited.sort((a, b) {
          final distA = Geolocator.distanceBetween(
              ref.latitude, ref.longitude, a.deliveryLat!, a.deliveryLng!);
          final distB = Geolocator.distanceBetween(
              ref.latitude, ref.longitude, b.deliveryLat!, b.deliveryLng!);
          return distA.compareTo(distB);
        });
        final nearest = unvisited.removeAt(0);
        orderedCustomerPts.add('${nearest.deliveryLat},${nearest.deliveryLng}');
        ref = LatLng(nearest.deliveryLat!, nearest.deliveryLng!);
      }
    }

    final destination = orderedCustomerPts.isNotEmpty
        ? orderedCustomerPts.last
        : (shops.isNotEmpty ? '${shops.last.lat},${shops.last.lng}' : '');

    if (origin.isEmpty || destination.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Cannot open map: Missing location coordinates.')));
      }
      return;
    }

    // Build waypoints: deduplicated unpicked shops + intermediate customer drop-offs
    final waypoints = <String>[
      ...unpickedShops.map((s) => '${s.lat},${s.lng}'),
      if (orderedCustomerPts.length > 1)
        ...orderedCustomerPts.sublist(0, orderedCustomerPts.length - 1),
    ];

    // 100x FIX (Edge Case 6): Cap waypoints to max 8 immediate stops to prevent Google Maps URL overflow
    final safeWaypoints = waypoints.take(8).toList();
    final waypointsParam =
        safeWaypoints.isNotEmpty ? '&waypoints=${safeWaypoints.join('|')}' : '';
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&origin=$origin&destination=$destination$waypointsParam');

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
    final activeGroups = _activeCustomerGroups;
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
      // Shop markers (100x FIX: 1 pin per physical shop stop)
      for (int i = 0; i < shops.length; i++) ...[
        Marker(
          point: applyJitter(shops[i].lat, shops[i].lng),
          width: 80,
          height: 70,
          child: _mapMarker(
            shops[i].isPickedUp
                ? _kShopPickedUpMarker
                : shops[i].isCancelled
                    ? _kShopCancelledMarker
                    : _kShopMarker,
            shops[i].isPickedUp
                ? Icons.check_circle_rounded
                : Icons.storefront_rounded,
            isMulti ? '${i + 1}. ${shops[i].name}' : shops[i].name,
          ),
        ),
      ],
      // Customer delivery markers (100x FIX: Clean labeling per active group)
      for (int i = 0; i < activeGroups.length; i++)
        if (activeGroups[i].deliveryLat != null &&
            activeGroups[i].deliveryLat != 0.0)
          Marker(
            point: applyJitter(activeGroups[i].deliveryLat!,
                activeGroups[i].deliveryLng!),
            width: 90,
            height: 70,
            child: _mapMarker(
                _isGroupDelivered(activeGroups[i])
                    ? Colors.grey
                    : _kCustomerMarker,
                Icons.location_on_rounded,
                _isGroupDelivered(activeGroups[i])
                    ? 'Delivered'
                    : (activeGroups.length > 1 ? 'Drop ${i + 1}' : 'Customer')),
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
                              activeGroups.length > 1
                                  ? 'Master Route (${activeGroups.length} Customers · ${shops.length} Stops)'
                                  : (isMulti
                                      ? 'Multi-Shop Route (${shops.length} Shops)'
                                      : 'Order #${primaryOrder.id.substring(0, math.min(8, primaryOrder.id.length)).toUpperCase()}'),
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
                                          '₹${(widget.groups != null && widget.groups!.isNotEmpty ? widget.groups!.fold(0.0, (sum, g) => sum + g.totalEarnings) : widget.group.totalEarnings).toStringAsFixed(0)}',
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
                        // Stop Selector Tabs (Pickup Stores vs Dropoff)
                        Builder(
                          builder: (context) {
                            final totalStops = shops.length + activeGroups.length;
                            final int selectedIndex = _selectedStopIndex
                                .clamp(0, math.max<int>(0, totalStops - 1))
                                .toInt();

                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      for (int i = 0; i < shops.length; i++) ...[
                                        GestureDetector(
                                          onTap: () => setState(
                                              () => _selectedStopIndex = i),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 14, vertical: 8),
                                            margin:
                                                const EdgeInsets.only(right: 8),
                                            decoration: BoxDecoration(
                                              color: selectedIndex == i
                                                  ? _kPickupColor
                                                      .withValues(alpha: 0.15)
                                                  : Colors.transparent,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              border: Border.all(
                                                color: selectedIndex == i
                                                    ? _kPickupColor
                                                    : Colors.grey
                                                        .withValues(alpha: 0.3),
                                              ),
                                            ),
                                            child: Center(
                                              child: Text(
                                                shops.length > 1
                                                    ? 'Shop ${i + 1}'
                                                    : 'Shop Info',
                                                style: GoogleFonts.outfit(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color: selectedIndex == i
                                                      ? _kPickupColor
                                                      : (isDark
                                                          ? Colors.white70
                                                          : Colors.black87),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                      for (int j = 0;
                                          j < activeGroups.length;
                                          j++) ...[
                                        GestureDetector(
                                          onTap: () => setState(() =>
                                              _selectedStopIndex =
                                                  shops.length + j),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 14, vertical: 8),
                                            margin:
                                                const EdgeInsets.only(right: 8),
                                            decoration: BoxDecoration(
                                              color: selectedIndex ==
                                                      (shops.length + j)
                                                  ? _kCustomerMarker
                                                      .withValues(alpha: 0.15)
                                                  : Colors.transparent,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              border: Border.all(
                                                color: selectedIndex ==
                                                        (shops.length + j)
                                                    ? _kCustomerMarker
                                                    : Colors.grey
                                                        .withValues(alpha: 0.3),
                                              ),
                                            ),
                                            child: Center(
                                              child: Text(
                                                activeGroups.length > 1
                                                    ? 'Drop ${j + 1}'
                                                    : 'Customer',
                                                style: GoogleFonts.outfit(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color: selectedIndex ==
                                                          (shops.length + j)
                                                      ? _kCustomerMarker
                                                      : (isDark
                                                          ? Colors.white70
                                                          : Colors.black87),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),

                                // Active Stop Details Card
                                if (selectedIndex < shops.length) ...[
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
                                            color: (shops[selectedIndex].isPickedUp
                                                    ? _kShopPickedUpMarker
                                                    : _kShopMarker)
                                                .withValues(alpha: 0.15),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                              shops[selectedIndex].isPickedUp
                                                  ? Icons.check_circle_rounded
                                                  : Icons.storefront_rounded,
                                              color: shops[selectedIndex].isPickedUp
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
                                                shops[selectedIndex].name,
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
                                                shops[selectedIndex].isPickedUp
                                                    ? 'Items picked up ✓'
                                                    : (shops[selectedIndex].orders.length > 1
                                                        ? 'Pick up for ${shops[selectedIndex].orders.length} customers'
                                                        : 'Pick up items here'),
                                                style: GoogleFonts.outfit(
                                                  fontSize: 11,
                                                  color: shops[selectedIndex].isPickedUp
                                                      ? AppColors.success
                                                      : (isDark
                                                          ? Colors.white54
                                                          : Colors.grey.shade600),
                                                  fontWeight:
                                                      shops[selectedIndex].isPickedUp
                                                          ? FontWeight.w600
                                                          : FontWeight.normal,
                                                ),
                                              ),
                                              if (shops[selectedIndex].orders.isNotEmpty)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(top: 2),
                                                  child: Text(
                                                    shops[selectedIndex]
                                                        .orders
                                                        .expand((o) => o.items)
                                                        .map((it) =>
                                                            '${it.quantity}x ${it.productName}')
                                                        .join(', '),
                                                    style: GoogleFonts.outfit(
                                                      fontSize: 10,
                                                      color: isDark
                                                          ? Colors.white60
                                                          : Colors.black54,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        if (shops[selectedIndex].phone != null)
                                          IconButton(
                                            onPressed: () => _call(
                                                shops[selectedIndex].phone),
                                            icon: const Icon(
                                                Icons.phone_rounded,
                                                color: AppColors.primary,
                                                size: 20),
                                            style: IconButton.styleFrom(
                                              backgroundColor: AppColors.primary
                                                  .withValues(alpha: 0.1),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ] else ...[
                                  // Customer Details Card (100x FIX: Dynamic customer selection)
                                  () {
                                    final custIdx =
                                        selectedIndex - shops.length;
                                    final group = (custIdx >= 0 &&
                                            custIdx < activeGroups.length)
                                        ? activeGroups[custIdx]
                                        : widget.group;
                                    final groupOrder = group.primaryOrder;

                                    return Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? const Color(0xFF141424)
                                            : const Color(0xFFF7F9FC),
                                        borderRadius:
                                            BorderRadius.circular(14),
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
                                            child: const Icon(
                                                Icons.home_rounded,
                                                color: _kCustomerMarker,
                                                size: 20),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  group.customerAddress,
                                                  style: GoogleFonts.outfit(
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 13,
                                                    color: isDark
                                                        ? Colors.white
                                                        : Colors.black87,
                                                  ),
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                if (groupOrder.deliveryNotes !=
                                                        null &&
                                                    groupOrder.deliveryNotes!
                                                        .isNotEmpty)
                                                  Text(
                                                    'Note: ${groupOrder.deliveryNotes}',
                                                    style: GoogleFonts.outfit(
                                                      fontSize: 11,
                                                      color: AppColors.warning,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                Text(
                                                  '${group.activeOrders.length} store${group.activeOrders.length > 1 ? 's' : ''} · ${group.activeOrders.fold<int>(0, (sum, o) => sum + o.items.fold<int>(0, (s, i) => s + i.quantity))} items',
                                                  style: GoogleFonts.outfit(
                                                    fontSize: 10,
                                                    color: isDark
                                                        ? Colors.white54
                                                        : Colors.grey.shade600,
                                                  ),
                                                ),
                                                const SizedBox(height: 3),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.success.withValues(alpha: 0.15),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    '💳 Prepaid (₹0)',
                                                    style: GoogleFonts.outfit(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.w700,
                                                      color: AppColors.success,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (group.customerPhone != null)
                                            IconButton(
                                              onPressed: () =>
                                                  _call(group.customerPhone),
                                              icon: const Icon(
                                                  Icons.phone_rounded,
                                                  color: AppColors.primary,
                                                  size: 20),
                                              style: IconButton.styleFrom(
                                                backgroundColor: AppColors
                                                    .primary
                                                    .withValues(alpha: 0.1),
                                              ),
                                            ),
                                        ],
                                      ),
                                    );
                                  }(),
                                ],
                              ],
                            );
                          },
                        ),
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
