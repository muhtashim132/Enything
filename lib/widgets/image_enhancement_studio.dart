import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import '../services/image_enhancement_service.dart';
import '../theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Internal slot model
// ─────────────────────────────────────────────────────────────────────────────

class _ImageSlot {
  final XFile? file; // New local image
  final String? url; // Existing remote URL
  final ImageEnhancementHistory history;
  Uint8List? cachedBytes; // Loaded bytes for local images
  bool isLoading; // True while bytes are being read from disk

  _ImageSlot.local(XFile f)
      : file = f,
        url = null,
        history = ImageEnhancementHistory(),
        isLoading = true;

  _ImageSlot.remote(String u)
      : file = null,
        url = u,
        history = ImageEnhancementHistory(),
        isLoading = false;

  bool get isLocal => file != null;
  String get key => file?.path ?? url ?? '';
}

// ─────────────────────────────────────────────────────────────────────────────
// ImageEnhancementStudio — full-screen editor page
// ─────────────────────────────────────────────────────────────────────────────

class ImageEnhancementStudio extends StatefulWidget {
  final List<XFile> newImages;
  final List<String> existingImageUrls;
  final bool initialBgRemovalEnabled;

  const ImageEnhancementStudio({
    super.key,
    required this.newImages,
    required this.existingImageUrls,
    this.initialBgRemovalEnabled = true,
  });

  /// Push the studio as a fullscreen modal page and return [StudioResult].
  static Future<StudioResult?> show(
    BuildContext context, {
    required List<XFile> newImages,
    required List<String> existingImageUrls,
    bool bgRemovalEnabled = true,
  }) {
    return Navigator.of(context).push<StudioResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ImageEnhancementStudio(
          newImages: newImages,
          existingImageUrls: existingImageUrls,
          initialBgRemovalEnabled: bgRemovalEnabled,
        ),
      ),
    );
  }

  @override
  State<ImageEnhancementStudio> createState() => _ImageEnhancementStudioState();
}

class _ImageEnhancementStudioState extends State<ImageEnhancementStudio>
    with SingleTickerProviderStateMixin {
  // ── State ──────────────────────────────────────────────────────────────────
  late List<_ImageSlot> _slots;
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _bgRemovalEnabled = true;
  bool _isApplying = false;
  late AnimationController _sliderAnimController;

  // ── Helpers ────────────────────────────────────────────────────────────────
  _ImageSlot get _current => _slots[_currentPage.clamp(0, _slots.length - 1)];
  ImageEnhancementSettings get _currentSettings => _current.history.current;
  bool get _currentIsLocal => _current.isLocal;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _bgRemovalEnabled = widget.initialBgRemovalEnabled;
    _sliderAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    // Build unified slot list: existing remote first, then new local
    _slots = [
      ...widget.existingImageUrls.map(_ImageSlot.remote),
      ...widget.newImages.map(_ImageSlot.local),
    ];
    _loadAllBytes();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _sliderAnimController.dispose();
    super.dispose();
  }

  Future<void> _loadAllBytes() async {
    for (int i = 0; i < _slots.length; i++) {
      final slot = _slots[i];
      if (slot.isLocal && slot.file != null) {
        try {
          final bytes = await slot.file!.readAsBytes();
          if (mounted) {
            setState(() {
              _slots[i].cachedBytes = bytes;
              _slots[i].isLoading = false;
            });
          }
        } catch (e) {
          if (mounted) setState(() => _slots[i].isLoading = false);
        }
      }
    }
  }

  // ── Enhancement actions ────────────────────────────────────────────────────
  void _updateSetting(ImageEnhancementSettings settings) {
    setState(() {
      _current.history.push(settings);
    });
  }

  void _undo() {
    setState(() => _current.history.undo());
  }

  void _redo() {
    setState(() => _current.history.redo());
  }

  void _autoEnhance() {
    _updateSetting(ImageEnhancementSettings.autoPreset);
    _sliderAnimController.forward(from: 0);
  }

  void _reset() {
    setState(() => _current.history.reset());
  }

  void _removeCurrentImage() {
    if (_slots.length <= 1) {
      Navigator.of(context).pop(); // Removing last image cancels studio
      return;
    }
    setState(() {
      _slots.removeAt(_currentPage);
      final newPage = _currentPage.clamp(0, _slots.length - 1);
      _currentPage = newPage;
      // Jump page controller
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients) {
          _pageController.jumpToPage(newPage);
        }
      });
    });
  }

  // ── Apply & return ─────────────────────────────────────────────────────────
  Future<void> _applyAndReturn() async {
    if (_isApplying) return;
    setState(() => _isApplying = true);

    try {
      final bakedBytesMap = <String, Uint8List>{};

      for (final slot in _slots) {
        if (slot.isLocal && slot.cachedBytes != null) {
          final settings = slot.history.current;
          final baked = await ImageEnhancementService.bakeEnhancement(
            slot.cachedBytes!,
            settings,
          );
          bakedBytesMap[slot.file!.path] = baked;
        }
      }

      if (!mounted) return;

      final result = StudioResult(
        newImagePaths:
            _slots.where((s) => s.isLocal).map((s) => s.file!.path).toList(),
        existingImageUrls:
            _slots.where((s) => !s.isLocal).map((s) => s.url!).toList(),
        bakedBytesMap: bakedBytesMap,
        bgRemovalEnabled: _bgRemovalEnabled,
      );

      Navigator.of(context).pop(result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Enhancement failed: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
        setState(() => _isApplying = false);
      }
    }
  }

  // ── Reorder ────────────────────────────────────────────────────────────────
  void _onReorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    setState(() {
      final slot = _slots.removeAt(oldIndex);
      _slots.insert(newIndex, slot);
      _currentPage = newIndex;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(newIndex);
      }
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final previewHeight = (size.height * 0.42).clamp(240.0, 380.0);

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          // ── Main image preview carousel ──────────────────────────────
          _buildImageCarousel(previewHeight),
          const SizedBox(height: 8),
          // ── Page dots indicator ──────────────────────────────────────
          if (_slots.length > 1) _buildPageDots(),
          const SizedBox(height: 8),
          // ── Thumbnail reorder strip ──────────────────────────────────
          if (_slots.length > 1) _buildThumbnailStrip(),
          // ── Controls (scrollable) ────────────────────────────────────
          Expanded(
            child: _buildControls(),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF0D0D1A),
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.close, color: Colors.white70),
        onPressed: () => Navigator.of(context).pop(),
        tooltip: 'Discard changes',
      ),
      title: const Text(
        '✨ Review & Enhance',
        style: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          fontFamily: 'Outfit',
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isApplying ? null : _applyAndReturn,
          child: _isApplying
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.accent,
                  ),
                )
              : const Text(
                  'Apply',
                  style: TextStyle(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    fontFamily: 'Outfit',
                  ),
                ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildImageCarousel(double height) {
    return SizedBox(
      height: height,
      child: PageView.builder(
        controller: _pageController,
        itemCount: _slots.length,
        onPageChanged: (i) => setState(() => _currentPage = i),
        itemBuilder: (context, index) {
          final slot = _slots[index];
          return _buildSlotPreview(slot);
        },
      ),
    );
  }

  Widget _buildSlotPreview(_ImageSlot slot) {
    final settings = slot.history.current;
    final matrix = settings.isIdentity
        ? null
        : ColorFilterMatrix.fromSettings(settings);

    Widget imageWidget;

    if (slot.isLocal) {
      if (slot.isLoading || slot.cachedBytes == null) {
        imageWidget = Container(
          color: const Color(0xFF1A1A2E),
          child: const Center(
            child: CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 2,
            ),
          ),
        );
      } else {
        imageWidget = Image.memory(
          slot.cachedBytes!,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _buildBrokenImage(),
        );
      }
    } else {
      imageWidget = CachedNetworkImage(
        imageUrl: slot.url!,
        fit: BoxFit.contain,
        placeholder: (_, __) => Container(
          color: const Color(0xFF1A1A2E),
          child: const Center(
            child: CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 2,
            ),
          ),
        ),
        errorWidget: (_, __, ___) => _buildBrokenImage(),
      );
    }

    // Wrap in ColorFiltered for live GPU preview
    final preview = matrix != null
        ? ColorFiltered(
            colorFilter: ColorFilter.matrix(matrix),
            child: imageWidget,
          )
        : imageWidget;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFF111128),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          preview,
          // "Existing" badge
          if (!slot.isLocal)
            Positioned(
              top: 10,
              left: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_done_rounded, color: Colors.white70, size: 12),
                    SizedBox(width: 4),
                    Text(
                      'Uploaded',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontFamily: 'Outfit',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Enhancement indicator
          if (!slot.history.current.isIdentity && slot.isLocal)
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6A1B9A), Color(0xFFAB47BC)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_fix_high, color: Colors.white, size: 12),
                    SizedBox(width: 4),
                    Text(
                      'Enhanced',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontFamily: 'Outfit',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBrokenImage() {
    return Container(
      color: const Color(0xFF1A1A2E),
      child: const Center(
        child: Icon(Icons.broken_image_outlined, color: Colors.white24, size: 48),
      ),
    );
  }

  Widget _buildPageDots() {
    return SmoothPageIndicator(
      controller: _pageController,
      count: _slots.length,
      effect: const WormEffect(
        dotHeight: 6,
        dotWidth: 6,
        activeDotColor: AppColors.accent,
        dotColor: Colors.white24,
        spacing: 6,
      ),
    );
  }

  Widget _buildThumbnailStrip() {
    return SizedBox(
      height: 72,
      child: ReorderableListView(
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: false,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        onReorder: _onReorder,
        children: List.generate(_slots.length, (index) {
          final slot = _slots[index];
          final isSelected = index == _currentPage;
          return ReorderableDragStartListener(
            key: ValueKey(slot.key),
            index: index,
            child: GestureDetector(
              onTap: () {
                setState(() => _currentPage = index);
                _pageController.animateToPage(
                  index,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 60,
                height: 60,
                margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.accent
                        : Colors.white.withValues(alpha: 0.15),
                    width: isSelected ? 2.5 : 1,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: AppColors.accent.withValues(alpha: 0.4),
                            blurRadius: 8,
                          )
                        ]
                      : null,
                ),
                clipBehavior: Clip.antiAlias,
                child: _buildThumbnailContent(slot),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildThumbnailContent(_ImageSlot slot) {
    if (slot.isLocal) {
      if (slot.cachedBytes == null) {
        return Container(
          color: const Color(0xFF1A1A2E),
          child: const Icon(Icons.hourglass_empty, color: Colors.white30, size: 16),
        );
      }
      return Image.memory(
        slot.cachedBytes!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            Container(color: Colors.white10, child: const Icon(Icons.broken_image, size: 16, color: Colors.white30)),
      );
    }
    return CachedNetworkImage(
      imageUrl: slot.url!,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(color: const Color(0xFF1A1A2E)),
      errorWidget: (_, __, ___) =>
          Container(color: Colors.white10, child: const Icon(Icons.broken_image, size: 16, color: Colors.white30)),
    );
  }

  Widget _buildControls() {
    final s = _currentSettings;
    final isLocal = _currentIsLocal;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Undo / Redo + Auto Enhance + Reset row ─────────────────
          Row(
            children: [
              _iconBtn(
                icon: Icons.undo_rounded,
                label: 'Undo',
                enabled: isLocal && _current.history.canUndo,
                onTap: _undo,
              ),
              const SizedBox(width: 8),
              _iconBtn(
                icon: Icons.redo_rounded,
                label: 'Redo',
                enabled: isLocal && _current.history.canRedo,
                onTap: _redo,
              ),
              const Spacer(),
              _gradientBtn(
                icon: Icons.auto_fix_high,
                label: '✨ Auto',
                enabled: isLocal,
                onTap: _autoEnhance,
              ),
              const SizedBox(width: 8),
              _iconBtn(
                icon: Icons.refresh_rounded,
                label: 'Reset',
                enabled: isLocal && !s.isIdentity,
                onTap: _reset,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Enhancement note for existing/remote images ────────────
          if (!isLocal)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.white38, size: 14),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Uploaded photos: use sliders to preview. Enhancements apply to new photos only.',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        fontFamily: 'Outfit',
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ── Sliders ────────────────────────────────────────────────
          const SizedBox(height: 8),
          _sliderRow(
            icon: Icons.wb_sunny_outlined,
            label: 'Brightness',
            value: s.brightness,
            min: -1.0,
            max: 1.0,
            enabled: isLocal,
            color: const Color(0xFFFACC15),
            onChanged: (v) =>
                _updateSetting(s.copyWith(brightness: v)),
          ),
          _sliderRow(
            icon: Icons.contrast,
            label: 'Contrast',
            value: s.contrast,
            min: -1.0,
            max: 1.0,
            enabled: isLocal,
            color: const Color(0xFF60A5FA),
            onChanged: (v) =>
                _updateSetting(s.copyWith(contrast: v)),
          ),
          _sliderRow(
            icon: Icons.palette_outlined,
            label: 'Saturation',
            value: s.saturation,
            min: -1.0,
            max: 1.0,
            enabled: isLocal,
            color: const Color(0xFFA78BFA),
            onChanged: (v) =>
                _updateSetting(s.copyWith(saturation: v)),
          ),
          _sliderRow(
            icon: Icons.thermostat_outlined,
            label: 'Warmth',
            value: s.warmth,
            min: -1.0,
            max: 1.0,
            enabled: isLocal,
            color: const Color(0xFFFB923C),
            onChanged: (v) =>
                _updateSetting(s.copyWith(warmth: v)),
          ),
          _sliderRow(
            icon: Icons.auto_fix_normal,
            label: 'Sharpness',
            value: s.sharpness,
            min: 0.0,
            max: 1.0,
            enabled: isLocal,
            color: const Color(0xFF34D399),
            onChanged: (v) =>
                _updateSetting(s.copyWith(sharpness: v)),
          ),
          const SizedBox(height: 12),

          // ── Image actions ──────────────────────────────────────────
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              // Remove image
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _removeCurrentImage,
                  icon: const Icon(Icons.delete_outline,
                      color: AppColors.danger, size: 18),
                  label: const Text(
                    'Remove',
                    style: TextStyle(
                      color: AppColors.danger,
                      fontFamily: 'Outfit',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.danger),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // BG Removal toggle
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _bgRemovalEnabled = !_bgRemovalEnabled),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: _bgRemovalEnabled
                          ? AppColors.primary.withValues(alpha: 0.2)
                          : Colors.white.withValues(alpha: 0.05),
                      border: Border.all(
                        color: _bgRemovalEnabled
                            ? AppColors.primary
                            : Colors.white24,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          size: 16,
                          color: _bgRemovalEnabled
                              ? AppColors.primary
                              : Colors.white38,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _bgRemovalEnabled ? 'BG Remove: ON' : 'BG Remove: OFF',
                            style: TextStyle(
                              color: _bgRemovalEnabled
                                  ? AppColors.primary
                                  : Colors.white38,
                              fontFamily: 'Outfit',
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D1A),
          border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
        ),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _isApplying ? null : _applyAndReturn,
            icon: _isApplying
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check_circle_rounded),
            label: Text(
              _isApplying ? 'Applying enhancements…' : 'Apply & Upload All Photos',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                fontFamily: 'Outfit',
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
          ),
        ),
      ),
    );
  }

  // ── Slider widget ──────────────────────────────────────────────────────────
  Widget _sliderRow({
    required IconData icon,
    required String label,
    required double value,
    required double min,
    required double max,
    required bool enabled,
    required Color color,
    required ValueChanged<double> onChanged,
  }) {
    final displayValue = (value * 100).round();
    final displayStr = displayValue >= 0 ? '+$displayValue' : '$displayValue';

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, color: enabled ? color : Colors.white24, size: 18),
          const SizedBox(width: 8),
          SizedBox(
            width: 82,
            child: Text(
              label,
              style: TextStyle(
                color: enabled ? Colors.white70 : Colors.white24,
                fontSize: 12,
                fontFamily: 'Outfit',
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: enabled ? color : Colors.white12,
                inactiveTrackColor: Colors.white12,
                thumbColor: enabled ? color : Colors.white24,
                overlayColor: color.withValues(alpha: 0.15),
                trackHeight: 3,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 7),
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: enabled ? onChanged : null,
              ),
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              displayStr,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: enabled
                    ? (value == 0 ? Colors.white38 : color)
                    : Colors.white24,
                fontSize: 11,
                fontFamily: 'Outfit',
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Button helpers ─────────────────────────────────────────────────────────
  Widget _iconBtn({
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: enabled
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 16,
                  color: enabled ? Colors.white70 : Colors.white24),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: enabled ? Colors.white70 : Colors.white24,
                  fontSize: 12,
                  fontFamily: 'Outfit',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _gradientBtn({
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: enabled
              ? const LinearGradient(
                  colors: [Color(0xFF6A1B9A), Color(0xFFAB47BC)],
                )
              : null,
          color: enabled ? null : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16,
                color: enabled ? Colors.white : Colors.white24),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: enabled ? Colors.white : Colors.white24,
                fontSize: 12,
                fontFamily: 'Outfit',
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
