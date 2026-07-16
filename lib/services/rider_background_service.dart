// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RiderBackgroundService
//
// Manages an Android Foreground Service that keeps the rider's GPS location
// syncing to Supabase every 15 seconds even when:
//   • The phone screen is locked
//   • The app is minimised / backgrounded
//
// Architecture:
//   Main isolate  ──invoke(msg)──►  Background isolate
//   Main isolate  ◄──on(event)────  Background isolate
//
// The foreground service is represented to the user as a persistent
// status-bar notification ("Enything is tracking your location for delivery").
// This is required by Android OS — it cannot be hidden.
//
// iOS note: flutter_background_service on iOS uses BGTaskScheduler which is
// heavily throttled by Apple. The foreground-app timer is the primary path on
// iOS. This service provides the Android lock-screen fix.
// ─────────────────────────────────────────────────────────────────────────────

/// Notification channel used exclusively for the Foreground Service
/// persistent notification. Different from the push/order channels.
const String _kFgChannelId = 'rider_location_fg_channel';
const String _kFgChannelName = 'Rider Location Tracking';
const int _kFgNotificationId = 9901;

/// How often the background isolate polls GPS and writes to Supabase (seconds).
const int _kIntervalSeconds = 15;

class RiderBackgroundService {
  RiderBackgroundService._();
  static final RiderBackgroundService instance = RiderBackgroundService._();

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Call once at app startup to register the service handler.
  /// Safe to call multiple times — idempotent.
  Future<void> initialize() async {
    final service = FlutterBackgroundService();

    // Create the persistent foreground notification channel (Android 8+).
    final notif = FlutterLocalNotificationsPlugin();
    const androidInit = AndroidInitializationSettings('ic_notification');
    await notif.initialize(const InitializationSettings(android: androidInit));

    final androidPlugin = notif.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _kFgChannelId,
        _kFgChannelName,
        description: 'Shows while Enything tracks your location for delivery',
        importance: Importance.low, // Low = no sound/vibration, just visible
        showBadge: false,
        playSound: false,
        enableVibration: false,
      ),
    );

    await service.configure(
      // ── Android ────────────────────────────────────────────────────────────
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: false, // We start it explicitly when rider goes online
        isForegroundMode: true, // Required to survive screen lock
        foregroundServiceTypes: const [AndroidForegroundType.location],
        notificationChannelId: _kFgChannelId,
        initialNotificationTitle: '🛵 Enything Delivery Active',
        initialNotificationContent:
            'Location tracking is on for your active delivery',
        foregroundServiceNotificationId: _kFgNotificationId,
      ),
      // ── iOS ────────────────────────────────────────────────────────────────
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _onStart,
        onBackground: _onIosBackground,
      ),
    );
  }

  /// Start the background service (call when rider goes online with active order).
  Future<void> startService({
    required String riderId,
    required String supabaseUrl,
    required String anonKey,
    required String trackingSecret,
  }) async {
    final service = FlutterBackgroundService();
    final isRunning = await service.isRunning();
    if (isRunning) {
      // Already running — just update the rider ID in case it changed
      service.invoke('update_rider', {'rider_id': riderId});
      return;
    }

    await service.startService();

    // Give the isolate ~500ms to boot, then pass the credentials
    await Future<void>.delayed(const Duration(milliseconds: 500));
    service.invoke('set_credentials', {
      'rider_id': riderId,
      'supabase_url': supabaseUrl,
      'anon_key': anonKey,
      'tracking_secret': trackingSecret,
    });
  }

  /// Stop the background service (call when rider goes offline or app comes to foreground).
  Future<void> stopService() async {
    final service = FlutterBackgroundService();
    service.invoke('stop_service');
  }

  /// Returns true if the background service is currently running.
  Future<bool> isRunning() async {
    return FlutterBackgroundService().isRunning();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Background Isolate Entry Point
// MUST be a top-level function decorated with @pragma('vm:entry-point').
// ─────────────────────────────────────────────────────────────────────────────

@pragma('vm:entry-point')
Future<void> _onStart(ServiceInstance service) async {
  // DartPluginRegistrant.ensureInitialized is required in background isolates
  // so that platform plugins (Geolocator, Supabase, etc.) work correctly.
  DartPluginRegistrant.ensureInitialized();

  // State tracked inside the background isolate
  String? riderId;
  String? trackingSecret;
  SupabaseClient? db;
  Timer? gpsTimer;

  bool isPushingLocation = false;

  // ── Helper: fetch GPS and push to Supabase ─────────────────────────────
  Future<void> pushLocation() async {
    if (riderId == null || db == null || isPushingLocation) return;
    isPushingLocation = true;

    try {
      // Check location service & permission (non-interactive in background)
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }

      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        );
      } catch (_) {
        pos = await Geolocator.getLastKnownPosition();
      }

      if (pos == null) return;

      final lat = pos.latitude;
      final lng = pos.longitude;

      // 1️⃣ Update delivery_partners row and cascade to orders (Stateless RPC)
      try {
        await db!.rpc('update_rider_location_bg', params: {
          'p_rider_id': riderId,
          'p_lat': lat,
          'p_lng': lng,
          'p_secret': trackingSecret,
        });
      } catch (e) {
        print('[RiderBgService] update_rider_location_bg RPC error: $e');
      }

      // 2️⃣ [STRESS-TEST FIX] The 'update_rider_location_bg' RPC now atomically cascades
      //    these coordinates to ALL active orders assigned to the rider directly in PostgreSQL.
      //    We deleted the redundant .select() loop and update_rider_order_location RPC call
      //    to eliminate 2,000 writes and 1,000 queries per minute per 1k riders.

      // Update the foreground notification content with last-updated time
      if (service is AndroidServiceInstance) {
        final now = DateTime.now();
        final hhmm =
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
        service.setForegroundNotificationInfo(
          title: '🛵 Enything Delivery Active',
          content: 'Location updated · $hhmm',
        );
      }

      print('[RiderBgService] ✅ Location pushed: $lat, $lng');
    } catch (e) {
      print('[RiderBgService] pushLocation error: $e');
    } finally {
      isPushingLocation = false;
    }
  }

  // ── Listen for messages from the main isolate ──────────────────────────

  service.on('set_credentials').listen((data) async {
    if (data == null) return;
    riderId = data['rider_id'] as String?;
    final supabaseUrl = data['supabase_url'] as String?;
    final receivedKey = data['anon_key'] as String?;
    trackingSecret = data['tracking_secret'] as String?;

    if (supabaseUrl == null || receivedKey == null || trackingSecret == null) {
      print('[RiderBgService] Missing Supabase credentials or tracking secret');
      return;
    }

    // 100x ARCHITECTURE FIX: Stateless BG Isolate
    // Eliminates race conditions with main isolate's token refresh
    db = SupabaseClient(supabaseUrl, receivedKey);

    // Start the periodic GPS timer
    gpsTimer?.cancel();
    await pushLocation(); // Immediate first push
    gpsTimer = Timer.periodic(
      const Duration(seconds: _kIntervalSeconds),
      (_) => pushLocation(),
    );
  });

  service.on('update_rider').listen((data) {
    if (data != null) riderId = data['rider_id'] as String?;
  });

  service.on('stop_service').listen((_) async {
    print('[RiderBgService] Stop signal received');
    gpsTimer?.cancel();
    await service.stopSelf();
  });

  // Keep the isolate alive on Android as a foreground service
  if (service is AndroidServiceInstance) {
    service
        .on('setAsForeground')
        .listen((_) => service.setAsForegroundService());
    service
        .on('setAsBackground')
        .listen((_) => service.setAsBackgroundService());
    await service.setAsForegroundService();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// iOS background handler — BGTaskScheduler callback
// ─────────────────────────────────────────────────────────────────────────────

@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true; // Keep alive
}
