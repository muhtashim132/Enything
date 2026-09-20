import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import '../main.dart';
import '../theme/app_colors.dart';

class PermissionUtils {
  /// Displays a Google Play Policy compliant prominent disclosure dialog
  /// immediately before triggering the native location permission prompt.
  ///
  /// **iOS**: Skips the custom dialog entirely — Apple guidelines discourage
  /// pre-permission prompts. The `Info.plist` usage description serves as the
  /// disclosure. Directly triggers the native permission prompt.
  ///
  /// **Android**: Shows a dismissible dialog with "Not Now" and "I Understand"
  /// buttons. If the user taps "Not Now" or dismisses, returns
  /// [LocationPermission.denied] without triggering the native prompt.
  static Future<LocationPermission> requestLocationPermissionWithDisclosure({
    String? customReason,
  }) async {
    // iOS: Apple discourages custom pre-permission dialogs.
    // The Info.plist usage description serves as the disclosure.
    if (Platform.isIOS) {
      return await Geolocator.requestPermission();
    }

    // Android: Google Play requires a prominent disclosure before requesting
    // location permission. Show a dismissible dialog with "Not Now" option.
    final ctx = navigatorKey.currentContext;

    if (ctx != null && ctx.mounted) {
      final accepted = await showDialog<bool>(
        context: ctx,
        barrierDismissible: true,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.location_on_rounded,
                  color: AppColors.primary, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Location Access',
                  style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold, fontSize: 20),
                ),
              ),
            ],
          ),
          content: Text(
            customReason ??
                'Enything collects location data to enable accurate delivery tracking, live order dispatching, and seamless map routing even when the app is closed or not in use.',
            style: GoogleFonts.outfit(fontSize: 16, color: Colors.black87),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'Not Now',
                style: GoogleFonts.outfit(color: Colors.grey.shade600),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(
                'I Understand',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );

      // User dismissed or tapped "Not Now" — don't fire native prompt
      if (accepted != true) {
        return LocationPermission.denied;
      }
    }

    // After the disclosure is accepted (or skipped if no context), request the native permission
    return await Geolocator.requestPermission();
  }

  /// Shows a confirmation dialog before opening device settings.
  ///
  /// Used when location services are disabled or permission is permanently
  /// denied. The user must explicitly confirm they want to leave the app and
  /// open iOS/Android settings — we never redirect automatically.
  ///
  /// Returns `true` if the user chose to open settings, `false` otherwise.
  static Future<bool> showOpenSettingsDialog({
    required String title,
    required String message,
    String actionLabel = 'Open Settings',
  }) async {
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return false;

    final result = await showDialog<bool>(
      context: ctx,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.settings_rounded,
                color: AppColors.primary, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold, fontSize: 20),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: GoogleFonts.outfit(fontSize: 16, color: Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Not Now',
              style: GoogleFonts.outfit(color: Colors.grey.shade600),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(
              actionLabel,
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    return result ?? false;
  }
}
