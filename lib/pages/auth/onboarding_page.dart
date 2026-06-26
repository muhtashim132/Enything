import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/routes.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  static const _slides = [
    _OnboardingSlide(
      emoji: '🚀',
      title: 'Delivered at\nthe speed of life',
      subtitle:
          'From groceries to medicines, hot food to electronics — anything from your neighbourhood in minutes.',
      bgColors: [Color(0xFF05093D), Color(0xFF0A1260), Color(0xFF1A2BC4)],
      accentColor: Color(0xFFF4C542),
      tag: '⚡ INSTANT DELIVERY',
      floatingEmoji1: '🍕',
      floatingEmoji2: '💊',
      floatingEmoji3: '📦',
    ),
    _OnboardingSlide(
      emoji: '🏪',
      title: 'Support your\nlocal community',
      subtitle:
          'Every order you place helps local shopkeepers, restaurants, and entrepreneurs in your city thrive.',
      bgColors: [Color(0xFF0A2E14), Color(0xFF0F4C1A), Color(0xFF1E7A32)],
      accentColor: Color(0xFF7DEFA1),
      tag: '🌿 LOCAL FIRST',
      floatingEmoji1: '🥦',
      floatingEmoji2: '🧁',
      floatingEmoji3: '💐',
    ),
    _OnboardingSlide(
      emoji: '📡',
      title: 'Track your order\nin real-time',
      subtitle:
          'Live GPS tracking from the moment you order to your doorstep. Always know where your order is.',
      bgColors: [Color(0xFF2A0050), Color(0xFF4A0080), Color(0xFF7B1FA2)],
      accentColor: Color(0xFFE1BEE7),
      tag: '📍 LIVE TRACKING',
      floatingEmoji1: '🗺️',
      floatingEmoji2: '🛵',
      floatingEmoji3: '🔔',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _markSeenAndNavigate() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenOnboarding', true);
    if (mounted) {
      Navigator.pushReplacementNamed(context, AppRoutes.roleSelect);
    }
  }

  void _nextPage() {
    if (_currentPage < _slides.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _markSeenAndNavigate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final slide = _slides[_currentPage];
    final isLast = _currentPage == _slides.length - 1;

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: slide.bgColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── Top bar with skip ────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!isLast)
                      TextButton(
                        onPressed: _markSeenAndNavigate,
                        child: Text(
                          'Skip',
                          style: GoogleFonts.outfit(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // ── Page content ─────────────────────────────────────────
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (i) {
                    _fadeCtrl.reset();
                    setState(() => _currentPage = i);
                    _fadeCtrl.forward();
                  },
                  itemCount: _slides.length,
                  itemBuilder: (context, index) =>
                      _buildSlide(_slides[index], index == _currentPage),
                ),
              ),

              // ── Bottom controls ──────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                child: Column(
                  children: [
                    // Dot indicators
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_slides.length, (i) {
                        final active = _currentPage == i;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 320),
                          curve: Curves.easeOutCubic,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: active ? 28 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: active
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 28),

                    // CTA button
                    GestureDetector(
                      onTap: _nextPage,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: double.infinity,
                        height: 58,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              isLast ? 'Get Started' : 'Continue',
                              style: GoogleFonts.outfit(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: slide.bgColors.last,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              isLast
                                  ? Icons.rocket_launch_rounded
                                  : Icons.arrow_forward_rounded,
                              color: slide.bgColors.last,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSlide(_OnboardingSlide slide, bool isActive) {
    return FadeTransition(
      opacity: isActive ? _fadeAnim : const AlwaysStoppedAnimation(1.0),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const SizedBox(height: 8),

            // ── Large hero emoji with floating decorations ────────────
            Expanded(
              flex: 5,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer glow ring
                  Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  // Inner ring
                  Container(
                    width: 170,
                    height: 170,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.09),
                    ),
                  ),
                  // Glassmorphism center card
                  ClipOval(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        width: 130,
                        height: 130,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.15),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25),
                            width: 1.5,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            slide.emoji,
                            style: const TextStyle(fontSize: 60),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Floating emoji decorations
                  Positioned(
                    top: 20,
                    right: 10,
                    child: _FloatingEmoji(emoji: slide.floatingEmoji1, delay: 0),
                  ),
                  Positioned(
                    bottom: 30,
                    left: 15,
                    child: _FloatingEmoji(emoji: slide.floatingEmoji2, delay: 200),
                  ),
                  Positioned(
                    top: 60,
                    left: 5,
                    child: _FloatingEmoji(emoji: slide.floatingEmoji3, delay: 400),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // ── Tag chip ─────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: slide.accentColor,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: slide.accentColor.withValues(alpha: 0.4),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Text(
                slide.tag,
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: Colors.black87,
                  letterSpacing: 0.5,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ── Title ─────────────────────────────────────────────────
            Text(
              slide.title,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 30,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                height: 1.15,
                letterSpacing: -0.5,
              ),
            ),

            const SizedBox(height: 14),

            // ── Subtitle ──────────────────────────────────────────────
            Text(
              slide.subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.78),
                height: 1.55,
                fontWeight: FontWeight.w400,
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Floating emoji with gentle pulse animation
// ─────────────────────────────────────────────────────────────────────────────
class _FloatingEmoji extends StatefulWidget {
  final String emoji;
  final int delay;

  const _FloatingEmoji({required this.emoji, required this.delay});

  @override
  State<_FloatingEmoji> createState() => _FloatingEmojiState();
}

class _FloatingEmojiState extends State<_FloatingEmoji>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _anim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, -6 * _anim.value),
        child: Opacity(
          opacity: 0.6 + 0.4 * _anim.value,
          child: child,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Text(widget.emoji, style: const TextStyle(fontSize: 22)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Data class for slide content
// ─────────────────────────────────────────────────────────────────────────────
class _OnboardingSlide {
  final String emoji;
  final String title;
  final String subtitle;
  final List<Color> bgColors;
  final Color accentColor;
  final String tag;
  final String floatingEmoji1;
  final String floatingEmoji2;
  final String floatingEmoji3;

  const _OnboardingSlide({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.bgColors,
    required this.accentColor,
    required this.tag,
    required this.floatingEmoji1,
    required this.floatingEmoji2,
    required this.floatingEmoji3,
  });
}
