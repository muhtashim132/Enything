import 'package:flutter/material.dart';
import '../../theme/sensory_haptics.dart';

/// Interactive 3D Perspective Card widget.
/// Responds to touch/drag coordinates by tilting in 3D space with specular sheen reflection.
class PerspectiveCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double maxTiltAngle; // In radians (default ~0.08 rad / ~4.5 deg)
  final double pressScale;
  final double borderRadius;
  final bool enableSpecular;
  final bool enableHaptics;
  final Color? specularColor;
  final BorderRadius? customBorderRadius;

  const PerspectiveCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.maxTiltAngle = 0.07,
    this.pressScale = 0.975,
    this.borderRadius = 20,
    this.enableSpecular = true,
    this.enableHaptics = true,
    this.specularColor,
    this.customBorderRadius,
  });

  @override
  State<PerspectiveCard> createState() => _PerspectiveCardState();
}

class _PerspectiveCardState extends State<PerspectiveCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _springController;
  late Animation<double> _tiltXAnim;
  late Animation<double> _tiltYAnim;
  late Animation<double> _scaleAnim;

  double _targetTiltX = 0.0;
  double _targetTiltY = 0.0;
  double _currentScale = 1.0;
  double _specularX = 0.5;
  double _specularY = 0.5;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _springController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _tiltXAnim = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _springController, curve: Curves.easeOutCubic),
    );
    _tiltYAnim = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _springController, curve: Curves.easeOutCubic),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.0).animate(
      CurvedAnimation(parent: _springController, curve: Curves.easeOutCubic),
    );

    _springController.addListener(() {
      setState(() {
        _targetTiltX = _tiltXAnim.value;
        _targetTiltY = _tiltYAnim.value;
        _currentScale = _scaleAnim.value;
      });
    });
  }

  @override
  void dispose() {
    _springController.dispose();
    super.dispose();
  }

  void _handlePointerDown(PointerDownEvent event, BoxConstraints constraints) {
    if (widget.onTap == null && widget.onLongPress == null) return;
    _springController.stop();

    if (widget.enableHaptics) {
      SensoryHaptics.light();
    }

    _updateCoordinates(event.localPosition, constraints.biggest);
    setState(() {
      _isPressed = true;
      _currentScale = widget.pressScale;
    });
  }

  void _handlePointerMove(PointerMoveEvent event, BoxConstraints constraints) {
    if (!_isPressed) return;
    _updateCoordinates(event.localPosition, constraints.biggest);
  }

  void _handlePointerUp(PointerUpEvent event) {
    _releaseSpring();
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _releaseSpring();
  }

  void _updateCoordinates(Offset localPos, Size size) {
    if (size.width == 0 || size.height == 0) return;
    // Normalize coordinates: -1.0 (left/top) to +1.0 (right/bottom)
    final normX = ((localPos.dx / size.width) - 0.5) * 2.0;
    final normY = ((localPos.dy / size.height) - 0.5) * 2.0;

    setState(() {
      // Rotation around Y axis comes from horizontal delta X
      _targetTiltY = (normX * widget.maxTiltAngle).clamp(-widget.maxTiltAngle, widget.maxTiltAngle);
      // Rotation around X axis comes from vertical delta Y (inverted)
      _targetTiltX = (-normY * widget.maxTiltAngle).clamp(-widget.maxTiltAngle, widget.maxTiltAngle);
      _specularX = (localPos.dx / size.width).clamp(0.0, 1.0);
      _specularY = (localPos.dy / size.height).clamp(0.0, 1.0);
    });
  }

  void _releaseSpring() {
    if (!_isPressed && _targetTiltX == 0 && _targetTiltY == 0) return;
    setState(() => _isPressed = false);

    _tiltXAnim = Tween<double>(begin: _targetTiltX, end: 0.0).animate(
      CurvedAnimation(parent: _springController, curve: Curves.easeOutBack),
    );
    _tiltYAnim = Tween<double>(begin: _targetTiltY, end: 0.0).animate(
      CurvedAnimation(parent: _springController, curve: Curves.easeOutBack),
    );
    _scaleAnim = Tween<double>(begin: _currentScale, end: 1.0).animate(
      CurvedAnimation(parent: _springController, curve: Curves.easeOutBack),
    );

    _springController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final effectiveBorderRadius = widget.customBorderRadius ??
        BorderRadius.circular(widget.borderRadius);

    final transformMatrix = Matrix4.identity()
      ..setEntry(3, 2, 0.0012) // Perspective projection
      ..rotateX(_targetTiltX)
      ..rotateY(_targetTiltY)
      ..scaleByDouble(_currentScale, _currentScale, 1.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        return Listener(
          onPointerDown: (e) => _handlePointerDown(e, constraints),
          onPointerMove: (e) => _handlePointerMove(e, constraints),
          onPointerUp: _handlePointerUp,
          onPointerCancel: _handlePointerCancel,
          child: GestureDetector(
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            behavior: HitTestBehavior.opaque,
            child: Transform(
              transform: transformMatrix,
              alignment: FractionalOffset.center,
              child: Stack(
                children: [
                  widget.child,
                  if (widget.enableSpecular && _isPressed)
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: effectiveBorderRadius,
                        child: IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                center: Alignment(
                                  (_specularX - 0.5) * 2.0,
                                  (_specularY - 0.5) * 2.0,
                                ),
                                radius: 0.8,
                                colors: [
                                  (widget.specularColor ?? Colors.white)
                                      .withValues(alpha: 0.18),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
