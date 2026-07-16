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
  AudioPlayer? _previewPlayer;
  bool _isPlaying = false;

  bool get hasPendingOrders => _pendingOrderIds.isNotEmpty;
  int  get pendingCount     => _pendingOrderIds.length;

  String? get _userId {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  bool _isStarting = false;

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<void> addPendingOrder(String orderId) async {
    if (_pendingOrderIds.contains(orderId)) return;
    _pendingOrderIds.add(orderId);
    
    // STRESS-TEST FIX: Prevent synchronous FFI bottleneck on the main thread during high burst loads.
    if (kDebugMode) {
      if (_pendingOrderIds.length <= 10) {
        debugPrint('[BellAlert] +order: $orderId | pending=${_pendingOrderIds.length}');
      } else if (_pendingOrderIds.length % 50 == 0) {
        debugPrint('[BellAlert] +batch orders... pending=${_pendingOrderIds.length}');
      }
    }

    if (!_isPlaying && !_isStarting) {
      _isStarting = true;
      try {
        await _startBell();
      } finally {
        _isStarting = false;
      }
    }
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

  bool _isPreviewing = false;

  /// Play the current bell sound once for in-settings preview.
  /// Uses a Singleton AudioPlayer to prevent audio overlap and memory leaks.
  Future<void> previewBell() async {
    if (_isPreviewing) return;
    _isPreviewing = true;
    try {
      final uid = _userId;
      final customPath = uid != null
          ? await BellSettingsService.instance.getCustomBellPath(uid)
          : null;

      final oldPreview = _previewPlayer;
      _previewPlayer = null;
      try {
        await oldPreview?.stop();
      } catch (_) {}
      oldPreview?.dispose();

      _previewPlayer = AudioPlayer();
      try {
        await _previewPlayer!.setReleaseMode(ReleaseMode.release);
        await _playSource(_previewPlayer!, customPath);
        // Auto-dispose after 10 s (covers most bell sounds)
        Timer(const Duration(seconds: 10), () {
          if (_previewPlayer != null) {
            _previewPlayer!.dispose();
            _previewPlayer = null;
          }
        });
      } catch (e) {
        debugPrint('[BellAlert] previewBell error: $e');
        _previewPlayer?.dispose();
        _previewPlayer = null;
      }
    } finally {
      _isPreviewing = false;
    }
  }

  // ── Internal ────────────────────────────────────────────────────────────────

  Future<void> _startBell() async {
    if (_pendingOrderIds.isEmpty) return;

    final uid = _userId;
    final loop = uid != null
        ? await BellSettingsService.instance.isLoopBellEnabled(uid)
        : true;
    final customPath = uid != null
        ? await BellSettingsService.instance.getCustomBellPath(uid)
        : null;

    // Check if orders were removed while we were awaiting settings
    if (_pendingOrderIds.isEmpty) {
      _isPlaying = false;
      return;
    }

    // STRESS-TEST FIX: Prevent async race condition by isolating the old player reference.
    final oldPlayer = _player;
    _player = null;
    try {
      await oldPlayer?.stop();
    } catch (_) {}
    oldPlayer?.dispose();
    
    // Final check before instantiating new player
    if (_pendingOrderIds.isEmpty) {
      _isPlaying = false;
      return;
    }

    _player = AudioPlayer();

    try {
      await _player!.setVolume(1.0);
      await _player!.setReleaseMode(
        loop ? ReleaseMode.loop : ReleaseMode.release,
      );

      _isPlaying = true;
      await _playSource(_player!, customPath);
      debugPrint('[BellAlert] Bell started (loop=$loop, custom=$customPath)');

      // Universally bind the completion listener to prevent the Silent Bell Deadlock
      // If loop is true, this won't fire until manually stopped or toggled to single-ring mid-flight.
      _player!.onPlayerComplete.listen((_) {
        _isPlaying = false;
        debugPrint('[BellAlert] Audio completed. Ready for next order.');
      });
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
    // STRESS-TEST FIX: Prevent stopBell from accidentally killing a newly started _player during event-loop yields.
    final currentPlayer = _player;
    _player = null;
    
    if (currentPlayer != null) {
      try {
        await currentPlayer.stop();
      } catch (_) {}
      currentPlayer.dispose();
    }
    
    debugPrint('[BellAlert] Bell stopped.');
  }
}
