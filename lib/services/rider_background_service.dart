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

    final androidPlugin =
        notif.resolvePlatformSpecificImplementation<
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
        autoStart: false,           // We start it explicitly when rider goes online
        isForegroundMode: true,     // Required to survive screen lock
        foregroundServiceTypes: const [AndroidForegroundType.location],
        notificationChannelId: _kFgChannelId,
        initialNotificationTitle: '🛵 Enything Delivery Active',
        initialNotificationContent: 'Location tracking is on for your active delivery',
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
  /// Passes [riderId] and [supabaseUrl] + [anonKey] so the isolate can init Supabase.
  Future<void> startService({
    required String riderId,
    required String supabaseUrl,
    required String anonKey,
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
  SupabaseClient? db;
  Timer? gpsTimer;

  // ── Helper: fetch GPS and push to Supabase ─────────────────────────────
  Future<void> pushLocation() async {
    if (riderId == null || db == null) return;

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

      // 1️⃣ Update delivery_partners row (PostGIS point + lat/lng columns)
      try {
        await db!.rpc('update_rider_location', params: {
          'p_lat': lat,
          'p_lng': lng,
        });
      } catch (e) {
        print('[RiderBgService] update_rider_location RPC error: $e');
      }

      // 2️⃣ Update rider_lat/lng on all active orders assigned to this rider
      const activeStatuses = [
        'confirmed',
        'preparing',
        'ready_for_pickup',
        'picked_up',
        'out_for_delivery',
      ];

      try {
        final rows = await db!
            .from('orders')
            .select('id')
            .eq('delivery_partner_id', riderId!)
            .inFilter('status', activeStatuses);

        for (final row in (rows as List)) {
          final orderId = row['id'] as String?;
          if (orderId == null) continue;
          try {
            await db!.from('orders').update({
              'rider_lat': lat,
              'rider_lng': lng,
              'rider_location_updated_at': DateTime.now().toIso8601String(),
            }).eq('id', orderId);
          } catch (e) {
            print('[RiderBgService] order update error ($orderId): $e');
          }
        }
      } catch (e) {
        print('[RiderBgService] order query error: $e');
      }

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
    }
  }

  // ── Listen for messages from the main isolate ──────────────────────────

  service.on('set_credentials').listen((data) async {
    if (data == null) return;
    riderId = data['rider_id'] as String?;
    final supabaseUrl = data['supabase_url'] as String?;
    final receivedKey = data['anon_key'] as String?;

    if (supabaseUrl == null || receivedKey == null) {
      print('[RiderBgService] Missing Supabase credentials — cannot start');
      return;
    }

    // Initialize Supabase in this isolate (safe to call multiple times)
    try {
      await Supabase.initialize(url: supabaseUrl, publishableKey: receivedKey);
      db = Supabase.instance.client;
      print('[RiderBgService] Supabase initialized for rider: $riderId');
    } catch (e) {
      // Already initialized — grab the existing client
      try {
        db = Supabase.instance.client;
      } catch (_) {
        print('[RiderBgService] Supabase init failed: $e');
        return;
      }
    }

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
    service.on('setAsForeground').listen((_) => service.setAsForegroundService());
    service.on('setAsBackground').listen((_) => service.setAsBackgroundService());
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

