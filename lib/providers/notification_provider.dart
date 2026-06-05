import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// A single in-app notification entry.
class AppNotification {
  final String id;
  final String title;
  final String body;
  final String? orderId;
  final DateTime createdAt;
  bool isRead;

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    this.orderId,
    DateTime? createdAt,
    this.isRead = false,
  }) : createdAt = createdAt ?? DateTime.now();
}

/// Manages real-time in-app notifications for all roles by listening to
/// Supabase Realtime order changes.
///
/// Usage:
///   - Call [listenAsCustomer], [listenAsSeller], or [listenAsDelivery]
///     once after login to subscribe.
///   - Call [stopListening] on logout / role change.
///   - Call [markAllRead] / [markRead] to manage unread state.
class NotificationProvider extends ChangeNotifier {
  final _supabase = Supabase.instance.client;

  final List<AppNotification> _notifications = [];
  RealtimeChannel? _channel;
  String? _listeningUserId;
  String? _listeningRole;
  
  StreamSubscription? _fcmTokenSub;
  StreamSubscription? _fcmMessageSub;

  List<AppNotification> get notifications =>
      List.unmodifiable(_notifications.reversed.toList());

  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  // ── FCM Push Notification Registration ───────────────────────────────────

  /// Call this once after the user logs in to register their FCM device token.
  /// Stores the token in Supabase `device_tokens` table for push delivery.
  Future<void> registerFcmToken(String userId, String role) async {
    try {
      final messaging = FirebaseMessaging.instance;

      // Request permission (required for iOS; no-op on Android)
      final settings = await messaging.requestPermission(
        alert: true, badge: true, sound: true,
      );
      debugPrint('FCM permission: ${settings.authorizationStatus}');

      final token = await messaging.getToken();
      debugPrint('FCM token obtained: ${token == null ? "NULL - FAILED" : token.substring(0, 20) + "..."}');
      if (token == null) return;

      // Try upsert first, then plain insert as fallback
      final response = await _supabase.from('device_tokens').upsert({
        'user_id': userId,
        'token': token,
        'platform': Platform.isIOS ? 'ios' : 'android',
        'role': role,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,token');

      debugPrint('FCM token upsert done. Response: $response');

      // Verify it was actually saved
      final check = await _supabase
          .from('device_tokens')
          .select('id')
          .eq('user_id', userId)
          .eq('token', token)
          .maybeSingle();
      if (check == null) {
        // Upsert silently failed — try plain insert
        debugPrint('FCM token NOT found after upsert - trying plain INSERT...');
        final insertRes = await _supabase.from('device_tokens').insert({
          'user_id': userId,
          'token': token,
          'platform': Platform.isIOS ? 'ios' : 'android',
          'role': role,
        });
        debugPrint('FCM plain INSERT result: $insertRes');
      } else {
        debugPrint('FCM token confirmed saved in DB: ${check['id']}');
      }

      // Listen for token refresh and re-register
      _fcmTokenSub?.cancel();
      _fcmTokenSub = messaging.onTokenRefresh.listen((newToken) async {
        await _supabase.from('device_tokens').upsert({
          'user_id': userId,
          'token': newToken,
          'platform': Platform.isIOS ? 'ios' : 'android',
          'role': role,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'user_id,token');
      });

      // Handle foreground messages by adding them as in-app notifications
      _fcmMessageSub?.cancel();
      _fcmMessageSub = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        final notif = message.notification;
        if (notif == null) return;
        _notifications.add(AppNotification(
          id: message.messageId ?? DateTime.now().toIso8601String(),
          title: notif.title ?? 'Notification',
          body: notif.body ?? '',
          orderId: message.data['order_id'] as String?,
        ));
        notifyListeners();
      });
    } catch (e) {
      debugPrint('FCM token registration failed: $e');
    }
  }

  // ── Start listening ──────────────────────────────────────────────────────────────

  /// Customer: watches their own orders for status changes.
  void listenAsCustomer(String customerId) {
    if (_listeningUserId == customerId && _listeningRole == 'customer') return;
    stopListening();
    _listeningUserId = customerId;
    _listeningRole = 'customer';

    _channel = _supabase
        .channel('notif-customer-$customerId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'customer_id',
            value: customerId,
          ),
          callback: (payload) {
            if (payload.newRecord.isEmpty) return;
            final newStatus = payload.newRecord['status'] as String?;
            final oldStatus = payload.oldRecord['status'] as String?;
            final orderId = payload.newRecord['id'] as String?;
            
            final sellerAcceptedNow = payload.newRecord['seller_accepted'] == true;
            final sellerAcceptedBefore = payload.oldRecord['seller_accepted'] == true;

            // Notify customer when the shop accepts (one down, rider still needed)
            if (sellerAcceptedNow && !sellerAcceptedBefore && newStatus == 'awaiting_acceptance') {
              _add(AppNotification(
                id: '${orderId}_shop_accepted',
                title: '🏪 Shop Accepted!',
                body: 'The shop accepted your order. Waiting for a rider now...',
                orderId: orderId,
              ));
            }

            if (newStatus == null || newStatus == oldStatus) return;

            final (title, body) = _customerStatusMessage(newStatus, orderId);
            if (title != null) {
              _add(AppNotification(
                id: '${orderId}_$newStatus',
                title: title,
                body: body!,
                orderId: orderId,
              ));
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'customer_id',
            value: customerId,
          ),
          callback: (payload) {
            final orderId = payload.newRecord['id'] as String?;
            _add(AppNotification(
              id: '${orderId}_placed',
              title: '🛍️ Order Sent!',
              body: 'Waiting for the shop & rider to accept. No charge yet — you pay only after both confirm.',
              orderId: orderId,
            ));
          },
        )
        .subscribe();

    // Restore persisted notification history for this user
    _loadFromDb();
  }

  /// Seller: watches orders for their shops (new orders arriving).
  void listenAsSeller(String shopId) {
    if (_listeningUserId == shopId && _listeningRole == 'seller') return;
    stopListening();
    _listeningUserId = shopId;
    _listeningRole = 'seller';

    _channel = _supabase
        .channel('notif-seller-$shopId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'shop_id',
            value: shopId,
          ),
          callback: (payload) {
            final orderId = payload.newRecord['id'] as String?;
            final amount =
                (payload.newRecord['total_amount'] ?? 0.0).toDouble();
            _add(AppNotification(
              id: '${orderId}_new',
              title: '🔔 New Order!',
              body:
                  'You have a new order of ₹${amount.toStringAsFixed(0)} waiting for your acceptance.',
              orderId: orderId,
            ));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'shop_id',
            value: shopId,
          ),
          callback: (payload) {
            if (payload.newRecord.isEmpty) return;
            final newStatus = payload.newRecord['status'] as String?;
            final oldStatus = payload.oldRecord['status'] as String?;
            final orderId = payload.newRecord['id'] as String?;
            if (newStatus == null || newStatus == oldStatus) return;

            final (title, body) = _sellerStatusMessage(newStatus, orderId);
            if (title != null) {
              _add(AppNotification(
                id: '${orderId}_$newStatus',
                title: title,
                body: body!,
                orderId: orderId,
              ));
            }
          },
        )
        .subscribe();

    // Restore persisted notification history for this user
    _loadFromDb();
  }

  /// Delivery partner: watches for new available orders and their active ones.
  void listenAsDelivery(String partnerId) {
    if (_listeningUserId == partnerId && _listeningRole == 'delivery') return;
    stopListening();
    _listeningUserId = partnerId;
    _listeningRole = 'delivery';

    _channel = _supabase
        .channel('notif-delivery-$partnerId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'delivery_partner_id',
            value: partnerId,
          ),
          callback: (payload) {
            if (payload.newRecord.isEmpty) return;
            final newRecord = payload.newRecord;
            final oldRecord = payload.oldRecord;

            final orderId = newRecord['id'] as String?;
            final newStatus = newRecord['status'] as String?;
            final oldStatus = oldRecord['status'] as String?;

            if (newStatus == null || newStatus == oldStatus) return;

            final (title, body) = _deliveryStatusMessage(newStatus, orderId);
            if (title != null) {
              _add(AppNotification(
                id: '${orderId}_$newStatus',
                title: title,
                body: body!,
                orderId: orderId,
              ));
            }
          },
        )
        .subscribe();

    // Restore persisted notification history for this user
    _loadFromDb();
  }

  /// Admin: watches for new KYC applications and complaints.
  void listenAsAdmin(String adminId) {
    if (_listeningUserId == adminId && _listeningRole == 'admin') return;
    stopListening();
    _listeningUserId = adminId;
    _listeningRole = 'admin';

    _channel = _supabase
        .channel('notif-admin-$adminId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'shops',
          callback: (payload) {
            final shopId = payload.newRecord['id'] as String?;
            final shopName = payload.newRecord['shop_name'] as String? ?? 'A new shop';
            _add(AppNotification(
              id: 'shop_kyc_$shopId',
              title: '🏪 New Shop KYC!',
              body: '$shopName has registered and is pending verification.',
            ));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'delivery_partners',
          callback: (payload) {
            final partnerId = payload.newRecord['id'] as String?;
            _add(AppNotification(
              id: 'rider_kyc_$partnerId',
              title: '🛵 New Rider KYC!',
              body: 'A new delivery partner has registered and is pending verification.',
            ));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'support_tickets',
          callback: (payload) {
            final id = payload.newRecord['id'] as String?;
            final reason = payload.newRecord['subject'] as String? ?? payload.newRecord['title'] as String? ?? 'A new support ticket';
            _add(AppNotification(
              id: 'ticket_$id',
              title: '🚨 New Support Ticket!',
              body: reason,
            ));
          },
        )
        .subscribe();

    // Restore persisted notification history for this user
    _loadFromDb();
  }

  // ── Stop listening ────────────────────────────────────────────────────────

  void stopListening() {
    _channel?.unsubscribe();
    _channel = null;
    
    _fcmTokenSub?.cancel();
    _fcmTokenSub = null;
    _fcmMessageSub?.cancel();
    _fcmMessageSub = null;
    
    _listeningUserId = null;
    _listeningRole = null;
    _clearMemory(); // Clear RAM only — DB history is preserved per user
  }

  // ── Manage notifications ──────────────────────────────────────────────────

  void markRead(String notificationId) {
    final idx = _notifications.indexWhere((n) => n.id == notificationId);
    if (idx != -1) {
      _notifications[idx].isRead = true;
      notifyListeners();
      _markReadInDb(notificationId); // sync to DB (fire and forget)
    }
  }

  void markAllRead() {
    for (final n in _notifications) {
      n.isRead = true;
    }
    notifyListeners();
    _markAllReadInDb(); // sync to DB (fire and forget)
  }

  /// Clears notifications from memory AND from the DB for this user.
  /// Called when the user taps "Clear All" in the notification panel.
  void clearAll() {
    _notifications.clear();
    notifyListeners();
    _clearFromDb(); // delete from DB (fire and forget)
  }

  /// Clears only the in-memory list. DB history is NOT touched.
  /// Used internally when switching roles so history can be reloaded.
  void _clearMemory() {
    _notifications.clear();
    notifyListeners();
  }

  void _add(AppNotification notification) {
    // Deduplicate by id
    if (_notifications.any((n) => n.id == notification.id)) return;
    _notifications.add(notification);
    notifyListeners();
    _persistToDb(notification); // persist to DB (fire and forget)
  }

  // ── DB Persistence Helpers ────────────────────────────────────────────────

  /// Loads the last 50 notifications for the currently logged-in user from
  /// the DB and merges them into the in-memory list (dedup by notif_key).
  /// Called automatically at the start of every listenAs*() setup.
  Future<void> _loadFromDb() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final rows = await _supabase
          .from('notifications')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: true)
          .limit(50);
      for (final row in (rows as List)) {
        final notif = AppNotification(
          id: row['notif_key'] as String,
          title: row['title'] as String,
          body: row['body'] as String,
          orderId: row['order_id'] as String?,
          createdAt: DateTime.parse(row['created_at'] as String),
          isRead: row['is_read'] as bool,
        );
        if (!_notifications.any((n) => n.id == notif.id)) {
          _notifications.add(notif);
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load notifications from DB: $e');
    }
  }

  /// Persists a single notification to DB using upsert (safe on duplicates).
  Future<void> _persistToDb(AppNotification notif) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await _supabase.from('notifications').upsert({
        'user_id': userId,
        'notif_key': notif.id,
        'title': notif.title,
        'body': notif.body,
        if (notif.orderId != null) 'order_id': notif.orderId,
        'is_read': notif.isRead,
      }, onConflict: 'user_id,notif_key');
    } catch (e) {
      debugPrint('Failed to persist notification to DB: $e');
    }
  }

  /// Marks a single notification as read in the DB.
  Future<void> _markReadInDb(String notifKey) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', userId)
          .eq('notif_key', notifKey);
    } catch (e) {
      debugPrint('Failed to mark notification read in DB: $e');
    }
  }

  /// Marks all notifications as read in the DB for the current user.
  Future<void> _markAllReadInDb() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', userId)
          .eq('is_read', false);
    } catch (e) {
      debugPrint('Failed to mark all notifications read in DB: $e');
    }
  }

  /// Deletes all notifications from the DB for the current user.
  Future<void> _clearFromDb() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await _supabase
          .from('notifications')
          .delete()
          .eq('user_id', userId);
    } catch (e) {
      debugPrint('Failed to clear notifications from DB: $e');
    }
  }

  // ── Status message helpers ────────────────────────────────────────────────

  (String?, String?) _customerStatusMessage(String status, String? orderId) {
    switch (status) {
      case 'awaiting_payment':
        return (
          '✅ Shop & Rider Ready! Pay Now',
          'Both the shop and rider have accepted your order. Open the app to complete payment.'
        );
      case 'confirmed':
        return (
          '💳 Payment Confirmed!',
          'Your payment was captured. Shop is preparing your order.'
        );
      case 'preparing':
        return (
          '👨‍🍳 Order Being Prepared',
          'The shop is now preparing your order.'
        );
      case 'ready_for_pickup':
        return (
          '📦 Ready for Pickup',
          'Your order is packed and waiting for the rider.'
        );
      case 'picked_up':
        return ('🛵 Rider Picked Up', 'Your order is on its way!');
      case 'out_for_delivery':
        return (
          '🚀 Out for Delivery!',
          'Your order is almost there. Get ready!'
        );
      case 'delivered':
        return ('🎉 Order Delivered!', 'Your order has been delivered. Enjoy!');
      case 'cancelled':
        return ('❌ Order Cancelled', 'Your order has been cancelled. No payment was taken.');
      case 'seller_rejected':
        return ('😔 Order Rejected', 'The shop could not accept your order. No payment was taken.');
      default:
        return (null, null);
    }
  }

  (String?, String?) _sellerStatusMessage(String status, String? orderId) {
    switch (status) {
      case 'awaiting_payment':
        return (
          '⌛ Waiting for Customer Payment',
          'Both you and the rider accepted. Customer is completing payment now.'
        );
      case 'confirmed':
        return (
          '💳 Payment Done! Start Packing',
          'Customer payment captured. Pack the order now — rider is on the way!'
        );
      case 'cancelled':
        return ('❌ Order Cancelled', 'This order has been cancelled.');
      case 'picked_up':
        return (
          '✅ Order Picked Up',
          'The rider has collected the order from your shop.'
        );
      case 'delivered':
        return ('🎉 Order Delivered', 'The order was delivered successfully!');
      default:
        return (null, null);
    }
  }

  (String?, String?) _deliveryStatusMessage(String status, String? orderId) {
    switch (status) {
      case 'awaiting_payment':
        return (
          '⌛ Waiting for Customer Payment',
          'Customer is completing payment. Stand by — you will be confirmed shortly!'
        );
      case 'confirmed':
        return (
          '💳 Payment Done! Go Pick Up 🛵',
          'Customer paid. Head to the shop and pick up the order now!'
        );
      case 'cancelled':
        return (
          '❌ Order Cancelled',
          'The order you accepted has been cancelled.'
        );
      case 'preparing':
        return (
          '👨‍🍳 Shop Preparing',
          'The shop has started preparing the order. Head over!'
        );
      case 'ready_for_pickup':
        return (
          '📦 Ready for Pickup!',
          'The order is ready. Go pick it up now!'
        );
      default:
        return (null, null);
    }
  }

  // ── Edge Function Push Notification Helper ────────────────────────────────
  
  /// Invokes the `send-push` Edge Function to deliver a Firebase Cloud Message
  /// to the target user, so they get notified even when the app is closed.
  Future<void> sendBackgroundPush({
    required String targetUserId,
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    try {
      await _supabase.functions.invoke('send-push', body: {
        'user_id': targetUserId,
        'title': title,
        'body': body,
        if (data != null) 'data': data,
      });
    } catch (e) {
      debugPrint('Error sending background push: $e');
    }
  }

  /// Broadcasts a push notification to ALL devices registered under a given
  /// audience role. Use this instead of [sendBackgroundPush] when you need
  /// to reach every rider, seller, or customer.
  ///
  /// [audience] must be one of: `'All Users'`, `'Customers'`, `'Sellers'`, `'Riders'`
  Future<void> sendBroadcastToAudience({
    required String audience,
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    try {
      await _supabase.functions.invoke('send-broadcast', body: {
        'audience': audience,
        'title': title,
        'body': body,
        if (data != null) 'data': data,
      });
    } catch (e) {
      debugPrint('Error sending broadcast push [$audience]: $e');
    }
  }

  @override
  void dispose() {
    stopListening();
    super.dispose();
  }
}
