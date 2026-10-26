import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';

import 'telemetry_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const int _orderNotificationId = 888;

  Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final darwinNotificationCategories = <DarwinNotificationCategory>[
      DarwinNotificationCategory(
        'order_alert_category',
        actions: <DarwinNotificationAction>[
          DarwinNotificationAction.plain(
            'accept',
            'Accept',
            options: <DarwinNotificationActionOption>{
              DarwinNotificationActionOption.foreground,
            },
          ),
          DarwinNotificationAction.plain(
            'decline',
            'Decline',
            options: <DarwinNotificationActionOption>{
              DarwinNotificationActionOption.destructive,
            },
          ),
        ],
        options: <DarwinNotificationCategoryOption>{
          DarwinNotificationCategoryOption.customDismissAction,
        },
      ),
    ];

    final DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: false, // We request via FCM separately
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: darwinNotificationCategories,
    );

    final InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        if (response.payload != null && response.payload!.isNotEmpty) {
          try {
            final data = jsonDecode(response.payload!) as Map<String, dynamic>;
            if (response.actionId == 'decline') {
              final orderId = data['order_id'] as String?;
              final currentUserId =
                  Supabase.instance.client.auth.currentUser?.id;
              if (orderId != null && currentUserId != null) {
                await Supabase.instance.client.rpc('rider_reject_order',
                    params: {
                      'p_order_id': orderId,
                      'p_rider_id': currentUserId
                    });
                debugPrint('Order $orderId declined via iOS notification.');
              }
              if (response.id != null) {
                await _flutterLocalNotificationsPlugin.cancel(response.id!);
              }
              return;
            }
            // Centralize routing logic in main.dart. If navigator is not ready
            // (e.g. terminated launch), this safely no-ops and SplashPage takes over.
            handleNotificationClick(data);
          } catch (e, st) {
            TelemetryService.instance.logError('NotificationTapParser', e, st);
          }
        }
      },
    );

    final androidPlugin =
        _flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    // Clean up stale channels to ensure fresh AudioAttributes are applied
    try {
      await androidPlugin?.deleteNotificationChannel('enything_urgent_alerts_v5');
      await androidPlugin?.deleteNotificationChannel('enything_bell_channel_v4');
      await androidPlugin?.deleteNotificationChannel('order_alert_bell_channel');
    } catch (_) {}

    // CRITICAL: Create the order alert bell channel — used for all foreground
    // and background buzz notifications for sellers, riders, and customers.
    // Sound: enything_bell.wav from android/app/src/main/res/raw/
    // audioAttributesUsage: alarm ensures full volume & bypasses silent modes
    await androidPlugin?.createNotificationChannel(
      AndroidNotificationChannel(
        'enything_urgent_order_v1',
        'Enything Urgent Orders',
        description:
            'Urgent order notifications with screen wake up and alarm sound',
        importance: Importance.max,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('enything_bell'),
        audioAttributesUsage: AudioAttributesUsage.alarm,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
        enableLights: true,
        showBadge: true,
      ),
    );

    // CRITICAL: Create the order tracking channel for the persistent live tracking notification
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'order_tracking_channel',
        'Order Tracking',
        description: 'Shows real-time order progress',
        importance: Importance.max,
        playSound: false,
        enableVibration: false,
        showBadge: false,
      ),
    );
  }

  int getNotificationIdForOrder(String? orderId) {
    if (orderId == null || orderId.isEmpty) return _orderNotificationId;
    return (orderId.hashCode.abs() % 100000) + 10000;
  }

  Future<void> showOrderProgressNotification({
    required String title,
    required String body,
    required int progress, // 0 to 100
    String? orderId,
    String? summaryText,
  }) async {
    final notifId = getNotificationIdForOrder(orderId);
    final payload = orderId != null
        ? jsonEncode({'role': 'customer', 'order_id': orderId})
        : null;

    if (Platform.isIOS) {
      // iOS: Display clean grouped notification for progress milestones
      final DarwinNotificationDetails iosPlatformSpecifics =
          DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: false,
        threadIdentifier: 'order_progress_$notifId',
        interruptionLevel: InterruptionLevel.active,
      );

      await _flutterLocalNotificationsPlugin.show(
        notifId,
        title,
        body,
        NotificationDetails(iOS: iosPlatformSpecifics),
        payload: payload,
      );
      return;
    }

    final bigTextStyle = BigTextStyleInformation(
      body,
      contentTitle: title,
      summaryText: summaryText ?? '$progress% completed',
      htmlFormatBigText: false,
      htmlFormatContentTitle: false,
      htmlFormatSummaryText: false,
    );

    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'order_tracking_channel',
      'Order Tracking',
      channelDescription: 'Shows real-time order progress',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.progress,
      visibility: NotificationVisibility.public,
      onlyAlertOnce: true,
      showProgress: true,
      maxProgress: 100,
      progress: progress,
      ongoing: true, // This makes it persistent on Lock Screen and Shade
      autoCancel: false,
      color: const Color(0xFFFF5200), // Vibrant orange matching Live Activity theme
      icon: '@mipmap/ic_launcher',
      styleInformation: bigTextStyle,
      actions: <AndroidNotificationAction>[
        const AndroidNotificationAction(
          'track_order',
          'Track Order 🛵',
          showsUserInterface: true,
        ),
      ],
    );

    final NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await _flutterLocalNotificationsPlugin.show(
      notifId,
      title,
      body,
      platformChannelSpecifics,
      payload: payload,
    );
  }

  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    // Use enything_bell_channel_v2 which has the custom enything_bell.wav sound.
    // This ensures ALL in-app buzz notifications (sellers, riders, customers)
    // play the Enything Bell regardless of role.
    final androidDetails = AndroidNotificationDetails(
      'enything_urgent_order_v1',
      'Enything Urgent Orders',
      channelDescription: 'Push notifications for orders and updates',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('enything_bell'),
      audioAttributesUsage: AudioAttributesUsage.alarm,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      icon: '@mipmap/ic_launcher',
    );

    // iOS foreground notification details with time-sensitive interruption level and custom bell sound
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'enything_bell.wav',
      categoryIdentifier: 'order_alert_category',
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    final platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // Parse order_id from payload for deterministic notification ID
    int notifId = DateTime.now().millisecondsSinceEpoch % 100000;
    if (payload != null) {
      try {
        final data = jsonDecode(payload) as Map<String, dynamic>;
        if (data['order_id'] != null) {
          notifId = (data['order_id'] as String).hashCode;
        }
      } catch (_) {}
    }

    await _flutterLocalNotificationsPlugin.show(
      notifId,
      title,
      body,
      platformDetails,
      payload: payload,
    );
  }

  Future<void> cancelOrderProgressNotification([String? orderId]) async {
    if (orderId != null && orderId.isNotEmpty) {
      await _flutterLocalNotificationsPlugin.cancel(getNotificationIdForOrder(orderId));
    }
    await _flutterLocalNotificationsPlugin.cancel(_orderNotificationId);
  }

  void updateOrderNotificationFromStatus(
    String status, {
    String? orderId,
    String? etaText,
    String? deliveryOtp,
    String? shopName,
  }) {
    int progress = 0;
    String title = 'Order Update';
    String body = 'Checking status...';

    switch (status) {
      // PRE-PAYMENT STATES & TERMINAL STATES - CANCEL NOTIFICATION
      case 'pending': // Legacy
      case 'awaiting_acceptance':
      case 'awaiting_payment':
      case 'verification_failed':
      case 'payment_failed':
      case 'cancelled':
      case 'seller_rejected':
      case 'partner_rejected':
      case 'delivered':
        cancelOrderProgressNotification(orderId);
        return;

      // POST-PAYMENT FULFILLMENT STATES - SHOW/UPDATE NOTIFICATION
      case 'confirmed':
        progress = 25;
        title = shopName != null ? 'Order Confirmed · $shopName' : 'Order Confirmed';
        body = 'Shop & rider confirmed — preparing soon!';
        break;
      case 'preparing':
      case 'ready_for_pickup':
        progress = 50;
        title = etaText != null ? 'Preparing your order ($etaText)' : 'Preparing your order';
        body = shopName != null ? '$shopName is packing your order 📦' : 'Shop is packing your order 📦';
        break;
      case 'picked_up':
        progress = 75;
        title = etaText != null ? 'Order Picked Up ($etaText)' : 'Order Picked Up';
        body = 'Rider has your order — on the way!';
        break;
      case 'out_for_delivery':
        progress = 90;
        title = etaText != null ? 'Out for Delivery · $etaText' : 'Out for Delivery';
        body = (deliveryOtp != null && deliveryOtp.isNotEmpty)
            ? 'Almost there! 🛵 · Share OTP: $deliveryOtp'
            : 'Almost there! Rider is en-route 🛵';
        break;
      default:
        // For any unknown edge cases, default to cancelling to prevent leaks
        cancelOrderProgressNotification(orderId);
        return;
    }

    final summary = (deliveryOtp != null && deliveryOtp.isNotEmpty && status == 'out_for_delivery')
        ? '🔑 Delivery OTP: $deliveryOtp'
        : (etaText != null ? '$progress% completed · $etaText' : '$progress% completed');

    showOrderProgressNotification(
      title: title,
      body: body,
      progress: progress,
      orderId: orderId,
      summaryText: summary,
    );
  }
}
