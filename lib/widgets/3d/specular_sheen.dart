import 'package:flutter/material.dart';

/// Sweeps a subtle glossy specular light sheen diagonally across any widget.
class SpecularSheen extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Duration interval;
  final Color sheenColor;
  final double sheenWidth;
  final bool autoPlay;

  const SpecularSheen({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 1400),
    this.interval = const Duration(seconds: 4),
    this.sheenColor = Colors.white,
    this.sheenWidth = 0.35,
    this.autoPlay = true,
  });

  @override
  State<SpecularSheen> createState() => _SpecularSheenState();
}

class _SpecularSheenState extends State<SpecularSheen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _animation = Tween<double>(begin: -1.5, end: 2.5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
    );

    if (widget.autoPlay) {
      _startLoop();
    }
  }

  void _startLoop() async {
    while (mounted) {
      await Future.delayed(widget.interval);
      if (!mounted) break;
      await _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: const Alignment(-1.0, -1.0),
              end: const Alignment(1.0, 1.0),
              transform: _SlidingGradientTransform(slidePercent: _animation.value),
              colors: [
                Colors.transparent,
                widget.sheenColor.withValues(alpha: 0.0),
                widget.sheenColor.withValues(alpha: 0.22),
                widget.sheenColor.withValues(alpha: 0.0),
                Colors.transparent,
              ],
              stops: [
                0.0,
                (_animation.value - widget.sheenWidth).clamp(0.0, 1.0),
                _animation.value.clamp(0.0, 1.0),
                (_animation.value + widget.sheenWidth).clamp(0.0, 1.0),
                1.0,
              ],
            ).createShader(bounds);
          },
          child: widget.child,
        );
      },
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  final double slidePercent;
  const _SlidingGradientTransform({required this.slidePercent});

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * (slidePercent - 0.5), 0.0, 0.0);
  }
}
