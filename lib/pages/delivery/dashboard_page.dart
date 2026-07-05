import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/notification_provider.dart';
import '../../models/order_model.dart';
import '../../models/shop_model.dart';
import '../../theme/app_colors.dart';
import '../../config/routes.dart';
import '../../widgets/common/rating_bottom_sheet.dart';
import '../../widgets/common/notification_bell.dart';
import '../../widgets/order_countdown_timer.dart';
import 'order_route_map_page.dart';
import '../../utils/time_utils.dart';
import '../../models/order_group.dart';
import '../../utils/delivery_calculator.dart';
import '../../services/rider_background_service.dart';

class DeliveryDashboardPage extends StatefulWidget {
  const DeliveryDashboardPage({super.key});
  @override
  State<DeliveryDashboardPage> createState() => _DeliveryDashboardPageState();
}

class _DeliveryDashboardPageState extends State<DeliveryDashboardPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final _supabase = Supabase.instance.client;
  bool _isOnline = false;
  List<OrderGroup> _availableGroups = [];
  List<OrderGroup> _myGroups = [];
  double _todayEarnings = 0.0;
  double _totalKmsDriven = 0.0;
  bool _isLoading = false;
  bool _isOrdersLoadInProgress = false; // C2: debounce guard
  // Bug #19: rider's current GPS position for geographic filtering
  double? _riderLat;
  double? _riderLng;
  bool _locationUnavailable = false;

  // Location broadcast timer — updates rider_lat/rider_lng every 15s
  Timer? _locationBroadcastTimer;

  // shopId → {lat, lng, name} resolved from joined shop data in available orders
  final Map<String, ({double lat, double lng, String name})> _shopInfoCache = {};

  late AnimationController _bgCtrl;
  late Animation<double> _bgAnim;

  String _navApp = 'google_maps';
  String _vehicleType = 'motorcycle';

  // Track collapsed state so it doesn't reset on timer/realtime updates
  final Set<String> _collapsedAvailableGroups = {};
  final Set<String> _collapsedActiveGroups = {};
  DateTime? _lastBackPressTime;

  // FCM foreground message subscription — triggers _loadOrders() on push
  StreamSubscription? _fcmForegroundSub;
  RealtimeChannel? _realtimeChannel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bgCtrl =
        AnimationController(duration: const Duration(seconds: 5), vsync: this)
          ..repeat(reverse: true);
    _bgAnim = CurvedAnimation(parent: _bgCtrl, curve: Curves.easeInOut);

    _loadOrders();
    _initNotifications();
    // Initialize background GPS service (registers the isolate entry point).
    // Must be called once per app session before startService() can be used.
    RiderBackgroundService.instance.initialize();
  }

  void _initNotifications() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      final userId = auth.currentUserId;
      if (userId != null) {
        final notifProvider = context.read<NotificationProvider>();
        notifProvider.listenAsDelivery(userId);
        notifProvider.registerFcmToken(userId, 'delivery'); // Register push token
      }

      // Reload available orders when a push arrives while the dashboard is open
      _fcmForegroundSub = FirebaseMessaging.onMessage.listen((_) {
        if (mounted) _loadOrders();
      });

      // D3 FIX: Filter INSERT events to only orders with no delivery partner yet.
      // Without this, every new order on the platform would trigger _loadOrders()
      // for every connected rider, creating O(riders × orders) load spikes.
      _realtimeChannel = _supabase
          .channel('delivery-orders-$userId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'orders',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'delivery_partner_id',
              value: 'null', // Supabase realtime IS NULL filter syntax
            ),
            callback: (_) {
              if (mounted) _loadOrders();
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'orders',
            callback: (payload) {
              if (mounted) {
                // A1: newRecord is non-nullable in Supabase SDK v2
                final orderId = payload.newRecord['id'] as String?;
                if (orderId != null) {
                  final wasAvailable = _availableGroups.expand((g) => g.orders).any((o) => o.id == orderId);
                  if (wasAvailable) {
                    _loadOrders();
                  }
                }
              }
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'orders',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'delivery_partner_id',
              value: userId,
            ),
            callback: (payload) {
              if (mounted) {
                // A1: oldRecord and newRecord are non-nullable in Supabase SDK v2
                final oldRec = payload.oldRecord;
                final newRec = payload.newRecord;
                if (oldRec['status'] != newRec['status']) {
                  final newStatus = newRec['status'];
                  if (newStatus == 'confirmed') {
                    _showSnack('💳 Payment Confirmed! Head to the shop.', isError: false);
                  } else if (newStatus == 'preparing') {
                    _showSnack('👨‍🍳 A shop started preparing an order!', isError: false);
                  } else if (newStatus == 'ready_for_pickup') {
                    _showSnack('📦 An order is ready for pickup!', isError: false);
                  }
                }
                _loadOrders();
              }
            },
          )
          .subscribe();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _locationBroadcastTimer?.cancel();
    _fcmForegroundSub?.cancel();
    _realtimeChannel?.unsubscribe();
    // D2+APP5 FIX: Stop background GPS service when the delivery page is
    // disposed (e.g., user switches role or logs out). Without this, the
    // foreground notification "Enything is tracking your location" stays
    // visible after the rider has left the delivery screen.
    RiderBackgroundService.instance.stopService();
    _bgCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (mounted) _loadOrders();
      // App came back to foreground — stop background service so the
      // existing foreground timer takes over (avoids double GPS polling).
      if (_isOnline) {
        RiderBackgroundService.instance.stopService();
      }
    } else if (state == AppLifecycleState.paused ||
               state == AppLifecycleState.detached) {
      // App went to background / screen locked — start background service
      // so GPS keeps updating for the customer map even when screen is off.
      if (_isOnline) {
        final auth = context.read<AuthProvider>();
        final riderId = auth.currentUserId;
        if (riderId != null) {
          _launchBackgroundService(riderId);
        }
      }
    }
  }

  void _launchBackgroundService(String riderId) {
    // flutter_dotenv is already loaded in main() before runApp().
    // We read the values here to pass them into the background isolate
    // (which has no access to the main isolate's in-memory dotenv state).
    final url = dotenv.env['SUPABASE_URL'] ?? '';
    final anonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';
    if (url.isEmpty || anonKey.isEmpty) {
      debugPrint('[Dashboard] Cannot start background service: missing Supabase env vars');
      return;
    }
    RiderBackgroundService.instance.startService(
      riderId: riderId,
      supabaseUrl: url,
      anonKey: anonKey,
    );
  }

  // Starts pushing GPS location to DB every 15s while online.
  void _startLocationBroadcast() {
    _locationBroadcastTimer?.cancel();
    _locationBroadcastTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (!_isOnline) {
        _stopLocationBroadcast();
        return;
      }
      await _fetchRiderLocation();
      if (_riderLat == null || _riderLng == null) return;
      
      // Update the delivery partner's current location via RPC
      try {
        await _supabase.rpc('update_rider_location', params: {
          'p_lat': _riderLat,
          'p_lng': _riderLng,
        });
      } catch (e) {
        debugPrint('Failed to update delivery partner location: $e');
      }

      // Also update orders that the rider is actively handling
      // BUG-GPS2 FIX: Include 'awaiting_payment' so the rider's location keeps
      // updating while the customer is completing payment. Without it, the rider
      // marker on the customer's map would freeze during the 10-minute payment window.
      final activeStatuses = ['awaiting_payment', 'confirmed', 'preparing', 'ready_for_pickup', 'picked_up', 'out_for_delivery'];

      final activeOrders = _myGroups.expand((g) => g.orders).where((o) => activeStatuses.contains(o.status)).toList();
      
      for (final order in activeOrders) {
        try {
          await _supabase.from('orders').update({
            'rider_lat': _riderLat,
            'rider_lng': _riderLng,
            'rider_location_updated_at': DateTime.now().toIso8601String(),
          }).eq('id', order.id);
        } catch (e) {
          debugPrint('Location broadcast error: $e');
        }
      }
    });
  }

  void _stopLocationBroadcast() {
    _locationBroadcastTimer?.cancel();
    _locationBroadcastTimer = null;
  }

  /// Attempt to get the rider's current GPS position.
  /// Returns true if location was obtained, false otherwise.
  Future<bool> _fetchRiderLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return false;

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) return false;

      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 10),
          ),
        );
      } catch (_) {
        pos = await Geolocator.getLastKnownPosition();
      }

      if (pos != null) {
        _riderLat = pos.latitude;
        _riderLng = pos.longitude;
        return true;
      }
    } catch (e) {
      debugPrint('Rider location error: $e');
    }
    return false;
  }

  List<OrderGroup> _groupOrders(List<OrderModel> orders) {
    final groups = <String, OrderGroup>{};
    for (var o in orders) {
      // Group by cart_group_id so multi-shop orders for a single cart become a "collected order"
      final gid = o.cartGroupId ?? o.id;
      if (!groups.containsKey(gid)) {
        groups[gid] = OrderGroup(gid, []);
      }
      groups[gid]!.orders.add(o);
    }
    return groups.values.toList();
  }

  Future<void> _loadOrders() async {
    // C2: Debounce guard — prevent concurrent load calls
    if (_isOrdersLoadInProgress) return;
    _isOrdersLoadInProgress = true;
    setState(() => _isLoading = true);
    final auth = context.read<AuthProvider>();
    try {
      // C3: Location is handled by _startLocationBroadcast timer (every 15s).
      // Only fetch location if we don't have it yet (first load).
      if (_riderLat == null || _riderLng == null) {
        final hasLocation = await _fetchRiderLocation();
        setState(() => _locationUnavailable = !hasLocation);
      }

      if (auth.currentUserId != null) {
        final partnerResp = await _supabase
            .from('delivery_partners')
            .select('is_active, preferred_nav_app, vehicle_type')
            .eq('id', auth.currentUserId!)
            .maybeSingle();
        if (partnerResp != null) {
          if (partnerResp['is_active'] != null) _isOnline = partnerResp['is_active'] as bool;
          if (partnerResp['preferred_nav_app'] != null) _navApp = partnerResp['preferred_nav_app'] as String;
          if (partnerResp['vehicle_type'] != null) _vehicleType = partnerResp['vehicle_type'] as String;
        }
      }

      // B5: Only unassigned awaiting_acceptance/pending orders — 'confirmed' means already assigned.
      final available = await _supabase
          .from('orders')
          .select('*, order_items(*), shops!shop_id(id, name, location)')
          .isFilter('delivery_partner_id', null)   // no rider assigned yet
          .inFilter('status', ['awaiting_acceptance', 'pending']);

      final myOrders = await _supabase
          .from('orders')
          .select('*, order_items(*)')
          .eq('delivery_partner_id', auth.currentUserId ?? '')
          .neq('status', 'delivered')
          .neq('status', 'cancelled')
          .neq('status', 'seller_rejected')
          .neq('status', 'partner_rejected');
          // awaiting_acceptance is INCLUDED: rider accepted first, waiting for seller

      // Populate _shopInfoCache from the joined shop data
      _shopInfoCache.clear();
      for (final o in (available as List)) {
        final shopMap = o['shops'] as Map<String, dynamic>?;
        if (shopMap != null) {
          try {
            final sm = ShopModel.fromMap(shopMap);
            if (sm.location.latitude != 0.0 || sm.location.longitude != 0.0) {
              _shopInfoCache[sm.id] = (
                lat: sm.location.latitude,
                lng: sm.location.longitude,
                name: sm.name,
              );
            }
          } catch (_) {}
        }
      }

      final allAvailable = (available).map((o) {
        final model = OrderModel.fromMap(o);
        model.items = (o['order_items'] as List? ?? [])
            .map((i) => OrderItem.fromMap(i))
            .toList();
        return model;
      }).toList();

      // B1: Geographic distance filter — only show orders where the shop is within
      // maxDeliveryRadiusKm of the rider's current location.
      const maxRadiusKm = 15.0; // matches platform_config default
      List<OrderModel> filtered;
      if (_riderLat != null && _riderLng != null) {
        filtered = allAvailable.where((order) {
          if (order.shopId == null) return true; // include if no shop data
          final shopInfo = _shopInfoCache[order.shopId];
          if (shopInfo == null) return true; // include if shop location unknown
          // C4 FIX: Equirectangular approximation — accurate for <50km, accounts for
          // latitude-based longitude compression (the missing cos term in old formula).
          const double degToRad = 3.14159265358979 / 180.0;
          final dLat = (shopInfo.lat - _riderLat!) * degToRad;
          final dLng = (shopInfo.lng - _riderLng!) * degToRad;
          final midLatRad = ((_riderLat! + shopInfo.lat) / 2.0) * degToRad;
          final x = dLng * math.cos(midLatRad);
          final distKm = 6371.0 * math.sqrt(dLat * dLat + x * x);
          return distKm <= maxRadiusKm;
        }).toList();
      } else {
        // No location yet — show all orders so rider isn't left with empty screen
        filtered = allAvailable;
      }

      if (filtered.isEmpty) {
        try {
          await _supabase.from('app_logs').insert({'message': 'Rider load: allAvailable is empty. Query returned ${available.length} rows.'});
        } catch (_) {}
      }

      double tempTodayEarnings = 0.0;
      double tempTotalKmsDriven = 0.0;
      final today = DateTime.now();
      
      // Fetch delivered orders separately to compute earnings (they are excluded from myOrders)
      if (auth.currentUserId != null) {
        try {
          final deliveredResp = await _supabase
              .from('orders')
              .select('id, cart_group_id, rider_earnings, wait_time_penalty, estimated_distance_km, created_at')
              .eq('delivery_partner_id', auth.currentUserId!)
              .eq('status', 'delivered');
              
          final Map<String, double> groupMaxDistances = {};
          
          for (var row in deliveredResp as List) {
            final groupId = row['cart_group_id'] as String? ?? row['id'].toString();
            final dist = (row['estimated_distance_km'] ?? 0.0).toDouble();
            
            if (!groupMaxDistances.containsKey(groupId) || dist > groupMaxDistances[groupId]!) {
              groupMaxDistances[groupId] = dist;
            }

            final created = DateTime.tryParse(row['created_at'] ?? '')?.toIST();
            if (created != null &&
                created.year == today.year &&
                created.month == today.month &&
                created.day == today.day) {
              tempTodayEarnings += (row['rider_earnings'] ?? 0.0).toDouble() + (row['wait_time_penalty'] ?? 0.0).toDouble();
            }
          }
          
          tempTotalKmsDriven = groupMaxDistances.values.fold(0.0, (sum, dist) => sum + dist);
        } catch (_) {}
      }

      setState(() {
        _availableGroups = _groupOrders(filtered);
        
        final myRawOrders = (myOrders as List).map((o) {
          final model = OrderModel.fromMap(o);
          model.items = (o['order_items'] as List? ?? []).map((i) => OrderItem.fromMap(i)).toList();
          return model;
        }).toList();
        _myGroups = _groupOrders(myRawOrders);

        _todayEarnings = tempTodayEarnings;
        _totalKmsDriven = tempTotalKmsDriven;
        
        _isLoading = false;
      });

      // Auto-start broadcast if rider is online
      if (_isOnline && _locationBroadcastTimer == null) {
        _startLocationBroadcast();
      }
    } catch (e, stacktrace) {
      debugPrint('Error loading rider orders: $e');
      try {
        await _supabase.from('app_logs').insert({'message': 'Rider order load error: $e\n$stacktrace'});
      } catch (_) {}
      if (mounted) {
        setState(() => _isLoading = false);
      }
    } finally {
      // C2: Always release the debounce guard
      _isOrdersLoadInProgress = false;
    }
  }

  Future<void> _acceptOrderGroup(OrderGroup group) async {
    setState(() => _isLoading = true);
    // A2: Track failures and surface them to the rider
    int failedCount = 0;
    for (int i = 0; i < group.orders.length; i++) {
      final success = await _acceptOrder(group.orders[i], skipReload: true, notifyCustomer: i == 0);
      if (!success) failedCount++;
    }
    if (failedCount > 0 && mounted) {
      _showSnack(
        failedCount == group.orders.length
            ? '⚠️ All orders in this group were already taken.'
            : '⚠️ $failedCount order(s) in this group could not be accepted.',
        isError: true,
      );
    }
    _loadOrders();
  }

  Future<bool> _acceptOrder(OrderModel order, {bool skipReload = false, bool notifyCustomer = true}) async {
    final auth = context.read<AuthProvider>();
    try {
      double? shopLat;
      double? shopLng;
      if (order.shopId != null) {
        try {
          final shopResp = await _supabase
              .from('shops')
              .select('location')
              .eq('id', order.shopId!)
              .maybeSingle();
          if (shopResp != null && shopResp['location'] != null) {
            final sm = ShopModel.fromMap(shopResp);
            shopLat = sm.location.latitude;
            shopLng = sm.location.longitude;
          }
        } catch (_) {}
      }

      // Fetch latest state to prevent race conditions (TOCTOU)
      final latest = await _supabase.from('orders').select('seller_accepted').eq('id', order.id).maybeSingle();
      final bothAccepted = latest?['seller_accepted'] == true;

      final newStatus = bothAccepted ? 'awaiting_payment' : 'awaiting_acceptance';
      final paymentDeadline = bothAccepted
          ? DateTime.now().toUtc().add(const Duration(minutes: 10)).toIso8601String()
          : null;

      final updateResult = await _supabase.from('orders').update({
        'delivery_partner_id': auth.currentUserId,
        'partner_accepted': true,
        'status': newStatus,
        if (paymentDeadline != null) 'payment_deadline': paymentDeadline,
        if (shopLat != null && shopLat != 0.0) 'shop_lat': shopLat,
        if (shopLng != null && shopLng != 0.0) 'shop_lng': shopLng,
        'rider_phone': auth.user?.phone ?? '',
      }).eq('id', order.id).isFilter('delivery_partner_id', null).select();

      if ((updateResult as List).isEmpty) {
        if (mounted) {
          _showSnack('⚠️ This order was already assigned to another rider.', isError: true);
        }
        return false;
      }

      if (mounted) {
        final notifProv = context.read<NotificationProvider>();

        if (bothAccepted) {
          _showSnack('✅ Order accepted! Waiting for customer to pay.');
          // Push customer to complete payment NOW
          if (notifyCustomer) {
            notifProv.sendBackgroundPush(
              targetUserId: order.customerId,
              title: '✅ Shop & Rider Ready! Pay Now 💳',
              body:
                  'Both the shop and rider accepted your order. Open the app and complete payment within 10 minutes.',
              data: {'order_id': order.id, 'action': 'pay'},
            );
          }
          // Notify seller: waiting for customer payment
          if (order.shopId != null) {
            _supabase
                .from('shops')
                .select('seller_id')
                .eq('id', order.shopId!)
                .maybeSingle()
                .then((shopData) {
              if (shopData != null && shopData['seller_id'] != null) {
                notifProv.sendBackgroundPush(
                  targetUserId: shopData['seller_id'],
                  title: '⌛ Waiting for Customer Payment',
                  body:
                      'Both you and the rider accepted. Customer is completing payment now.',
                );
              }
            });
          }
        } else {
          // Rider accepted FIRST — seller has not yet accepted
          _showSnack('✅ Accepted! Waiting for the shop to also accept.');

          // Push seller: a rider is already waiting — accept quickly!
          if (order.shopId != null) {
            _supabase
                .from('shops')
                .select('seller_id')
                .eq('id', order.shopId!)
                .maybeSingle()
                .then((shopData) {
              if (shopData != null && shopData['seller_id'] != null) {
                notifProv.sendBackgroundPush(
                  targetUserId: shopData['seller_id'] as String,
                  title: '🛵 A Rider is Ready!',
                  body: 'A rider already accepted this order ₹${order.grandTotal.toStringAsFixed(0)}. Accept now to confirm!',
                  data: {'order_id': order.id},
                );
              }
            });
          }

          // Push customer: rider is on standby, waiting for shop
          if (notifyCustomer) {
            notifProv.sendBackgroundPush(
              targetUserId: order.customerId,
              title: '🛵 Rider is Ready!',
              body: 'A rider accepted your order and is on standby. Waiting for the shop to also confirm.',
            );
          }
        }
      }
      if (!skipReload) _loadOrders();
      return true;
    } on PostgrestException catch (pe) {
      debugPrint('Accept Postgrest error: $pe');
      if (mounted) {
        _showSnack(pe.message, isError: true);
      }
      return false;
    } catch (e) {
      debugPrint('Accept error: $e');
      return false;
    }
  }

  Future<void> _updateStatus(OrderModel order, String status, {bool skipReload = false, bool skipRating = false}) async {
    try {
      if (status == 'arrived') {
        if (order.shopLat == null || order.shopLng == null || order.shopLat == 0.0 || order.shopLng == 0.0) {
          _showSnack('⚠️ Shop location missing. Cannot verify arrival.', isError: true);
          return;
        }
        await _fetchRiderLocation();
        if (_riderLat == null || _riderLng == null) {
          _showSnack('⚠️ Cannot fetch your GPS. Ensure location is enabled.', isError: true);
          return;
        }
        final dist = Geolocator.distanceBetween(_riderLat!, _riderLng!, order.shopLat!, order.shopLng!);
        if (dist > 300) {
          _showSnack('⚠️ Too far from shop! You are ${(dist).toInt()}m away (max 300m).', isError: true);
          return;
        }
        await _supabase.from('orders').update({
          'arrived_at_shop_time': DateTime.now().toIso8601String(),
        }).eq('id', order.id);
      } else if (status == 'reassign' || status == 'reassign_disputed') {
        double penalty = 0.0;
        if (order.arrivedAtShopTime != null) {
          final waitMinutes =
              DateTime.now().difference(order.arrivedAtShopTime!).inMinutes;
          final paidMinutes = math.max(0, math.min(10, waitMinutes - 10));
          penalty = paidMinutes * 1.5;
        }
        await _supabase.from('orders').update({
          'delivery_partner_id': null,
          'partner_accepted': false,
          'status': 'pending',
          'wait_time_penalty': penalty,
          'wait_time_disputed': status == 'reassign_disputed',
        }).eq('id', order.id);

        // Notify customer and seller that the rider dropped the order
        if (mounted) {
          final notifProv = context.read<NotificationProvider>();

          // Push customer
          notifProv.sendBackgroundPush(
            targetUserId: order.customerId,
            title: '🛵 Rider Dropped Your Order',
            body: 'Your previous rider is unavailable. We are looking for a new rider now.',
            data: {'order_id': order.id, 'role': 'customer'},
          );

          // Push seller
          if (order.shopId != null) {
            _supabase
                .from('shops')
                .select('seller_id')
                .eq('id', order.shopId!)
                .maybeSingle()
                .then((shopData) {
              if (shopData != null && shopData['seller_id'] != null) {
                notifProv.sendBackgroundPush(
                  targetUserId: shopData['seller_id'] as String,
                  title: '🛵 Rider Dropped the Order',
                  body: status == 'reassign_disputed'
                      ? 'Rider reported a dispute and dropped the order. Looking for a new rider.'
                      : 'The rider dropped the order. Looking for a new rider.',
                  data: {'order_id': order.id, 'role': 'seller'},
                );
              }
            });
          }
        }
      } else if (status == 'shop_dispute_cancel') {
        // Rider reported shop lied / items not given. Cancel order, do NOT reassign.
        await _supabase.from('orders').update({
          'status': 'cancelled',
          'cancelled_reason': 'shop_dispute',
          'wait_time_disputed': true,
        }).eq('id', order.id);

        if (mounted) {
          final notifProv = context.read<NotificationProvider>();

          // Notify customer with apology and refund info
          notifProv.sendBackgroundPush(
            targetUserId: order.customerId,
            title: '😔 We\'re Sorry — Order Cancelled',
            body: 'There was an issue at the shop. Your order has been cancelled. '
                'If you were charged, a full refund will be initiated within 5–7 business days. '
                'We sincerely apologise for this rare inconvenience.',
            data: {'order_id': order.id, 'role': 'customer'},
          );

          // Notify seller: dispute has been filed
          if (order.shopId != null) {
            _supabase
                .from('shops')
                .select('seller_id')
                .eq('id', order.shopId!)
                .maybeSingle()
                .then((shopData) {
              if (shopData != null && shopData['seller_id'] != null) {
                notifProv.sendBackgroundPush(
                  targetUserId: shopData['seller_id'] as String,
                  title: '⚠️ Order Cancelled — Dispute Filed',
                  body: 'The delivery rider reported that items were not given or the shop was not '
                      'ready as stated. This order has been cancelled. Our team will review this report.',
                  data: {'order_id': order.id, 'role': 'seller'},
                );
              }
            });
          }
        }
        _loadOrders();
        return;
      } else if (status == 'delivered') {

        await _supabase.from('orders').update({
          'status': status,
        }).eq('id', order.id);
        
        if (mounted) {
          context.read<NotificationProvider>().sendBackgroundPush(
            targetUserId: order.customerId,
            title: '🎉 Order Delivered!',
            body: 'Your order has been delivered. Enjoy!',
            data: {'order_id': order.id, 'role': 'customer'},
          );
        }

        _stopLocationBroadcast();
        RiderBackgroundService.instance.stopService(); // Also kill background GPS
        if (!skipReload) _loadOrders();
        // Show rating prompt after delivering
        if (mounted && !order.hasDeliveryRated && !skipRating) {
          Future.delayed(const Duration(milliseconds: 500),
              () => _showDeliveryRatingFlow(order));
        }
        return;
      } else {
        final updateData = <String, dynamic>{'status': status};
        if (status == 'picked_up' && order.orderReadyTime == null) {
          final readyTime = DateTime.now();
          updateData['order_ready_time'] = readyTime.toIso8601String();
          if (order.arrivedAtShopTime != null) {
            final waitMins = readyTime.difference(order.arrivedAtShopTime!).inMinutes;
            final prepLimit = order.shopPrepTimeSnapshot;
            if (waitMins > prepLimit) {
              updateData['wait_time_penalty'] = (waitMins - prepLimit) * 2.0;
            }
          }
        }
        await _supabase
            .from('orders')
            .update(updateData).eq('id', order.id);
            
        if (mounted) {
          final notifProv = context.read<NotificationProvider>();
          if (status == 'picked_up') {
            notifProv.sendBackgroundPush(
              targetUserId: order.customerId,
              title: '🛵 Rider Picked Up',
              body: 'Your order is on its way!',
              data: {'order_id': order.id, 'role': 'customer'},
            );
          } else if (status == 'out_for_delivery') {
            notifProv.sendBackgroundPush(
              targetUserId: order.customerId,
              title: '🚀 Out for Delivery!',
              body: 'Your order is almost there. Get ready!',
              data: {'order_id': order.id, 'role': 'customer'},
            );
          }
        }
      }
      // Start broadcasting location when rider is out for delivery
      if (status == 'out_for_delivery') {
        _startLocationBroadcast();
      }
      if (!skipReload) _loadOrders();
    } catch (e) {
      debugPrint('Status update error: $e');
    }
  }

  void _showDeliveryRatingFlow(OrderModel order) {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => RatingBottomSheet(
        title: 'Rate the Customer 👤',
        subtitle: 'How was the pickup/drop experience?',
        onSubmit: (rating, review) async {
          await _submitDeliveryRating(
            orderId: order.id,
            rateeId: order.customerId,
            rateeRole: 'customer',
            rating: rating,
            review: review,
          );
          // Then rate the shop
          if (mounted) {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.white,
              shape: const RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(28))),
              builder: (_) => RatingBottomSheet(
                title: 'Rate the Shop 🏪',
                subtitle: 'How was your wait time and experience at the shop?',
                onSubmit: (r, rv) => _submitDeliveryRating(
                  orderId: order.id,
                  rateeId: null,
                  shopId: order.shopId, // link to the actual shop
                  rateeRole: 'seller',
                  rating: r,
                  review: rv,
                  markRated: true,
                ),
              ),
            );
          }
        },
      ),
    );
  }

  void _showGroupDeliveryRatingFlow(OrderGroup group) {
    if (!mounted || group.orders.isEmpty) return;
    
    int currentShopIndex = 0;
    
    void rateNextShop() {
      if (currentShopIndex < group.orders.length) {
        final orderToRate = group.orders[currentShopIndex];
        currentShopIndex++;
        
        if (mounted) {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.white,
            shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
            builder: (_) => RatingBottomSheet(
              title: group.orders.length > 1 ? 'Rate Shop $currentShopIndex 🏪' : 'Rate the Shop 🏪',
              subtitle: 'How was your wait time and experience at the shop?',
              onSubmit: (r, rv) async {
                await _submitDeliveryRating(
                  orderId: orderToRate.id,
                  rateeId: null,
                  shopId: orderToRate.shopId,
                  rateeRole: 'seller',
                  rating: r,
                  review: rv,
                  markRated: true,
                );
                rateNextShop();
              },
            ),
          );
        }
      }
    }

    // First rate customer
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => RatingBottomSheet(
        title: 'Rate the Customer 👤',
        subtitle: 'How was the pickup/drop experience?',
        onSubmit: (rating, review) async {
          await _submitDeliveryRating(
            orderId: group.orders.first.id,
            rateeId: group.orders.first.customerId,
            rateeRole: 'customer',
            rating: rating,
            review: review,
          );
          rateNextShop();
        },
      ),
    );
  }

  Future<void> _submitDeliveryRating({
    required String orderId,
    required String? rateeId,
    String? shopId,
    required String rateeRole,
    required int rating,
    required String review,
    bool markRated = false,
  }) async {
    try {
      final auth = context.read<AuthProvider>();
      await _supabase.from('ratings').insert({
        'order_id': orderId,
        'rater_id': auth.currentUserId,
        'ratee_id': rateeId,
        'shop_id': shopId,
        'rater_role': 'delivery',
        'ratee_role': rateeRole,
        'rating': rating,
        'review': review.isEmpty ? null : review,
      });
      if (markRated) {
        await _supabase
            .from('orders')
            .update({'has_delivery_rated': true}).eq('id', orderId);
      }
    } catch (e) {
      debugPrint('Delivery rating error: $e');
    }
  }

  void _showDisputeDialog(OrderModel order) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Report Shop Issue',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text(
            'If the shop is not giving you the items, lied about readiness, or is being dishonest, '
            'you can cancel this order. The customer will be notified and a refund will be initiated within 5–7 business days.',
            style: GoogleFonts.outfit()),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Go Back')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _updateStatus(order, 'shop_dispute_cancel');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Cancel & Report Shop'),
          ),
        ],
      ),
    );
  }


  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.outfit()),
      backgroundColor: isError ? AppColors.danger : AppColors.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ── Route Map Launcher ─────────────────────────────────────────────────────

  void _openRouteMapForGroup(OrderGroup group, {bool isViewOnly = false}) {
    // Resolve shop coords: prefer joined cache, fall back to snapshot on order
    final shops = group.orders.map((order) {
      final shopInfo = _shopInfoCache[order.shopId];
      final sLat = shopInfo?.lat ?? order.shopLat;
      final sLng = shopInfo?.lng ?? order.shopLng;
      final sName = shopInfo?.name ?? 'Shop';
      return (lat: sLat ?? 0.0, lng: sLng ?? 0.0, name: sName);
    }).toList();

    if (shops.any((s) => s.lat == 0.0 || s.lng == 0.0)) {
      _showSnack('Map not available — shop location missing for one or more shops', isError: true);
      return;
    }
    final primaryOrder = group.orders.first;
    if (primaryOrder.deliveryLat == null || primaryOrder.deliveryLng == null) {
      _showSnack('Map not available — customer location missing', isError: true);
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrderRouteMapPage(
          group: group,
          riderLat: _riderLat,
          riderLng: _riderLng,
          shops: shops,
          isViewOnly: isViewOnly,
          onAccept: () {
            Navigator.pop(context);
            _acceptOrderGroup(group);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = themeProvider.isDarkMode;
    final size = MediaQuery.of(context).size;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final now = DateTime.now();
        if (_lastBackPressTime == null || now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
          _lastBackPressTime = now;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Press back again to exit'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          // ignore: use_build_context_synchronously
          SystemNavigator.pop();
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF080812) : const Color(0xFFF0F4FF),
        body: CustomScrollView(
          slivers: [
            // ── Animated Header ───────────────────────────────────────────
            SliverAppBar(
              expandedHeight: 240,
              pinned: true,
              elevation: 0,
              backgroundColor: const Color(0xFF0D2137),
              surfaceTintColor: Colors.transparent,
              leading: const SizedBox.shrink(),
              flexibleSpace: FlexibleSpaceBar(
                background: AnimatedBuilder(
                  animation: _bgCtrl,
                  builder: (_, __) => Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color.lerp(const Color(0xFF0D2137),
                              const Color(0xFF0A3260), _bgAnim.value)!,
                          Color.lerp(const Color(0xFF061222),
                              const Color(0xFF061A36), _bgAnim.value)!,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Stack(
                      children: [
                        // Blobs
                        Positioned(
                            top: -50,
                            right: -50,
                            child: _blob(220, const Color(0xFF00B4D8),
                                0.12 + _bgAnim.value * 0.06)),
                        Positioned(
                            bottom: -40,
                            left: -40,
                            child: _blob(180, const Color(0xFF51CF66), 0.10)),
                        // Stars
                        CustomPaint(
                            size: Size(size.width, 240),
                            painter: _MiniStarPainter(_bgCtrl.value)),
                        // Content
                        SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Top bar
                                Row(children: [
                                  _glassAvatar(auth.user?.initials ?? 'D',
                                      const Color(0xFF00B4D8)),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                              'Hi, ${auth.user?.fullName.split(' ').first ?? 'Partner'}!',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.outfit(
                                                  color: Colors.white,
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.w800)),
                                          const SizedBox(height: 4),
                                          _badge('🛵  Delivery Partner',
                                              const Color(0xFF00B4D8)),
                                        ]),
                                  ),
                                  _iconBtn(
                                      isDark
                                          ? Icons.light_mode_outlined
                                          : Icons.dark_mode_outlined,
                                      () => themeProvider.toggleTheme()),
                                  const NotificationBell(
                                    iconColor: Colors.white70,
                                    containerColor: Colors.transparent,
                                    badgeColor: Color(0xFFFF6B6B),
                                  ),

                                  _iconBtn(
                                      Icons.settings_outlined,
                                      () => Navigator.pushNamed(
                                          context, AppRoutes.settings)),
                                ]),
                                const SizedBox(height: 24),

                                // Stats row
                                Row(children: [
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () => Navigator.pushNamed(
                                          context, AppRoutes.earnings),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 12),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(
                                              color: Colors.white.withValues(alpha: 0.2)),
                                        ),
                                        child: Row(children: [
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: AppColors.success.withValues(alpha: 0.2),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                                Icons.account_balance_wallet_rounded,
                                                color: AppColors.success,
                                                size: 20),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Text('Today\'s Earnings',
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: GoogleFonts.outfit(
                                                        color: Colors.white70,
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.w600)),
                                                Text('₹${_todayEarnings.toStringAsFixed(0)}',
                                                    style: GoogleFonts.outfit(
                                                        color: Colors.white,
                                                        fontSize: 18,
                                                        fontWeight: FontWeight.bold)),
                                              ],
                                            ),
                                          ),
                                        ]),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () => Navigator.pushNamed(
                                          context, AppRoutes.earnings),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 12),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(
                                              color: Colors.white.withValues(alpha: 0.2)),
                                        ),
                                      child: Row(children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF00B4D8).withValues(alpha: 0.2),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                              Icons.local_shipping_rounded,
                                              color: Color(0xFF00B4D8),
                                              size: 20),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text('Total KMs Driven',
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: GoogleFonts.outfit(
                                                      color: Colors.white70,
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w600)),
                                              Text('${_totalKmsDriven.toStringAsFixed(1)} km',
                                                  style: GoogleFonts.outfit(
                                                      color: Colors.white,
                                                      fontSize: 18,
                                                      fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                        ),
                                      ]),
                                    ),
                                  ),
                                  ),
                                ]),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── Content ────────────────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // Full-width Online Toggle Card
                  GestureDetector(
                    onTap: () async {
                      final newVal = !_isOnline;
                      setState(() => _isOnline = newVal);
                      if (newVal) {
                        _startLocationBroadcast();
                        // Background service will be started by didChangeAppLifecycleState
                        // when/if the app is backgrounded. No action needed here.
                      } else {
                        _stopLocationBroadcast();
                        // Also stop the background service if it happened to be running
                        RiderBackgroundService.instance.stopService();
                      }
                      final auth = context.read<AuthProvider>();
                      if (auth.currentUserId != null) {
                        try {
                          await _supabase
                              .from('delivery_partners')
                              .update({'is_active': newVal})
                              .eq('id', auth.currentUserId!);
                        } catch (e) {
                          debugPrint('Error updating duty status: $e');
                        }
                      }
                      if (newVal) _loadOrders();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _isOnline 
                              ? [const Color(0xFF2ECC71), const Color(0xFF27AE60)]
                              : isDark 
                                  ? [const Color(0xFF2A2A3A), const Color(0xFF1E1E2E)]
                                  : [Colors.grey.shade300, Colors.grey.shade200],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          if (_isOnline)
                            BoxShadow(
                              color: const Color(0xFF2ECC71).withValues(alpha: 0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _isOnline ? Icons.power_rounded : Icons.power_off_rounded,
                              color: _isOnline ? Colors.white : (isDark ? Colors.white54 : Colors.black54),
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _isOnline ? 'You\'re Online' : 'You\'re Offline',
                                  style: GoogleFonts.outfit(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: _isOnline ? Colors.white : (isDark ? Colors.white : Colors.black87),
                                  ),
                                ),
                                Text(
                                  _isOnline ? 'Receiving delivery requests' : 'Tap to start receiving orders',
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    color: _isOnline ? Colors.white.withValues(alpha: 0.8) : (isDark ? Colors.white54 : Colors.black54),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _isOnline,
                            onChanged: (val) async {
                              setState(() => _isOnline = val);
                              if (val) {
                                _startLocationBroadcast();
                              } else {
                                _stopLocationBroadcast();
                              }
                              final auth = context.read<AuthProvider>();
                              if (auth.currentUserId != null) {
                                try {
                                  await _supabase
                                      .from('delivery_partners')
                                      .update({'is_active': val})
                                      .eq('id', auth.currentUserId!);
                                } catch (e) {
                                  debugPrint('Error updating duty status: $e');
                                }
                              }
                              if (val) _loadOrders();
                            },
                            activeThumbColor: Colors.white,
                            activeTrackColor: Colors.white.withValues(alpha: 0.3),
                            inactiveThumbColor: isDark ? Colors.white54 : Colors.grey.shade400,
                            inactiveTrackColor: isDark ? Colors.white10 : Colors.grey.shade300,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Work management secondary row
                  Row(
                    children: [
                      Expanded(
                        child: _actionTile(
                          icon: Icons.two_wheeler_rounded,
                          gradient: const [Color(0xFF00B4D8), Color(0xFF0077A8)],
                          title: 'Vehicle',
                          subtitle: _vehicleTypeLabel(_vehicleType),
                          badge: null,
                          isDark: isDark,
                          onTap: _showVehicleChangeSheet,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _actionTile(
                          icon: Icons.settings_rounded,
                          gradient: const [Color(0xFF4C6EF5), Color(0xFF364FC7)],
                          title: 'Settings',
                          subtitle: 'Nav & Prefs',
                          badge: null,
                          isDark: isDark,
                          onTap: _showWorkManagementSheet,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Active deliveries
                  if (_myGroups.isNotEmpty) ...[
                    _sectionHeader('🚗 My Active Deliveries',
                        '${_myGroups.length}', const Color(0xFF4C6EF5), isDark),
                    const SizedBox(height: 14),
                    ..._myGroups.map((g) => _activeOrderGroupCard(g, isDark)),
                    const SizedBox(height: 24),
                  ],

                  // Available orders
                  _sectionHeader(
                      '📦 Available Orders',
                      '${_availableGroups.length}',
                      const Color(0xFFFF8C42),
                      isDark),
                  const SizedBox(height: 14),


                  // Location unavailable warning (kept):
                  if (_locationUnavailable && _isOnline)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.location_off_outlined,
                            color: Colors.orange, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Location unavailable — showing all nearby orders. Enable GPS for distance-based filtering.',
                            style: GoogleFonts.outfit(
                                color: Colors.orange, fontSize: 12),
                          ),
                        ),
                      ]),
                    ),

                  if (_isLoading)
                    const Center(
                        child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(),
                    ))
                  else if (!_isOnline)
                    _offlineState(isDark)
                  else if (_availableGroups.isEmpty)
                    _emptyState(isDark)
                  else
                    ..._availableGroups
                        .map((g) => _availableOrderGroupCard(g, isDark)),
                ]),
              ),
            ),
          ],
        ),
      ),
    ));
  }

  // ── Card Builders ─────────────────────────────────────────────────────────

  /// Renders the customer delivery address with an optional label badge.
  ///
  /// [address] is the full string from [OrderGroup.customerAddress], which
  /// already prepends "🏠 Home · " when the order has an [addressLabel].
  /// The method splits on the first " · " to separate the badge from the text.
  Widget _buildAddressDisplay({
    required String address,
    required bool isDark,
    bool lightTheme = false,
  }) {
    // Try to split "🏠 Home · A-404, Bandipora…" into badge + body
    final sepIdx = address.indexOf(' · ');
    final hasLabel = sepIdx != -1;
    final badge = hasLabel ? address.substring(0, sepIdx) : null;
    final body = hasLabel ? address.substring(sepIdx + 3) : address;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (badge != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: lightTheme
                  ? Colors.white.withValues(alpha: 0.20)
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.10)
                      : const Color(0xFFEEF2FF)),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              badge,
              style: GoogleFonts.outfit(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: lightTheme
                    ? Colors.white
                    : (isDark ? Colors.white70 : const Color(0xFF4C6EF5)),
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
        Text(
          body,
          style: GoogleFonts.outfit(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: lightTheme
                ? Colors.white.withValues(alpha: 0.85)
                : (isDark ? Colors.white60 : Colors.grey.shade600),
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  // ── Distance helpers ────────────────────────────────────────────────────────

  /// Straight-line km from rider to shop (used on the card chip).
  // ignore: unused_element
  double? _pickupDistKm(OrderModel order) {
    if (_riderLat == null || _riderLng == null) return null;
    final shopInfo = _shopInfoCache[order.shopId];
    final sLat = shopInfo?.lat ?? order.shopLat;
    final sLng = shopInfo?.lng ?? order.shopLng;
    if (sLat == null || sLng == null) return null;
    return Geolocator.distanceBetween(_riderLat!, _riderLng!, sLat, sLng) / 1000;
  }

  /// Straight-line km from shop to customer (used on the card chip).
  // ignore: unused_element
  double? _deliveryDistKm(OrderModel order) {
    final shopInfo = _shopInfoCache[order.shopId];
    final sLat = shopInfo?.lat ?? order.shopLat;
    final sLng = shopInfo?.lng ?? order.shopLng;
    if (sLat == null || sLng == null) return null;
    if (order.deliveryLat == null || order.deliveryLng == null) return null;
    return Geolocator.distanceBetween(sLat, sLng, order.deliveryLat!, order.deliveryLng!) / 1000;
  }

  // ignore: unused_element
  Widget _distanceChip({
    required Color color,
    required IconData icon,
    required String label,
    required double? km,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: 13),
        ),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: GoogleFonts.outfit(
                    fontSize: 10,
                    color: color,
                    fontWeight: FontWeight.w600)),
            Text(
              km != null ? '${km.toStringAsFixed(1)} km' : '— km',
              style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: km != null ? color : Colors.grey),
            ),
          ],
        ),
      ]),
    );
  }

  Widget _availableOrderGroupCard(OrderGroup group, bool isDark) {
    final totalEarnings = group.orders.fold(0.0, (sum, o) => sum + o.riderEarnings);
    bool isExpanded = !_collapsedAvailableGroups.contains(group.groupId);

    return StatefulBuilder(
      builder: (context, setStateBuilder) {
        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF121222) : Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 6))
            ],
            border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.transparent),
          ),
          child: Column(children: [
            GestureDetector(
              onTap: () {
                setStateBuilder(() => isExpanded = !isExpanded);
                if (isExpanded) {
                  _collapsedAvailableGroups.remove(group.groupId);
                } else {
                  _collapsedAvailableGroups.add(group.groupId);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0xFF0D2137), Color(0xFF1A3A5C)]),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                ),
                child: Row(children: [
                  const Icon(Icons.storefront_outlined, color: Colors.white70, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Collected Order (${group.orders.length} Shops)',
                        style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                        color: const Color(0xFF2ECC71),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF2ECC71).withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.currency_rupee_rounded, color: Colors.white, size: 14),
                        Text(totalEarnings.toStringAsFixed(0),
                            style: GoogleFonts.outfit(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: Colors.white70),
                ]),
              ),
            ),
            if (isExpanded)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.location_on_outlined, size: 16, color: AppColors.danger),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _buildAddressDisplay(
                            address: group.customerAddress,
                            isDark: isDark,
                          ),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      Text('Contains items from ${group.orders.length} shops', 
                        style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.amber)),
                      const SizedBox(height: 6),
                      ...group.orders.map((o) {
                        final shopName = _shopInfoCache[o.shopId]?.name ?? 'Shop';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              const Icon(Icons.circle, size: 6, color: Colors.amber),
                              const SizedBox(width: 8),
                              Expanded(child: Text(shopName, style: GoogleFonts.outfit(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87))),
                            ],
                          ),
                        );
                      }),
                      if (group.orders.isNotEmpty && group.orders.first.acceptanceDeadline != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.red.withValues(alpha: 0.18)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Acceptance Time Left',
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.red,
                                ),
                              ),
                              OrderCountdownTimer(
                                acceptanceDeadline: group.orders.first.acceptanceDeadline!,
                                fontSize: 13,
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Row(children: [
                        OutlinedButton.icon(
                          onPressed: () => _openRouteMapForGroup(group),
                          icon: const Icon(Icons.map_rounded, size: 18),
                          label: Text('See Route', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF4C6EF5),
                            side: const BorderSide(color: Color(0xFF4C6EF5), width: 1.2),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => _acceptOrderGroup(group),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.success,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 4,
                              shadowColor: AppColors.success.withValues(alpha: 0.4),
                            ),
                            child: Text('Accept Group', style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 14)),
                          ),
                        ),
                      ]),
                    ]),
              ),
          ]),
        );
      }
    );
  }

  Widget _activeOrderGroupCard(OrderGroup group, bool isDark) {
    final statusGradient = group.groupStatus == 'out_for_delivery'
        ? [const Color(0xFF4C6EF5), const Color(0xFF364FC7)]
        : group.groupStatus == 'picked_up'
            ? [const Color(0xFF51CF66), const Color(0xFF2F9E44)]
            : [const Color(0xFFFF8C42), const Color(0xFFE8590C)];

    bool isExpanded = !_collapsedActiveGroups.contains(group.groupId);

    return StatefulBuilder(
      builder: (context, setStateBuilder) {
        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF121222) : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: statusGradient.first.withValues(alpha: 0.3), width: 1.5),
            boxShadow: [BoxShadow(color: statusGradient.first.withValues(alpha: 0.15), blurRadius: 16, offset: const Offset(0, 6))],
          ),
          child: Column(children: [
            // Header
            GestureDetector(
              onTap: () {
                setStateBuilder(() => isExpanded = !isExpanded);
                if (isExpanded) {
                  _collapsedActiveGroups.remove(group.groupId);
                } else {
                  _collapsedActiveGroups.add(group.groupId);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: statusGradient),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(children: [
                  Text('Collected Order (${group.orders.length})',
                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
                    child: Text(group.groupStatus == 'awaiting_payment' ? 'PAYMENT IN PROGRESS' : group.groupStatus.toUpperCase().replaceAll('_', ' '),
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 8),
                  Icon(isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: Colors.white70),
                ]),
              ),
            ),
            // Body
            if (isExpanded)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  // Destination
                  Row(children: [
                    const Icon(Icons.location_on_outlined, size: 16, color: AppColors.danger),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _buildAddressDisplay(
                        address: group.customerAddress,
                        isDark: isDark,
                        lightTheme: true,
                      ),
                    ),
                  ]),
                  // ── ETA chip for rider (drop-off time estimate) ──
                  if (group.orders.isNotEmpty && group.orders.first.estimatedDistanceKm > 0) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(50),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.access_time_rounded, color: Colors.white, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            'Drop in ~${DeliveryCalculator.etaLabel(group.orders.first.estimatedDistanceKm, 0)}',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '· by ${DeliveryCalculator.etaArrivalTime(group.orders.first.estimatedDistanceKm, 0)}',
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (group.customerPhone != null && group.customerPhone!.isNotEmpty) ...[
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _callPhone(group.customerPhone!),
                            icon: const Icon(Icons.phone_outlined, size: 16),
                            label: Text('Call Customer', style: GoogleFonts.outfit(fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              side: const BorderSide(color: AppColors.primary),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _openRouteMapForGroup(group, isViewOnly: true),
                          icon: const Icon(Icons.map_outlined, size: 16),
                          label: Text('See Route', style: GoogleFonts.outfit(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF4C6EF5),
                            side: const BorderSide(color: Color(0xFF4C6EF5)),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  
                  // Render individual shop pickup cards
                  ...group.orders.map((o) => _buildShopPickupTile(o, isDark)),

                  // Master Actions
                  if (group.allPickedUp && !group.allOutForDelivery)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          for (var o in group.orders) {
                            await _updateStatus(o, 'out_for_delivery');
                          }
                        },
                        icon: const Icon(Icons.rocket_launch, size: 18),
                        label: Text('Mark All Out for Delivery', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4C6EF5), foregroundColor: Colors.white),
                      ),
                    ),
                  if (group.allOutForDelivery && group.groupStatus != 'delivered')
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          for (var o in group.orders) {
                            await _updateStatus(o, 'delivered', skipReload: true, skipRating: true);
                          }
                          _loadOrders();
                          if (mounted) {
                            _showGroupDeliveryRatingFlow(group);
                          }
                        },
                        icon: const Icon(Icons.check_circle_outline, size: 18),
                        label: Text('Mark All Delivered', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white),
                      ),
                    ),
                ]),
              ),
          ]),
        );
      }
    );
  }

  Widget _buildShopPickupTile(OrderModel order, bool isDark) {
    String? nextStatus;
    String? nextLabel;

    if (order.status == 'confirmed' || order.status == 'preparing') {
      if (order.arrivedAtShopTime == null) {
        nextStatus = 'arrived';
        nextLabel = '📍 Mark Arrived';
      } else {
        nextLabel = 'Waiting for Shop to Pack...';
        nextStatus = null;
      }
    } else if (order.status == 'ready_for_pickup') {
      nextStatus = 'picked_up';
      nextLabel = '✅ Confirm Received';
    }

    final shopInfo = _shopInfoCache[order.shopId];
    final shopName = shopInfo?.name ?? 'Shop';

    Color getStatusColor() {
      switch (order.status) {
        case 'confirmed':
          return const Color(0xFF4C6EF5); // Bright Blue
        case 'preparing':
          return const Color(0xFFF5A623); // Bright Orange
        case 'ready_for_pickup':
          return const Color(0xFF51CF66); // Bright Green
        case 'picked_up':
          return const Color(0xFF845EF7); // Bright Purple
        default:
          return const Color(0xFF15AABF); // Bright Cyan
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storefront_rounded, size: 16, color: AppColors.accent),
              const SizedBox(width: 6),
              Expanded(child: Text(shopName, style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: getStatusColor().withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: getStatusColor().withValues(alpha: 0.3)),
                ),
                child: Text(
                  order.status == 'awaiting_payment' ? 'PAYMENT IN PROGRESS' : order.statusDisplay.toUpperCase(),
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: getStatusColor(),
                  ),
                ),
              ),
            ],
          ),
          if (order.shopPhone != null && order.shopPhone!.isNotEmpty) ...[
            const SizedBox(height: 6),
            InkWell(
              onTap: () => _callPhone(order.shopPhone!),
              child: Text('📞 Call Shop', style: GoogleFonts.outfit(fontSize: 12, color: AppColors.accent, decoration: TextDecoration.underline)),
            )
          ],
          if (nextLabel != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: nextStatus == null
                    ? null
                    : () {
                        if (nextStatus == 'arrived') {
                          _showSnack('📍 GPS verified: At Shop');
                          _updateStatus(order, nextStatus!);
                        } else {
                          _updateStatus(order, nextStatus!);
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  elevation: 0,
                ),
                child: Text(nextLabel, style: GoogleFonts.outfit(fontSize: 12)),
              ),
            ),
          ],
          if (order.status == 'confirmed' || order.status == 'preparing' || order.status == 'ready_for_pickup') ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => _showDisputeDialog(order),
              icon: const Icon(Icons.report_problem_outlined, color: AppColors.danger, size: 16),
              label: Text(
                  order.status == 'ready_for_pickup'
                      ? 'Shop Lied — Items Not Received'
                      : 'Shop Lied / Items Not Given',
                  style: GoogleFonts.outfit(color: AppColors.danger, fontSize: 12)),
            ),
          ],
        ],
      ),
    );
  }


  Widget _offlineState(bool isDark) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF141425) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
        ),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.power_off_rounded, size: 64, color: isDark ? Colors.white54 : Colors.grey),
          ),
          const SizedBox(height: 24),
          Text('You\'re Offline',
              style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF0A0A14))),
          const SizedBox(height: 8),
          Text('Toggle the switch above to go online and start accepting orders.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                  color: isDark ? Colors.white60 : Colors.grey.shade600,
                  fontSize: 14)),
        ]),
      );

  Widget _emptyState(bool isDark) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF141425) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
        ),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.radar_rounded, size: 64, color: AppColors.primary.withValues(alpha: 0.8)),
          ),
          const SizedBox(height: 24),
          Text('Finding Orders...',
              style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF0A0A14))),
          const SizedBox(height: 8),
          Text('Stay in a busy area to increase your chances of receiving requests.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                  color: isDark ? Colors.white60 : Colors.grey.shade600,
                  fontSize: 14)),
        ]),
      );

  Widget _sectionHeader(String title, String count, Color color, bool isDark) =>
      Row(children: [
        Text(title,
            style: GoogleFonts.outfit(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : const Color(0xFF0A0A14))),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(20)),
          child: Text(count,
              style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800)),
        ),
      ]);

  Widget _glassAvatar(String initials, Color color) => Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.6)]),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
                color: color.withValues(alpha: 0.5),
                blurRadius: 14,
                offset: const Offset(0, 4))
          ],
        ),
        child: Center(
            child: Text(initials,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900))),
      );

  Widget _badge(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.5))),
        child: Text(label,
            style: GoogleFonts.outfit(
                color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      );

  Widget _iconBtn(IconData icon, VoidCallback onTap) => IconButton(
        icon: Icon(icon, color: Colors.white70, size: 22),
        onPressed: onTap,
        splashRadius: 20,
      );
      
  // ignore: unused_element
  Widget _progressStep({required IconData icon, required bool isActive}) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.2),
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        size: 14,
        color: isActive ? AppColors.primary : Colors.white54,
      ),
    );
  }

  // ignore: unused_element
  Widget _progressLine({required bool isActive}) {
    return Expanded(
      child: Container(
        height: 2,
        color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.2),
      ),
    );
  }
  Widget _blob(double size, Color color, double opacity) => Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient:
                    RadialGradient(colors: [color, color.withValues(alpha: 0)]))),
      );

  Widget _actionTile({
    required IconData icon,
    required List<Color> gradient,
    required String title,
    required String subtitle,
    required String? badge,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF141425) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
          Container(
            padding: const EdgeInsets.all(12),
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: gradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                    color: gradient.first.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4))
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 12),
          Text(title,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: isDark ? Colors.white : const Color(0xFF0A0A14))),
          const SizedBox(height: 4),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: isDark ? Colors.white54 : Colors.grey.shade600)),
        ]),
      ),
    );
  }

  void _showWorkManagementSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1A1A2E)
          : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheetState) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Work Management 🛠️',
                  style: GoogleFonts.outfit(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black)),
              const SizedBox(height: 8),
              Text('Manage your shift, tools, and availability.',
                  style: GoogleFonts.outfit(
                      fontSize: 14,
                      color: isDark ? Colors.white60 : Colors.black54)),
              const SizedBox(height: 24),
              // Online/Offline Toggle
              Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SwitchListTile(
                  title: Text('Duty Status',
                      style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black)),
                  subtitle: Text(
                      _isOnline
                          ? 'Online - Receiving orders'
                          : 'Offline - Not receiving orders',
                      style: GoogleFonts.outfit(
                          color: isDark ? Colors.white70 : Colors.black54)),
                  value: _isOnline,
                  activeThumbColor: AppColors.success,
                  secondary: Icon(Icons.power_settings_new_rounded,
                      color: _isOnline ? AppColors.success : Colors.grey),
                  onChanged: (val) async {
                    setSheetState(() => _isOnline = val);
                    setState(() => _isOnline = val);
                    if (val) {
                      _startLocationBroadcast();
                    } else {
                      _stopLocationBroadcast();
                    }
                    final auth = context.read<AuthProvider>();
                    if (auth.currentUserId != null) {
                      try {
                        await _supabase
                            .from('delivery_partners')
                            .update({'is_active': val})
                            .eq('id', auth.currentUserId!);
                      } catch (e) {
                        debugPrint('Error updating duty status: $e');
                      }
                    }
                    if (val) _loadOrders();
                  },
                ),
              ),
              const SizedBox(height: 12),
              // Navigation App setting follows below
              Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ListTile(
                  title: Text('Navigation App',
                      style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black)),
                  subtitle: Text(_navApp == 'apple_maps' ? 'Apple Maps' : _navApp == 'waze' ? 'Waze' : 'Google Maps',
                      style: GoogleFonts.outfit(
                          color: isDark ? Colors.white70 : Colors.black54)),
                  leading: const Icon(Icons.map_outlined, color: Colors.blue),
                  trailing:
                      const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                  onTap: () async {
                    final apps = ['google_maps', 'waze', 'apple_maps'];
                    int idx = apps.indexOf(_navApp);
                    final newApp = apps[(idx + 1) % apps.length];
                    setSheetState(() {
                      _navApp = newApp;
                    });
                    setState(() {});
                    final auth = context.read<AuthProvider>();
                    if (auth.currentUserId != null) {
                      await _supabase
                          .from('delivery_partners')
                          .update({'preferred_nav_app': newApp}).eq('id', auth.currentUserId!);
                    }
                  },
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        );
      }),
    );
  }

  String _vehicleTypeLabel(String type) {
    switch (type) {
      case 'bicycle':
        return 'Bicycle 🚲';
      case '3-wheeler':
        return '3-Wheeler 🛺';
      case 'car':
        return 'Car 🚗';
      case 'motorcycle':
      default:
        return 'Motorcycle 🏍️';
    }
  }

  void _showVehicleChangeSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Change Vehicle', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ...['bicycle', 'motorcycle', '3-wheeler', 'car'].map((type) => ListTile(
                title: Text(_vehicleTypeLabel(type)),
                trailing: _vehicleType == type ? const Icon(Icons.check, color: AppColors.success) : null,
                onTap: () async {
                  Navigator.pop(context);
                  if (type == _vehicleType) return;
                  final auth = context.read<AuthProvider>();
                  if (auth.currentUserId != null) {
                    try {
                      await _supabase.from('vehicle_change_requests').insert({
                        'rider_id': auth.currentUserId!,
                        'requested_type': type,
                      });

                      _showSnack('Vehicle change requested. Awaiting admin approval.');
                    } catch (e) {
                      _showSnack('Error requesting vehicle change', isError: true);
                    }
                  }
                },
              )),
            ],
          ),
        );
      },
    );
  }

  // ignore: unused_element
  Future<void> _launchNavigation(OrderModel order) async {
    final isOutForDelivery = order.status == 'out_for_delivery';
    final lat = isOutForDelivery ? order.deliveryLat : order.shopLat;
    final lng = isOutForDelivery ? order.deliveryLng : order.shopLng;
    final label = isOutForDelivery ? 'Customer' : 'Shop';

    if (lat == null || lng == null) {
      _showSnack('$label coordinates not available', isError: true);
      return;
    }
    final Uri uri = switch (_navApp) {
      'waze'        => Uri.parse('waze://?ll=$lat,$lng&navigate=yes'),
      'apple_maps'  => Uri.parse('maps://maps.apple.com/?daddr=$lat,$lng'),
      _             => Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng'),
    };
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      // Fallback
      await launchUrl(Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng'), mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _callPhone(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _showSnack('Could not launch dialer');
    }
  }
}

class _MiniStarPainter extends CustomPainter {
  final double t;
  _MiniStarPainter(this.t);
  static final _rnd = math.Random(42);
  static final _stars = List.generate(
      25,
      (_) => [
            _rnd.nextDouble(),
            _rnd.nextDouble(),
            _rnd.nextDouble() * 1.2 + 0.4,
            _rnd.nextDouble() * math.pi * 2,
          ]);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..style = PaintingStyle.fill;
    for (final s in _stars) {
      final tw = (math.sin(t * math.pi * 2 + s[3]) + 1) / 2;
      p.color = Colors.white.withValues(alpha: 0.02 + tw * 0.10);
      canvas.drawCircle(Offset(s[0] * size.width, s[1] * size.height), s[2], p);
    }
  }

  @override
  bool shouldRepaint(_MiniStarPainter o) => o.t != t;
}
