import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';

class LiquidStepItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isCompleted;
  final bool isCurrent;

  const LiquidStepItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isCompleted,
    required this.isCurrent,
  });
}

/// Liquid glowing conduit vertical order tracking stepper with pulsing active stage.
class LiquidStepProgress extends StatelessWidget {
  final List<LiquidStepItem> steps;
  final bool isDark;

  const LiquidStepProgress({
    super.key,
    required this.steps,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(steps.length, (index) {
        final step = steps[index];
        final isLast = index == steps.length - 1;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Node & Conduit Column
            Column(
              children: [
                // Glowing Node Circle
                _buildNodeCircle(step),
                if (!isLast)
                  // Liquid Conduit Pipe
                  _buildConduit(step, steps[index + 1]),
              ],
            ),
            const SizedBox(width: 16),
            // Right Text Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          step.title,
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: step.isCurrent || step.isCompleted
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: step.isCurrent
                                ? AppColors.primaryLight
                                : (step.isCompleted
                                    ? (isDark ? Colors.white : AppColors.textPrimary)
                                    : (isDark ? Colors.white38 : AppColors.textSecondary)),
                          ),
                        ),
                        if (step.isCurrent) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'IN PROGRESS',
                              style: GoogleFonts.outfit(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primaryLight,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      step.subtitle,
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: isDark ? Colors.white54 : AppColors.textSecondary,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildNodeCircle(LiquidStepItem step) {
    if (step.isCompleted) {
      return Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: AppColors.success,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.success.withValues(alpha: 0.4),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(Icons.check_rounded, color: Colors.white, size: 18),
      );
    } else if (step.isCurrent) {
      return Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.55),
              blurRadius: 14,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Icon(step.icon, color: Colors.white, size: 16),
      );
    } else {
      return Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E2034) : const Color(0xFFECEEF8),
          shape: BoxShape.circle,
          border: Border.all(
            color: isDark ? Colors.white12 : Colors.grey.shade300,
            width: 1.5,
          ),
        ),
        child: Icon(
          step.icon,
          color: isDark ? Colors.white30 : Colors.grey.shade400,
          size: 15,
        ),
      );
    }
  }

  Widget _buildConduit(LiquidStepItem current, LiquidStepItem next) {
    final isFlowing = current.isCompleted;

    return Container(
      width: 3,
      height: 42,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: isFlowing
            ? AppColors.success
            : (isDark ? const Color(0xFF1E2034) : const Color(0xFFECEEF8)),
        borderRadius: BorderRadius.circular(2),
        boxShadow: isFlowing
            ? [
                BoxShadow(
                  color: AppColors.success.withValues(alpha: 0.35),
                  blurRadius: 6,
                ),
              ]
            : null,
      ),
    );
  }
}
