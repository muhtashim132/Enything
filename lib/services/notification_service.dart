import 'dart:io';
import 'dart:convert';
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

    // CRITICAL: Create the order alert bell channel — used for all foreground
    // buzz notifications for sellers, riders, and customers.
    // Sound: enything_bell.wav from android/app/src/main/res/raw/
    // NOTE: Channel sound is locked on first creation on a device (Android OS
    // limitation). A fresh channel name guarantees the WAV is applied correctly.
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'enything_urgent_alerts_v5',
        'Order Alert Bell',
        description:
            'Custom bell sound for order notifications (Enything Bell)',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('enything_bell'),
        enableVibration: true,
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

  Future<void> showOrderProgressNotification({
    required String title,
    required String body,
    required int progress, // 0 to 100
  }) async {
    if (Platform.isIOS) {
      // iOS: Display clean grouped notification for progress milestones
      const DarwinNotificationDetails iosPlatformSpecifics =
          DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: false,
        threadIdentifier: 'order_progress_$_orderNotificationId',
        interruptionLevel: InterruptionLevel.active,
      );

      await _flutterLocalNotificationsPlugin.show(
        _orderNotificationId,
        title,
        body,
        const NotificationDetails(iOS: iosPlatformSpecifics),
      );
      return;
    }

    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'order_tracking_channel',
      'Order Tracking',
      channelDescription: 'Shows real-time order progress',
      importance: Importance.max,
      priority: Priority.high,
      showProgress: true,
      maxProgress: 100,
      progress: progress,
      ongoing: true, // This makes it persistent
      autoCancel: false,
      color: const Color(0xFF9C27B0), // Purple color to match theme
      icon:
          '@mipmap/ic_launcher', // Fixed: was 'ic_notification' which doesn't exist. To revert: 'ic_notification'
    );

    final NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await _flutterLocalNotificationsPlugin.show(
      _orderNotificationId,
      title,
      body,
      platformChannelSpecifics,
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
    const androidDetails = AndroidNotificationDetails(
      'enything_urgent_alerts_v5',
      'Enything Order Alerts',
      channelDescription: 'Push notifications for orders and updates',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('enything_bell'),
      enableVibration: true,
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

    const platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch % 100000,
      title,
      body,
      platformDetails,
      payload: payload,
    );
  }

  Future<void> cancelOrderProgressNotification() async {
    await _flutterLocalNotificationsPlugin.cancel(_orderNotificationId);
  }

  void updateOrderNotificationFromStatus(String status) {
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
        cancelOrderProgressNotification();
        return;

      // POST-PAYMENT FULFILLMENT STATES - SHOW/UPDATE NOTIFICATION
      case 'confirmed':
        progress = 25;
        title = 'Order Confirmed';
        body = 'Shop & rider confirmed — preparing soon!';
        break;
      case 'preparing':
      case 'ready_for_pickup':
        progress = 50;
        title = 'Preparing your order';
        body = 'Shop is packing your order 📦';
        break;
      case 'picked_up':
        progress = 75;
        title = 'Order Picked Up';
        body = 'Rider has your order — on the way!';
        break;
      case 'out_for_delivery':
        progress = 90;
        title = 'Out for Delivery';
        body = 'Almost there! Rider is en-route 🛵';
        break;
      default:
        // For any unknown edge cases, default to cancelling to prevent leaks
        cancelOrderProgressNotification();
        return;
    }

    showOrderProgressNotification(
      title: title,
      body: body,
      progress: progress,
    );
  }
}
