import 'package:flutter/services.dart';

/// Centralized haptic feedback system for tactile sensory UX.
/// Calibrated for premium feel across iOS and Android.
class SensoryHaptics {
  SensoryHaptics._();

  /// Very subtle tick on scroll snaps, slider ticks, and light hover
  static void selection() {
    HapticFeedback.selectionClick();
  }

  /// Light impact on standard button taps, chips, tab changes
  static void light() {
    HapticFeedback.lightImpact();
  }

  /// Medium impact on cart add/remove, toggle switches, filter applies
  static void medium() {
    HapticFeedback.mediumImpact();
  }

  /// Heavy impact on major actions like order placement, slider lock, slide-to-confirm
  static void heavy() {
    HapticFeedback.heavyImpact();
  }

  /// Celebration / success feedback pattern on delivery, payment success, coupon apply
  static void success() async {
    HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 120));
    HapticFeedback.heavyImpact();
  }

  /// Error / warning double vibration on validation failure or stock out
  static void error() async {
    HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    HapticFeedback.heavyImpact();
  }
}
