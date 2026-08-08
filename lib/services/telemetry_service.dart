// ignore_for_file: avoid_print
import 'package:flutter/foundation.dart';

/// ---------------------------------------------------------------------------
/// TelemetryService
/// ---------------------------------------------------------------------------
/// Centralized service for tracking application metrics, background service
/// latency, and isolated errors. Designed to be 100% additive and safe.
///
/// Usage:
///   TelemetryService.instance.logError('BackgroundSync', e, stackTrace);
///   await TelemetryService.instance.trackLatency('update_rider_bg', () async { ... });
/// ---------------------------------------------------------------------------
class TelemetryService {
  TelemetryService._();
  static final TelemetryService instance = TelemetryService._();

  /// Logs an error with context.
  /// In a full production environment, this could forward to Firebase Crashlytics
  /// or a dedicated Supabase 'telemetry_logs' table.
  void logError(String context, dynamic error, [StackTrace? stackTrace]) {
    if (kDebugMode) {
      debugPrint('🔴 [Telemetry][$context] ERROR: $error');
      if (stackTrace != null) {
        debugPrint('Stacktrace: $stackTrace');
      }
    } else {
      // Print in release mode for basic observability via adb logcat
      print('[Telemetry][$context] ERROR: $error');
    }
  }

  /// Tracks a generic event (e.g., Background sync fired).
  void trackEvent(String eventName, [Map<String, dynamic>? data]) {
    if (kDebugMode) {
      debugPrint('🔵 [Telemetry][Event] $eventName | Data: $data');
    }
  }

  /// Wraps an asynchronous operation to track how long it takes to execute.
  /// Useful for identifying SQL or network degradation in background isolates.
  Future<T> trackLatency<T>(
      String operationName, Future<T> Function() operation) async {
    final stopwatch = Stopwatch()..start();
    try {
      final result = await operation();
      stopwatch.stop();
      if (kDebugMode) {
        debugPrint(
            '⏱️ [Telemetry][Latency] $operationName completed in ${stopwatch.elapsedMilliseconds}ms');
      }
      return result;
    } catch (e, st) {
      stopwatch.stop();
      logError(
          '$operationName (Failed after ${stopwatch.elapsedMilliseconds}ms)',
          e,
          st);
      rethrow;
    }
  }
}
