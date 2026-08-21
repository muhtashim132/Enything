import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Smooth odometer / rolling counter animation for numbers and currencies.
class OdometerCounter extends StatelessWidget {
  final num value;
  final String prefix;
  final String suffix;
  final int decimalDigits;
  final TextStyle? textStyle;
  final Duration duration;
  final Curve curve;

  const OdometerCounter({
    super.key,
    required this.value,
    this.prefix = '',
    this.suffix = '',
    this.decimalDigits = 0,
    this.textStyle,
    this.duration = const Duration(milliseconds: 900),
    this.curve = Curves.easeOutCubic,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: value.toDouble()),
      duration: duration,
      curve: curve,
      builder: (context, val, child) {
        final formatter = NumberFormat.currency(
          symbol: prefix,
          decimalDigits: decimalDigits,
          customPattern: '$prefix#,##0${decimalDigits > 0 ? '.00' : ''}',
        );
        final formatted = '${formatter.format(val)}$suffix';
        return Text(
          formatted,
          style: textStyle,
        );
      },
    );
  }
}
