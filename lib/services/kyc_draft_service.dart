import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to persist and recover KYC form drafts and pending image picker slots.
///
/// Prevents data loss when the Android OS Low Memory Killer (LMK) destroys
/// MainActivity while the Camera or Gallery Intent is active.
class KycDraftService {
  static const _prefix = 'enything_kyc_draft_';
  static const _pendingSlotPrefix = 'enything_kyc_pending_slot_';

  // ==========================================
  // PENDING PICKER SLOT TRACKING (FOR LMK RECOVERY)
  // ==========================================

  /// Records which document slot the user is currently capturing before
  /// launching the camera/gallery picker.
  static Future<void> setPendingSlot(String workflow, String slotKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_pendingSlotPrefix$workflow', slotKey);
    } catch (e) {
      debugPrint('Error setting pending KYC slot: $e');
    }
  }

  /// Retrieves the slot key that was being picked if the OS restarted the app.
  static Future<String?> getPendingSlot(String workflow) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('$_pendingSlotPrefix$workflow');
    } catch (e) {
      debugPrint('Error getting pending KYC slot: $e');
      return null;
    }
  }

  /// Clears the pending slot after successful retrieval or cancellation.
  static Future<void> clearPendingSlot(String workflow) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_pendingSlotPrefix$workflow');
    } catch (e) {
      debugPrint('Error clearing pending KYC slot: $e');
    }
  }

  // ==========================================
  // SELLER KYC DRAFT MANAGEMENT
  // ==========================================

  static Future<void> saveSellerDraft({
    required String userId,
    required Map<String, String> textFields,
    required Map<String, String?> filePaths,
    bool? isGstRegistered,
    bool? exemptionDeclared,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'textFields': textFields,
        'filePaths': filePaths,
        'isGstRegistered': isGstRegistered,
        'exemptionDeclared': exemptionDeclared,
        'updatedAt': DateTime.now().toIso8601String(),
      };
      await prefs.setString('${_prefix}seller_$userId', jsonEncode(data));
    } catch (e) {
      debugPrint('Error saving seller KYC draft: $e');
    }
  }

  static Future<Map<String, dynamic>?> getSellerDraft(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('${_prefix}seller_$userId');
      if (raw == null || raw.isEmpty) return null;
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Error reading seller KYC draft: $e');
      return null;
    }
  }

  static Future<void> clearSellerDraft(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('${_prefix}seller_$userId');
    } catch (e) {
      debugPrint('Error clearing seller KYC draft: $e');
    }
  }

  // ==========================================
  // DELIVERY KYC DRAFT MANAGEMENT
  // ==========================================

  static Future<void> saveDeliveryDraft({
    required String userId,
    required Map<String, String> textFields,
    required Map<String, String?> filePaths,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'textFields': textFields,
        'filePaths': filePaths,
        'updatedAt': DateTime.now().toIso8601String(),
      };
      await prefs.setString('${_prefix}delivery_$userId', jsonEncode(data));
    } catch (e) {
      debugPrint('Error saving delivery KYC draft: $e');
    }
  }

  static Future<Map<String, dynamic>?> getDeliveryDraft(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('${_prefix}delivery_$userId');
      if (raw == null || raw.isEmpty) return null;
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Error reading delivery KYC draft: $e');
      return null;
    }
  }

  static Future<void> clearDeliveryDraft(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('${_prefix}delivery_$userId');
    } catch (e) {
      debugPrint('Error clearing delivery KYC draft: $e');
    }
  }

  /// Helper to convert a cached file path to a valid File object if it exists.
  static File? fileFromPath(String? path) {
    if (path == null || path.isEmpty) return null;
    try {
      final f = File(path);
      if (f.existsSync()) return f;
    } catch (e) {
      debugPrint('File check failed for path $path: $e');
    }
    return null;
  }
}
