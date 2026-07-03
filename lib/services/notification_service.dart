import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../main.dart';
import '../config/routes.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const int _orderNotificationId = 888;

  Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('ic_notification');

    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.payload != null && response.payload!.isNotEmpty) {
          try {
            final data = jsonDecode(response.payload!) as Map<String, dynamic>;
            final role = data['role'] as String?;
            final action = data['action'] as String?;
            final orderId = data['order_id'] as String?;

            if (role == 'seller') {
              // Seller tap: go to seller dashboard then push orders on top.
              navigatorKey.currentState?.pushNamedAndRemoveUntil(
                  AppRoutes.sellerDashboard, (route) => false);
              Future.microtask(() {
                navigatorKey.currentState?.pushNamed(AppRoutes.sellerOrders);
              });
            } else if (role == 'rider' || role == 'delivery' || action == 'new_order') {
              // Rider tap: go to delivery dashboard.
              navigatorKey.currentState?.pushNamedAndRemoveUntil(
                  AppRoutes.deliveryDashboard, (route) => false);
            } else if (role == 'customer' || (role == null && orderId != null)) {
              // Customer tap: establish customerHome as base, then push
              // trackOrder on top so the back button works correctly.
              if (orderId != null) {
                navigatorKey.currentState?.pushNamedAndRemoveUntil(
                    AppRoutes.customerHome, (route) => false);
                Future.microtask(() {
                  navigatorKey.currentState?.pushNamed(
                    AppRoutes.trackOrder,
                    arguments: {'orderId': orderId},
                  );
                });
              } else {
                // No order_id — fall back to customer home.
                navigatorKey.currentState?.pushNamedAndRemoveUntil(
                    AppRoutes.customerHome, (route) => false);
              }
            }
          } catch (e) {
            debugPrint('Error parsing notification payload: $e');
          }
        }
      },
    );

    // CRITICAL: Create the notification channel that FCM uses when app is killed.
    // Must match the channel ID in AndroidManifest.xml and in the Edge Function.
    // Without this channel created with HIGH importance, Android shows notifications silently.
    final androidPlugin = _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'enything_push_channel',         // must match AndroidManifest.xml
        'Enything Notifications',
        description: 'Push notifications for orders and updates',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      ),
    );

    // CRITICAL: Create the order alert bell channel — used for all foreground
    // buzz notifications for sellers, riders, and customers.
    // Sound: enything_bell.wav from android/app/src/main/res/raw/
    // NOTE: Channel sound is locked on first creation on a device (Android OS
    // limitation). A fresh channel name guarantees the WAV is applied correctly.
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'order_alert_loop_channel',
        'Order Alert Bell',
        description: 'Custom bell sound for order notifications (Enything Bell)',
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
      icon: 'ic_notification',
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
    // Use order_alert_loop_channel which has the custom enything_bell.wav sound.
    // This ensures ALL in-app buzz notifications (sellers, riders, customers)
    // play the Enything Bell regardless of role.
    const androidDetails = AndroidNotificationDetails(
      'order_alert_loop_channel',
      'Order Alert Bell',
      channelDescription: 'Custom bell sound for order notifications (Enything Bell)',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('enything_bell'),
      enableVibration: true,
      icon: 'ic_notification',
    );
    const platformDetails = NotificationDetails(android: androidDetails);

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
