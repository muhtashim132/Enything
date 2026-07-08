import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_service.dart';
import '../services/bell_alert_service.dart';

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
  SupabaseClient get _supabase => Supabase.instance.client;

  final List<AppNotification> _notifications = [];
  RealtimeChannel? _channel;
  String? _listeningUserId;
  String? _listeningRole;
  
  StreamSubscription<String>? _fcmTokenSub;
  StreamSubscription<RemoteMessage>? _fcmMessageSub;

  final Map<String, String> _lastProcessedStatus = {};

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
      debugPrint('FCM token obtained: ${token == null ? "NULL - FAILED" : "${token.substring(0, 20)}..."}');
      if (token == null) return;

      final prefs = await SharedPreferences.getInstance();
      final cachedToken = prefs.getString('fcm_token_$userId');
      final cachedRole = prefs.getString('fcm_role_$userId');
      if (cachedToken == token && cachedRole == role) {
        debugPrint('FCM token and role unchanged, skipping DB upsert');
      } else {
        // ── SECURITY FIX: Delete stale cross-user tokens before registering ──
        // If another user was previously logged in on this device, their token
        // row may still exist in device_tokens with the SAME FCM token but a
        // DIFFERENT user_id. We must purge it first to prevent admin-role
        // notifications (e.g. KYC alerts) from leaking to this device.
        // The DB trigger `tr_enforce_single_token_per_device` handles this at
        // the DB level too — this is client-side defense-in-depth.
        try {
          await _supabase
              .from('device_tokens')
              .delete()
              .eq('token', token)
              .neq('user_id', userId);
          debugPrint('Purged stale cross-user tokens for FCM token on this device.');
        } catch (e) {
          debugPrint('Non-fatal: could not purge stale device tokens: $e');
        }

        // ── Retrieve or generate a stable device_id ─────────────────────────
        // We store a UUID in SharedPreferences on first launch. This gives us
        // a stable, device-scoped identifier that survives FCM token rotation
        // (FCM tokens can change on uninstall/reinstall; device_id does not).
        String? deviceId = prefs.getString('stable_device_id');
        if (deviceId == null) {
          deviceId = 'dev_${DateTime.now().millisecondsSinceEpoch}_${userId.substring(0, 8)}';
          await prefs.setString('stable_device_id', deviceId);
        }

        // Try upsert first, then plain insert as fallback
        final response = await _supabase.from('device_tokens').upsert({
          'user_id': userId,
          'token': token,
          'platform': Platform.isIOS ? 'ios' : 'android',
          'role': role,
          'device_id': deviceId,
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
            'device_id': deviceId,
          });
          debugPrint('FCM plain INSERT result: $insertRes');
        } else {
          debugPrint('FCM token confirmed saved in DB: ${check['id']}');
        }
        await prefs.setString('fcm_token_$userId', token);
        await prefs.setString('fcm_role_$userId', role);
      }

      // Listen for token refresh and re-register
      _fcmTokenSub?.cancel();
      _fcmTokenSub = messaging.onTokenRefresh.listen((newToken) async {
        final prefs = await SharedPreferences.getInstance();
        final deviceId = prefs.getString('stable_device_id');
        final currentRole = prefs.getString('fcm_role_$userId') ?? role;
        await _supabase.from('device_tokens').upsert({
          'user_id': userId,
          'token': newToken,
          'platform': Platform.isIOS ? 'ios' : 'android',
          'role': currentRole,
          'device_id': deviceId,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'user_id,token');
        await prefs.setString('fcm_token_$userId', newToken);
      });

      // Handle foreground FCM messages — show a heads-up buzz notification
      // identical to the behaviour when the app is closed/backgrounded.
      //
      // IMPORTANT: On Android, FCM does NOT display a system notification
      // when the app is in the foreground. We must manually show one using
      // flutter_local_notifications so sellers and riders get the same buzz
      // whether the app is open or not.
      //
      // Two sub-cases:
      //   1. notification+data message  → use notif.title/body for the buzz
      //   2. data-only message          → use message.data['title'/'body']
      _fcmMessageSub?.cancel();
      _fcmMessageSub = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        final notif = message.notification;

        // Resolve title/body from whichever field is present
        final title = notif?.title ?? message.data['title'] as String? ?? 'Enything';
        final body  = notif?.body  ?? message.data['body']  as String? ?? '';
        final orderId = message.data['order_id'] as String?;

        // Skip empty messages
        if (title.isEmpty && body.isEmpty) return;

        // ── In-app bell notification (dedup + DB persist via _add) ─────────────
        // For order-related FCM pushes: the Supabase Realtime path (_add) already
        // adds the in-app entry. Using _add() here as well is safe because _add()
        // deduplicates by id — the second call is a no-op.
        // For non-order pushes (broadcasts, admin messages): this is the only path.
        final fcmId = orderId != null
            ? '${orderId}_fcm_foreground' // stable dedup key per order
            : (message.messageId ?? DateTime.now().toIso8601String());

        _add(AppNotification(
          id: fcmId,
          title: title,
          body: body,
          orderId: orderId,
        ));

        // ── System heads-up buzz ────────────────────────────────────────────────
        // _add() already calls NotificationService().showNotification() internally,
        // so the buzz is triggered for every call above. Nothing extra needed here.
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
            final orderId = payload.newRecord['id'] as String?;
            
            final sellerAcceptedNow = payload.newRecord['seller_accepted'] == true;
            final sellerAcceptedBefore = payload.oldRecord['seller_accepted'] == true;

            final cartGroupId = payload.newRecord['cart_group_id'] as String?;

            // Notify customer when the shop accepts (one down, rider still needed)
            if (sellerAcceptedNow && !sellerAcceptedBefore && newStatus == 'awaiting_acceptance') {
              _add(AppNotification(
                id: '${orderId}_shop_accepted', // Keep per-order
                title: '🏪 Shop Accepted!',
                body: 'The shop accepted your order. Waiting for a rider now...',
                orderId: orderId,
              ));
            }

            if (orderId == null || newStatus == null) return;

            final lastStatus = _lastProcessedStatus[orderId];
            if (newStatus == lastStatus) return;
            _lastProcessedStatus[orderId] = newStatus;

            final (title, body) = _customerStatusMessage(newStatus, orderId);
            if (title != null) {
              // For statuses that happen to the whole group at once, deduplicate using cart_group_id
              final isGroupStatus = newStatus == 'confirmed' || 
                                    newStatus == 'out_for_delivery' || 
                                    newStatus == 'delivered' || 
                                    newStatus == 'cancelled';
              final notifId = (isGroupStatus && cartGroupId != null) 
                  ? '${cartGroupId}_$newStatus' 
                  : '${orderId}_$newStatus';

              _add(AppNotification(
                id: notifId,
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
            final cartGroupId = payload.newRecord['cart_group_id'] as String?;
            
            _add(AppNotification(
              id: cartGroupId != null ? '${cartGroupId}_placed' : '${orderId}_placed',
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
            final status = payload.newRecord['status'] as String?;
            
            if (status == 'awaiting_acceptance') {
              final amount =
                  (payload.newRecord['total_amount'] ?? 0.0).toDouble();
              _add(AppNotification(
                id: '${orderId}_new',
                title: '🔔 New Order!',
                body:
                    'You have a new order of ₹${amount.toStringAsFixed(0)} waiting for your acceptance.',
                orderId: orderId,
              ));
              // [BELL] Ring alert bell for new pending order
              if (orderId != null) BellAlertService.instance.addPendingOrder(orderId);
            }
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
            if (orderId == null || newStatus == null) return;

            // [BELL] Handle status progression (e.g., pending_verification -> awaiting_acceptance)
            if (newStatus == 'awaiting_acceptance' && oldStatus != 'awaiting_acceptance') {
              final amount = (payload.newRecord['total_amount'] ?? 0.0).toDouble();
              _add(AppNotification(
                id: '${orderId}_new',
                title: '🔔 New Order!',
                body: 'You have a new order of ₹${amount.toStringAsFixed(0)} waiting for your acceptance.',
                orderId: orderId,
              ));
              BellAlertService.instance.addPendingOrder(orderId);
            }

            // [BELL] Remove order from bell when seller accepts or order is resolved.
            // Checked BEFORE the status-dedup guard so seller_accepted change is caught
            // even when the status field itself hasn’t changed yet.
            final sellerAcceptedNow    = payload.newRecord['seller_accepted'] == true;
            final sellerAcceptedBefore = payload.oldRecord['seller_accepted'] == true;
            if ((sellerAcceptedNow && !sellerAcceptedBefore) ||
                const [
                  'verification_failed', 'payment_failed', 'awaiting_payment', 
                  'confirmed', 'cancelled', 'seller_rejected', 'delivered'
                ].contains(newStatus)) {
              BellAlertService.instance.removePendingOrder(orderId);
            }

            final lastStatus = _lastProcessedStatus[orderId];
            if (newStatus == lastStatus) return;
            _lastProcessedStatus[orderId] = newStatus;

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
    // [BELL] Re-ring bell if there are already pending orders (e.g. app restart)
    _initBellForPendingSeller(shopId);
  }

  /// Seller: watches orders for MULTIPLE shops at once.
  void listenAsSellerMultiShop(List<String> shopIds) {
    if (shopIds.isEmpty) return;
    
    // Create a deterministic key for the channel and checking if already listening
    final sortedIds = List<String>.from(shopIds)..sort();
    final listeningKey = sortedIds.join('-');
    
    if (_listeningUserId == listeningKey && _listeningRole == 'seller') return;
    stopListening();
    _listeningUserId = listeningKey;
    _listeningRole = 'seller';

    var chan = _supabase.channel('notif-seller-$listeningKey');
    
    for (final shopId in shopIds) {
      chan = chan.onPostgresChanges(
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
          final status = payload.newRecord['status'] as String?;

          if (status == 'awaiting_acceptance') {
            final amount =
                (payload.newRecord['total_amount'] ?? 0.0).toDouble();
            _add(AppNotification(
              id: '${orderId}_new',
              title: '🔔 New Order!',
              body:
                  'You have a new order of ₹${amount.toStringAsFixed(0)} waiting for your acceptance.',
              orderId: orderId,
            ));
            // [BELL] Ring alert bell for new pending order
            if (orderId != null) BellAlertService.instance.addPendingOrder(orderId);
          }
        },
      ).onPostgresChanges(
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
          if (orderId == null || newStatus == null) return;

          // [BELL] Handle status progression (e.g., pending_verification -> awaiting_acceptance)
          if (newStatus == 'awaiting_acceptance' && oldStatus != 'awaiting_acceptance') {
            final amount = (payload.newRecord['total_amount'] ?? 0.0).toDouble();
            _add(AppNotification(
              id: '${orderId}_new',
              title: '🔔 New Order!',
              body: 'You have a new order of ₹${amount.toStringAsFixed(0)} waiting for your acceptance.',
              orderId: orderId,
            ));
            BellAlertService.instance.addPendingOrder(orderId);
          }

          // [BELL] Remove order from bell when seller accepts or order is resolved.
          final sellerAcceptedNow    = payload.newRecord['seller_accepted'] == true;
          final sellerAcceptedBefore = payload.oldRecord['seller_accepted'] == true;
          if ((sellerAcceptedNow && !sellerAcceptedBefore) ||
              const [
                'verification_failed', 'payment_failed', 'awaiting_payment', 
                'confirmed', 'cancelled', 'seller_rejected', 'delivered'
              ].contains(newStatus)) {
            BellAlertService.instance.removePendingOrder(orderId);
          }

          final lastStatus = _lastProcessedStatus[orderId];
          if (newStatus == lastStatus) return;
          _lastProcessedStatus[orderId] = newStatus;

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
      );
    }
    
    _channel = chan.subscribe();

    // Restore persisted notification history for this user
    _loadFromDb();
    // [BELL] Re-ring bell if there are already pending orders (e.g. app restart)
    _initBellForPendingSellerMulti(shopIds);
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

            final orderId = newRecord['id'] as String?;
            final newStatus = newRecord['status'] as String?;
            final newPartnerId = newRecord['delivery_partner_id'] as String?;

            if (orderId == null || newStatus == null) return;
            
            // Check if the order was reassigned to someone else
            if (newPartnerId != null && newPartnerId != partnerId) {
              BellAlertService.instance.removePendingOrder(orderId);
              return;
            }

            // [BELL] Ring bell when payment confirmed (rider must go pick up).
            // Stop when rider picks up, order is cancelled, delivered, or any other terminal/waiting state.
            if (newStatus == 'confirmed') {
              BellAlertService.instance.addPendingOrder(orderId);
            } else if (!const ['confirmed', 'preparing', 'ready_for_pickup'].contains(newStatus)) {
              BellAlertService.instance.removePendingOrder(orderId);
            }

            final lastStatus = _lastProcessedStatus[orderId];
            if (newStatus == lastStatus) return;
            _lastProcessedStatus[orderId] = newStatus;

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
    // [BELL] Re-ring bell if rider already has confirmed orders pending pickup
    _initBellForPendingRider(partnerId);
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

    // [BELL] Stop and clear all pending order bells on role switch / logout
    BellAlertService.instance.clearAll();

    // NOTE: FCM subscriptions (_fcmTokenSub and _fcmMessageSub) are intentionally
    // NOT cancelled here. They are user-session-level (not role-level) and must
    // persist across role switches (e.g. customer → seller → delivery).
    // They are only cancelled on full logout via clearFcmSubs().

    _listeningUserId = null;
    _listeningRole = null;
    _lastProcessedStatus.clear();
    _clearMemory(); // Clear RAM only — DB history is preserved per user
  }

  /// Called on user logout to fully tear down all subscriptions including FCM.
  Future<void> clearFcmSubs() async {
    _fcmTokenSub?.cancel();
    _fcmTokenSub = null;
    _fcmMessageSub?.cancel();
    _fcmMessageSub = null;
    
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('fcm_token_$userId');
      if (token != null) {
        await _supabase
            .from('device_tokens')
            .delete()
            .eq('token', token)
            .eq('user_id', userId);
        await prefs.remove('fcm_token_$userId');
        debugPrint('Deleted FCM token on logout for user: $userId');
      }
    } catch (e) {
      debugPrint('Error deleting FCM token on logout: $e');
    }
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
    
    // Buzz notification in the foreground!
    NotificationService().showNotification(
      title: notification.title,
      body: notification.body,
      payload: jsonEncode({
        if (notification.orderId != null) 'order_id': notification.orderId,
        if (_listeningRole != null) 'role': _listeningRole,
      }),
    );

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
      for (final row in rows) {
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

  // ── Bell Initialization (restore pending orders on app restart) ────────────────────

  /// Query DB for seller orders that are still awaiting acceptance.
  /// Called when the seller subscribes so the bell re-rings after app restart.
  Future<void> _initBellForPendingSeller(String shopId) async {
    try {
      final rows = await _supabase
          .from('orders')
          .select('id')
          .eq('shop_id', shopId)
          .eq('seller_accepted', false)
          .inFilter('status', ['awaiting_acceptance']);
      for (final row in rows) {
        final orderId = row['id'] as String?;
        if (orderId != null) BellAlertService.instance.addPendingOrder(orderId);
      }
    } catch (e) {
      debugPrint('[NotifProvider] _initBellForPendingSeller: $e');
    }
  }

  /// Same as above for sellers with multiple shops.
  Future<void> _initBellForPendingSellerMulti(List<String> shopIds) async {
    if (shopIds.isEmpty) return;
    try {
      final rows = await _supabase
          .from('orders')
          .select('id')
          .inFilter('shop_id', shopIds)
          .eq('seller_accepted', false)
          .inFilter('status', ['awaiting_acceptance']);
      for (final row in rows) {
        final orderId = row['id'] as String?;
        if (orderId != null) BellAlertService.instance.addPendingOrder(orderId);
      }
    } catch (e) {
      debugPrint('[NotifProvider] _initBellForPendingSellerMulti: $e');
    }
  }

  /// Query DB for rider orders in 'confirmed' status (payment done, pick-up needed).
  /// Called when the rider subscribes so the bell re-rings after app restart.
  Future<void> _initBellForPendingRider(String partnerId) async {
    try {
      final rows = await _supabase
          .from('orders')
          .select('id')
          .eq('delivery_partner_id', partnerId)
          .inFilter('status', ['confirmed', 'preparing', 'ready_for_pickup']);
      for (final row in rows) {
        final orderId = row['id'] as String?;
        if (orderId != null) BellAlertService.instance.addPendingOrder(orderId);
      }
    } catch (e) {
      debugPrint('[NotifProvider] _initBellForPendingRider: $e');
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
      case 'verification_failed':
        return (
          '🚫 Prescription Rejected',
          'Your prescription was rejected by the admin. The order has been cancelled.'
        );
      case 'payment_failed':
        return (
          '❌ Payment Failed',
          'Your payment could not be processed. Please try again.'
        );
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
  Future<String?> sendBackgroundPush({
    required String targetUserId,
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    try {
      final res = await _supabase.functions.invoke('send-push', body: {
        'user_id': targetUserId,
        'title': title,
        'body': body,
        if (data != null) 'data': data,
      });
      if (res.status != 200) return 'Push failed: ${res.status}';
      return null;
    } catch (e) {
      debugPrint('Error sending background push: $e');
      return 'Failed to send notification';
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
