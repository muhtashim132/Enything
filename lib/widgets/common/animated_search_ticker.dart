import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Dynamic rolling animated search placeholder ticker for the discovery search bar.
class AnimatedSearchTicker extends StatefulWidget {
  final List<String> items;
  final TextStyle? textStyle;
  final Duration interval;

  const AnimatedSearchTicker({
    super.key,
    this.items = const [
      'Search "Fresh Milk & Bread" 🥛',
      'Search "Hot Biryani & Burgers" 🍔',
      'Search "Paracetamol & Vitamins" 💊',
      'Search "Organic Apples & Veggies" 🥑',
      'Search "Cotton T-Shirts & Jeans" 👕',
      'Search "Running Shoes & Sneaks" 👟',
    ],
    this.textStyle,
    this.interval = const Duration(milliseconds: 2800),
  });

  @override
  State<AnimatedSearchTicker> createState() => _AnimatedSearchTickerState();
}

class _AnimatedSearchTickerState extends State<AnimatedSearchTicker> {
  int _currentIndex = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.interval, (timer) {
      if (mounted && widget.items.isNotEmpty) {
        setState(() {
          _currentIndex = (_currentIndex + 1) % widget.items.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      transitionBuilder: (Widget child, Animation<double> animation) {
        final inAnimation = Tween<Offset>(
          begin: const Offset(0.0, 0.8),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));

        return SlideTransition(
          position: inAnimation,
          child: FadeTransition(
            opacity: animation,
            child: child,
          ),
        );
      },
      child: Text(
        widget.items[_currentIndex],
        key: ValueKey<int>(_currentIndex),
        style: widget.textStyle ??
            GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade400,
            ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
