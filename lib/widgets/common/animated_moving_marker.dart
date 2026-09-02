import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import '../../utils/geo_utils.dart';

/// Top-level forwarding helpers
double calculateBearing(LatLng from, LatLng to) =>
    GeoUtils.calculateBearing(from, to);
double lerpAngle(double from, double to, double t) =>
    GeoUtils.lerpAngle(from, to, t);
LatLng lerpLatLng(LatLng from, LatLng to, double t) =>
    GeoUtils.lerpLatLng(from, to, t);

/// 100x High-Performance Animated Moving Rider Marker Layer for FlutterMap.
///
/// Dynamically drives Marker.point coordinate interpolation and compass heading
/// rotation on every animation tick using cubic bezier easing, ensuring that
/// markers smoothly glide across the map canvas without sudden teleport jumps
/// or map widget reloads.
class SmoothMovingRiderMarkerLayer extends StatefulWidget {
  final Map<String, LatLng> riderLocations;
  final String label;
  final Color color;
  final IconData icon;
  final bool rotateWithHeading;
  final bool showPulse;
  final Duration duration;

  const SmoothMovingRiderMarkerLayer({
    super.key,
    required this.riderLocations,
    this.label = 'Rider',
    this.color = const Color(0xFF2ECC71),
    this.icon = Icons.navigation_rounded,
    this.rotateWithHeading = true,
    this.showPulse = true,
    this.duration = const Duration(milliseconds: 1400),
  });

  @override
  State<SmoothMovingRiderMarkerLayer> createState() =>
      _SmoothMovingRiderMarkerLayerState();
}

class _SmoothMovingRiderMarkerLayerState
    extends State<SmoothMovingRiderMarkerLayer>
    with SingleTickerProviderStateMixin {
  late AnimationController _tickerCtrl;
  late Animation<double> _curveAnim;

  final Map<String, LatLng> _startLocs = {};
  final Map<String, LatLng> _targetLocs = {};
  final Map<String, LatLng> _animatedLocs = {};

  final Map<String, double> _startBearings = {};
  final Map<String, double> _targetBearings = {};
  final Map<String, double> _animatedBearings = {};

  final Distance _distCalc = const Distance();

  @override
  void initState() {
    super.initState();
    _tickerCtrl = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _curveAnim = CurvedAnimation(
      parent: _tickerCtrl,
      curve: Curves.easeInOutCubic,
    )..addListener(_onTick);

    for (final entry in widget.riderLocations.entries) {
      _startLocs[entry.key] = entry.value;
      _targetLocs[entry.key] = entry.value;
      _animatedLocs[entry.key] = entry.value;
      _startBearings[entry.key] = 0.0;
      _targetBearings[entry.key] = 0.0;
      _animatedBearings[entry.key] = 0.0;
    }
  }

  @override
  void didUpdateWidget(covariant SmoothMovingRiderMarkerLayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    bool needsAnimation = false;

    // Prune removed rider IDs
    _startLocs.removeWhere((k, _) => !widget.riderLocations.containsKey(k));
    _targetLocs.removeWhere((k, _) => !widget.riderLocations.containsKey(k));
    _animatedLocs.removeWhere((k, _) => !widget.riderLocations.containsKey(k));
    _startBearings.removeWhere((k, _) => !widget.riderLocations.containsKey(k));
    _targetBearings.removeWhere((k, _) => !widget.riderLocations.containsKey(k));
    _animatedBearings.removeWhere((k, _) => !widget.riderLocations.containsKey(k));

    for (final entry in widget.riderLocations.entries) {
      final key = entry.key;
      final newTarget = entry.value;
      final prevTarget = _targetLocs[key];
      final currentPos = _animatedLocs[key] ?? newTarget;

      if (prevTarget == null) {
        // Initial rider placement
        _startLocs[key] = newTarget;
        _targetLocs[key] = newTarget;
        _animatedLocs[key] = newTarget;
        _startBearings[key] = 0.0;
        _targetBearings[key] = 0.0;
        _animatedBearings[key] = 0.0;
      } else if (prevTarget.latitude != newTarget.latitude ||
          prevTarget.longitude != newTarget.longitude) {
        final double distanceMeters = _distCalc.as(
          LengthUnit.Meter,
          currentPos,
          newTarget,
        );

        // Micro-jitter guard: ignore moves < 1.5 meters to prevent GPS jitter loops
        if (distanceMeters < 1.5) {
          continue;
        }

        // Teleport guard: if move is huge (> 5km), snap immediately without cross-city sliding
        if (distanceMeters > 5000) {
          _startLocs[key] = newTarget;
          _targetLocs[key] = newTarget;
          _animatedLocs[key] = newTarget;
          _startBearings[key] = 0.0;
          _targetBearings[key] = 0.0;
          _animatedBearings[key] = 0.0;
          continue;
        }

        // Setup glide animation
        _startLocs[key] = currentPos;
        _targetLocs[key] = newTarget;

        _startBearings[key] = _animatedBearings[key] ?? 0.0;
        // 100x Heading Noise Guard: Only rotate compass bearing if moved >= 3.5m
        if (distanceMeters >= 3.5) {
          _targetBearings[key] =
              GeoUtils.calculateBearing(currentPos, newTarget);
        } else {
          _targetBearings[key] = _startBearings[key]!;
        }

        needsAnimation = true;
      }
    }

    if (needsAnimation) {
      _tickerCtrl.forward(from: 0.0);
    }
  }

  void _onTick() {
    final t = _curveAnim.value;
    setState(() {
      for (final key in _targetLocs.keys) {
        final start = _startLocs[key];
        final target = _targetLocs[key];
        if (start != null && target != null) {
          _animatedLocs[key] = GeoUtils.lerpLatLng(start, target, t);
        }

        final startB = _startBearings[key] ?? 0.0;
        final targetB = _targetBearings[key] ?? 0.0;
        _animatedBearings[key] = GeoUtils.lerpAngle(startB, targetB, t);
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
              bearing: _animatedBearings[entry.key] ?? 0.0,
              rotateWithHeading: widget.rotateWithHeading,
              showPulse: widget.showPulse,
            ),
          ),
      ],
    );
  }
}

/// Convenience Layer for tracking a single Rider location
class SmoothSingleRiderMarkerLayer extends StatelessWidget {
  final LatLng? riderLocation;
  final String label;
  final Color color;
  final IconData icon;
  final bool rotateWithHeading;
  final bool showPulse;
  final Duration duration;

  const SmoothSingleRiderMarkerLayer({
    super.key,
    required this.riderLocation,
    this.label = 'Rider',
    this.color = const Color(0xFF2ECC71),
    this.icon = Icons.navigation_rounded,
    this.rotateWithHeading = true,
    this.showPulse = true,
    this.duration = const Duration(milliseconds: 1400),
  });

  @override
  Widget build(BuildContext context) {
    if (riderLocation == null ||
        riderLocation!.latitude == 0.0 ||
        riderLocation!.longitude == 0.0) {
      return const SizedBox.shrink();
    }

    return SmoothMovingRiderMarkerLayer(
      riderLocations: {'primary_rider': riderLocation!},
      label: label,
      color: color,
      icon: icon,
      rotateWithHeading: rotateWithHeading,
      showPulse: showPulse,
      duration: duration,
    );
  }
}

/// Internal animated Pin Widget with smooth heading rotation and pulse glow
class _RiderPinWidget extends StatefulWidget {
  final String label;
  final Color color;
  final IconData icon;
  final double bearing;
  final bool rotateWithHeading;
  final bool showPulse;

  const _RiderPinWidget({
    required this.label,
    required this.color,
    required this.icon,
    required this.bearing,
    required this.rotateWithHeading,
    required this.showPulse,
  });

  @override
  State<_RiderPinWidget> createState() => _RiderPinWidgetState();
}

class _RiderPinWidgetState extends State<_RiderPinWidget>
    with SingleTickerProviderStateMixin {
  AnimationController? _pulseCtrl;
  Animation<double>? _pulseAnim;

  @override
  void initState() {
    super.initState();
    if (widget.showPulse) {
      _pulseCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1800),
      )..repeat(reverse: true);

      _pulseAnim = Tween<double>(begin: 0.90, end: 1.08).animate(
        CurvedAnimation(parent: _pulseCtrl!, curve: Curves.easeInOut),
      );
    }
  }

  @override
  void dispose() {
    _pulseCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isNavArrow = widget.icon == Icons.navigation_rounded ||
        widget.icon == Icons.navigation;

    Widget pinBody = Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: widget.color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: widget.color.withValues(alpha: 0.5),
            blurRadius: 14,
            spreadRadius: 2,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(color: Colors.white, width: 2.5),
      ),
      child: Center(
        child: isNavArrow
            ? Transform.rotate(
                angle: widget.rotateWithHeading
                    ? (widget.bearing * (math.pi / 180.0))
                    : 0.0,
                child: Icon(widget.icon, color: Colors.white, size: 24),
              )
            : Stack(
                alignment: Alignment.center,
                children: [
                  // Upright vehicle icon
                  Icon(widget.icon, color: Colors.white, size: 24),
                  // Directional nose pointer if rotateWithHeading is true
                  if (widget.rotateWithHeading)
                    Transform.rotate(
                      angle: widget.bearing * (math.pi / 180.0),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );

    if (_pulseAnim != null) {
      pinBody = ScaleTransition(
        scale: _pulseAnim!,
        child: pinBody,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        pinBody,
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
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
  }
}

/// Standalone Animated Rider Marker for preview thumbnail maps
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
    this.icon = Icons.navigation_rounded,
    this.showPulse = true,
    this.rotateWithHeading = true,
  });

  @override
  State<SmoothRiderMarker> createState() => _SmoothRiderMarkerState();
}

class _SmoothRiderMarkerState extends State<SmoothRiderMarker> {
  double _currentBearing = 0.0;
  LatLng? _prevPos;

  @override
  void didUpdateWidget(covariant SmoothRiderMarker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_prevPos != null &&
        (_prevPos!.latitude != widget.targetLocation.latitude ||
            _prevPos!.longitude != widget.targetLocation.longitude)) {
      final dist = const Distance().as(
        LengthUnit.Meter,
        _prevPos!,
        widget.targetLocation,
      );
      if (dist >= 3.5) {
        _currentBearing =
            GeoUtils.calculateBearing(_prevPos!, widget.targetLocation);
      }
    }
    _prevPos = widget.targetLocation;
  }

  @override
  Widget build(BuildContext context) {
    return _RiderPinWidget(
      label: widget.label,
      color: widget.color,
      icon: widget.icon,
      bearing: _currentBearing,
      rotateWithHeading: widget.rotateWithHeading,
      showPulse: widget.showPulse,
    );
  }
}
