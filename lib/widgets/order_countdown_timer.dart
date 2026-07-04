import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class OrderCountdownTimer extends StatefulWidget {
  final DateTime acceptanceDeadline;
  final VoidCallback? onExpire;
  final double fontSize;
  final Color? color;

  const OrderCountdownTimer({
    Key? key,
    required this.acceptanceDeadline,
    this.onExpire,
    this.fontSize = 12,
    this.color,
  }) : super(key: key);

  @override
  State<OrderCountdownTimer> createState() => _OrderCountdownTimerState();
}

class _OrderCountdownTimerState extends State<OrderCountdownTimer> {
  Timer? _timer;
  int _secondsLeft = 0;

  @override
  void initState() {
    super.initState();
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      _updateTime();
    });
  }

  void _updateTime() {
    final remaining = widget.acceptanceDeadline
        .difference(DateTime.now().toUtc())
        .inSeconds;
    final clamped = remaining.clamp(0, 180);
    if (clamped == 0 && _secondsLeft > 0) {
      widget.onExpire?.call();
    }
    if (_secondsLeft != clamped) {
      setState(() {
        _secondsLeft = clamped;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_secondsLeft <= 0) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_off_outlined, size: widget.fontSize + 2, color: Colors.red),
          const SizedBox(width: 4),
          Text(
            'Expired',
            style: GoogleFonts.outfit(
              fontSize: widget.fontSize,
              fontWeight: FontWeight.w700,
              color: Colors.red,
            ),
          ),
        ],
      );
    }

    final m = _secondsLeft ~/ 60;
    final s = _secondsLeft % 60;
    final timeStr = '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    final textColor = widget.color ?? (_secondsLeft < 60 ? Colors.red : Colors.orange);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.timer_outlined, size: widget.fontSize + 2, color: textColor),
        const SizedBox(width: 4),
        Text(
          timeStr,
          style: GoogleFonts.outfit(
            fontSize: widget.fontSize,
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
        ),
      ],
    );
  }
}
