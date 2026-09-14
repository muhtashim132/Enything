import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// High-performance background worker to composite alignment transforms and canvas fill
Uint8List _renderAlignedImageWorker(Map<String, dynamic> params) {
  final bytes = params['bytes'] as Uint8List;
  final scale = (params['scale'] as num?)?.toDouble() ?? 1.0;
  final angle = (params['angle'] as num?)?.toDouble() ?? 0.0;
  final normOffsetX = (params['normOffsetX'] as num?)?.toDouble() ?? 0.0;
  final normOffsetY = (params['normOffsetY'] as num?)?.toDouble() ?? 0.0;
  final flipH = params['flipH'] as bool? ?? false;
  final flipV = params['flipV'] as bool? ?? false;
  final bgColorValue = params['bgColorValue'] as int? ?? 0xFFFFFFFF;
  final aspectRatio = (params['aspectRatio'] as num?)?.toDouble();

  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;

  var processed = decoded;

  // 1. Mirror Flips
  if (flipH) {
    processed = img.flipHorizontal(processed);
  }
  if (flipV) {
    processed = img.flipVertical(processed);
  }

  // 2. Straighten & Tilt Rotation
  if (angle.abs() > 0.05) {
    processed = img.copyRotate(processed, angle: angle);
  }

  // 3. Target Canvas Dimensions (high-resolution e-commerce standards)
  final int canvasWidth;
  final int canvasHeight;
  const int maxDim = 1600;
  const int minDim = 800;

  if (aspectRatio != null) {
    if ((aspectRatio - 1.0).abs() < 0.01) {
      // 1:1 Square
      final side = math.max(processed.width, processed.height).clamp(minDim, maxDim);
      canvasWidth = side;
      canvasHeight = side;
    } else if (aspectRatio > 1.0) {
      // Widescreen (e.g. 16:9 banner)
      canvasWidth = math.max(processed.width, minDim).clamp(minDim, maxDim);
      canvasHeight = (canvasWidth / aspectRatio).round();
    } else {
      // Portrait / Fashion (e.g. 3:4)
      canvasHeight = math.max(processed.height, minDim).clamp(minDim, maxDim);
      canvasWidth = (canvasHeight * aspectRatio).round();
    }
  } else {
    // Free aspect ratio: Canvas fits the rotated image dimensions
    canvasWidth = processed.width;
    canvasHeight = processed.height;
  }

  // 4. Base Fit Scale + User Zoom Scaling
  final double baseScale = math.min(
    canvasWidth / processed.width,
    canvasHeight / processed.height,
  );
  final effectiveScale = baseScale * scale;
  final targetW = math.max(1, (processed.width * effectiveScale).round());
  final targetH = math.max(1, (processed.height * effectiveScale).round());

  final scaledImage = img.copyResize(
    processed,
    width: targetW,
    height: targetH,
    interpolation: img.Interpolation.linear,
  );

  // 5. Canvas with Selected Background Fill
  final canvas = img.Image(width: canvasWidth, height: canvasHeight);
  final bgR = (bgColorValue >> 16) & 0xFF;
  final bgG = (bgColorValue >> 8) & 0xFF;
  final bgB = bgColorValue & 0xFF;
  final bgA = (bgColorValue >> 24) & 0xFF;
  canvas.clear(img.ColorRgba8(bgR, bgG, bgB, bgA));

  // 6. Center Placement + Relative User Pan Offset
  final centerX = (canvasWidth - targetW) ~/ 2;
  final centerY = (canvasHeight - targetH) ~/ 2;
  final shiftX = (normOffsetX * canvasWidth).round();
  final shiftY = (normOffsetY * canvasHeight).round();

  img.compositeImage(
    canvas,
    scaledImage,
    dstX: centerX + shiftX,
    dstY: centerY + shiftY,
  );

  // 7. Output High-Quality JPEG
  return Uint8List.fromList(img.encodeJpg(canvas, quality: 92));
}

/// Dual Studio Modes
enum StudioMode { crop, align }

class CustomImageCropperPage extends StatefulWidget {
  final String imagePath;
  final double? aspectRatio;
  final String title;
  final bool initialAlignMode;

  const CustomImageCropperPage({
    super.key,
    required this.imagePath,
    this.aspectRatio,
    this.title = 'Crop Image',
    this.initialAlignMode = false,
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
  late double? _currentAspectRatio;

  // Studio Mode
  late StudioMode _mode;

  // Alignment & Scale Transform State
  double _alignScale = 1.0;
  double _alignAngle = 0.0;
  Offset _alignOffset = Offset.zero;
  bool _flipH = false;
  bool _flipV = false;
  Color _canvasBgColor = Colors.white;

  // Image pixel dimensions for auto-fitting calculations
  int _imgPixelWidth = 1;
  int _imgPixelHeight = 1;

  // Gesture tracking
  Offset _startFocalPoint = Offset.zero;
  Offset _startOffset = Offset.zero;
  double _startScale = 1.0;
  bool _isInteracting = false;

  // Canvas bounds cache for normalized coordinate math
  double _lastFrameWidth = 0.0;
  double _lastFrameHeight = 0.0;

  @override
  void initState() {
    super.initState();
    _currentAspectRatio = widget.aspectRatio;
    _mode = widget.initialAlignMode ? StudioMode.align : StudioMode.crop;
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

        // Fast native decode to cache image aspect ratio for smart presets
        ui.decodeImageFromList(bytes, (ui.Image img) {
          if (mounted) {
            setState(() {
              _imgPixelWidth = img.width;
              _imgPixelHeight = img.height;
            });
          }
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
          // Swap dimensions
          final tempW = _imgPixelWidth;
          _imgPixelWidth = _imgPixelHeight;
          _imgPixelHeight = tempW;
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
      _alignScale = 1.0;
      _alignAngle = 0.0;
      _alignOffset = Offset.zero;
      _flipH = false;
      _flipV = false;
      _canvasBgColor = Colors.white;
    });
  }

  /// Calculates the scale required to completely cover the framing box
  double _computeFillScale() {
    if (_imgPixelWidth <= 0 || _imgPixelHeight <= 0) return 1.0;
    final imgRatio = _imgPixelWidth / _imgPixelHeight;
    final targetRatio = _currentAspectRatio ?? imgRatio;

    if (imgRatio > targetRatio) {
      return (imgRatio / targetRatio).clamp(0.5, 3.0);
    } else {
      return (targetRatio / imgRatio).clamp(0.5, 3.0);
    }
  }

  Future<void> _applyAlignmentAndExport() async {
    if (_imageData == null || _isProcessing) return;
    setState(() => _isProcessing = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final previewW = _lastFrameWidth > 0 ? _lastFrameWidth : 400.0;
      final previewH = _lastFrameHeight > 0 ? _lastFrameHeight : 400.0;
      final normOffsetX = _alignOffset.dx / previewW;
      final normOffsetY = _alignOffset.dy / previewH;

      final renderedBytes = await compute(_renderAlignedImageWorker, {
        'bytes': _imageData!,
        'scale': _alignScale,
        'angle': _alignAngle,
        'normOffsetX': normOffsetX,
        'normOffsetY': normOffsetY,
        'flipH': _flipH,
        'flipV': _flipV,
        'bgColorValue': _canvasBgColor.toARGB32(),
        'aspectRatio': _currentAspectRatio,
      });

      final dir = await getTemporaryDirectory();
      final tempPath =
          '${dir.path}/aligned_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = File(tempPath);
      await file.writeAsBytes(renderedBytes);

      if (mounted) {
        navigator.pop(CroppedFile(tempPath));
      }
    } catch (e) {
      debugPrint('Error applying alignment: $e');
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Error saving aligned image: $e')),
        );
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0E0E1A) : const Color(0xFF181824);
    final cardColor = isDark ? const Color(0xFF1C1C2E) : const Color(0xFF222238);
    const foregroundColor = Colors.white;

    final isWidescreenBanner = widget.aspectRatio != null &&
        (widget.aspectRatio! - (16.0 / 9.0)).abs() < 0.1;

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
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Cancel',
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Studio Mode Switcher Bar ──────────────────────────────
            Container(
              margin: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _ModeTab(
                      icon: Icons.crop_rounded,
                      label: 'Crop & Frame',
                      isSelected: _mode == StudioMode.crop,
                      onTap: () {
                        if (_isProcessing || _isRotating) return;
                        HapticFeedback.selectionClick();
                        setState(() => _mode = StudioMode.crop);
                      },
                    ),
                  ),
                  Expanded(
                    child: _ModeTab(
                      icon: Icons.tune_rounded,
                      label: 'Align & Scale',
                      isSelected: _mode == StudioMode.align,
                      onTap: () {
                        if (_isProcessing || _isRotating) return;
                        HapticFeedback.selectionClick();
                        setState(() => _mode = StudioMode.align);
                      },
                    ),
                  ),
                ],
              ),
            ),

            // ── Interactive Canvas Area ───────────────────────────────
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
                            style:
                                TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  : _mode == StudioMode.crop
                      ? _buildCropCanvas(bgColor)
                      : _buildAlignCanvas(),
            ),

            // ── Controls & Action Bar ─────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: _mode == StudioMode.crop
                  ? _buildCropControls(isWidescreenBanner)
                  : _buildAlignControls(isWidescreenBanner),
            ),
          ],
        ),
      ),
    );
  }

  // ── Mode 1: Crop Canvas ───────────────────────────────────────────
  Widget _buildCropCanvas(Color bgColor) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Crop(
          key: ValueKey('${_imageData.hashCode}_$_currentAspectRatio'),
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
          aspectRatio: _currentAspectRatio,
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
    );
  }

  // ── Mode 2: Align & Scale Canvas ──────────────────────────────────
  Widget _buildAlignCanvas() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final imgRatio = _imgPixelWidth > 0 && _imgPixelHeight > 0
            ? _imgPixelWidth / _imgPixelHeight
            : 1.0;
        final targetRatio = _currentAspectRatio ?? imgRatio;

        final availW = math.max(10.0, constraints.maxWidth - 24);
        final availH = math.max(10.0, constraints.maxHeight - 24);

        double frameW;
        double frameH;
        if (availW / availH > targetRatio) {
          frameH = availH;
          frameW = frameH * targetRatio;
        } else {
          frameW = availW;
          frameH = frameW / targetRatio;
        }

        _lastFrameWidth = frameW;
        _lastFrameHeight = frameH;

        return Center(
          child: GestureDetector(
            onScaleStart: (details) {
              _startFocalPoint = details.localFocalPoint;
              _startOffset = _alignOffset;
              _startScale = _alignScale;
              setState(() => _isInteracting = true);
            },
            onScaleUpdate: (details) {
              final delta = details.localFocalPoint - _startFocalPoint;
              setState(() {
                _alignOffset = _startOffset + delta;
                if (details.scale != 1.0) {
                  _alignScale = (_startScale * details.scale).clamp(0.5, 3.0);
                }
              });
            },
            onScaleEnd: (_) {
              setState(() => _isInteracting = false);
            },
            child: Container(
              width: frameW,
              height: frameH,
              decoration: BoxDecoration(
                color: _canvasBgColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isInteracting ? AppColors.primary : Colors.white24,
                  width: _isInteracting ? 2.0 : 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Transformed Image with matrix alignment
                    Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..translateByDouble(_alignOffset.dx, _alignOffset.dy, 0.0, 1.0)
                        ..scaleByDouble(
                          _flipH ? -_alignScale : _alignScale,
                          _flipV ? -_alignScale : _alignScale,
                          1.0,
                          1.0,
                        )
                        ..rotateZ(_alignAngle * math.pi / 180.0),
                      child: Image.memory(
                        _imageData!,
                        fit: BoxFit.contain,
                      ),
                    ),

                    // Dynamic Horizon & Rule-of-Thirds Leveling Grid
                    IgnorePointer(
                      child: CustomPaint(
                        size: Size(frameW, frameH),
                        painter: AlignmentGridPainter(
                          isInteracting: _isInteracting,
                        ),
                      ),
                    ),

                    // Live Status Badge (Top-Right)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Text(
                          '${_alignScale.toStringAsFixed(2)}x • ${_alignAngle >= 0 ? '+' : ''}${_alignAngle.toStringAsFixed(1)}°',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Controls: Crop Mode ───────────────────────────────────────────
  Widget _buildCropControls(bool isWidescreenBanner) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Aspect Ratio Selector Chips
        _buildRatioChips(isWidescreenBanner),
        const SizedBox(height: 14),

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

        // Cancel / Done Buttons
        _buildActionRow(
          onDone: _isProcessing || _isRotating || _imageData == null
              ? null
              : () {
                  setState(() => _isProcessing = true);
                  _controller.crop();
                },
        ),
      ],
    );
  }

  // ── Controls: Align & Scale Mode ──────────────────────────────────
  Widget _buildAlignControls(bool isWidescreenBanner) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Ratio Chips
          _buildRatioChips(isWidescreenBanner),
          const SizedBox(height: 10),

          // 2. Alignment Scale Slider & Presets
          Row(
            children: [
              const Icon(Icons.zoom_in_rounded, color: Colors.white70, size: 18),
              const SizedBox(width: 6),
              Text(
                'Scale',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
              ),
              const Spacer(),
              Text(
                '${(_alignScale * 100).round()}% (${_alignScale.toStringAsFixed(2)}x)',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 7),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor: AppColors.primary,
                    inactiveTrackColor: Colors.white12,
                    thumbColor: Colors.white,
                  ),
                  child: Slider(
                    value: _alignScale,
                    min: 0.5,
                    max: 3.0,
                    onChanged: (val) {
                      setState(() => _alignScale = val);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _QuickActionChip(
                label: 'Fit',
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() {
                    _alignScale = 1.0;
                    _alignOffset = Offset.zero;
                  });
                },
              ),
              const SizedBox(width: 4),
              _QuickActionChip(
                label: 'Fill',
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() {
                    _alignScale = _computeFillScale();
                    _alignOffset = Offset.zero;
                  });
                },
              ),
              const SizedBox(width: 4),
              _QuickActionChip(
                label: '1.0x',
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() => _alignScale = 1.0);
                },
              ),
            ],
          ),

          // 3. Straighten & Tilt Slider
          Row(
            children: [
              const Icon(Icons.straighten_rounded,
                  color: Colors.white70, size: 18),
              const SizedBox(width: 6),
              Text(
                'Straighten',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
              ),
              const Spacer(),
              Text(
                '${_alignAngle >= 0 ? '+' : ''}${_alignAngle.toStringAsFixed(1)}°',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 7),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor: AppColors.primary,
                    inactiveTrackColor: Colors.white12,
                    thumbColor: Colors.white,
                  ),
                  child: Slider(
                    value: _alignAngle,
                    min: -45.0,
                    max: 45.0,
                    onChanged: (val) {
                      // Auto-snap to 0.0 if within ±0.5°
                      final angle = val.abs() <= 0.5 ? 0.0 : val;
                      setState(() => _alignAngle = angle);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _QuickActionChip(
                label: '0° Reset',
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() => _alignAngle = 0.0);
                },
              ),
            ],
          ),

          // 4. Quick Alignment Tools & Canvas Fill Swatches
          const SizedBox(height: 6),
          Row(
            children: [
              // 1-Tap Alignment Tool Icons
              _SmallIconButton(
                icon: Icons.filter_center_focus_rounded,
                tooltip: 'Center All',
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() => _alignOffset = Offset.zero);
                },
              ),
              const SizedBox(width: 4),
              _SmallIconButton(
                icon: Icons.align_horizontal_center_rounded,
                tooltip: 'H-Center',
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() =>
                      _alignOffset = Offset(0, _alignOffset.dy));
                },
              ),
              const SizedBox(width: 4),
              _SmallIconButton(
                icon: Icons.align_vertical_center_rounded,
                tooltip: 'V-Center',
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() =>
                      _alignOffset = Offset(_alignOffset.dx, 0));
                },
              ),
              const SizedBox(width: 4),
              _SmallIconButton(
                icon: Icons.flip_rounded,
                tooltip: 'Flip Horizontal',
                isActive: _flipH,
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() => _flipH = !_flipH);
                },
              ),
              const SizedBox(width: 4),
              _SmallIconButton(
                icon: Icons.flip_camera_android_rounded,
                tooltip: 'Flip Vertical',
                isActive: _flipV,
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() => _flipV = !_flipV);
                },
              ),

              const Spacer(),

              // Background Fill Swatches (White, Light Gray, Dark)
              Text(
                'Fill:',
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white54,
                ),
              ),
              const SizedBox(width: 6),
              _ColorSwatch(
                color: Colors.white,
                tooltip: 'Pure White (Standard)',
                isSelected: _canvasBgColor == Colors.white,
                onTap: () => setState(() => _canvasBgColor = Colors.white),
              ),
              const SizedBox(width: 6),
              _ColorSwatch(
                color: const Color(0xFFF4F5F7),
                tooltip: 'Neutral Light Gray',
                isSelected: _canvasBgColor == const Color(0xFFF4F5F7),
                onTap: () =>
                    setState(() => _canvasBgColor = const Color(0xFFF4F5F7)),
              ),
              const SizedBox(width: 6),
              _ColorSwatch(
                color: const Color(0xFF181824),
                tooltip: 'Dark Canvas',
                isSelected: _canvasBgColor == const Color(0xFF181824),
                onTap: () =>
                    setState(() => _canvasBgColor = const Color(0xFF181824)),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 5. Cancel / Done Action Row
          _buildActionRow(
            onDone: _isProcessing || _isRotating || _imageData == null
                ? null
                : _applyAlignmentAndExport,
          ),
        ],
      ),
    );
  }

  // ── Helper: Aspect Ratio Chips ────────────────────────────────────
  Widget _buildRatioChips(bool isWidescreenBanner) {
    if (isWidescreenBanner) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _RatioChip(
            label: '16:9 Banner',
            icon: Icons.panorama_rounded,
            isSelected: _currentAspectRatio != null &&
                (_currentAspectRatio! - (16.0 / 9.0)).abs() < 0.1,
            onTap: () {
              if (_isRotating || _isProcessing) return;
              setState(() => _currentAspectRatio = 16.0 / 9.0);
            },
          ),
          const SizedBox(width: 8),
          _RatioChip(
            label: '1:1 Square',
            icon: Icons.crop_square_rounded,
            isSelected: _currentAspectRatio != null &&
                (_currentAspectRatio! - 1.0).abs() < 0.01,
            onTap: () {
              if (_isRotating || _isProcessing) return;
              setState(() => _currentAspectRatio = 1.0);
            },
          ),
          const SizedBox(width: 8),
          _RatioChip(
            label: 'Free',
            icon: Icons.crop_free_rounded,
            isSelected: _currentAspectRatio == null,
            onTap: () {
              if (_isRotating || _isProcessing) return;
              setState(() => _currentAspectRatio = null);
            },
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _RatioChip(
          label: '1:1 Square',
          icon: Icons.crop_square_rounded,
          isSelected: _currentAspectRatio != null &&
              (_currentAspectRatio! - 1.0).abs() < 0.01,
          onTap: () {
            if (_isRotating || _isProcessing) return;
            setState(() => _currentAspectRatio = 1.0);
          },
        ),
        const SizedBox(width: 8),
        _RatioChip(
          label: '3:4 Fashion',
          icon: Icons.crop_portrait_rounded,
          isSelected: _currentAspectRatio != null &&
              (_currentAspectRatio! - (3.0 / 4.0)).abs() < 0.01,
          onTap: () {
            if (_isRotating || _isProcessing) return;
            setState(() => _currentAspectRatio = 3.0 / 4.0);
          },
        ),
        const SizedBox(width: 8),
        _RatioChip(
          label: 'Free',
          icon: Icons.crop_free_rounded,
          isSelected: _currentAspectRatio == null,
          onTap: () {
            if (_isRotating || _isProcessing) return;
            setState(() => _currentAspectRatio = null);
          },
        ),
      ],
    );
  }

  // ── Helper: Action Buttons Row ────────────────────────────────────
  Widget _buildActionRow({required VoidCallback? onDone}) {
    return Row(
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
              padding: const EdgeInsets.symmetric(vertical: 13),
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
            onPressed: onDone,
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
              padding: const EdgeInsets.symmetric(vertical: 13),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Segmented Mode Tab ──────────────────────────────────────────────
class _ModeTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ModeTab({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : Colors.white60,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? Colors.white : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Horizon & Rule-of-Thirds Grid Painter ───────────────────────────
class AlignmentGridPainter extends CustomPainter {
  final bool isInteracting;
  final Color gridColor;

  AlignmentGridPainter({
    required this.isInteracting,
    this.gridColor = Colors.white,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paintLine = Paint()
      ..color = gridColor.withValues(alpha: isInteracting ? 0.35 : 0.16)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final paintCenter = Paint()
      ..color = AppColors.primary.withValues(alpha: isInteracting ? 0.85 : 0.4)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Rule-of-Thirds Grid Lines
    final x1 = size.width / 3.0;
    final x2 = size.width * 2.0 / 3.0;
    final y1 = size.height / 3.0;
    final y2 = size.height * 2.0 / 3.0;

    canvas.drawLine(Offset(x1, 0), Offset(x1, size.height), paintLine);
    canvas.drawLine(Offset(x2, 0), Offset(x2, size.height), paintLine);
    canvas.drawLine(Offset(0, y1), Offset(size.width, y1), paintLine);
    canvas.drawLine(Offset(0, y2), Offset(size.width, y2), paintLine);

    // Center Crosshairs Reticle
    final cx = size.width / 2.0;
    final cy = size.height / 2.0;
    const arm = 14.0;
    canvas.drawLine(Offset(cx - arm, cy), Offset(cx + arm, cy), paintCenter);
    canvas.drawLine(Offset(cx, cy - arm), Offset(cx, cy + arm), paintCenter);
  }

  @override
  bool shouldRepaint(covariant AlignmentGridPainter oldDelegate) {
    return oldDelegate.isInteracting != isInteracting;
  }
}

// ── Small Tool & Action Helpers ─────────────────────────────────────
class _QuickActionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickActionChip({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
          ),
        ),
      ),
    );
  }
}

class _SmallIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isActive;
  final VoidCallback onTap;

  const _SmallIconButton({
    required this.icon,
    required this.tooltip,
    this.isActive = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: isActive
            ? AppColors.primary
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isActive
                    ? AppColors.primary
                    : Colors.white.withValues(alpha: 0.12),
              ),
            ),
            child: Icon(
              icon,
              size: 16,
              color: isActive ? Colors.white : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  final Color color;
  final String tooltip;
  final bool isSelected;
  final VoidCallback onTap;

  const _ColorSwatch({
    required this.color,
    required this.tooltip,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? AppColors.primary : Colors.white38,
              width: isSelected ? 2.0 : 1.0,
            ),
          ),
          child: isSelected
              ? Icon(
                  Icons.check,
                  size: 13,
                  color: color.computeLuminance() > 0.5
                      ? Colors.black87
                      : Colors.white,
                )
              : null,
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

class _RatioChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _RatioChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary
                : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? AppColors.primary
                  : Colors.white.withValues(alpha: 0.15),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected ? Colors.white : Colors.white70,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? Colors.white : Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
