import 'dart:async';
import 'package:flutter/foundation.dart';

/// 100x Debounce Utility
///
/// Delays executing [action] until [duration] has elapsed since the last invocation.
/// Perfect for search inputs, auto-save fields, and filter sliders.
class Debouncer {
  final Duration duration;
  Timer? _timer;

  Debouncer({required this.duration});

  /// Executes [action] after the configured [duration] has elapsed without new calls.
  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(duration, action);
  }

  /// Immediately cancels any pending execution.
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  /// Disposes the debouncer safely.
  void dispose() {
    cancel();
  }
}

/// 100x Throttle Utility
///
/// Ensures [action] is executed at most once every [duration].
/// Perfect for real-time rider GPS location updates, rapid cart button clicks, and scroll listeners.
class Throttler {
  final Duration duration;
  bool _isThrottled = false;
  Timer? _timer;

  Throttler({required this.duration});

  /// Executes [action] immediately if not throttled; ignores intermediate calls during [duration].
  void run(VoidCallback action) {
    if (!_isThrottled) {
      action();
      _isThrottled = true;
      _timer?.cancel();
      _timer = Timer(duration, () {
        _isThrottled = false;
      });
    }
  }

  /// Cancels any active throttling lock.
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _isThrottled = false;
  }

  /// Disposes the throttler safely.
  void dispose() {
    cancel();
  }
}
