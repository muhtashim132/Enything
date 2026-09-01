import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_cropper/image_cropper.dart' show CroppedFile;
import 'package:image/image.dart' as img;
import '../../theme/app_colors.dart';
import 'package:google_fonts/google_fonts.dart';

/// Background worker to rotate image bytes without freezing UI thread
Uint8List _rotateImageWorker(Map<String, dynamic> params) {
  final bytes = params['bytes'] as Uint8List;
  final angle = params['angle'] as int;
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  final rotated = img.copyRotate(decoded, angle: angle);
  return Uint8List.fromList(img.encodeJpg(rotated, quality: 92));
}

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
  Uint8List? _originalBytes;
  Uint8List? _imageData;
  bool _isProcessing = false;
  bool _isRotating = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final file = File(widget.imagePath);
      final bytes = await file.readAsBytes();
      if (mounted) {
        setState(() {
          _originalBytes = bytes;
          _imageData = bytes;
        });
      }
    } catch (e) {
      debugPrint('Error loading image for cropping: $e');
    }
  }

  Future<void> _rotate(int angle) async {
    if (_imageData == null || _isRotating || _isProcessing) return;
    setState(() => _isRotating = true);
    try {
      final rotated = await compute(_rotateImageWorker, {
        'bytes': _imageData!,
        'angle': angle,
      });
      if (mounted) {
        setState(() {
          _imageData = rotated;
          _isRotating = false;
        });
      }
    } catch (e) {
      debugPrint('Error rotating image: $e');
      if (mounted) {
        setState(() => _isRotating = false);
      }
    }
  }

  void _resetImage() {
    if (_originalBytes == null || _isRotating || _isProcessing) return;
    setState(() {
      _imageData = _originalBytes;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0E0E1A) : const Color(0xFF181824);
    final cardColor = isDark ? const Color(0xFF1C1C2E) : const Color(0xFF222238);
    const foregroundColor = Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          widget.title,
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w600,
            fontSize: 18,
            color: foregroundColor,
          ),
        ),
        centerTitle: true,
        backgroundColor: cardColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Cancel',
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Crop Canvas Area
            Expanded(
              child: _imageData == null || _isRotating
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: AppColors.primary),
                          SizedBox(height: 12),
                          Text(
                            'Loading image...',
                            style: TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Crop(
                          key: ValueKey(_imageData.hashCode),
                          image: _imageData!,
                          controller: _controller,
                          onCropped: (result) async {
                            final navigator = Navigator.of(context);
                            final messenger = ScaffoldMessenger.of(context);
                            if (result is CropSuccess) {
                              try {
                                final dir = await getTemporaryDirectory();
                                final tempPath =
                                    '${dir.path}/cropped_${DateTime.now().millisecondsSinceEpoch}.jpg';
                                final file = File(tempPath);
                                await file.writeAsBytes(result.croppedImage);
                                if (mounted) {
                                  navigator.pop(CroppedFile(tempPath));
                                }
                              } catch (e) {
                                if (mounted) {
                                  messenger.showSnackBar(
                                    const SnackBar(
                                        content: Text('Error saving cropped image.')),
                                  );
                                  navigator.pop();
                                }
                              }
                            } else {
                              if (mounted) {
                                messenger.showSnackBar(
                                  const SnackBar(
                                      content: Text('Error cropping image.')),
                                );
                                setState(() => _isProcessing = false);
                              }
                            }
                          },
                          aspectRatio: widget.aspectRatio,
                          baseColor: bgColor,
                          maskColor: Colors.black.withValues(alpha: 0.65),
                          radius: 12,
                          cornerDotBuilder: (size, edgeAlignment) => Container(
                            width: size,
                            height: size,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    ),
            ),

            // Controls & Action Bar
            Container(
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Rotation & Reset Tools
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _ToolButton(
                        icon: Icons.rotate_left_rounded,
                        label: 'Rotate Left',
                        onTap: _isRotating || _isProcessing ? null : () => _rotate(-90),
                      ),
                      const SizedBox(width: 24),
                      _ToolButton(
                        icon: Icons.refresh_rounded,
                        label: 'Reset',
                        onTap: _isRotating || _isProcessing ? null : _resetImage,
                      ),
                      const SizedBox(width: 24),
                      _ToolButton(
                        icon: Icons.rotate_right_rounded,
                        label: 'Rotate Right',
                        onTap: _isRotating || _isProcessing ? null : () => _rotate(90),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Cancel and Done CTA Buttons
                  Row(
                    children: [
                      // Cancel Button
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isProcessing || _isRotating
                              ? null
                              : () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded, size: 18),
                          label: Text(
                            'Cancel',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: const BorderSide(color: Colors.white24, width: 1.2),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      // Done Button
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isProcessing || _isRotating || _imageData == null
                              ? null
                              : () {
                                  setState(() => _isProcessing = true);
                                  _controller.crop();
                                },
                          icon: _isProcessing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check_rounded, size: 18),
                          label: Text(
                            _isProcessing ? 'Processing' : 'Done',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
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

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
