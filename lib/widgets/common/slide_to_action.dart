import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';
import '../../theme/sensory_haptics.dart';

/// 100x Tactile Slide-to-Confirm action button with spring physics, milestone haptics,
/// shimmer chevron trail, and smooth error-rebound.
class SlideToAction extends StatefulWidget {
  final String label;
  final Future<void> Function() onConfirmed;
  final Color? trackColor;
  final Color? thumbColor;
  final Color? activeTrackColor;
  final Widget? icon;
  final double height;
  final double borderRadius;
  final bool isDark;
  final bool enabled;
  final bool isLoading;

  const SlideToAction({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.trackColor,
    this.thumbColor,
    this.activeTrackColor,
    this.icon,
    this.height = 58,
    this.borderRadius = 18,
    required this.isDark,
    this.enabled = true,
    this.isLoading = false,
  });

  @override
  State<SlideToAction> createState() => SlideToActionState();
}

class SlideToActionState extends State<SlideToAction>
    with TickerProviderStateMixin {
  double _dragPosition = 0.0;
  bool _isConfirmed = false;
  bool _localLoading = false;
  late AnimationController _springController;
  late Animation<double> _springAnimation;

  // Milestone haptic tracking
  int _lastMilestone = 0;

  bool get _effectiveLoading => widget.isLoading || _localLoading;

  @override
  void initState() {
    super.initState();
    _springController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _springAnimation = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _springController, curve: Curves.easeOutBack),
    )..addListener(() {
        setState(() {
          _dragPosition = _springAnimation.value;
        });
      });
  }

  @override
  void didUpdateWidget(covariant SlideToAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If loading stops and we weren't navigated away (e.g. error happened), reset slider
    if (oldWidget.isLoading && !widget.isLoading && _isConfirmed) {
      reset();
    }
  }

  @override
  void dispose() {
    _springController.dispose();
    super.dispose();
  }

  /// Resets slider to starting position
  void reset() {
    if (!mounted) return;
    _springAnimation = Tween<double>(
      begin: _dragPosition,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _springController, curve: Curves.easeOutBack));
    _springController.forward(from: 0.0);
    setState(() {
      _isConfirmed = false;
      _localLoading = false;
      _lastMilestone = 0;
    });
  }

  void _onDragUpdate(DragUpdateDetails details, double maxDrag) {
    if (!widget.enabled || _isConfirmed || _effectiveLoading) return;
    _springController.stop();

    setState(() {
      _dragPosition = (_dragPosition + details.delta.dx).clamp(0.0, maxDrag);
    });

    final progress = maxDrag > 0 ? (_dragPosition / maxDrag) : 0.0;
    final milestone = (progress * 4).floor(); // 0, 1, 2, 3, 4
    if (milestone > _lastMilestone && milestone < 4) {
      _lastMilestone = milestone;
      SensoryHaptics.selection();
    }

    if (_dragPosition >= maxDrag * 0.92 && !_isConfirmed) {
      _triggerConfirmation();
    }
  }

  void _onDragEnd(DragEndDetails details, double maxDrag) {
    if (!widget.enabled || _isConfirmed || _effectiveLoading) return;
    if (_dragPosition < maxDrag * 0.92) {
      _springAnimation = Tween<double>(
        begin: _dragPosition,
        end: 0.0,
      ).animate(CurvedAnimation(parent: _springController, curve: Curves.easeOutBack));
      _springController.forward(from: 0.0);
      _lastMilestone = 0;
    }
  }

  void _triggerConfirmation() async {
    SensoryHaptics.heavy();
    setState(() {
      _isConfirmed = true;
      _localLoading = true;
    });

    try {
      await widget.onConfirmed();
    } catch (_) {
      // Handled by parent
    } finally {
      if (mounted) {
        setState(() => _localLoading = false);
        // If still on the screen after 600ms, reset so user can slide again
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted && _isConfirmed) {
            reset();
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final thumbSize = widget.height - 10;
    final defaultTrack = widget.isDark
        ? const Color(0xFF1E2034)
        : const Color(0xFFF1F3F9);
    final activeTrack = widget.activeTrackColor ?? AppColors.secondary;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxDrag = (constraints.maxWidth - thumbSize - 10).clamp(0.0, double.infinity);
        final progress = maxDrag > 0 ? (_dragPosition / maxDrag).clamp(0.0, 1.0) : 0.0;

        return Opacity(
          opacity: widget.enabled ? 1.0 : 0.5,
          child: Container(
            height: widget.height,
            width: double.infinity,
            decoration: BoxDecoration(
              color: widget.trackColor ?? defaultTrack,
              borderRadius: BorderRadius.circular(widget.borderRadius),
              border: Border.all(
                color: widget.isDark
                    ? Colors.white.withValues(alpha: 0.10)
                    : Colors.black.withValues(alpha: 0.06),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: widget.isDark ? 0.35 : 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // Active fill gradient behind thumb
                if (progress > 0.01)
                  Container(
                    width: _dragPosition + thumbSize + 5,
                    height: widget.height,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          activeTrack.withValues(alpha: 0.85),
                          activeTrack,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(widget.borderRadius),
                      boxShadow: [
                        BoxShadow(
                          color: activeTrack.withValues(alpha: 0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),

                // Center Action Label (Fades out as user slides)
                Center(
                  child: Opacity(
                    opacity: (1.0 - progress * 1.6).clamp(0.0, 1.0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.label,
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                            color: widget.isDark ? Colors.white : AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.keyboard_double_arrow_right_rounded,
                          size: 20,
                          color: activeTrack,
                        ),
                      ],
                    ),
                  ),
                ),

                // Draggable floating Thumb
                Positioned(
                  left: 5 + _dragPosition,
                  child: GestureDetector(
                    onHorizontalDragUpdate: (d) => _onDragUpdate(d, maxDrag),
                    onHorizontalDragEnd: (d) => _onDragEnd(d, maxDrag),
                    child: Container(
                      width: thumbSize,
                      height: thumbSize,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFFFFF), Color(0xFFF7FAFC)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: activeTrack.withValues(alpha: 0.40),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Center(
                        child: _effectiveLoading
                            ? SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: activeTrack,
                                ),
                              )
                            : widget.icon ??
                                Icon(
                                  _isConfirmed
                                      ? Icons.check_rounded
                                      : Icons.arrow_forward_rounded,
                                  color: activeTrack,
                                  size: 22,
                                ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
