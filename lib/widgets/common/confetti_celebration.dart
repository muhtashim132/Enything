import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 100x Lightweight Particle Confetti Celebration Effect
///
/// Physics-based celebration burst on successful checkout or goal achievement.
class ConfettiCelebration extends StatefulWidget {
  final Widget child;
  final bool isTriggered;

  const ConfettiCelebration({
    super.key,
    required this.child,
    this.isTriggered = false,
  });

  @override
  State<ConfettiCelebration> createState() => _ConfettiCelebrationState();
}

class _ConfettiCelebrationState extends State<ConfettiCelebration>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_ConfettiParticle> _particles = [];
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..addListener(() {
        if (mounted) setState(() {});
      });

    if (widget.isTriggered) {
      _spawnParticles();
      _controller.forward(from: 0.0);
    }
  }

  @override
  void didUpdateWidget(covariant ConfettiCelebration oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isTriggered && !oldWidget.isTriggered) {
      _spawnParticles();
      _controller.forward(from: 0.0);
    }
  }

  void _spawnParticles() {
    _particles.clear();
    const colors = [
      Color(0xFFFF3366),
      Color(0xFF33CC99),
      Color(0xFFFF9900),
      Color(0xFF3399FF),
      Color(0xFFFFCC00),
      Color(0xFF9933FF),
    ];

    for (int i = 0; i < 65; i++) {
      _particles.add(
        _ConfettiParticle(
          color: colors[_random.nextInt(colors.length)],
          startX: 0.5 + (_random.nextDouble() - 0.5) * 0.4,
          speedX: (_random.nextDouble() - 0.5) * 600,
          speedY: -200 - _random.nextDouble() * 500,
          gravity: 500 + _random.nextDouble() * 300,
          size: 6 + _random.nextDouble() * 6,
          rotationSpeed: (_random.nextDouble() - 0.5) * 15,
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_controller.isAnimating)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _ConfettiPainter(
                  particles: _particles,
                  progress: _controller.value,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ConfettiParticle {
  final Color color;
  final double startX;
  final double speedX;
  final double speedY;
  final double gravity;
  final double size;
  final double rotationSpeed;

  _ConfettiParticle({
    required this.color,
    required this.startX,
    required this.speedX,
    required this.speedY,
    required this.gravity,
    required this.size,
    required this.rotationSpeed,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiParticle> particles;
  final double progress;

  _ConfettiPainter({required this.particles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress * 2.5; // Seconds
    final opacity = (1.0 - progress).clamp(0.0, 1.0);

    for (final p in particles) {
      final paint = Paint()
        ..color = p.color.withValues(alpha: opacity)
        ..style = PaintingStyle.fill;

      final x = p.startX * size.width + p.speedX * t;
      final y = size.height * 0.4 + (p.speedY * t) + (0.5 * p.gravity * t * t);

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.rotationSpeed * t);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.6),
          const Radius.circular(2),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => true;
}
