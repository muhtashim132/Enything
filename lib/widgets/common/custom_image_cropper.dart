import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_cropper/image_cropper.dart' show CroppedFile;
import '../../theme/app_colors.dart';
import 'package:google_fonts/google_fonts.dart';

class CustomImageCropperPage extends StatefulWidget {
  final String imagePath;
  final double? aspectRatio;
  final String title;

  const CustomImageCropperPage({
    super.key,
    required this.imagePath,
    this.aspectRatio,
    this.title = 'Crop Image',
  });

  @override
  State<CustomImageCropperPage> createState() => _CustomImageCropperPageState();
}

class _CustomImageCropperPageState extends State<CustomImageCropperPage> {
  final _controller = CropController();
  Uint8List? _imageData;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    final file = File(widget.imagePath);
    final bytes = await file.readAsBytes();
    if (mounted) {
      setState(() {
        _imageData = bytes;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0E0E1A) : const Color(0xFFF4F6FB);
    final cardColor = isDark ? const Color(0xFF1C1C2E) : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          widget.title,
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w600,
            fontSize: 18,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        backgroundColor: cardColor,
        elevation: 0,
        automaticallyImplyLeading: false, // We use custom cancel button at bottom
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _imageData == null
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : Crop(
                      image: _imageData!,
                      controller: _controller,
                      onCropped: (result) async {
                        final navigator = Navigator.of(context);
                        final messenger = ScaffoldMessenger.of(context);
                        setState(() => _isProcessing = true);
                        if (result is CropSuccess) {
                          try {
                            final dir = await getTemporaryDirectory();
                            final tempPath = '${dir.path}/cropped_${DateTime.now().millisecondsSinceEpoch}.jpg';
                            final file = File(tempPath);
                            await file.writeAsBytes(result.croppedImage);
                            if (mounted) {
                              navigator.pop(CroppedFile(tempPath));
                            }
                          } catch (e) {
                            if (mounted) {
                              messenger.showSnackBar(
                                const SnackBar(content: Text('Error saving cropped image.')),
                              );
                              navigator.pop();
                            }
                          }
                        } else {
                          if (mounted) {
                            messenger.showSnackBar(
                              const SnackBar(content: Text('Error cropping image.')),
                            );
                            setState(() => _isProcessing = false);
                          }
                        }
                      },
                      aspectRatio: widget.aspectRatio,
                      baseColor: bgColor,
                      maskColor: isDark ? Colors.black54 : Colors.white54,
                    ),
            ),
            Container(
              color: cardColor,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Cancel Button
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, size: 20),
                      label: Text(
                        'Cancel',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        side: const BorderSide(color: AppColors.border, width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Done Button
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing ? null : () {
                        setState(() => _isProcessing = true);
                        _controller.crop();
                      },
                      icon: _isProcessing 
                          ? const SizedBox(
                              width: 20, 
                              height: 20, 
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)
                            )
                          : const Icon(Icons.check_rounded, size: 20),
                      label: Text(
                        _isProcessing ? 'Processing' : 'Done',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
