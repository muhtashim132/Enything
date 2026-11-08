import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'haptic_utils.dart';

/// Semantic classification for toasts and notifications.
enum ToastType {
  error,
  warning,
  success,
  info,
}

/// 100x Modern Dynamic Alert & Missing-Field Pointer Engine.
///
/// Features:
/// • Top-anchored dynamic island / floating capsule below status bar.
/// • Never obscured by software keyboards or bottom sheets.
/// • Theme-matched dark space glassmorphic container with glowing neon borders.
/// • Two-tier typography (bold field/title identifier + friendly actionable copy).
/// • Interactive swipe-up to dismiss gesture and auto-dismiss timer.
/// • Integrated haptic feedback and autofocus for missing form fields.
/// • Resilient fallback to ScaffoldMessenger when Overlay is unavailable.
class AppToast {
  static OverlayEntry? _activeEntry;
  static Timer? _dismissTimer;

  /// Display a modern floating alert at the top of the screen.
  static void show(
    BuildContext context, {
    required String message,
    String? title,
    ToastType type = ToastType.error,
    IconData? icon,
    Duration duration = const Duration(milliseconds: 3500),
    VoidCallback? onTap,
    FocusNode? focusNode,
  }) {
    // 1. Tactile Haptic Feedback
    switch (type) {
      case ToastType.error:
        HapticUtils.error();
        break;
      case ToastType.warning:
        HapticUtils.warning();
        break;
      case ToastType.success:
        HapticUtils.success();
        break;
      case ToastType.info:
        HapticUtils.light();
        break;
    }

    // 2. Auto-focus field if provided
    if (focusNode != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (focusNode.canRequestFocus) {
          focusNode.requestFocus();
        }
      });
    }

    // 3. Clear any existing active toast smoothly
    dismissCurrent();

    // 4. Resolve Overlay
    final overlayState = Overlay.maybeOf(context, rootOverlay: true) ??
        Overlay.maybeOf(context);

    if (overlayState == null) {
      // Graceful fallback to SnackBar if overlay is not available
      showSnackBar(
        context,
        message: message,
        title: title,
        type: type,
        icon: icon,
        duration: duration,
      );
      return;
    }

    // 5. Build and insert top overlay entry
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _TopToastWidget(
        title: title,
        message: message,
        type: type,
        icon: icon,
        onTap: onTap,
        onDismiss: () {
          if (_activeEntry == entry) {
            dismissCurrent();
          }
        },
      ),
    );

    _activeEntry = entry;
    overlayState.insert(entry);

    // 6. Schedule auto-dismiss
    _dismissTimer = Timer(duration, () {
      if (_activeEntry == entry) {
        dismissCurrent();
      }
    });
  }

  /// Specialized helper for highlighting missing fields or unfulfilled inputs.
  ///
  /// Points out precisely what detail is missing (e.g., "Mobile Number Required")
  /// and tells the user exactly what to enter, automatically requesting focus.
  static void showMissingField(
    BuildContext context, {
    required String fieldName,
    required String actionMessage,
    FocusNode? focusNode,
    IconData? icon,
  }) {
    show(
      context,
      title: '$fieldName Required',
      message: actionMessage,
      type: ToastType.error,
      icon: icon ?? Icons.priority_high_rounded,
      focusNode: focusNode,
    );
  }

  /// Convenience helper for errors.
  static void showError(
    BuildContext context, {
    required String message,
    String? title,
    IconData? icon,
    Duration duration = const Duration(milliseconds: 3500),
    FocusNode? focusNode,
  }) {
    show(
      context,
      title: title ?? 'Action Failed',
      message: message,
      type: ToastType.error,
      icon: icon ?? Icons.error_outline_rounded,
      duration: duration,
      focusNode: focusNode,
    );
  }

  /// Convenience helper for warnings.
  static void showWarning(
    BuildContext context, {
    required String message,
    String? title,
    IconData? icon,
    Duration duration = const Duration(milliseconds: 3500),
  }) {
    show(
      context,
      title: title ?? 'Notice',
      message: message,
      type: ToastType.warning,
      icon: icon ?? Icons.warning_amber_rounded,
      duration: duration,
    );
  }

  /// Convenience helper for successes.
  static void showSuccess(
    BuildContext context, {
    required String message,
    String? title,
    IconData? icon,
    Duration duration = const Duration(milliseconds: 3000),
  }) {
    show(
      context,
      title: title ?? 'Success',
      message: message,
      type: ToastType.success,
      icon: icon ?? Icons.check_circle_rounded,
      duration: duration,
    );
  }

  /// Convenience helper for informative notes.
  static void showInfo(
    BuildContext context, {
    required String message,
    String? title,
    IconData? icon,
    Duration duration = const Duration(milliseconds: 3000),
  }) {
    show(
      context,
      title: title ?? 'Information',
      message: message,
      type: ToastType.info,
      icon: icon ?? Icons.info_outline_rounded,
      duration: duration,
    );
  }

  /// Dismiss active toast entry immediately.
  static void dismissCurrent() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _activeEntry?.remove();
    _activeEntry = null;
  }

  /// Modernized floating SnackBar with identical theme-matched visuals.
  /// Used in bottom-bar contexts or when Overlay is unavailable.
  static void showSnackBar(
    BuildContext context, {
    required String message,
    String? title,
    ToastType type = ToastType.error,
    IconData? icon,
    Duration duration = const Duration(milliseconds: 3500),
  }) {
    final colors = _getSemanticColors(type);
    final displayIcon = icon ?? _getDefaultIcon(type);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        duration: duration,
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF14162B),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: colors.accent.withValues(alpha: 0.8),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: colors.accent.withValues(alpha: 0.28),
                blurRadius: 18,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colors.accent.withValues(alpha: 0.35),
                  ),
                ),
                child: Center(
                  child: Icon(displayIcon, color: colors.accent, size: 20),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null && title.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          title,
                          style: GoogleFonts.outfit(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    Text(
                      message,
                      style: GoogleFonts.outfit(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w400,
                        color: Colors.white70,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static _SemanticColors _getSemanticColors(ToastType type) {
    switch (type) {
      case ToastType.error:
        return const _SemanticColors(
          accent: Color(0xFFFF3B30), // Crimson Ruby
          bgTint: Color(0xFF261214),
        );
      case ToastType.warning:
        return const _SemanticColors(
          accent: Color(0xFFFFB800), // Amber Gold
          bgTint: Color(0xFF241C0F),
        );
      case ToastType.success:
        return const _SemanticColors(
          accent: Color(0xFF00E676), // Emerald Mint
          bgTint: Color(0xFF0E2218),
        );
      case ToastType.info:
        return const _SemanticColors(
          accent: Color(0xFF3D6BFF), // Electric Cobalt
          bgTint: Color(0xFF101932),
        );
    }
  }

  static IconData _getDefaultIcon(ToastType type) {
    switch (type) {
      case ToastType.error:
        return Icons.error_outline_rounded;
      case ToastType.warning:
        return Icons.warning_amber_rounded;
      case ToastType.success:
        return Icons.check_circle_rounded;
      case ToastType.info:
        return Icons.info_outline_rounded;
    }
  }
}

class _SemanticColors {
  final Color accent;
  final Color bgTint;
  const _SemanticColors({required this.accent, required this.bgTint});
}

class _TopToastWidget extends StatefulWidget {
  final String? title;
  final String message;
  final ToastType type;
  final IconData? icon;
  final VoidCallback? onTap;
  final VoidCallback onDismiss;

  const _TopToastWidget({
    this.title,
    required this.message,
    required this.type,
    this.icon,
    this.onTap,
    required this.onDismiss,
  });

  @override
  State<_TopToastWidget> createState() => _TopToastWidgetState();
}

class _TopToastWidgetState extends State<_TopToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;
  double _dragOffsetY = 0.0;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
      reverseDuration: const Duration(milliseconds: 250),
    );

    _slideAnim = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    ));

    _fadeAnim = CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );

    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleDismiss() async {
    try {
      await _animCtrl.reverse();
    } catch (_) {}
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppToast._getSemanticColors(widget.type);
    final displayIcon = widget.icon ?? AppToast._getDefaultIcon(widget.type);
    final safeTop = MediaQuery.of(context).padding.top;

    return Positioned(
      top: safeTop + 10,
      left: 14,
      right: 14,
      child: Material(
        type: MaterialType.transparency,
        child: AnimatedBuilder(
          animation: _animCtrl,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(
                _slideAnim.value.dx,
                _slideAnim.value.dy + _dragOffsetY,
              ),
              child: Opacity(
                opacity: _fadeAnim.value.clamp(0.0, 1.0),
                child: child,
              ),
            );
          },
          child: GestureDetector(
            onTap: () {
              widget.onTap?.call();
              _handleDismiss();
            },
            onVerticalDragUpdate: (details) {
              if (details.primaryDelta != null && details.primaryDelta! < 0) {
                setState(() {
                  _dragOffsetY += details.primaryDelta!;
                });
              }
            },
            onVerticalDragEnd: (details) {
              if (_dragOffsetY < -20 ||
                  (details.primaryVelocity != null &&
                      details.primaryVelocity! < -100)) {
                _handleDismiss();
              } else {
                setState(() {
                  _dragOffsetY = 0.0;
                });
              }
            },
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              decoration: BoxDecoration(
                color: const Color(0xFF14162B),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: colors.accent.withValues(alpha: 0.85),
                  width: 1.3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: colors.accent.withValues(alpha: 0.32),
                    blurRadius: 22,
                    offset: const Offset(0, 6),
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Icon badge with glowing background
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: colors.accent.withValues(alpha: 0.4),
                        width: 1.2,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        displayIcon,
                        color: colors.accent,
                        size: 21,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Title + Message
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.title != null && widget.title!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              widget.title!,
                              style: GoogleFonts.outfit(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        Text(
                          widget.message,
                          style: GoogleFonts.outfit(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w400,
                            color: Colors.white.withValues(alpha: 0.85),
                            height: 1.32,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Close icon
                  GestureDetector(
                    onTap: _handleDismiss,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        color: Colors.white54,
                        size: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
