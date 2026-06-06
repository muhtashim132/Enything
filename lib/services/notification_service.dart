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
            
            if (role == 'seller') {
              navigatorKey.currentState?.pushNamedAndRemoveUntil(
                  AppRoutes.sellerDashboard, (route) => false);
            } else if (role == 'rider' || action == 'new_order') {
              navigatorKey.currentState?.pushNamedAndRemoveUntil(
                  AppRoutes.deliveryDashboard, (route) => false);
            } else if (data['order_id'] != null) {
              navigatorKey.currentState?.pushNamed(
                AppRoutes.trackOrder,
                arguments: {'orderId': data['order_id']},
              );
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
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'enything_push_channel',
      'Enything Notifications',
      channelDescription: 'Push notifications for orders and updates',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      icon: 'ic_notification',
    );
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await _flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch % 100000,
      title,
      body,
      platformChannelSpecifics,
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
