import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import '../main.dart';
import '../theme/app_colors.dart';

class PermissionUtils {
  /// Displays a Google Play Policy compliant prominent disclosure dialog
  /// immediately before triggering the native location permission prompt.
  static Future<LocationPermission> requestLocationPermissionWithDisclosure({
    String? customReason,
  }) async {
    final ctx = navigatorKey.currentContext;

    // Show the prominent disclosure if a context is available
    if (ctx != null && ctx.mounted) {
      await showDialog(
        context: ctx,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.location_on_rounded, color: AppColors.primary, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Location Access',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 20),
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
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(
                'I Understand',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    }

    // After the dialog is dismissed (or skipped if no context), request the native permission
    return await Geolocator.requestPermission();
  }
}
