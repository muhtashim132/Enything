import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

/// Calculates the initial bearing from point A to point B in degrees [0, 360).
double calculateBearing(LatLng from, LatLng to) {
  final lat1 = from.latitude * (math.pi / 180.0);
  final lat2 = to.latitude * (math.pi / 180.0);
  final dLng = (to.longitude - from.longitude) * (math.pi / 180.0);

  final y = math.sin(dLng) * math.cos(lat2);
  final x = math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLng);

  final rad = math.atan2(y, x);
  return (rad * 180.0 / math.pi + 360.0) % 360.0;
}

/// Linear interpolation between two coordinates.
LatLng lerpLatLng(LatLng from, LatLng to, double t) {
  return LatLng(
    from.latitude + (to.latitude - from.latitude) * t,
    from.longitude + (to.longitude - from.longitude) * t,
  );
}

/// Smooth shortest-path angle interpolation between two angles in degrees [0, 360).
double lerpAngle(double from, double to, double t) {
  double diff = (to - from) % 360.0;
  if (diff > 180.0) diff -= 360.0;
  if (diff < -180.0) diff += 360.0;
  return (from + diff * t) % 360.0;
}

/// A standalone animated moving rider marker that smoothly glides and rotates
/// along coordinates without triggering parent widget rebuilds or map reloading.
class SmoothRiderMarker extends StatefulWidget {
  final LatLng targetLocation;
  final Duration duration;
  final Curve curve;
  final double width;
  final double height;
  final String label;
  final Color color;
  final IconData icon;
  final bool showPulse;
  final bool rotateWithHeading;

  const SmoothRiderMarker({
    super.key,
    required this.targetLocation,
    this.duration = const Duration(milliseconds: 1200),
    this.curve = Curves.easeInOutCubic,
    this.width = 80,
    this.height = 72,
    this.label = 'Rider',
    this.color = const Color(0xFF2ECC71),
    this.icon = Icons.delivery_dining_rounded,
    this.showPulse = true,
    this.rotateWithHeading = false,
  });

  @override
  State<SmoothRiderMarker> createState() => SmoothRiderMarkerState();
}

class SmoothRiderMarkerState extends State<SmoothRiderMarker>
    with TickerProviderStateMixin {
  late AnimationController _moveCtrl;
  late Animation<double> _moveAnim;

  AnimationController? _pulseCtrl;
  Animation<double>? _pulseAnim;

  LatLng _startLocation = const LatLng(0, 0);
  LatLng _endLocation = const LatLng(0, 0);
  LatLng _currentAnimatedLocation = const LatLng(0, 0);

  double _startBearing = 0.0;
  double _endBearing = 0.0;
  double _currentAnimatedBearing = 0.0;

  LatLng get currentPoint => _currentAnimatedLocation;
  double get currentBearing => _currentAnimatedBearing;

  final Distance _distanceCalc = const Distance();

  @override
  void initState() {
    super.initState();
    _startLocation = widget.targetLocation;
    _endLocation = widget.targetLocation;
    _currentAnimatedLocation = widget.targetLocation;

    _moveCtrl = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _moveAnim = CurvedAnimation(
      parent: _moveCtrl,
      curve: widget.curve,
    )..addListener(_onAnimationTick);

    if (widget.showPulse) {
      _pulseCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1800),
      )..repeat(reverse: true);
      _pulseAnim = Tween<double>(begin: 0.85, end: 1.05).animate(
        CurvedAnimation(parent: _pulseCtrl!, curve: Curves.easeInOut),
      );
    }
  }

  @override
  void didUpdateWidget(covariant SmoothRiderMarker oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.targetLocation.latitude != _endLocation.latitude ||
        widget.targetLocation.longitude != _endLocation.longitude) {
      final double distanceMeters = _distanceCalc.as(
        LengthUnit.Meter,
        _currentAnimatedLocation,
        widget.targetLocation,
      );

      // Micro-jitter guard: ignore moves < 1.2 meters to prevent GPS jitter
      if (distanceMeters < 1.2) {
        return;
      }

      // Teleport guard: if move is huge (> 5km), snap immediately without cross-city glide
      if (distanceMeters > 5000) {
        _startLocation = widget.targetLocation;
        _endLocation = widget.targetLocation;
        _currentAnimatedLocation = widget.targetLocation;
        _moveCtrl.stop();
        if (mounted) setState(() {});
        return;
      }

      _startLocation = _currentAnimatedLocation;
      _endLocation = widget.targetLocation;

      final newBearing = calculateBearing(_startLocation, _endLocation);
      _startBearing = _currentAnimatedBearing;
      _endBearing = newBearing;

      _moveCtrl.forward(from: 0.0);
    }
  }

  void _onAnimationTick() {
    final t = _moveAnim.value;
    setState(() {
      _currentAnimatedLocation = lerpLatLng(_startLocation, _endLocation, t);
      _currentAnimatedBearing = lerpAngle(_startBearing, _endBearing, t);
    });
  }

  @override
  void dispose() {
    _moveCtrl.removeListener(_onAnimationTick);
    _moveCtrl.dispose();
    _pulseCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget markerContent = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.rotate(
          angle: widget.rotateWithHeading
              ? (_currentAnimatedBearing * (math.pi / 180.0))
              : 0.0,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.5),
                  blurRadius: 16,
                  spreadRadius: 2,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(color: Colors.white, width: 2.5),
            ),
            child: Icon(widget.icon, color: Colors.white, size: 26),
          ),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            widget.label,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );

    if (_pulseAnim != null) {
      markerContent = ScaleTransition(
        scale: _pulseAnim!,
        child: markerContent,
      );
    }

    return markerContent;
  }
}

/// A dedicated MarkerLayer wrapper for single or multiple live moving riders
/// that automatically interpolates coordinate changes and updates positions.
class SmoothMovingRiderMarkerLayer extends StatefulWidget {
  final Map<String, LatLng> riderLocations;
  final String label;
  final Color color;
  final IconData icon;

  const SmoothMovingRiderMarkerLayer({
    super.key,
    required this.riderLocations,
    this.label = 'Rider',
    this.color = const Color(0xFF2ECC71),
    this.icon = Icons.delivery_dining_rounded,
  });

  @override
  State<SmoothMovingRiderMarkerLayer> createState() =>
      _SmoothMovingRiderMarkerLayerState();
}

class _SmoothMovingRiderMarkerLayerState
    extends State<SmoothMovingRiderMarkerLayer>
    with SingleTickerProviderStateMixin {
  late AnimationController _tickerCtrl;
  final Map<String, LatLng> _startLocs = {};
  final Map<String, LatLng> _targetLocs = {};
  final Map<String, LatLng> _animatedLocs = {};
  final Distance _dist = const Distance();

  @override
  void initState() {
    super.initState();
    _tickerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..addListener(_onTick);

    for (final entry in widget.riderLocations.entries) {
      _startLocs[entry.key] = entry.value;
      _targetLocs[entry.key] = entry.value;
      _animatedLocs[entry.key] = entry.value;
    }
  }

  @override
  void didUpdateWidget(covariant SmoothMovingRiderMarkerLayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    bool needsAnimation = false;

    // Remove old riders that are no longer present
    _startLocs.removeWhere((k, _) => !widget.riderLocations.containsKey(k));
    _targetLocs.removeWhere((k, _) => !widget.riderLocations.containsKey(k));
    _animatedLocs.removeWhere((k, _) => !widget.riderLocations.containsKey(k));

    for (final entry in widget.riderLocations.entries) {
      final key = entry.key;
      final newTarget = entry.value;
      final prevTarget = _targetLocs[key];

      if (prevTarget == null) {
        // New rider appeared
        _startLocs[key] = newTarget;
        _targetLocs[key] = newTarget;
        _animatedLocs[key] = newTarget;
      } else if (prevTarget.latitude != newTarget.latitude ||
          prevTarget.longitude != newTarget.longitude) {
        final d = _dist.as(
          LengthUnit.Meter,
          _animatedLocs[key] ?? prevTarget,
          newTarget,
        );

        if (d >= 1.2 && d <= 5000) {
          _startLocs[key] = _animatedLocs[key] ?? prevTarget;
          _targetLocs[key] = newTarget;
          needsAnimation = true;
        } else if (d > 5000) {
          _startLocs[key] = newTarget;
          _targetLocs[key] = newTarget;
          _animatedLocs[key] = newTarget;
        }
      }
    }

    if (needsAnimation) {
      _tickerCtrl.forward(from: 0.0);
    }
  }

  void _onTick() {
    final t = Curves.easeInOutCubic.transform(_tickerCtrl.value);
    setState(() {
      for (final key in _targetLocs.keys) {
        final start = _startLocs[key];
        final target = _targetLocs[key];
        if (start != null && target != null) {
          _animatedLocs[key] = lerpLatLng(start, target, t);
        }
      }
    });
  }

  @override
  void dispose() {
    _tickerCtrl.removeListener(_onTick);
    _tickerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_animatedLocs.isEmpty) return const SizedBox.shrink();

    return MarkerLayer(
      markers: [
        for (final entry in _animatedLocs.entries)
          Marker(
            point: entry.value,
            width: 80,
            height: 72,
            child: _RiderPinWidget(
              label: widget.label,
              color: widget.color,
              icon: widget.icon,
            ),
          ),
      ],
    );
  }
}

class _RiderPinWidget extends StatefulWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _RiderPinWidget({
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  State<_RiderPinWidget> createState() => _RiderPinWidgetState();
}

class _RiderPinWidgetState extends State<_RiderPinWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _scale = Tween<double>(begin: 0.90, end: 1.08).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.5),
                  blurRadius: 16,
                  spreadRadius: 2,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(color: Colors.white, width: 2.5),
            ),
            child: Icon(widget.icon, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: widget.color,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              widget.label,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
