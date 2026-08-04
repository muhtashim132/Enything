import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class PremiumLoadingIndicator extends StatelessWidget {
  final double size;
  final double strokeWidth;
  final bool isDark;

  const PremiumLoadingIndicator({
    super.key,
    this.size = 40.0,
    this.strokeWidth = 3.5,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(
          strokeWidth: strokeWidth,
          valueColor: AlwaysStoppedAnimation<Color>(
            isDark ? AppColors.secondaryLight : AppColors.primary,
          ),
          backgroundColor: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : AppColors.primary.withValues(alpha: 0.1),
        ),
      ),
    );
  }
}

class PremiumPulseLoadingIndicator extends StatefulWidget {
  final double size;
  final bool isDark;

  const PremiumPulseLoadingIndicator({
    super.key,
    this.size = 60.0,
    required this.isDark,
  });

  @override
  State<PremiumPulseLoadingIndicator> createState() =>
      _PremiumPulseLoadingIndicatorState();
}

class _PremiumPulseLoadingIndicatorState
    extends State<PremiumPulseLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _opacityAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Opacity(
            opacity: _opacityAnimation.value,
            child: Transform.scale(
              scale: _scaleAnimation.value,
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.isDark
                      ? AppColors.secondaryLight.withValues(alpha: 0.5)
                      : AppColors.primary.withValues(alpha: 0.5),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
