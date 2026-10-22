import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local-only per-admin Dispatch Radar preference storage.
///
/// Follows the established Enything architecture (matching BellSettingsService):
/// - All data lives in SharedPreferences — zero DB migrations, zero network latency.
/// - Scoped strictly by `adminId` so Super Admins and Normal Admins on the same
///   or different devices each maintain their own independent preferences.
/// - Defaults `isRadarActive` to `false` for any admin who hasn't explicitly
///   toggled it ON. This prevents unwanted audio alarms on fresh logins.
///   Once turned ON, it stays ON permanently until explicitly turned OFF.
class AdminDispatchSettingsService {
  AdminDispatchSettingsService._();
  static final AdminDispatchSettingsService instance =
      AdminDispatchSettingsService._();

  static const _radarActiveKey = 'admin_dispatch_radar_active_';
  static const _buzzEnabledKey = 'admin_dispatch_buzz_enabled_';
  static const _radiusKmKey = 'admin_dispatch_radius_km_';

  final ValueNotifier<bool> radarActiveNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<int> pendingOrderCountNotifier = ValueNotifier<int>(0);

  // ── Dispatch Radar Toggle (Per Admin) ──────────────────────────────────────

  /// Returns whether Dispatch Radar is actively running for [adminId].
  /// Defaults to `false` (dormant/OFF) until the admin explicitly toggles it ON.
  Future<bool> isRadarActive(String adminId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final val = prefs.getBool('$_radarActiveKey$adminId') ?? false;
      radarActiveNotifier.value = val;
      return val;
    } catch (e) {
      debugPrint('[AdminDispatchSettings] Error reading radarActive: $e');
      return false;
    }
  }

  /// Sets whether Dispatch Radar is active for [adminId].
  Future<void> setRadarActive(String adminId, {required bool active}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_radarActiveKey$adminId', active);
      radarActiveNotifier.value = active;
      debugPrint(
          '[AdminDispatchSettings] Persisted radarActive=$active for admin=$adminId');
    } catch (e) {
      debugPrint('[AdminDispatchSettings] Error saving radarActive: $e');
    }
  }

  // ── Audio Buzz Alert Toggle (Per Admin) ────────────────────────────────────

  /// Returns whether the audio buzzer is unmuted for [adminId].
  /// Defaults to `true` (unmuted) so alerts ring when Radar is active.
  Future<bool> isBuzzEnabled(String adminId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('$_buzzEnabledKey$adminId') ?? true;
    } catch (e) {
      debugPrint('[AdminDispatchSettings] Error reading buzzEnabled: $e');
      return true;
    }
  }

  /// Sets whether audio buzz is enabled for [adminId].
  Future<void> setBuzzEnabled(String adminId, {required bool enabled}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_buzzEnabledKey$adminId', enabled);
      debugPrint(
          '[AdminDispatchSettings] Persisted buzzEnabled=$enabled for admin=$adminId');
    } catch (e) {
      debugPrint('[AdminDispatchSettings] Error saving buzzEnabled: $e');
    }
  }

  // ── Radar Search Radius (Per Admin) ────────────────────────────────────────

  /// Returns saved radius in km for [adminId]. Null represents 'Unlimited'.
  Future<double?> getRadiusKm(String adminId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasKey = prefs.containsKey('$_radiusKmKey$adminId');
      if (!hasKey) return 15.0; // Default 15 km
      final val = prefs.getDouble('$_radiusKmKey$adminId');
      return val; // null if explicitly saved as unlimited
    } catch (e) {
      debugPrint('[AdminDispatchSettings] Error reading radiusKm: $e');
      return 15.0;
    }
  }

  Future<void> setRadiusKm(String adminId, double? radius) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (radius == null) {
        await prefs.remove('$_radiusKmKey$adminId');
      } else {
        await prefs.setDouble('$_radiusKmKey$adminId', radius);
      }
    } catch (e) {
      debugPrint('[AdminDispatchSettings] Error saving radiusKm: $e');
    }
  }

  // ── Live Order Count Broadcaster ───────────────────────────────────────────

  /// Updates the live pending dispatch orders count observed by the admin panel.
  void updatePendingCount(int count) {
    if (pendingOrderCountNotifier.value != count) {
      pendingOrderCountNotifier.value = count;
    }
  }
}
