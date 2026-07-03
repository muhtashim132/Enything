import 'package:shared_preferences/shared_preferences.dart';

/// Local-only bell preference storage.
///
/// All data lives in SharedPreferences — zero DB, zero network,
/// zero app-size impact. Keyed by userId so multiple accounts on the
/// same device each get their own preferences.
class BellSettingsService {
  BellSettingsService._();
  static final BellSettingsService instance = BellSettingsService._();

  static const _loopKey   = 'bell_loop_enabled_';
  static const _soundKey  = 'bell_custom_path_';

  // ── Loop bell preference ─────────────────────────────────────────────────

  /// Whether the continuous loop bell is enabled for [userId].
  /// Defaults to true (loop on) — sellers and riders hear the bell until
  /// they take action. Returns true for any userId not yet in prefs.
  Future<bool> isLoopBellEnabled(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_loopKey$userId') ?? true;
  }

  Future<void> setLoopBellEnabled(String userId, {required bool enabled}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_loopKey$userId', enabled);
  }

  // ── Custom bell sound ────────────────────────────────────────────────────

  /// File path of a custom bell sound picked from device storage, or null
  /// to use the default built-in enything_bell.wav.
  Future<String?> getCustomBellPath(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_soundKey$userId');
  }

  Future<void> setCustomBellPath(String userId, String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null) {
      await prefs.remove('$_soundKey$userId');
    } else {
      await prefs.setString('$_soundKey$userId', path);
    }
  }
}
