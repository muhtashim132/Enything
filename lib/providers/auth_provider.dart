import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';

class AuthProvider extends ChangeNotifier {
  final _supabase = Supabase.instance.client;
  UserModel? _user;
  bool _isLoading = false;
  String? _error;
  String? _pendingPhone; // Phone waiting for OTP verification
  String? _mockUserId; // ID used for magic numbers

  // ─── Admin (God Mode) State ───────────────────────────────────────────────
  bool _isAdminVerified = false; // true after 2nd-factor password gate
  Map<String, dynamic>? _adminData; // row from admin_users table

  UserModel? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _user != null;
  String? get currentUserId => _supabase.auth.currentUser?.id ?? _mockUserId;
  String? get pendingPhone => _pendingPhone;

  bool get isAdminVerified => _isAdminVerified;
  bool get isAdmin => _adminData != null;
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

  void _init() {
    _supabase.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.signedIn) {
        _fetchProfile();
      } else if (event.event == AuthChangeEvent.signedOut) {
        _user = null;
        _mockUserId = null;
        _pendingPhone = null;
        notifyListeners();
      }
    });
    if (_supabase.auth.currentUser != null) {
      _fetchProfile();
    }
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
    } catch (_) {}

    try {
      final seller = await _supabase
          .from('shops')
          .select('seller_id')
          .eq('seller_id', userId)
          .maybeSingle();
      if (seller != null) roles.add('seller');
    } catch (_) {}

    try {
      final delivery = await _supabase
          .from('delivery_partners')
          .select('id')
          .eq('id', userId)
          .maybeSingle();
      if (delivery != null) roles.add('delivery_partner');
    } catch (_) {}

    // ── Admin / God Mode detection ───────────────────────────────────────────
    if (userId.endsWith('9999999996')) {
      roles.add('admin');
      _adminData = {
        'id': userId,
        'admin_level': 'superadmin',
        'permissions': {
          'view_financials': true,
          'manage_shops': true,
          'manage_riders': true,
          'manage_admins': true,
          'view_master_pnl': true,
          'ban_users': true
        },
        'is_active': true,
        'admin_password': 'admin',
      };
    } else {
      try {
        final admin = await _supabase
            .from('admin_users')
            .select('id, admin_level, is_active, admin_password')
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
    }

    return roles;
  }

  // ─── Admin 2nd-Factor Password Verification ──────────────────────────────
  /// Called from AdminPasswordPage after OTP succeeds.
  /// Returns true if the supplied [password] matches the stored admin_password.
  Future<bool> verifyAdminPassword(String password) async {
    final userId = currentUserId;
    if (userId == null || _adminData == null) return false;

    final storedPassword = _adminData!['admin_password'] as String?;
    if (storedPassword == null || storedPassword.isEmpty) return false;

    // Dev: plain-text comparison (swap with bcrypt Edge Function in prod)
    if (password.trim() == storedPassword.trim()) {
      _isAdminVerified = true;
      notifyListeners();

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
    notifyListeners();
  }

  Future<void> _fetchProfile({String? preferredRole}) async {
    try {
      final userId = _supabase.auth.currentUser?.id ?? _mockUserId;
      if (userId == null) return;

      Map<String, dynamic>? data;
      try {
        final response =
            await _supabase.from('profiles').select().eq('id', userId).single();
        data = Map<String, dynamic>.from(response);
      } catch (e) {
        // If profile doesn't exist, it might be an admin-only account
        data = {
          'id': userId,
          'full_name': 'Admin User',
          'phone': _supabase.auth.currentUser?.phone ?? _pendingPhone ?? '',
          'role': 'admin'
        };
      }

      if (!data.containsKey('full_name') && data.containsKey('name')) {
        data['full_name'] = data['name'];
      }

      // Detect all roles across role-specific tables
      final allRoles = await _detectUserRoles(userId);
      // If no roles detected yet, fall back to the profiles.role value
      if (allRoles.isEmpty) allRoles.add(data['role'] ?? 'customer');

      final primaryRole = data['role'] ?? 'customer';
      // Prefer the requested role if valid, otherwise use primary
      final sessionRole =
          (preferredRole != null && allRoles.contains(preferredRole))
              ? preferredRole
              : primaryRole;

      // ── Detect verification status for the session role ──
      String verificationStatus = 'verified'; // Default for customer
      if (sessionRole == 'seller') {
        final sellerData = await _supabase.from('shops').select('verification_status').eq('seller_id', userId).maybeSingle();
        verificationStatus = sellerData?['verification_status'] ?? 'pending';
      } else if (sessionRole == 'delivery_partner') {
        final deliveryData = await _supabase.from('delivery_partners').select('verification_status').eq('id', userId).maybeSingle();
        verificationStatus = deliveryData?['verification_status'] ?? 'pending';
      }

      _user = UserModel.fromMap({
        ...data,
        'email': _supabase.auth.currentUser?.email ?? '',
        'phone': _supabase.auth.currentUser?.phone ?? data['phone'] ?? '',
        'activeRoles': allRoles,
        'activeSessionRole': sessionRole,
        'verification_status': verificationStatus,
      });
      notifyListeners();
    } catch (e) {
      debugPrint('Profile fetch error: $e');
    }
  }

  /// Switch the active session role (user must already be registered for that role).
  void switchSessionRole(String role) {
    if (_user == null) return;
    if (!_user!.activeRoles.contains(role)) return;
    _user = _user!.copyWith(activeSessionRole: role);
    notifyListeners();
  }

  // ─── OTP Auth (Phone) via Fast2SMS ──────────────────────────────────────

  /// Generates a cryptographically random 6-digit OTP.
  String _generateOtp() {
    final rng = Random.secure();
    return (100000 + rng.nextInt(900000)).toString();
  }

  /// Derives a stable email+password pair from a phone number so we can
  /// create a real Supabase Auth session after Fast2SMS OTP verification.
  String _emailFromPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    return '$digits@auth.enything.app';
  }

  String _passwordFromPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    return 'Enything$digits#Auth2025';
  }

  /// Step 1: Generate OTP, store in Supabase, and deliver via Fast2SMS.
  Future<String?> sendPhoneOtp(String phone) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    // ── Magic number bypass for internal testing ──────────────────────────
    if (phone.contains('9999999991') ||
        phone.contains('9999999992') ||
        phone.contains('9999999993') ||
        phone.contains('9999999994') ||
        phone.contains('9999999995') ||
        phone.contains('9999999996')) {
      _pendingPhone = phone;
      _isLoading = false;
      notifyListeners();
      return null;
    }

    try {
      final otp = _generateOtp();
      final expiresAt =
          DateTime.now().toUtc().add(const Duration(minutes: 10)).toIso8601String();

      // 1️⃣ Persist OTP in Supabase (upsert so resends overwrite old OTP)
      await _supabase.from('phone_otps').upsert({
        'phone': phone,
        'otp': otp,
        'expires_at': expiresAt,
      }, onConflict: 'phone');

      // 2️⃣ Send OTP via Fast2SMS
      final apiKey = dotenv.maybeGet('FAST2SMS_API_KEY') ?? '';
      final mobileNumber = phone.replaceAll(RegExp(r'^\+91'), '').replaceAll(RegExp(r'\D'), '');

      final response = await http.post(
        Uri.parse('https://www.fast2sms.com/dev/bulkV2'),
        headers: {
          'authorization': apiKey,
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'route': 'q',
          'message': 'Your Enything login OTP is $otp. Do not share this with anyone.',
          'flash': 0,
          'numbers': mobileNumber,
        }),
      ).timeout(const Duration(seconds: 15));

      final body = json.decode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200 || body['return'] != true) {
        final msg = body['message']?.toString() ?? 'SMS delivery failed.';
        _error = msg;
        _isLoading = false;
        notifyListeners();
        return _error;
      }

      _pendingPhone = phone;
      _isLoading = false;
      notifyListeners();
      return null; // success
    } catch (e) {
      _error = 'Could not send OTP. Check your number and try again.';
      debugPrint('sendPhoneOtp error: $e');
    }
    _isLoading = false;
    notifyListeners();
    return _error;
  }

  /// Step 2: Verify OTP against Supabase `phone_otps` table, then create
  /// or sign in to the Supabase Auth session using an email derived from
  /// the phone number.
  ///
  /// Returns:
  ///   'existing' — user has a profile (may have multiple roles)
  ///   'new'      — no profile yet, needs role selection + setup
  ///   null       — error (check [error])
  Future<String?> verifyPhoneOtp(String phone, String otp,
      {String? preferredRole}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    // ─── Magic Number Bypass (internal testing) ────────────────────────────
    if (phone.contains('9999999991') ||
        phone.contains('9999999992') ||
        phone.contains('9999999993') ||
        phone.contains('9999999994') ||
        phone.contains('9999999995') ||
        phone.contains('9999999996')) {
      await Future.delayed(const Duration(seconds: 1));

      String mockId =
          '00000000-0000-0000-0000-${phone.replaceAll("+", "").padLeft(12, "0")}';
      _mockUserId = mockId;

      final existing = await _supabase
          .from('profiles')
          .select('id, role')
          .eq('id', mockId)
          .maybeSingle();

      _isLoading = false;
      notifyListeners();

      if (existing != null ||
          preferredRole == 'admin' ||
          phone.contains('9999999996')) {
        await _fetchProfile(preferredRole: preferredRole);
        return 'existing';
      }
      return 'new';
    }
    // ──────────────────────────────────────────────────────────────────────

    try {
      // 1️⃣ Validate OTP from phone_otps table
      final record = await _supabase
          .from('phone_otps')
          .select('otp, expires_at')
          .eq('phone', phone)
          .maybeSingle();

      if (record == null) {
        _error = 'OTP expired or not found. Please request a new one.';
        _isLoading = false;
        notifyListeners();
        return null;
      }

      final storedOtp = record['otp'] as String? ?? '';
      final expiresAt = DateTime.tryParse(record['expires_at'] as String? ?? '');

      if (storedOtp != otp.trim()) {
        _error = 'Invalid OTP. Please try again.';
        _isLoading = false;
        notifyListeners();
        return null;
      }

      if (expiresAt == null || DateTime.now().toUtc().isAfter(expiresAt)) {
        _error = 'OTP has expired. Please request a new one.';
        _isLoading = false;
        notifyListeners();
        return null;
      }

      // 2️⃣ OTP is valid — clean up the record
      await _supabase.from('phone_otps').delete().eq('phone', phone);

      // 3️⃣ Create / sign-in to Supabase Auth using phone-derived credentials
      final email = _emailFromPhone(phone);
      final password = _passwordFromPhone(phone);

      String? userId;
      try {
        // Attempt sign-in first (existing user)
        final signInRes = await _supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );
        userId = signInRes.user?.id;
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
          notifyListeners();
          return null;
        }
      }

      if (userId == null) {
        _error = 'Authentication failed. Please try again.';
        _isLoading = false;
        notifyListeners();
        return null;
      }

      // 4️⃣ Check if this user already has a profile
      final existing = await _supabase
          .from('profiles')
          .select('id, role')
          .eq('id', userId)
          .maybeSingle();

      _isLoading = false;
      notifyListeners();

      if (existing != null || preferredRole == 'admin') {
        await _fetchProfile(preferredRole: preferredRole);
        return 'existing';
      }
      return 'new';
    } on AuthException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Verification failed. Please try again.';
      debugPrint('verifyPhoneOtp error: $e');
    }
    _isLoading = false;
    notifyListeners();
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
    notifyListeners();

    try {
      final userId = _supabase.auth.currentUser?.id ??
          '00000000-0000-0000-0000-${_pendingPhone?.replaceAll("+", "").padLeft(12, "0") ?? "000000000001"}';
      final phone = _supabase.auth.currentUser?.phone ?? _pendingPhone ?? '';

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
        if (s.contains('full_name') || s.contains('PGRST204')) {
          await _supabase.from('profiles').upsert(
            {
              'id': userId,
              'role': role,
              'name': fullName,
              'phone': phone,
            },
            onConflict: 'id',
          );
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
      } else if (role == 'seller') {
        final existing = await _supabase
            .from('shops')
            .select('id')
            .eq('seller_id', userId)
            .maybeSingle();
        if (existing == null) {
          await _supabase.from('shops').insert({
            'seller_id': userId,
            if (additionalData != null) ...additionalData,
          });
        } else if (additionalData != null) {
          await _supabase
              .from('shops')
              .update(additionalData)
              .eq('seller_id', userId);
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
      notifyListeners();
      return null;
    } catch (e) {
      _error = 'Profile setup failed: ${e.toString()}';
    }
    _isLoading = false;
    notifyListeners();
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
    notifyListeners();
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
        notifyListeners();
        return null;
      }
      _error = 'Registration failed.';
    } on AuthException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Registration failed: ${e.toString()}';
    }
    _isLoading = false;
    notifyListeners();
    return _error;
  }

  Future<String?> signIn(
      {required String email, required String password}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await _supabase.auth.signInWithPassword(email: email, password: password);
      await _fetchProfile();
      _isLoading = false;
      notifyListeners();
      return null;
    } on AuthException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Login failed.';
    }
    _isLoading = false;
    notifyListeners();
    return _error;
  }

  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
    } catch (_) {}
    _user = null;
    _pendingPhone = null;
    _mockUserId = null;
    _isAdminVerified = false;
    _adminData = null;
    notifyListeners();
  }
}
