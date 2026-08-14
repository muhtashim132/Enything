import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:uuid/uuid.dart';
import '../models/user_model.dart';
import '../main.dart';
import '../services/rider_background_service.dart';
import '../services/bell_alert_service.dart';
import 'package:provider/provider.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'cart_provider.dart';
import 'favorites_provider.dart';
import 'location_provider.dart';
import 'coupon_provider.dart';
import 'referral_provider.dart';
import 'recently_viewed_provider.dart';
import 'notification_provider.dart';

class AuthProvider extends ChangeNotifier {
  bool _isDisposed = false;

  void safeNotifyListeners() {
    if (!_isDisposed) notifyListeners();
  }

  SupabaseClient get _supabase => Supabase.instance.client;
  UserModel? _user;
  bool _isLoading = false;
  bool _isProfileFetched = false;
  String? _error;
  String? _pendingPhone; // Phone waiting for OTP verification
  String? _mockUserId; // ID used for magic numbers
  bool _isManualSignOut = false;
  bool _isHandlingForcedLogout = false;

  // ─── Single Device Session State ──────────────────────────────────────────
  String? _localSessionId;
  RealtimeChannel? _sessionRealtimeChannel;

  // ─── Admin (God Mode) State ───────────────────────────────────────────────
  bool _isAdminVerified = false; // true after 2nd-factor password gate
  Map<String, dynamic>? _adminData; // row from admin_users table
  String? _currentSessionId; // ID of the active admin_sessions row

  UserModel? get user => _user;
  bool get isLoading => _isLoading;
  bool get isProfileFetched => _isProfileFetched;
  String? get error => _error;
  bool get isAuthenticated => _user != null;
  String? get currentUserId => _supabase.auth.currentUser?.id ?? _mockUserId;
  String? get pendingPhone => _pendingPhone;
  String? get localSessionId => _localSessionId;

  bool get isAdminVerified => _isAdminVerified;
  bool get isAdmin => _adminData != null;
  String? get currentSessionId => _currentSessionId;
  Map<String, dynamic>? get adminData => _adminData;
  String get adminLevel => _adminData?['admin_level'] as String? ?? '';
  Map<String, dynamic> get adminPermissions =>
      Map<String, dynamic>.from(_adminData?['permissions'] as Map? ?? {});
  @Deprecated('Use RbacProvider.can instead')
  bool adminCan(String permission) =>
      adminPermissions[permission] == true || adminLevel == 'superadmin';

  AuthProvider() {
    _init();
  }

  StreamSubscription<AuthState>? _authSubscription;

  void _init() {
    _authSubscription = _supabase.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.signedIn) {
        _fetchProfile();
      } else if (event.event == AuthChangeEvent.signedOut) {
        // Auto-deactivate shop/rider for FORCED logouts (session revoked from another device).
        // Manual signOut() already deactivated before this event fires, so skip to avoid double-write.
        if (!_isManualSignOut) {
          final userId = _supabase.auth.currentUser?.id ?? _mockUserId;
          final role = _user?.activeSessionRole;
          if (userId != null) {
            if (role == 'seller') {
              _supabase
                  .from('shops')
                  .update({'is_accepting_orders': false})
                  .eq('seller_id', userId)
                  .then((_) {})
                  .catchError((_) {});
            } else if (role == 'delivery_partner') {
              _supabase
                  .from('delivery_partners')
                  .update({'is_accepting_orders': false})
                  .eq('id', userId)
                  .then((_) {})
                  .catchError((_) {});
            }
          }
        }

        bool wasManual = _isManualSignOut;
        _isManualSignOut = false; // Reset

        _user = null;
        _mockUserId = null;
        _pendingPhone = null;
        _isProfileFetched = false;

        // Ensure sticky background service stops if OS restarted it
        RiderBackgroundService.instance.stopService();

        // C1 FIX: Clear cart from shared preferences on logout to prevent dirty state
        SharedPreferences.getInstance().then((prefs) {
          prefs.remove('enything_cart_v2');
          prefs.remove('enything_cart_v1');
        });

        safeNotifyListeners();

        // If it wasn't a manual sign out, it means the session was revoked from another device
        if (!wasManual && navigatorKey.currentState != null) {
          // FIX BUG-12: Wrong route '/roleSelect' doesn't match AppRoutes.roleSelect = '/auth/role'
          navigatorKey.currentState!
              .pushNamedAndRemoveUntil('/auth/role', (route) => false);

          final context = navigatorKey.currentContext;
          if (context != null) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'You have been logged out because your account was accessed from another device.'),
                backgroundColor: Colors.redAccent,
                duration: Duration(seconds: 4),
              ),
            );
          }
        }
      }
    });
    if (_supabase.auth.currentUser != null) {
      _fetchProfile();
    }
  }

  void retryProfileFetch() {
    _fetchProfile();
  }

  // ─── Single Device Session Engine ─────────────────────────────────────────

  /// Generates and records a new active session for [userId], purging older
  /// device tokens and invalidating remote sessions on other phones.
  Future<void> _establishActiveSession(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final newSessionId = const Uuid().v4();
      _localSessionId = newSessionId;
      await prefs.setString('local_session_id', newSessionId);

      // Get or generate stable_device_id
      String? deviceId = prefs.getString('stable_device_id');
      if (deviceId == null) {
        deviceId =
            'dev_${DateTime.now().millisecondsSinceEpoch}_${userId.substring(0, 8)}';
        await prefs.setString('stable_device_id', deviceId);
      }

      // Enforce single device in DB via atomic RPC
      try {
        await _supabase.rpc('enforce_single_device_login', params: {
          'p_user_id': userId,
          'p_session_id': newSessionId,
          'p_device_id': deviceId,
        });
      } catch (rpcErr) {
        debugPrint('enforce_single_device_login RPC fallback: $rpcErr');
        await _supabase.from('profiles').update({
          'current_session_id': newSessionId,
          'current_device_id': deviceId,
          'session_created_at': DateTime.now().toIso8601String(),
        }).eq('id', userId);

        if (deviceId.isNotEmpty) {
          try {
            await _supabase
                .from('device_tokens')
                .delete()
                .eq('user_id', userId)
                .neq('device_id', deviceId);
          } catch (_) {}
        }
      }

      // Invalidate other refresh tokens on Supabase Auth
      try {
        await _supabase.auth.signOut(scope: SignOutScope.others);
      } catch (_) {}

      // Start listening to real-time session updates
      _listenToSessionStream(userId);
    } catch (e) {
      debugPrint('Error establishing active session: $e');
    }
  }

  /// Subscribes to real-time session changes on the user's profile row.
  /// If another device logs in, an UPDATE event triggers immediate logout.
  void _listenToSessionStream(String userId) {
    try {
      _sessionRealtimeChannel?.unsubscribe();
      _sessionRealtimeChannel = null;
    } catch (_) {}

    try {
      _sessionRealtimeChannel = _supabase
          .channel('profile-session-$userId')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'profiles',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: userId,
            ),
            callback: (payload) {
              final newRecord = payload.newRecord;
              final incomingSessionId =
                  newRecord['current_session_id'] as String?;
              if (incomingSessionId != null &&
                  _localSessionId != null &&
                  incomingSessionId != _localSessionId) {
                debugPrint(
                    '[SingleDeviceAuth] Remote login detected on another device! Local: $_localSessionId vs DB: $incomingSessionId');
                handleRemoteForcedLogout(
                  message:
                      'You have been logged out because your account was logged in on another device.',
                );
              }
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('Failed to subscribe to session realtime stream: $e');
    }
  }

  /// Handles forced logout when this device's session is superseded by another device.
  Future<void> handleRemoteForcedLogout({String? message}) async {
    if (_isHandlingForcedLogout) return;
    _isHandlingForcedLogout = true;

    debugPrint(
        '[SingleDeviceAuth] Executing remote forced logout for user ${currentUserId ?? "unknown"}');

    // 1. Auto-deactivate shop or delivery partner duty
    final userId = _supabase.auth.currentUser?.id ?? _mockUserId;
    final role = _user?.activeSessionRole;
    if (userId != null) {
      try {
        if (role == 'seller') {
          await _supabase
              .from('shops')
              .update({'is_accepting_orders': false}).eq('seller_id', userId);
        } else if (role == 'delivery_partner') {
          await _supabase
              .from('delivery_partners')
              .update({'is_accepting_orders': false}).eq('id', userId);
        }
      } catch (_) {}
    }

    // 2. Stop rider background tracking & alert bell immediately
    try {
      RiderBackgroundService.instance.stopService();
    } catch (_) {}
    try {
      BellAlertService.instance.clearAll();
    } catch (_) {}

    // 3. Unsubscribe from session stream
    try {
      _sessionRealtimeChannel?.unsubscribe();
      _sessionRealtimeChannel = null;
    } catch (_) {}

    // 4. Clear SharedPreferences session keys
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('local_session_id');
      await prefs.remove('last_active_role');
      await prefs.remove('admin_session_id');
      await prefs.remove('enything_cart_v2');
      await prefs.remove('enything_cart_v1');
      await prefs.remove('cart_v2');
      await prefs.remove('cart_items');
      await prefs.remove('recently_viewed');
      await prefs.remove('favorite_shops');
      await prefs.remove('favorite_products');
    } catch (_) {}

    // 5. Clear in-memory state
    _user = null;
    _localSessionId = null;
    _mockUserId = null;
    _pendingPhone = null;
    _isAdminVerified = false;
    _adminData = null;
    _isProfileFetched = false;

    // 6. Sign out locally & cancel all active notification banners/sounds
    try {
      await _supabase.auth.signOut(scope: SignOutScope.local);
    } catch (_) {}
    try {
      await FlutterLocalNotificationsPlugin().cancelAll();
    } catch (_) {}
    try {
      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null) {
        await _supabase
            .from('device_tokens')
            .delete()
            .eq('token', fcmToken);
      }
    } catch (_) {}

    // 7. Clear context providers if mounted
    try {
      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        context.read<CartProvider>().clear();
        context.read<FavoritesProvider>().clear();
        context.read<LocationProvider>().clear();
        context.read<CouponProvider>().clearCoupon();
        context.read<ReferralProvider>().reset();
        context.read<RecentlyViewedProvider>().clear();
        final notifProvider = context.read<NotificationProvider>();
        notifProvider.stopListening();
        notifProvider.clearFcmSubs();
      }
    } catch (_) {}

    safeNotifyListeners();

    // 8. Navigate to role selection and display clear warning
    if (navigatorKey.currentState != null) {
      navigatorKey.currentState!
          .pushNamedAndRemoveUntil('/auth/role', (route) => false);

      final msg = message ??
          'You have been logged out because your account was logged in on another device.';
      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.devices_other, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    msg,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.redAccent.shade700,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }

    _isHandlingForcedLogout = false;
  }

  /// Validates if the local session matches the active database session.
  /// Returns false if invalidated (and triggers forced logout).
  Future<bool> validateActiveSession() async {
    final userId = _supabase.auth.currentUser?.id ?? _mockUserId;
    if (userId == null) return true;

    // Load local session ID from SharedPreferences if not in memory
    if (_localSessionId == null) {
      final prefs = await SharedPreferences.getInstance();
      _localSessionId = prefs.getString('local_session_id');
    }

    if (_localSessionId == null) return true;

    try {
      final row = await _supabase
          .from('profiles')
          .select('current_session_id')
          .eq('id', userId)
          .maybeSingle();

      final dbSessionId = row?['current_session_id'] as String?;
      if (dbSessionId != null &&
          dbSessionId.isNotEmpty &&
          dbSessionId != _localSessionId) {
        debugPrint(
            '[SingleDeviceAuth] Validation check failed: DB session ($dbSessionId) != local ($_localSessionId). Logging out.');
        await handleRemoteForcedLogout();
        return false;
      }
    } catch (e) {
      debugPrint('Error validating active session: $e');
    }
    return true;
  }

  // ─── Detect all roles for a given userId ────────────────────────────────
  /// Returns list of roles the user has already signed up for.
  Future<List<String>> _detectUserRoles(String userId) async {
    final roles = <String>[];
    try {
      final customer = await _supabase
          .from('customers')
          .select('id')
          .eq('id', userId)
          .maybeSingle();
      if (customer != null) roles.add('customer');
    } catch (e) {
      debugPrint('_detectUserRoles[customers] error: $e');
    }

    try {
      final seller = await _supabase
          .from('shops')
          .select('seller_id')
          .eq('seller_id', userId)
          .limit(1)
          .maybeSingle();
      if (seller != null) roles.add('seller');
    } catch (e) {
      debugPrint('_detectUserRoles[shops] error: $e');
    }

    try {
      final delivery = await _supabase
          .from('delivery_partners')
          .select('id')
          .eq('id', userId)
          .maybeSingle();
      if (delivery != null) roles.add('delivery_partner');
    } catch (e) {
      debugPrint('_detectUserRoles[delivery_partners] error: $e');
    }

    // ── Admin detection ──────────────────────────────────────────────────
    try {
      final admin = await _supabase
          .from('admin_users')
          .select('id, admin_level, is_active')
          .eq('id', userId)
          .eq('is_active', true)
          .maybeSingle();
      if (admin != null) {
        roles.add('admin');
        _adminData = Map<String, dynamic>.from(admin);
      }
    } catch (e) {
      debugPrint('Admin Check Error: $e');
    }

    return roles;
  }

  // ─── Admin 2nd-Factor Password Verification ──────────────────────────────
  /// Called from AdminPasswordPage after OTP succeeds.
  /// Returns true if the supplied [password] matches the stored admin_password.
  Future<bool> verifyAdminPassword(String password) async {
    final userId = currentUserId;
    if (userId == null || _adminData == null) return false;

    try {
      bool isVerified = false;
      try {
        final res = await _supabase.rpc(
          'verify_admin_password',
          params: {'p_admin_id': userId, 'p_password': password.trim()},
        );
        isVerified = res == true;
      } catch (rpcError) {
        // B4: Security fix — do NOT fall back to plaintext DB comparison.
        // If the RPC is unavailable, fail closed (deny access) rather than
        // fall open (compare plaintext). Log the RPC error for investigation.
        debugPrint('verify_admin_password RPC failed: $rpcError');
        return false;
      }

      if (isVerified) {
        _isAdminVerified = true;

        // ── Create admin session ──
        try {
          final sessionData = await _supabase
              .from('admin_sessions')
              .insert({
                'admin_id': userId,
                'device_info':
                    'Enything Admin App', // You can use device_info package later
              })
              .select('id')
              .single();

          _currentSessionId = sessionData['id'];
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('admin_session_id', _currentSessionId!);
        } catch (e) {
          debugPrint('Failed to create admin session: $e');
        }

        safeNotifyListeners();

        // Audit log: record login
        try {
          await _supabase.from('audit_logs').insert({
            'actor_id': userId,
            'actor_role': 'admin',
            'action': 'admin_login',
            'entity_type': 'system',
            'metadata': {'timestamp': DateTime.now().toIso8601String()},
          });
          await _supabase
              .from('admin_users')
              .update({'last_login_at': DateTime.now().toIso8601String()}).eq(
                  'id', userId);
        } catch (_) {}

        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Admin password verification error: $e');
      return false;
    }
  }

  /// Log an admin action to the activity log.
  @Deprecated('Use AuditProvider.log instead')
  Future<void> logAdminAction(
    String action, {
    String? targetType,
    String? targetId,
    Map<String, dynamic>? details,
  }) async {
    final userId = currentUserId;
    if (userId == null || !_isAdminVerified) return;
    try {
      await _supabase.from('audit_logs').insert({
        'actor_id': userId,
        'actor_role': 'admin',
        'action': action,
        if (targetType != null) 'entity_type': targetType,
        if (targetId != null) 'entity_id': targetId,
        'metadata': details ?? {},
      });
    } catch (_) {}
  }

  /// Clear admin verification (e.g. session timeout or explicit sign-out).
  void adminSignOut() {
    _isAdminVerified = false;
    _adminData = null;
    safeNotifyListeners();
  }

  /// Switch from admin mode into another role the user already holds
  /// (e.g. customer, seller, delivery_partner) WITHOUT ending the Supabase
  /// auth session. Clears admin verification flag and sets the new session role.
  /// Used by the "Switch Role" button in the Admin Dashboard header.
  Future<void> switchFromAdminToRole(String role) async {
    if (_user == null) return;
    if (!_user!.activeRoles.contains(role)) return;
    // Drop admin mode — no 2FA required for the new non-admin role
    _isAdminVerified = false;
    _adminData = null;
    // Reuse existing switchSessionRole to set role + persist to SharedPreferences
    await switchSessionRole(role);
  }

  Future<void> _fetchProfile({String? preferredRole}) async {
    try {
      final userId = _supabase.auth.currentUser?.id ?? _mockUserId;
      if (userId == null) {
        _isProfileFetched = true;
        safeNotifyListeners();
        return;
      }

      // Detect all roles across role-specific tables FIRST
      final allRoles = await _detectUserRoles(userId);

      Map<String, dynamic>? data;
      try {
        final response =
            await _supabase.from('profiles').select().eq('id', userId).single();
        data = Map<String, dynamic>.from(response);
      } catch (e) {
        // If profile doesn't exist, check if they are a real admin
        if (allRoles.contains('admin')) {
          data = {
            'id': userId,
            'full_name': 'Admin User',
            'phone': _supabase.auth.currentUser?.phone ?? _pendingPhone ?? '',
            'role': 'admin'
          };
        } else {
          // User verified OTP but never completed profile setup!
          _user = null;
          _isProfileFetched = true;
          safeNotifyListeners();
          return;
        }
      }

      if (!data.containsKey('full_name') && data.containsKey('name')) {
        data['full_name'] = data['name'];
      }

      // Always include the primary profile role
      final primaryRole = data['role'] ?? 'customer';
      if (!allRoles.contains(primaryRole)) {
        allRoles.add(primaryRole);
      }

      // Load last active role from SharedPreferences to persist role switching across reboots
      final prefs = await SharedPreferences.getInstance();
      final lastActiveRole = prefs.getString('last_active_role');

      String? targetRole = preferredRole;
      if (targetRole == null &&
          lastActiveRole != null &&
          allRoles.contains(lastActiveRole)) {
        targetRole = lastActiveRole;
      }

      // Prefer the requested/saved role if valid, otherwise use primary
      final sessionRole = (targetRole != null && allRoles.contains(targetRole))
          ? targetRole
          : primaryRole;

      // Save it immediately so it's fresh
      await prefs.setString('last_active_role', sessionRole);

      // ── Detect verification status for the session role ──

      // If active role is admin, check if session is revoked
      if (sessionRole == 'admin' && _isAdminVerified) {
        final savedSessionId = prefs.getString('admin_session_id');
        if (savedSessionId != null) {
          try {
            final sessionRow = await _supabase
                .from('admin_sessions')
                .select('revoked_at')
                .eq('id', savedSessionId)
                .maybeSingle();
            if (sessionRow == null || sessionRow['revoked_at'] != null) {
              // Session was revoked remotely! Kick them out completely.
              debugPrint('Admin session was revoked remotely.');
              await signOut();
              return;
            } else {
              _currentSessionId = savedSessionId;
              // Update last seen
              _supabase
                  .from('admin_sessions')
                  .update({'last_seen_at': DateTime.now().toIso8601String()})
                  .eq('id', savedSessionId)
                  .then((_) {})
                  .catchError((_) {});
            }
          } catch (e) {
            debugPrint('Error checking admin session: $e');
          }
        }
      }

      String verificationStatus = 'verified'; // Default for customer
      String sellerVerificationStatus = 'unverified';
      String riderVerificationStatus = 'unverified';

      if (allRoles.contains('seller')) {
        final sellerData = await _supabase
            .from('shops')
            .select('verification_status')
            .eq('seller_id', userId)
            .limit(1)
            .maybeSingle();
        sellerVerificationStatus =
            sellerData?['verification_status'] ?? 'unverified';
        if (sessionRole == 'seller') {
          verificationStatus = sellerVerificationStatus;
        }
      }
      if (allRoles.contains('delivery_partner')) {
        final deliveryData = await _supabase
            .from('delivery_partners')
            .select('verification_status')
            .eq('id', userId)
            .maybeSingle();
        riderVerificationStatus =
            deliveryData?['verification_status'] ?? 'unverified';
        if (sessionRole == 'delivery_partner') {
          verificationStatus = riderVerificationStatus;
        }
      }

      _user = UserModel.fromMap({
        ...data,
        'email': _supabase.auth.currentUser?.email ?? '',
        'phone': (_supabase.auth.currentUser?.email?.contains('9999999996') ==
                true)
            ? '+919999999996'
            : (_supabase.auth.currentUser?.email?.contains('9999999997') ==
                    true)
                ? '+919999999997'
                : (_supabase.auth.currentUser?.email?.contains('9999999998') ==
                        true)
                    ? '+919999999998'
                    : (_supabase.auth.currentUser?.phone?.isNotEmpty == true)
                        ? _supabase.auth.currentUser!.phone!
                        : (data['phone'] ?? ''),
        'activeRoles': allRoles,
        'activeSessionRole': sessionRole,
        'verification_status': verificationStatus,
        'seller_verification_status': sellerVerificationStatus,
        'rider_verification_status': riderVerificationStatus,
      });

      // ── Single Device Session Tracking ──
      _localSessionId ??= prefs.getString('local_session_id');
      if (_localSessionId == null) {
        final dbSession = data['current_session_id'] as String?;
        if (dbSession != null && dbSession.isNotEmpty) {
          _localSessionId = dbSession;
          await prefs.setString('local_session_id', dbSession);
        } else {
          await _establishActiveSession(userId);
        }
      }
      _listenToSessionStream(userId);

      _isProfileFetched = true;
      safeNotifyListeners();
    } catch (e) {
      debugPrint('Profile fetch error: $e');
      _isProfileFetched = true;
      safeNotifyListeners();
    }
  }

  /// Switch the active session role (user must already be registered for that role).
  Future<void> switchSessionRole(String role) async {
    if (_user == null) return;
    if (!_user!.activeRoles.contains(role)) return;

    // Auto-deactivate delivery toggle when switching away from rider role
    if (_user!.activeSessionRole == 'delivery_partner' &&
        role != 'delivery_partner') {
      try {
        await _supabase
            .from('delivery_partners')
            .update({'is_accepting_orders': false}).eq('id', _user!.id);
        RiderBackgroundService.instance.stopService();
      } catch (e) {
        debugPrint('Failed to deactivate delivery partner: $e');
      }
    }

    // Auto-deactivate shop accepting orders when switching away from seller role
    if (_user!.activeSessionRole == 'seller' && role != 'seller') {
      try {
        await _supabase
            .from('shops')
            .update({'is_accepting_orders': false}).eq('seller_id', _user!.id);
      } catch (e) {
        debugPrint('Failed to deactivate seller orders: $e');
      }
    }

    String verificationStatus = 'verified'; // Default
    try {
      if (role == 'seller') {
        final sellerData = await _supabase
            .from('shops')
            .select('verification_status')
            .eq('seller_id', _user!.id)
            .limit(1)
            .maybeSingle();
        verificationStatus = sellerData?['verification_status'] ?? 'unverified';
      } else if (role == 'delivery_partner') {
        final deliveryData = await _supabase
            .from('delivery_partners')
            .select('verification_status')
            .eq('id', _user!.id)
            .maybeSingle();
        verificationStatus =
            deliveryData?['verification_status'] ?? 'unverified';
      }
    } catch (e) {
      debugPrint('Error fetching verification status on role switch: $e');
    }

    _user = _user!.copyWith(
        activeSessionRole: role, verificationStatus: verificationStatus);

    // Persist the switched role so it survives an app restart
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_active_role', role);

    safeNotifyListeners();
  }

  // ─── OTP Auth (Phone) via Supabase Edge Functions + Fast2SMS ───────────

  /// Derives a stable email+password pair from a phone number so we can
  /// create a real Supabase Auth session after OTP verification.
  String _emailFromPhone(String phone) {
    if (phone.endsWith('9999999996')) return 'mock919999999996@enything.com';
    if (phone.endsWith('9999999997')) return 'mock919999999997@enything.com';
    if (phone.endsWith('9999999998')) return 'mock919999999998@enything.com';
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    return '$digits@auth.enything.app';
  }

  String _legacyPasswordFromPhone(String phone) {
    if (phone.endsWith('9999999996') ||
        phone.endsWith('9999999997') ||
        phone.endsWith('9999999998')) {
      return 'Dummy123';
    }
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    return 'Enything$digits#Auth2025';
  }

  String _passwordFromPhone(String phone) {
    if (phone.endsWith('9999999996') ||
        phone.endsWith('9999999997') ||
        phone.endsWith('9999999998')) {
      return 'Dummy123';
    }
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final bytes = utf8.encode('Enything_${digits}_Secured#2026');
    final digest = sha256.convert(bytes);
    return 'EnY\$${digest.toString().substring(0, 16)}';
  }

  // S4 FIX: Magic test numbers are ONLY active in debug builds EXCEPT for reviewer numbers.
  bool _isMagicNumber(String phone) {
    if (phone.endsWith('9999999996') ||
        phone.endsWith('9999999997') ||
        phone.endsWith('9999999998')) {
      return true;
    }
    if (!kDebugMode) return false;
    return phone.endsWith('9999999991') ||
        phone.endsWith('9999999992') ||
        phone.endsWith('9999999993') ||
        phone.endsWith('9999999994') ||
        phone.endsWith('9999999995');
  }

  /// Step 1: Send OTP via the `send-otp` Supabase Edge Function (Fast2SMS).
  Future<String?> sendPhoneOtp(String phone) async {
    if (_isLoading) return null;
    _isLoading = true;
    _error = null;
    safeNotifyListeners();

    // ── Magic number bypass for internal testing ──────────────────────────
    if (_isMagicNumber(phone)) {
      _pendingPhone = phone;
      _isLoading = false;
      safeNotifyListeners();
      return null;
    }

    try {
      final response = await _supabase.functions.invoke(
        'send-otp',
        body: {'phone': phone},
      );

      if (response.status != 200) {
        final data = response.data;
        _error = (data is Map ? data['error'] as String? : null) ??
            'Failed to send OTP. Please try again.';
        _isLoading = false;
        safeNotifyListeners();
        return _error;
      }

      _pendingPhone = phone;
      _isLoading = false;
      safeNotifyListeners();
      return null; // null = success
    } on FunctionException catch (e) {
      final data = e.details;
      _error = (data is Map ? data['error'] as String? : null) ??
          'Failed to send OTP: ${e.reasonPhrase ?? "Unknown error"}';
      debugPrint('sendPhoneOtp FunctionException: $e');
    } catch (e) {
      final errorStr = e.toString();
      if (errorStr.contains('SocketException') ||
          errorStr.contains('Failed host lookup') ||
          errorStr.contains('ClientException')) {
        _error =
            'No internet connection. Please check your network and try again.';
      } else {
        _error = 'Could not send OTP: $errorStr';
      }
      debugPrint('sendPhoneOtp error: $e');
    }
    _isLoading = false;
    safeNotifyListeners();
    return _error;
  }

  /// Step 2: Verify OTP via the `verify-otp` Edge Function, then create
  /// or sign in to the Supabase Auth session using a phone-derived credential.
  ///
  /// Returns:
  ///   'existing' — user has a profile (may have multiple roles)
  ///   'new'      — no profile yet, needs role selection + setup
  ///   null       — error (check [error])
  Future<String?> verifyPhoneOtp(String phone, String otp,
      {String? preferredRole}) async {
    if (_isLoading) return null;
    _isLoading = true;
    _error = null;
    safeNotifyListeners();

    // ──────────────────────────────────────────────────────────────────────

    try {
      // 1️⃣ Verify OTP via Edge Function
      if (!_isMagicNumber(phone)) {
        final verifyResp = await _supabase.functions.invoke(
          'verify-otp',
          body: {'phone': phone, 'otp': otp.trim()},
        );

        if (verifyResp.status != 200) {
          final data = verifyResp.data;
          _error = (data is Map ? data['error'] as String? : null) ??
              'Invalid OTP. Please try again.';
          _isLoading = false;
          safeNotifyListeners();
          return null;
        }
      }

      // 2️⃣ Create / sign-in to Supabase Auth using phone-derived credentials
      final email = _emailFromPhone(phone);
      final password = _passwordFromPhone(phone);
      final legacyPassword = _legacyPasswordFromPhone(phone);

      String? userId;
      try {
        // Attempt sign-in first (new secure password)
        final signInRes = await _supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );
        userId = signInRes.user?.id;
      } on AuthException {
        try {
          // Attempt sign-in with legacy password
          final legacyRes = await _supabase.auth.signInWithPassword(
            email: email,
            password: legacyPassword,
          );
          userId = legacyRes.user?.id;

          // Transparently upgrade password
          if (userId != null) {
            try {
              await _supabase.auth
                  .updateUser(UserAttributes(password: password));
            } catch (e) {
              debugPrint('Failed to upgrade legacy password: $e');
              // Proceed anyway, they are logged in!
            }
          }
        } on AuthException {
          // User doesn't exist yet — create them
          try {
            final signUpRes = await _supabase.auth.signUp(
              email: email,
              password: password,
              data: {'phone': phone},
            );
            userId = signUpRes.user?.id;
          } on AuthException catch (e) {
            _error = e.message;
            _isLoading = false;
            safeNotifyListeners();
            return null;
          }
        }
      }

      if (userId == null) {
        _error = 'Authentication failed. Please try again.';
        _isLoading = false;
        safeNotifyListeners();
        return null;
      }

      // For Razorpay reviewer, auto-insert profile + role specific row + address
      if (phone.endsWith('9999999996') ||
          phone.endsWith('9999999997') ||
          phone.endsWith('9999999998')) {
        String mockRole = 'customer';
        if (phone.endsWith('9999999997')) mockRole = 'seller';
        if (phone.endsWith('9999999998')) mockRole = 'delivery_partner';

        final assignedRole = preferredRole ?? mockRole;
        const hardcodedLocation = 'POINT(74.6366 34.4225)';

        // 1. Upsert profile — handle phone uniqueness gracefully
        // Reviewer names: 9999999996 → Rajesh Kumar (Customer)
        //                 9999999997 → Amit Bandana (Seller)
        //                 9999999998 → Kishan Nadda  (Delivery Partner)
        final reviewerName = phone.endsWith('9999999996')
            ? 'Rajesh Kumar'
            : phone.endsWith('9999999997')
                ? 'Amit Bandana'
                : 'Kishan Nadda';
        try {
          final uniquePhone = phone.contains('999999999')
              ? '+9199999${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}'
              : phone;
          await _supabase.from('profiles').upsert({
            'id': userId,
            'role': assignedRole,
            'full_name': reviewerName,
            'phone': uniquePhone
          }, onConflict: 'id');
        } catch (e) {
          debugPrint('Mock profile upsert failed: $e');
        }

        // 2. Upsert specific role row (with hardcoded location)
        try {
          if (assignedRole == 'customer') {
            await _supabase.from('customers').upsert({
              'id': userId,
              'location': hardcodedLocation,
            }, onConflict: 'id');
          } else if (assignedRole == 'seller') {
            await _supabase.from('shops').upsert({
              'seller_id': userId,
              'name': 'Amit Medical Store',
              'category': 'Medical Store',
              'categories': ['Medical Store'],
              'address': 'Main Market, Bandipora, J&K 193502',
              'is_active': true,
              'is_accepting_orders': true,
              'verification_status': 'verified',
              'location': hardcodedLocation,
              'opening_hours': '00:00 - 23:59',
              'open_time': '00:00:00',
              'close_time': '23:59:59',
            }, onConflict: 'seller_id');
          } else if (assignedRole == 'delivery_partner') {
            await _supabase.from('delivery_partners').upsert({
              'id': userId,
              'is_active': true,
              'verification_status': 'verified',
              'location': hardcodedLocation,
            }, onConflict: 'id');
          }
        } catch (e) {
          debugPrint('Mock role upsert failed: $e');
        }

        // 3. Insert a saved address so the reviewer can place orders
        try {
          final existingAddr = await _supabase
              .from('saved_addresses')
              .select()
              .eq('user_id', userId)
              .maybeSingle();

          if (existingAddr == null) {
            await _supabase.from('saved_addresses').insert({
              'user_id': userId,
              'label': 'Home',
              'address': 'Main Market, Bandipora',
              'landmark': 'Near Jamia Masjid',
              'pincode': '193502',
              'latitude': 34.4225,
              'longitude': 74.6366,
              'is_default': true
            });
          }
        } catch (e) {
          debugPrint('Mock address insert failed: $e');
        }

        // Always treat Razorpay reviewer as an existing user — skip setup page
        await _fetchProfile(preferredRole: assignedRole);
        _isLoading = false;
        safeNotifyListeners();
        return 'existing';
      }

      // Establish unique active session in DB and start realtime listener
      await _establishActiveSession(userId);

      // 3️⃣ Check if this user already has a profile or is an admin
      final existing = await _supabase
          .from('profiles')
          .select('id, role')
          .eq('id', userId)
          .maybeSingle();

      final isAdmin = await _supabase
          .from('admin_users')
          .select('id')
          .eq('id', userId)
          .eq('is_active', true)
          .maybeSingle();

      _isLoading = false;
      safeNotifyListeners();

      if (existing != null || preferredRole == 'admin' || isAdmin != null) {
        await _fetchProfile(preferredRole: preferredRole);
        return 'existing';
      }
      return 'new';
    } on AuthException catch (e) {
      _error = e.message;
    } on FunctionException catch (e) {
      final data = e.details;
      _error = (data is Map ? data['error'] as String? : null) ??
          'Verification failed: ${e.reasonPhrase ?? "Unknown error"}';
      debugPrint('verifyPhoneOtp FunctionException: $e');
    } on PostgrestException catch (e) {
      _error = 'Database error: ${e.message}';
      debugPrint('verifyPhoneOtp PostgrestException: $e');
    } catch (e) {
      final errorStr = e.toString();
      if (errorStr.contains('SocketException') ||
          errorStr.contains('Failed host lookup') ||
          errorStr.contains('ClientException')) {
        _error =
            'No internet connection. Please check your network and try again.';
      } else {
        _error = 'Verification failed. Please try again.';
      }
      debugPrint('verifyPhoneOtp error: $e');
    }
    _isLoading = false;
    safeNotifyListeners();
    return null;
  }

  // ─── Create / Update Profile ─────────────────────────────────────────────
  /// One phone user can have ONE profile row AND also independent rows in
  /// sellers/customers/delivery_partners. This method upserts both.
  Future<String?> createProfile({
    required String fullName,
    required String role,
    Map<String, dynamic>? additionalData,
  }) async {
    _isLoading = true;
    _error = null;
    safeNotifyListeners();

    try {
      final user = _supabase.auth.currentUser;
      final userId = user?.id ??
          '00000000-0000-0000-0000-${_pendingPhone?.replaceAll("+", "").padLeft(12, "0") ?? "000000000001"}';

      String phone = user?.phone ?? '';
      if (phone.isEmpty) {
        phone = user?.userMetadata?['phone'] as String? ?? '';
      }
      if (phone.isEmpty) {
        phone = _pendingPhone ?? '';
      }

      // Upsert into profiles (uses onConflict:'id' to avoid 42P10 error)
      try {
        await _supabase.from('profiles').upsert(
          {
            'id': userId,
            'role': role,
            'full_name': fullName,
            'phone': phone,
          },
          onConflict: 'id',
        );
      } catch (profileError) {
        final s = profileError.toString();
        if (s.contains('profiles_phone_key') || s.contains('23505')) {
          _error =
              'An account with this phone number already exists. If you recently deleted your account, please wait or contact support.';
          _isLoading = false;
          safeNotifyListeners();
          return _error;
        }
        if (s.contains('full_name') || s.contains('PGRST204')) {
          try {
            await _supabase.from('profiles').upsert(
              {
                'id': userId,
                'role': role,
                'name': fullName,
                'phone': phone,
              },
              onConflict: 'id',
            );
          } catch (innerError) {
            final innerStr = innerError.toString();
            if (innerStr.contains('profiles_phone_key') ||
                innerStr.contains('23505')) {
              _error =
                  'An account with this phone number already exists. If you recently deleted your account, please wait or contact support.';
              _isLoading = false;
              safeNotifyListeners();
              return _error;
            }
            rethrow;
          }
        } else {
          rethrow;
        }
      }

      // Insert role-specific record — each is independent so same user can
      // have multiple rows across tables.
      if (role == 'customer') {
        final existing = await _supabase
            .from('customers')
            .select('id')
            .eq('id', userId)
            .maybeSingle();
        if (existing == null) {
          await _supabase.from('customers').insert({
            'id': userId,
            if (additionalData != null) ...additionalData,
          });
        } else if (additionalData != null) {
          await _supabase
              .from('customers')
              .update(additionalData)
              .eq('id', userId);
        }

        // ── Explicitly upsert a 'Home' saved address ────────────────────────
        // The DB trigger (trg_sync_customer_address) can be silently blocked by
        // RLS when auth.uid() is NULL in the trigger context. We do it here in
        // the authenticated Dart context so it is always reliable and includes
        // house_number → flat_number which the trigger misses.
        if (additionalData != null) {
          final addressText =
              (additionalData['default_address'] as String? ?? '').trim();
          if (addressText.isNotEmpty) {
            try {
              // Parse lat/lng from the locationPoint string e.g. "POINT(lng lat)"
              double lat = 0, lng = 0;
              final locStr = additionalData['location']?.toString() ?? '';
              final match =
                  RegExp(r'POINT\(([^\s]+)\s+([^\)]+)\)').firstMatch(locStr);
              if (match != null) {
                lng = double.tryParse(match.group(1) ?? '') ?? 0;
                lat = double.tryParse(match.group(2) ?? '') ?? 0;
              }

              // Check if user already has a saved 'Home' address
              final existingAddr = await _supabase
                  .from('saved_addresses')
                  .select('id')
                  .eq('user_id', userId)
                  .eq('label', 'Home')
                  .maybeSingle();

              if (existingAddr == null) {
                // First clear any stale default flag
                await _supabase
                    .from('saved_addresses')
                    .update({'is_default': false}).eq('user_id', userId);

                await _supabase.from('saved_addresses').insert({
                  'user_id': userId,
                  'label': 'Home',
                  'flat_number':
                      (additionalData['house_number'] as String? ?? '')
                              .trim()
                              .isEmpty
                          ? null
                          : (additionalData['house_number'] as String).trim(),
                  'address': addressText,
                  'landmark': (additionalData['landmark'] as String? ?? '')
                          .trim()
                          .isEmpty
                      ? null
                      : (additionalData['landmark'] as String).trim(),
                  'pincode': (additionalData['pincode'] as String? ?? '')
                          .trim()
                          .isEmpty
                      ? null
                      : (additionalData['pincode'] as String).trim(),
                  'latitude': lat,
                  'longitude': lng,
                  'is_default': true,
                });
                debugPrint('Home saved_address created for user $userId');
              }
            } catch (addrErr) {
              // Non-fatal — address can be added later from Profile settings
              debugPrint('Failed to create saved address on signup: $addrErr');
            }
          }
        }
      } else if (role == 'seller') {
        final existing = await _supabase
            .from('shops')
            .select('id')
            .eq('seller_id', userId)
            .limit(1)
            .maybeSingle();
        if (existing == null) {
          final res = await _supabase
              .from('shops')
              .insert({
                'seller_id': userId,
                'is_active': false, // shops are inactive pending KYC
                if (additionalData != null) ...additionalData,
              })
              .select('id')
              .single();
          if (additionalData != null) {
            additionalData['shop_id'] = res['id'];
          }
        } else if (additionalData != null) {
          additionalData['shop_id'] = existing['id'];
          await _supabase
              .from('shops')
              .update(additionalData)
              .eq('id', existing['id']);
        }
      } else if (role == 'delivery_partner') {
        final existing = await _supabase
            .from('delivery_partners')
            .select('id')
            .eq('id', userId)
            .maybeSingle();
        if (existing == null) {
          await _supabase.from('delivery_partners').insert({
            'id': userId,
            if (additionalData != null) ...additionalData,
          });
        } else if (additionalData != null) {
          await _supabase
              .from('delivery_partners')
              .update(additionalData)
              .eq('id', userId);
        }
      }

      await _fetchProfile(preferredRole: role);
      _isLoading = false;
      safeNotifyListeners();
      return null;
    } catch (e) {
      _error = 'Profile setup failed: ${e.toString()}';
    }
    _isLoading = false;
    safeNotifyListeners();
    return _error;
  }

  // ─── Legacy Email Auth ───────────────────────────────────────────────────
  Future<String?> signUp({
    required String email,
    required String password,
    required String fullName,
    required String phone,
    required String role,
    Map<String, dynamic>? additionalData,
  }) async {
    _isLoading = true;
    _error = null;
    safeNotifyListeners();
    try {
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': fullName, 'role': role, 'phone': phone},
      );
      if (response.user != null) {
        await createProfile(
            fullName: fullName, role: role, additionalData: additionalData);
        _isLoading = false;
        safeNotifyListeners();
        return null;
      }
      _error = 'Registration failed.';
    } on AuthException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Registration failed: ${e.toString()}';
    }
    _isLoading = false;
    safeNotifyListeners();
    return _error;
  }

  // ─── Accept Admin Invite Flow ──────────────────────────────────────────────

  /// Fetch invite details (email, role_name) by token
  Future<Map<String, dynamic>?> fetchInviteDetails(String token) async {
    _isLoading = true;
    _error = null;
    safeNotifyListeners();
    try {
      final response = await _supabase
          .rpc('get_invitation_details', params: {'p_token': token});
      final List data = response as List;
      if (data.isNotEmpty) {
        _isLoading = false;
        safeNotifyListeners();
        return data.first as Map<String, dynamic>;
      }
      _error = 'Invalid or expired invite code.';
    } catch (e) {
      _error = 'Error fetching invite: ${e.toString()}';
    }
    _isLoading = false;
    safeNotifyListeners();
    return null;
  }

  /// Registers the user, accepts the invite, and signs them in
  Future<String?> acceptAdminInvite({
    required String token,
    required String email,
    required String password,
    required String fullName,
  }) async {
    _isLoading = true;
    _error = null;
    safeNotifyListeners();

    try {
      // 1. Sign up the user (or if they exist, it might throw, but let's assume new user)
      final authResponse = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': fullName, 'role': 'admin'},
      );

      final userId = authResponse.user?.id;
      if (userId == null) {
        throw Exception(
            'Failed to create user account. Check your email/password.');
      }

      // 2. Accept the invitation via RPC
      await _supabase.rpc('accept_admin_invitation', params: {
        'p_token': token,
        'p_auth_user_id': userId,
        'p_full_name': fullName,
        'p_admin_password': password, // Store for 2FA verification
      });

      // 3. Establish active session and fetch profile
      await _establishActiveSession(userId);
      await _fetchProfile(preferredRole: 'admin');

      _isLoading = false;
      safeNotifyListeners();
      return null;
    } on AuthException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = e.toString();
      if (_error!.contains('Invalid or expired')) {
        _error = 'Invalid or expired invite code.';
      }
    }
    _isLoading = false;
    safeNotifyListeners();
    return _error;
  }

  Future<String?> signIn(
      {required String email, required String password}) async {
    _isLoading = true;
    _error = null;
    safeNotifyListeners();
    try {
      await _supabase.auth.signInWithPassword(email: email, password: password);
      final userId = _supabase.auth.currentUser?.id;
      if (userId != null) {
        await _establishActiveSession(userId);
      }
      await _fetchProfile();
      _isLoading = false;
      safeNotifyListeners();
      return null;
    } on AuthException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Login failed.';
    }
    _isLoading = false;
    safeNotifyListeners();
    return _error;
  }

  Future<void> signOut() async {
    if (_isManualSignOut) return;
    _isManualSignOut = true;

    // Auto-deactivate shop/rider status before signing out so they don't
    // appear Open/Online after the user logs out or deletes the app.
    final userId = _supabase.auth.currentUser?.id ?? _mockUserId;
    final role = _user?.activeSessionRole;
    if (userId != null) {
      try {
        if (role == 'seller') {
          await _supabase
              .from('shops')
              .update({'is_accepting_orders': false}).eq('seller_id', userId);
        } else if (role == 'delivery_partner') {
          await _supabase
              .from('delivery_partners')
              .update({'is_accepting_orders': false}).eq('id', userId);
          RiderBackgroundService.instance.stopService();
        }
      } catch (_) {} // Never block logout on deactivation failure
    }

    // Unsubscribe from session stream
    try {
      _sessionRealtimeChannel?.unsubscribe();
      _sessionRealtimeChannel = null;
    } catch (_) {}
    _localSessionId = null;

    // ── SECURITY FIX: Delete this device's FCM token from DB on every logout ──
    if (userId != null) {
      try {
        final fcmToken = await FirebaseMessaging.instance.getToken();
        if (fcmToken != null) {
          await _supabase
              .from('device_tokens')
              .delete()
              .eq('user_id', userId)
              .eq('token', fcmToken);
          debugPrint('Device token purged for user $userId on logout.');
        }
      } catch (e) {
        // Never block logout on token cleanup failure
        debugPrint('Failed to purge device token on logout: $e');
      }
    }

    try {
      if (_currentSessionId != null) {
        await _supabase
            .from('admin_sessions')
            .delete()
            .eq('id', _currentSessionId!);
      }
    } catch (_) {}

    try {
      await _supabase.auth.signOut();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('local_session_id');
      await prefs.remove('last_active_role');
      await prefs.remove('admin_session_id');
    } catch (_) {}
    _user = null;
    _pendingPhone = null;
    _mockUserId = null;
    _isAdminVerified = false;
    _adminData = null;

    try {
      await FlutterLocalNotificationsPlugin().cancelAll();
    } catch (_) {}

    try {
      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        context.read<CartProvider>().clear();
        context.read<FavoritesProvider>().clear();
        context.read<LocationProvider>().clear();
        context.read<CouponProvider>().clearCoupon();
        context.read<ReferralProvider>().reset();
        context.read<RecentlyViewedProvider>().clear();
        final notifProvider = context.read<NotificationProvider>();
        notifProvider.stopListening();
        notifProvider.clearFcmSubs();
      }
    } catch (_) {}

    // STRESS-3 FIX: Fallback SharedPreferences wipe in case context was null
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('cart_v2');
      await prefs.remove('cart_items');
      await prefs.remove('recently_viewed');
      await prefs.remove('favorite_shops');
      await prefs.remove('favorite_products');
    } catch (_) {}

    safeNotifyListeners();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _sessionRealtimeChannel?.unsubscribe();
    _isDisposed = true;
    super.dispose();
  }
}
