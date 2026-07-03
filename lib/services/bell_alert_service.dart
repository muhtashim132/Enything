import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'bell_settings_service.dart';

/// Manages the looping alert bell for sellers and riders.
///
/// Architecture
/// ────────────
/// • Tracks a Set of pending order IDs that require the user's action.
/// • Plays enything_bell.wav in a continuous loop (audioplayers) while ANY
///   pending order exists — no overlapping audio, no FCM quota usage.
/// • Stops immediately when all pending orders are resolved.
/// • Single-ring mode: reads the user's loop preference from BellSettingsService.
///
/// Thread safety
/// ─────────────
/// All public methods are async. The `_isPlaying` flag prevents duplicate
/// audio players from starting concurrently.
///
/// FCM quota impact: ZERO — 100% local audio via AudioPlayer.
class BellAlertService {
  BellAlertService._();
  static final BellAlertService instance = BellAlertService._();

  final _pendingOrderIds = <String>{};
  AudioPlayer? _player;
  bool _isPlaying = false;

  bool get hasPendingOrders => _pendingOrderIds.isNotEmpty;
  int  get pendingCount     => _pendingOrderIds.length;

  String? get _userId => Supabase.instance.client.auth.currentUser?.id;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Track a new pending order and start the alert bell (if not already ringing).
  /// Safe to call multiple times with the same orderId — deduplicates internally.
  Future<void> addPendingOrder(String orderId) async {
    if (_pendingOrderIds.contains(orderId)) return;
    _pendingOrderIds.add(orderId);
    debugPrint('[BellAlert] +order: $orderId | pending=${_pendingOrderIds.length}');
    if (!_isPlaying) await _startBell();
  }

  /// Mark an order as resolved. Stops the bell when no pending orders remain.
  Future<void> removePendingOrder(String orderId) async {
    final removed = _pendingOrderIds.remove(orderId);
    if (!removed) return; // was never tracked — no-op
    debugPrint('[BellAlert] -order: $orderId | pending=${_pendingOrderIds.length}');
    if (_pendingOrderIds.isEmpty) await stopBell();
  }

  /// Stop the bell immediately and clear all tracked pending orders.
  /// Called on logout or role switch via NotificationProvider.stopListening().
  Future<void> clearAll() async {
    _pendingOrderIds.clear();
    await stopBell();
  }

  /// Called when the user toggles the loop preference while the bell is active.
  /// Updates the release mode on the live AudioPlayer without restarting it.
  Future<void> refreshMode() async {
    final uid = _userId;
    if (uid == null || !_isPlaying || _player == null) return;
    try {
      final loop = await BellSettingsService.instance.isLoopBellEnabled(uid);
      await _player!.setReleaseMode(
        loop ? ReleaseMode.loop : ReleaseMode.release,
      );
      debugPrint('[BellAlert] Mode refreshed → loop=$loop');
    } catch (e) {
      debugPrint('[BellAlert] refreshMode error: $e');
    }
  }

  /// Play the current bell sound once for in-settings preview.
  /// Uses a temporary AudioPlayer that auto-disposes after 10 s.
  Future<void> previewBell() async {
    final uid = _userId;
    final customPath = uid != null
        ? await BellSettingsService.instance.getCustomBellPath(uid)
        : null;

    final preview = AudioPlayer();
    try {
      await preview.setReleaseMode(ReleaseMode.release);
      await _playSource(preview, customPath);
      // Auto-dispose after 10 s (covers most bell sounds)
      Timer(const Duration(seconds: 10), preview.dispose);
    } catch (e) {
      debugPrint('[BellAlert] previewBell error: $e');
      preview.dispose();
    }
  }

  // ── Internal ────────────────────────────────────────────────────────────────

  Future<void> _startBell() async {
    final uid = _userId;
    final loop = uid != null
        ? await BellSettingsService.instance.isLoopBellEnabled(uid)
        : true;
    final customPath = uid != null
        ? await BellSettingsService.instance.getCustomBellPath(uid)
        : null;

    // Dispose any previous player cleanly before creating a fresh one
    await _player?.stop();
    _player?.dispose();
    _player = AudioPlayer();

    try {
      await _player!.setVolume(1.0);
      await _player!.setReleaseMode(
        loop ? ReleaseMode.loop : ReleaseMode.release,
      );

      await _playSource(_player!, customPath);
      _isPlaying = true;
      debugPrint('[BellAlert] Bell started (loop=$loop, custom=$customPath)');

      // In single-ring mode, clear the playing flag once the sound ends
      if (!loop) {
        _player!.onPlayerComplete.listen((_) {
          _isPlaying = false;
          debugPrint('[BellAlert] Single ring completed.');
        });
      }
    } catch (e) {
      debugPrint('[BellAlert] _startBell error: $e');
      _isPlaying = false;
      _player?.dispose();
      _player = null;
    }
  }

  /// Plays the custom URI/path or falls back to the bundled asset.
  /// Handles both file:// paths and content:// URIs (from Android native picker).
  Future<void> _playSource(AudioPlayer player, String? customPath) async {
    if (customPath != null) {
      try {
        if (customPath.startsWith('content://')) {
          // Android content URI — use UrlSource which handles content:// scheme
          await player.play(UrlSource(customPath));
        } else {
          await player.play(DeviceFileSource(customPath));
        }
        return;
      } catch (e) {
        debugPrint('[BellAlert] Custom sound failed, falling back to default: $e');
      }
    }
    // Default: enything_bell.wav bundled in assets/sounds/
    await player.play(AssetSource('sounds/enything_bell.wav'));
  }

  Future<void> stopBell() async {
    _isPlaying = false;
    try {
      await _player?.stop();
    } catch (_) {}
    _player?.dispose();
    _player = null;
    debugPrint('[BellAlert] Bell stopped.');
  }
}
