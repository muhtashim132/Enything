import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Dynamic rolling animated search placeholder ticker for the discovery search bar.
/// Uses a slot-machine vertical roll with hard ClipRect boundaries, left alignment,
/// and decoupled directional transitions to guarantee zero ghosting or overlapping artifacts.
class AnimatedSearchTicker extends StatefulWidget {
  final List<String> items;
  final TextStyle? textStyle;
  final Duration interval;
  final Duration transitionDuration;

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
    this.transitionDuration = const Duration(milliseconds: 350),
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
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    if (widget.items.length <= 1) return;
    _timer = Timer.periodic(widget.interval, (timer) {
      if (mounted && widget.items.isNotEmpty) {
        setState(() {
          _currentIndex = (_currentIndex + 1) % widget.items.length;
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isTickerActive = TickerMode.valuesOf(context).enabled;
    if (!isTickerActive && _timer != null) {
      _timer?.cancel();
      _timer = null;
    } else if (isTickerActive && _timer == null) {
      _startTimer();
    }
  }

  @override
  void didUpdateWidget(covariant AnimatedSearchTicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.interval != oldWidget.interval ||
        widget.items.length != oldWidget.items.length) {
      _startTimer();
    }
    if (widget.items.isNotEmpty && _currentIndex >= widget.items.length) {
      _currentIndex = 0;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    return ClipRect(
      child: SizedBox(
        height: 22,
        child: AnimatedSwitcher(
          duration: widget.transitionDuration,
          reverseDuration: widget.transitionDuration,
          layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
            return Stack(
              alignment: Alignment.centerLeft,
              children: <Widget>[
                ...previousChildren,
                if (currentChild != null) currentChild,
              ],
            );
          },
          transitionBuilder: (Widget child, Animation<double> animation) {
            // Distinguish incoming child from outgoing child using ValueKey
            final isIncoming =
                (child.key as ValueKey<int>?)?.value == _currentIndex;

            // Incoming slides UP from bottom (+1.0 -> 0.0)
            // Outgoing slides UP to top (0.0 -> -1.0)
            final slideAnimation = Tween<Offset>(
              begin: isIncoming
                  ? const Offset(0.0, 1.0)
                  : const Offset(0.0, -1.0),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(
                parent: animation,
                curve: Curves.easeInOutCubic,
              ),
            );

            // Staggered opacity: outgoing dims quickly, incoming fades in smoothly
            final fadeAnimation = CurvedAnimation(
              parent: animation,
              curve: isIncoming
                  ? const Interval(0.2, 1.0, curve: Curves.easeIn)
                  : const Interval(0.0, 0.7, curve: Curves.easeOut),
            );

            return SlideTransition(
              position: slideAnimation,
              child: FadeTransition(
                opacity: fadeAnimation,
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
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
