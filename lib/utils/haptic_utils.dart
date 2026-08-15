import 'package:flutter/services.dart';

/// 100x Standardized Haptic Feedback Utilities
///
/// Provides consistent tactile feedback across iOS and Android.
class HapticUtils {
  /// Subtle tap for tab switches, filter chips, and cart stepper increments.
  static void selection() {
    HapticFeedback.selectionClick();
  }

  /// Light impact for button presses, card taps, and favorite toggles.
  static void light() {
    HapticFeedback.lightImpact();
  }

  /// Medium impact for successful cart additions and drawer opens.
  static void medium() {
    HapticFeedback.mediumImpact();
  }

  /// Heavy impact for limit warnings and significant modal actions.
  static void heavy() {
    HapticFeedback.heavyImpact();
  }

  /// Multi-tap feedback pattern for successful order placements and payments.
  static void success() {
    HapticFeedback.mediumImpact();
    Future.delayed(const Duration(milliseconds: 100), () {
      HapticFeedback.lightImpact();
    });
  }

  /// Noticeable warning vibration when hitting stock limits or cart constraints.
  static void warning() {
    HapticFeedback.heavyImpact();
  }

  /// Error feedback for payment failures or validation errors.
  static void error() {
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 80), () {
      HapticFeedback.heavyImpact();
    });
  }
}
