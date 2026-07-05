
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';

/// Shows a premium bottom sheet letting the user choose between
/// Camera and Gallery. Returns the chosen [ImageSource] or null if dismissed.
///
/// Usage:
/// ```dart
/// final source = await showImageSourceSheet(context);
/// if (source == null) return;
/// final file = await picker.pickImage(source: source, imageQuality: 70);
/// ```
Future<ImageSource?> showImageSourceSheet(BuildContext context) async {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  return showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (ctx) {
      return Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C2E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Choose Image Source',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF0A0A14),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'How would you like to add your image?',
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                // Camera option
                Expanded(
                  child: _SourceOption(
                    isDark: isDark,
                    icon: Icons.camera_alt_rounded,
                    label: 'Take Photo',
                    sublabel: 'Use camera',
                    color: const Color(0xFF0A2A9E),
                    onTap: () => Navigator.pop(ctx, ImageSource.camera),
                  ),
                ),
                const SizedBox(width: 16),
                // Gallery option
                Expanded(
                  child: _SourceOption(
                    isDark: isDark,
                    icon: Icons.photo_library_rounded,
                    label: 'Gallery',
                    sublabel: 'Choose existing',
                    color: const Color(0xFF7C3AED),
                    onTap: () => Navigator.pop(ctx, ImageSource.gallery),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Cancel button
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: isDark ? Colors.white12 : Colors.black12,
                    ),
                  ),
                ),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _SourceOption extends StatelessWidget {
  final bool isDark;
  final IconData icon;
  final String label;
  final String sublabel;
  final Color color;
  final VoidCallback onTap;

  const _SourceOption({
    required this.isDark,
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.15 : 0.07),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF0A0A14),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sublabel,
              style: GoogleFonts.outfit(
                fontSize: 12,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Helper function to launch the image cropper with standard UI styling.
Future<CroppedFile?> cropImage(BuildContext context, String path,
    {CropAspectRatio? aspectRatio, String title = 'Crop Image'}) async {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  return await ImageCropper().cropImage(
    sourcePath: path,
    aspectRatio: aspectRatio,
    uiSettings: [
      AndroidUiSettings(
        toolbarTitle: title,
        toolbarColor: isDark ? const Color(0xFF1C1C2E) : Colors.white,
        toolbarWidgetColor: isDark ? Colors.white : Colors.black,
        initAspectRatio: CropAspectRatioPreset.original,
        lockAspectRatio: aspectRatio != null,
        hideBottomControls: false,
        backgroundColor:
            isDark ? const Color(0xFF0A0A14) : const Color(0xFFF4F6FB),
        activeControlsWidgetColor: const Color(0xFF4C6EF5),
        dimmedLayerColor: isDark ? Colors.black87 : Colors.black54,
      ),
      IOSUiSettings(
        title: title,
        aspectRatioLockEnabled: aspectRatio != null,
        rotateButtonsHidden: false,
        rotateClockwiseButtonHidden: false,
        resetButtonHidden: false,
      ),
    ],
  );
}
