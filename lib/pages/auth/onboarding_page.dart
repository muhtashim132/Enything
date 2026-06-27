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

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  static const _slides = [
    _OnboardingSlide(
      emoji: '🛍️',
      title: 'Everything you need,\ninstantly.',
      subtitle:
          'From hot food & groceries to medicines, clothes, and shoes — anything from your neighbourhood in minutes.',
      bgColors: [Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF312E81)],
      accentColor: Color(0xFF38BDF8),
      tag: '✨ ALL IN ONE APP',
      floatingEmoji1: '🍔',
      floatingEmoji2: '💊',
      floatingEmoji3: '👕',
    ),
    _OnboardingSlide(
      emoji: '🏪',
      title: 'Grow your business\nwith Enything.',
      subtitle:
          'Reach thousands of new customers daily. Set up your digital store in minutes and watch your sales skyrocket.',
      bgColors: [Color(0xFF022C22), Color(0xFF064E3B), Color(0xFF065F46)],
      accentColor: Color(0xFF34D399),
      tag: '📈 BECOME A SELLER',
      floatingEmoji1: '💵',
      floatingEmoji2: '📦',
      floatingEmoji3: '🚀',
    ),
    _OnboardingSlide(
      emoji: '🛵',
      title: 'Earn with us as a\nDelivery Partner.',
      subtitle:
          'Turn your free time into earnings. Enjoy flexible hours, instant payouts, and join a fast-growing community.',
      bgColors: [Color(0xFF450A0A), Color(0xFF7F1D1D), Color(0xFF991B1B)],
      accentColor: Color(0xFFF87171),
      tag: '🚀 JOIN THE FLEET',
      floatingEmoji1: '🤝',
      floatingEmoji2: '⚡',
      floatingEmoji3: '💰',
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

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOutSine),
    );
    _pulseCtrl.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _fadeCtrl.dispose();
    _pulseCtrl.dispose();
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
                              color: slide.accentColor.withValues(alpha: 0.5),
                              blurRadius: 25,
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
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: slide.bgColors.last,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              isLast
                                  ? Icons.rocket_launch_rounded
                                  : Icons.arrow_forward_rounded,
                              color: slide.bgColors.last,
                              size: 22,
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
                  // Massive glowing backdrop aura
                  AnimatedBuilder(
                    animation: _pulseAnim,
                    builder: (context, child) => Transform.scale(
                      scale: _pulseAnim.value,
                      child: Container(
                        width: 300,
                        height: 300,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              slide.accentColor.withValues(alpha: 0.25),
                              slide.accentColor.withValues(alpha: 0.05),
                              Colors.transparent,
                            ],
                            stops: const [0.2, 0.6, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),
                  
                  // Pulsing center hero
                  AnimatedBuilder(
                    animation: _pulseAnim,
                    builder: (context, child) => Transform.scale(
                      scale: _pulseAnim.value,
                      child: child,
                    ),
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
                            border: Border.all(
                              color: slide.accentColor.withValues(alpha: 0.15),
                              width: 1,
                            ),
                          ),
                        ),
                        // Inner ring
                        Container(
                          width: 170,
                          height: 170,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.09),
                            border: Border.all(
                              color: slide.accentColor.withValues(alpha: 0.25),
                              width: 1,
                            ),
                          ),
                        ),
                        // Glassmorphism center card with glowing shadow
                        Container(
                          width: 130,
                          height: 130,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: slide.accentColor.withValues(alpha: 0.3),
                                blurRadius: 30,
                                spreadRadius: -5,
                              )
                            ],
                          ),
                          child: ClipOval(
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withValues(alpha: 0.15),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.4),
                                    width: 1.5,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    slide.emoji,
                                    style: const TextStyle(
                                      fontSize: 60,
                                      shadows: [
                                        Shadow(
                                          color: Colors.black26,
                                          blurRadius: 10,
                                          offset: Offset(0, 4),
                                        )
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Floating emoji decorations
                  Positioned(
                    top: 10,
                    right: 0,
                    child: _FloatingEmoji(emoji: slide.floatingEmoji1, delay: 0),
                  ),
                  Positioned(
                    bottom: 20,
                    left: 10,
                    child: _FloatingEmoji(emoji: slide.floatingEmoji2, delay: 200),
                  ),
                  Positioned(
                    top: 50,
                    left: 0,
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
                fontSize: 34,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                height: 1.15,
                letterSpacing: -1.2,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ],
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
      builder: (_, child) {
        // Create an organic floating effect using translation and slight rotation
        final yOffset = -10 * _anim.value;
        final rotation = 0.15 * _anim.value - 0.075; // Rotates back and forth slightly

        return Transform.translate(
          offset: Offset(0, yOffset),
          child: Transform.rotate(
            angle: rotation,
            child: Opacity(
              opacity: 0.7 + 0.3 * _anim.value,
              child: child,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 15,
              offset: const Offset(0, 8),
            )
          ],
        ),
        child: Text(widget.emoji, style: const TextStyle(fontSize: 26)),
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
