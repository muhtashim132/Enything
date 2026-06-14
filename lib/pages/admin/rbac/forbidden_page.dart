import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class ForbiddenPage extends StatefulWidget {
  final bool fullPage;
  final String? requiredPermission;
  final VoidCallback? onBack;

  const ForbiddenPage({
    super.key,
    this.fullPage = true,
    this.requiredPermission,
    this.onBack,
  });

  @override
  State<ForbiddenPage> createState() => _ForbiddenPageState();
}

class _ForbiddenPageState extends State<ForbiddenPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _scaleAnim = Tween<double>(begin: 0.85, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = FadeTransition(
      opacity: _fadeAnim,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  const Color(0xFFFF5722).withValues(alpha: 0.3),
                  const Color(0xFFFF5722).withValues(alpha: 0.0),
                ]),
              ),
              child: const Icon(
                Icons.lock_rounded,
                color: Color(0xFFFF5722),
                size: 48,
              ),
            ),
            const SizedBox(height: 24),

            // 403
            Text(
              '403',
              style: GoogleFonts.outfit(
                color: const Color(0xFFFF5722).withValues(alpha: 0.5),
                fontSize: 72,
                fontWeight: FontWeight.w900,
                letterSpacing: -2,
              ),
            ),
            Text(
              'Access Denied',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                widget.requiredPermission != null
                    ? "You don't have the required permission:\n${widget.requiredPermission}"
                    : "You don't have permission to access this section.\nContact your Super Admin to request access.",
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  color: Colors.white54,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Back button
            ElevatedButton.icon(
              onPressed: () {
                HapticFeedback.lightImpact();
                if (widget.onBack != null) {
                  widget.onBack!();
                } else if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                foregroundColor: Colors.white70,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: Text('Go Back',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );

    if (!widget.fullPage) return body;

    return Scaffold(
      backgroundColor: const Color(0xFF06040F),
      body: Stack(
        children: [
          // Background aura
          Positioned(
            top: -80,
            left: -80,
            child: _aura(300, const Color(0xFFFF5722), 0.08),
          ),
          Positioned(
            bottom: -100,
            right: -60,
            child: _aura(250, const Color(0xFF8B2FC9), 0.06),
          ),
          Center(child: body),
        ],
      ),
    );
  }

  Widget _aura(double size, Color color, double opacity) => Opacity(
        opacity: opacity,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
                colors: [color, color.withValues(alpha: 0.0)]),
          ),
        ),
      );
}
