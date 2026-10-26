import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/order_model.dart';
import '../utils/delivery_calculator.dart';
import '../utils/order_messaging_helper.dart';
import 'notification_service.dart';
import 'telemetry_service.dart';

/// State snapshot representing the active order tracking information displayed
/// in the iOS Live Activity, Dynamic Island, Android Ongoing Notification, and
/// the In-App Floating Activity Pill.
class LiveActivityState {
  final String orderId;
  final String? cartGroupId;
  final String orderNumber;
  final String shopName;
  final String status;
  final String statusHeadline;
  final int etaMinutes;
  final DateTime estimatedArrivalTime;
  final double progress; // 0.0 to 1.0
  final String? riderName;
  final String? riderPhone;
  final bool isMultiShop;
  final int totalShops;
  final int pickedUpShops;
  final bool isRiderReassigning;
  final bool isTerminal;
  final String? deliveryOtp;
  final OrderFulfillmentCategory fulfillmentCategory;

  const LiveActivityState({
    required this.orderId,
    this.cartGroupId,
    required this.orderNumber,
    required this.shopName,
    required this.status,
    required this.statusHeadline,
    required this.etaMinutes,
    required this.estimatedArrivalTime,
    required this.progress,
    this.riderName,
    this.riderPhone,
    this.isMultiShop = false,
    this.totalShops = 1,
    this.pickedUpShops = 0,
    this.isRiderReassigning = false,
    this.isTerminal = false,
    this.deliveryOtp,
    this.fulfillmentCategory = OrderFulfillmentCategory.food,
  });

  Map<String, dynamic> toMap() {
    return {
      'orderId': orderId,
      'cartGroupId': cartGroupId,
      'orderNumber': orderNumber,
      'shopName': shopName,
      'statusKey': status,
      'statusHeadline': statusHeadline,
      'category': fulfillmentCategory.name,
      'etaMinutes': etaMinutes,
      'etaTimestamp': estimatedArrivalTime.millisecondsSinceEpoch / 1000.0,
      'progress': progress,
      'riderName': riderName,
      'isMultiShop': isMultiShop,
      'unpickedShopsCount': totalShops - pickedUpShops,
      'deliveryOtp': deliveryOtp,
    };
  }
}

/// 100x Forensic Service orchestrating iOS Live Activities (ActivityKit + Dynamic Island),
/// Android Ongoing Notifications (NotificationCompat with progress bar), and the
/// In-App Floating Activity Pill.
class LiveActivityService {
  static final LiveActivityService _instance = LiveActivityService._internal();
  factory LiveActivityService() => _instance;
  LiveActivityService._internal();

  static const MethodChannel _channel = MethodChannel('com.enything/live_activities');

  /// Active Live Activity state published for In-App Dynamic Island / Floating Activity Pill.
  final ValueNotifier<LiveActivityState?> activeStateNotifier = ValueNotifier<LiveActivityState?>(null);

  /// Tracks whether TrackOrderPage is currently active in the foreground, suppressing the floating pill.
  final ValueNotifier<bool> isTrackOrderPageOpenNotifier = ValueNotifier<bool>(false);

  String? _currentActivityId;
  String? _currentOrderId;

  String? get currentOrderId => _currentOrderId;

  final Map<String, int> _lastSmoothedEtaMinutes = {};
  final Map<String, DateTime> _lastSyncTimes = {};
  final Map<String, int> _lastSyncEtas = {};
  final Map<String, String> _lastSyncStatuses = {};

  static const String _prefKeyActivityId = 'enything_live_activity_id';
  static const String _prefKeyOrderId = 'enything_live_activity_order_id';

  /// Validates geographic coordinate sanity (rejects 0.0, NaN, and coordinates outside India bounds).
  static bool isValidCoordinate(LatLng? pt) {
    if (pt == null) return false;
    if (pt.latitude.isNaN || pt.longitude.isNaN) return false;
    if (pt.latitude == 0.0 && pt.longitude == 0.0) return false;
    // Bounding box for India (6.0°N to 38.0°N, 68.0°E to 98.0°E)
    return pt.latitude >= 6.0 && pt.latitude <= 38.0 && pt.longitude >= 68.0 && pt.longitude <= 98.0;
  }

  /// Initializes stored activity state on app startup.
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _currentActivityId = prefs.getString(_prefKeyActivityId);
      _currentOrderId = prefs.getString(_prefKeyOrderId);
    } catch (_) {}
  }

  /// Sets whether the user is actively viewing TrackOrderPage.
  void setTrackOrderPageOpen(bool isOpen) {
    isTrackOrderPageOpenNotifier.value = isOpen;
  }

  /// Checks if iOS Live Activities are supported and enabled on this device.
  Future<bool> areActivitiesEnabled() async {
    if (!Platform.isIOS) return false;
    try {
      final res = await _channel.invokeMethod<Map>('areActivitiesEnabled');
      return res?['enabled'] == true;
    } catch (e) {
      debugPrint('[LiveActivityService] areActivitiesEnabled check error: $e');
      return false;
    }
  }

  /// Computes the exact Swiggy-style headline, progress (0.0 to 1.0), and ETA in minutes.
  LiveActivityState computeState({
    required OrderModel order,
    List<OrderModel> groupOrders = const [],
    Map<String, LatLng>? riderLocations,
    String? fallbackShopName,
    String? riderName,
  }) {
    final status = order.status;
    final isMultiShop = order.cartGroupId != null && groupOrders.length > 1;

    // Filter active sub-orders
    final activeOrders = groupOrders.isNotEmpty
        ? groupOrders.where((o) => o.status != 'cancelled' && o.status != 'seller_rejected').toList()
        : [order];

    final totalShops = activeOrders.isNotEmpty ? activeOrders.length : 1;
    final pickedUpShops = activeOrders.where((o) => o.status == 'picked_up' || o.status == 'out_for_delivery').length;

    // Compute distance and prep time
    double distanceKm = order.estimatedDistanceKm > 0 ? order.estimatedDistanceKm : 3.0;
    int prepMins = order.shopPrepTimeSnapshot > 0 ? order.shopPrepTimeSnapshot : 25;

    for (final o in activeOrders) {
      if (o.estimatedDistanceKm > distanceKm) distanceKm = o.estimatedDistanceKm;
      if (o.shopPrepTimeSnapshot > prepMins) prepMins = o.shopPrepTimeSnapshot;
    }

    // Dynamic travel calculation with GPS sanity checks
    if (status == 'out_for_delivery' && riderLocations != null && riderLocations.isNotEmpty) {
      if (order.deliveryLat != null && order.deliveryLng != null) {
        final custPt = LatLng(order.deliveryLat!, order.deliveryLng!);
        if (isValidCoordinate(custPt)) {
          double maxDist = 0.0;
          for (final loc in riderLocations.values) {
            if (isValidCoordinate(loc)) {
              final d = DeliveryCalculator.haversineKm(loc, custPt);
              if (d > maxDist) maxDist = d;
            }
          }
          if (maxDist > 0) distanceKm = maxDist;
        }
      }
      prepMins = 0;
    } else if (status == 'picked_up' || status == 'out_for_delivery') {
      prepMins = 0;
    }

    int etaMins = DeliveryCalculator.etaMinutes(distanceKm, prepMins);
    if (etaMins < 2) etaMins = 2;

    double progress = 0.20;
    String headline = 'Your order is being prepared';
    bool isTerminal = false;
    bool isRiderReassigning = false;

    // Rider name resolution
    final activeRider = riderName ?? (order.riderPhone != null ? 'Assigned Partner' : null);

    final category = OrderMessagingHelper.resolveCategory(order, groupOrders);

    switch (status) {
      case 'confirmed':
        if (order.deliveryPartnerId != null) {
          headline = 'Rider is on the way to pick up';
          progress = 0.40;
          if (etaMins > 10) etaMins = 8;
        } else {
          headline = 'Order confirmed · Assigning partner...';
          progress = 0.25;
        }
        break;

      case 'preparing':
        final prepSubject = switch (category) {
          OrderFulfillmentCategory.pharmacy => 'Pharmacy is preparing your medicines',
          OrderFulfillmentCategory.grocery => 'Store is packing your groceries',
          OrderFulfillmentCategory.retail => 'Store is packing your package',
          OrderFulfillmentCategory.cateringFood => 'Kitchen cooking event feast',
          OrderFulfillmentCategory.cateringSupplies => 'Team preparing event supplies',
          _ => 'Your order is being prepared',
        };
        if (order.deliveryPartnerId != null) {
          headline = prepSubject;
          progress = 0.35;
          if (etaMins > 12) etaMins = 9;
        } else {
          headline = prepSubject;
          progress = 0.30;
        }
        break;

      case 'ready_for_pickup':
        if (order.arrivedAtShopTime != null) {
          headline = 'Rider at store · Packing order';
          progress = 0.50;
        } else {
          headline = 'Order packed · Waiting for partner';
          progress = 0.45;
        }
        if (etaMins > 8) etaMins = 7;
        break;

      case 'picked_up':
        if (isMultiShop && pickedUpShops < totalShops) {
          headline = '🛍️ $pickedUpShops of $totalShops stores collected · Next stop';
          progress = 0.65;
          if (etaMins > 8) etaMins = 6;
        } else {
          headline = 'Order picked up · On the way to you';
          progress = 0.75;
          if (etaMins > 7) etaMins = 5;
        }
        break;

      case 'out_for_delivery':
        if (order.deliveryOtp != null && order.deliveryOtp!.isNotEmpty) {
          headline = 'Almost there! · Share OTP: ${order.deliveryOtp}';
        } else {
          headline = 'Almost there! Rider is arriving 🛵';
        }
        progress = 0.90;
        if (etaMins > 4) etaMins = 3;
        break;

      case 'delivered':
        final sub = OrderMessagingHelper.getDeliveredSubtitle(order, groupOrders);
        headline = 'Delivered · $sub';
        progress = 1.0;
        etaMins = 0;
        isTerminal = true;
        break;

      case 'cancelled':
      case 'seller_rejected':
      case 'partner_rejected':
      case 'shop_dispute_cancel':
      case 'timeout':
      case 'failed':
        headline = 'Order Cancelled';
        progress = 0.0;
        etaMins = 0;
        isTerminal = true;
        break;

      case 'awaiting_acceptance':
      case 'awaiting_payment':
      default:
        headline = 'Confirming your order...';
        progress = 0.15;
        break;
    }

    // ETA Anti-Flapping Damper during out_for_delivery
    if (status == 'out_for_delivery') {
      final lastEta = _lastSmoothedEtaMinutes[order.id];
      if (lastEta != null) {
        if (etaMins > lastEta + 1) {
          // Rider momentarily stopped at signal or traffic: prevent erratic spike
          etaMins = lastEta;
        }
      }
      _lastSmoothedEtaMinutes[order.id] = etaMins;
    } else if (status == 'delivered' || status == 'cancelled' || status == 'seller_rejected') {
      _lastSmoothedEtaMinutes.remove(order.id);
    }

    final arrivalTime = DateTime.now().add(Duration(minutes: etaMins));
    final resolvedShopName = fallbackShopName ?? 'Enything Express';
    final orderNum = order.id.length >= 6 ? order.id.substring(0, 6).toUpperCase() : order.id.toUpperCase();

    return LiveActivityState(
      orderId: order.id,
      cartGroupId: order.cartGroupId,
      orderNumber: orderNum,
      shopName: resolvedShopName,
      status: status,
      statusHeadline: headline,
      etaMinutes: etaMins,
      estimatedArrivalTime: arrivalTime,
      progress: progress,
      riderName: activeRider,
      riderPhone: order.riderPhone,
      isMultiShop: isMultiShop,
      totalShops: totalShops,
      pickedUpShops: pickedUpShops,
      isRiderReassigning: isRiderReassigning,
      isTerminal: isTerminal,
      deliveryOtp: order.deliveryOtp,
      fulfillmentCategory: category,
    );
  }

  /// Synchronizes live order progress across iOS Live Activities, Android Ongoing Notification,
  /// and the In-App Floating Dynamic Island Pill.
  Future<void> syncOrderStatus({
    required OrderModel order,
    List<OrderModel> groupOrders = const [],
    Map<String, LatLng>? riderLocations,
    String? shopName,
    String? riderName,
  }) async {
    final state = computeState(
      order: order,
      groupOrders: groupOrders,
      riderLocations: riderLocations,
      fallbackShopName: shopName,
      riderName: riderName,
    );

    // Update in-app state notifier immediately for instant UI responsiveness
    activeStateNotifier.value = state.isTerminal ? null : state;

    // Handle terminal status: dismiss lock screen widgets & notifications cleanly
    if (state.isTerminal) {
      await endLiveActivity(order.id, dismissalPolicy: 'immediate');
      await NotificationService().cancelOrderProgressNotification(order.id);
      return;
    }

    // Battery & ActivityKit Budget Throttle: skip redundant sync if state and ETA are identical within 5s
    final now = DateTime.now();
    final lastSync = _lastSyncTimes[order.id];
    final lastEta = _lastSyncEtas[order.id];
    final lastStatus = _lastSyncStatuses[order.id];

    if (lastSync != null &&
        lastStatus == state.status &&
        lastEta == state.etaMinutes &&
        now.difference(lastSync).inSeconds < 5) {
      return;
    }
    _lastSyncTimes[order.id] = now;
    _lastSyncEtas[order.id] = state.etaMinutes;
    _lastSyncStatuses[order.id] = state.status;

    // Android: Update persistent ongoing notification with progress bar & live ETA
    if (Platform.isAndroid) {
      final notifTitle = 'Arriving in ${state.etaMinutes} mins · ${state.shopName}';
      final summary = state.deliveryOtp != null && state.status == 'out_for_delivery'
          ? '🔑 Delivery OTP: ${state.deliveryOtp}'
          : (state.isMultiShop
              ? 'Multi-Store (#${state.orderNumber})'
              : 'Order #${state.orderNumber}');
      await NotificationService().showOrderProgressNotification(
        title: notifTitle,
        body: state.statusHeadline,
        progress: (state.progress * 100).round(),
        orderId: state.orderId,
        summaryText: summary,
      );
    }

    // iOS: Start or update native ActivityKit Live Activity
    if (Platform.isIOS) {
      try {
        if (_currentOrderId == order.id && _currentActivityId != null) {
          final res = await _channel.invokeMethod<Map>('updateActivity', {
            'activityId': _currentActivityId,
            ...state.toMap(),
          });
          if (res?['notFound'] == true) {
            // Activity was dismissed externally; re-start
            await _startIosActivity(state);
          }
        } else {
          await _startIosActivity(state);
        }
      } catch (e, st) {
        TelemetryService.instance.logError('LiveActivitySync', e, st);
      }
    }
  }

  Future<void> _startIosActivity(LiveActivityState state) async {
    try {
      final res = await _channel.invokeMethod<Map>('startActivity', state.toMap());
      if (res?['success'] == true && res?['activityId'] != null) {
        _currentActivityId = res!['activityId'] as String;
        _currentOrderId = state.orderId;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefKeyActivityId, _currentActivityId!);
        await prefs.setString(_prefKeyOrderId, _currentOrderId!);
      }
    } catch (e) {
      debugPrint('[LiveActivityService] _startIosActivity failed: $e');
    }
  }

  /// Ends the Live Activity for the specified order.
  Future<void> endLiveActivity(String orderId, {String dismissalPolicy = 'immediate'}) async {
    activeStateNotifier.value = null;
    _lastSmoothedEtaMinutes.remove(orderId);
    _lastSyncTimes.remove(orderId);
    _lastSyncEtas.remove(orderId);
    _lastSyncStatuses.remove(orderId);

    if (Platform.isAndroid) {
      await NotificationService().cancelOrderProgressNotification(orderId);
    }

    if (Platform.isIOS) {
      try {
        await _channel.invokeMethod('endActivity', {
          'activityId': _currentActivityId,
          'orderId': orderId,
          'dismissalPolicy': dismissalPolicy,
        });
        _currentActivityId = null;
        _currentOrderId = null;
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_prefKeyActivityId);
        await prefs.remove(_prefKeyOrderId);
      } catch (e) {
        debugPrint('[LiveActivityService] endLiveActivity failed: $e');
      }
    }
  }
}
