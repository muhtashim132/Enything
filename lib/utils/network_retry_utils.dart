import 'dart:async';
import 'package:flutter/foundation.dart';

/// 100x Exponential Backoff Network Retry Utility
///
/// Ensures mission-critical operations (order placement, GPS updates, rider status)
/// succeed over unreliable cellular connectivity.
class NetworkRetry {
  /// Executes [action] with exponential backoff on transient errors.
  static Future<T> execute<T>(
    Future<T> Function() action, {
    int maxAttempts = 3,
    Duration initialDelay = const Duration(milliseconds: 500),
    double backoffMultiplier = 2.0,
    bool Function(dynamic error)? retryIf,
  }) async {
    int attempt = 0;
    Duration currentDelay = initialDelay;

    while (true) {
      attempt++;
      try {
        return await action();
      } catch (error) {
        if (attempt >= maxAttempts || (retryIf != null && !retryIf(error))) {
          rethrow;
        }

        if (kDebugMode) {
          debugPrint(
            '⚠️ [NetworkRetry] Attempt $attempt failed ($error). Retrying in ${currentDelay.inMilliseconds}ms...',
          );
        }

        await Future.delayed(currentDelay);
        currentDelay = Duration(
          milliseconds: (currentDelay.inMilliseconds * backoffMultiplier).round(),
        );
      }
    }
  }
}
