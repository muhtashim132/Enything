import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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

    // We only care about Android for this specific feature right now
    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Handle notification tap if needed
      },
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
      icon: '@mipmap/ic_launcher',
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

  Future<void> cancelOrderProgressNotification() async {
    await _flutterLocalNotificationsPlugin.cancel(_orderNotificationId);
  }

  void updateOrderNotificationFromStatus(String status) {
    int progress = 0;
    String title = 'Order Update';
    String body = 'Checking status...';

    switch (status) {
      case 'pending':
        progress = 10;
        title = 'Order Placed';
        body = 'Waiting for shop & rider to accept';
        break;
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
      case 'delivered':
        progress = 100;
        title = 'Delivered!';
        body = 'Enjoy your order! 🎉';
        cancelOrderProgressNotification(); // Optionally cancel or show completion
        return;
      case 'cancelled':
      case 'seller_rejected':
      case 'partner_rejected':
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
