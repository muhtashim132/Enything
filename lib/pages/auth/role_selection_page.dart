import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../config/routes.dart';
import '../../providers/platform_config_provider.dart';

class RoleSelectionPage extends StatefulWidget {
  const RoleSelectionPage({super.key});
  @override
  State<RoleSelectionPage> createState() => _RoleSelectionPageState();
}

class _RoleSelectionPageState extends State<RoleSelectionPage>
    with TickerProviderStateMixin {
  String? _selectedRole; // 'customer' | 'seller' | 'delivery_partner'

  late AnimationController _bgCtrl;
  late AnimationController _cardCtrl;
  late Animation<double> _bgAnim;
  late Animation<double> _card1Anim, _card2Anim, _card3Anim;
  late Animation<double> _titleFade, _titleSlide;

  @override
  void initState() {
    super.initState();

    _bgCtrl =
        AnimationController(duration: const Duration(seconds: 5), vsync: this)
          ..repeat(reverse: true);
    _bgAnim = CurvedAnimation(parent: _bgCtrl, curve: Curves.easeInOut);

    _cardCtrl = AnimationController(
        duration: const Duration(milliseconds: 900), vsync: this);
    _card1Anim = CurvedAnimation(
        parent: _cardCtrl,
        curve: const Interval(0.0, 0.60, curve: Curves.easeOutBack));
    _card2Anim = CurvedAnimation(
        parent: _cardCtrl,
        curve: const Interval(0.15, 0.75, curve: Curves.easeOutBack));
    _card3Anim = CurvedAnimation(
        parent: _cardCtrl,
        curve: const Interval(0.30, 1.00, curve: Curves.easeOutBack));
    _titleFade = CurvedAnimation(
        parent: _cardCtrl,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn));
    _titleSlide = Tween<double>(begin: 24, end: 0).animate(CurvedAnimation(
        parent: _cardCtrl,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut)));

    _cardCtrl.forward();
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    _cardCtrl.dispose();
    super.dispose();
  }

  void _proceed() {
    if (_selectedRole == null) return;
    Navigator.pushNamed(
      context,
      AppRoutes.phoneAuth,
      arguments: {'role': _selectedRole},
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final config = context.watch<PlatformConfigProvider>();

    return Scaffold(
      body: AnimatedBuilder(
        animation: _bgCtrl,
        builder: (_, __) => Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(const Color(0xFF04091E), const Color(0xFF07124A),
                    _bgAnim.value)!,
                const Color(0xFF02061A),
                Color.lerp(const Color(0xFF08043E), const Color(0xFF120860),
                    _bgAnim.value)!,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
          child: Stack(
            children: [
              // Aurora blobs
              Positioned(
                top: -size.height * 0.10,
                left: -size.width * 0.25,
                child: _aurora(size.width * 0.80, const Color(0xFF2B4FD4),
                    0.18 + _bgAnim.value * 0.10),
              ),
              Positioned(
                bottom: -size.height * 0.10,
                right: -size.width * 0.20,
                child: _aurora(size.width * 0.90, const Color(0xFF6230C8),
                    0.14 + (1 - _bgAnim.value) * 0.10),
              ),
              // Star field
              CustomPaint(size: size, painter: _StarPainter(_bgCtrl.value)),

              // Content
              SafeArea(
                child: AnimatedBuilder(
                  animation: _cardCtrl,
                  builder: (_, __) => LayoutBuilder(
                    builder: (context, constraints) {
                      final bool isSmallScreen = constraints.maxHeight < 700;
                      
                      Widget content = Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (isSmallScreen) const SizedBox(height: 32) else const Spacer(flex: 3),

                        // Logo
                        FadeTransition(
                          opacity: _titleFade,
                          child: Transform.translate(
                            offset: Offset(0, _titleSlide.value),
                            child: Column(
                              children: [
                                // Enything logo mark
                                Container(
                                  width: 110,
                                  height: 110,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFF1A2A6C),
                                        Color(0xFF0D1B4A)
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(30),
                                    border: Border.all(
                                        color: const Color(0xFF5B8BFF)
                                            .withValues(alpha: 0.40),
                                        width: 1.5),
                                    boxShadow: [
                                      BoxShadow(
                                          color: const Color(0xFF5B8BFF)
                                              .withValues(alpha: 0.30),
                                          blurRadius: 22,
                                          spreadRadius: 2),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(28),
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Image.asset(
                                        'logo/Enything_modern.png',
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, __, ___) =>
                                            const Center(
                                              child: Text('E',
                                                  style: TextStyle(
                                                      fontSize: 30,
                                                      color: Color(0xFF5B8BFF),
                                                      fontWeight: FontWeight.w900)),
                                            ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                ShaderMask(
                                  shaderCallback: (b) => const LinearGradient(
                                    colors: [
                                      Color(0xFF8BAAFF),
                                      Color(0xFF5B8BFF),
                                      Color(0xFF4C6EF5)
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ).createShader(b),
                                  child: Text('ENYTHING',
                                      style: GoogleFonts.outfit(
                                        color: Colors.white,
                                        fontSize: 42,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 8,
                                      )),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Join as who you are',
                                  style: GoogleFonts.outfit(
                                    color: Colors.white.withValues(alpha: 0.50),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w400,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                          if (isSmallScreen) const SizedBox(height: 40) else const Spacer(flex: 4),

                        // Heading
                        FadeTransition(
                          opacity: _titleFade,
                          child: Transform.translate(
                            offset: Offset(0, _titleSlide.value),
                            child: Column(
                              children: [
                                Text(
                                  'Choose your role',
                                  style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontSize: 26,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'One account — multiple roles. Pick one to start.',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.outfit(
                                    color: Colors.white.withValues(alpha: 0.50),
                                    fontSize: 13,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                          if (isSmallScreen) const SizedBox(height: 32) else const Spacer(flex: 3),

                        // Role cards
                        _AnimatedRoleCard(
                          anim: _card1Anim,
                          icon: '🛍️',
                          title: 'Customer',
                          subtitle:
                              'Shop from local stores & get\nfast doorstep delivery',
                          accentColor: const Color(0xFF4C6EF5),
                          badge: 'Shop Now',
                          selected: _selectedRole == 'customer',
                          onTap: () =>
                              setState(() => _selectedRole = 'customer'),
                        ),
                        const SizedBox(height: 16),
                        _AnimatedRoleCard(
                          anim: _card2Anim,
                          icon: '🏪',
                          title: 'Seller',
                          subtitle:
                              'List your products & grow\nyour business — ${config.unifiedCommissionPercent.toStringAsFixed(0)}% commission',
                          accentColor: const Color(0xFFF4C542),
                          badge: 'Sell Now',
                          selected: _selectedRole == 'seller',
                          onTap: () => setState(() => _selectedRole = 'seller'),
                        ),
                        const SizedBox(height: 16),
                        _AnimatedRoleCard(
                          anim: _card3Anim,
                          icon: '🏍️',
                          title: 'Delivery Partner',
                          subtitle:
                              'Earn by delivering orders\nin your neighbourhood',
                          accentColor: const Color(0xFF51CF66),
                          badge: 'Earn Now',
                          selected: _selectedRole == 'delivery_partner',
                          onTap: () => setState(
                              () => _selectedRole = 'delivery_partner'),
                        ),



                          if (isSmallScreen) const SizedBox(height: 40) else const Spacer(flex: 4),

                        // CTA
                        GestureDetector(
                          onTap: _selectedRole != null ? _proceed : null,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            width: double.infinity,
                            height: 58,
                            decoration: BoxDecoration(
                              gradient: _selectedRole != null
                                  ? const LinearGradient(colors: [
                                      Color(0xFFFFD700),
                                      Color(0xFFF4A800)
                                    ])
                                  : null,
                              color: _selectedRole == null
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : null,
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: _selectedRole != null
                                  ? [
                                      BoxShadow(
                                          color: const Color(0xFFF4C542)
                                              .withValues(alpha: 0.40),
                                          blurRadius: 20,
                                          offset: const Offset(0, 8))
                                    ]
                                  : [],
                            ),
                            child: Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _selectedRole != null
                                        ? 'Continue as ${_roleName(_selectedRole!)}'
                                        : 'Select a role to continue',
                                    style: GoogleFonts.outfit(
                                      color: _selectedRole != null
                                          ? Colors.black
                                          : Colors.white38,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  if (_selectedRole != null) ...[
                                    const SizedBox(width: 10),
                                    const Icon(Icons.arrow_forward_rounded,
                                        color: Colors.black, size: 20),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),

                          if (isSmallScreen) const SizedBox(height: 32) else const Spacer(flex: 3),
                        ],
                      );

                      if (isSmallScreen) {
                        content = SingleChildScrollView(
                          child: content,
                        );
                      }

                      return Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 540),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 28),
                            child: content,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _roleName(String role) {
    switch (role) {
      case 'customer':
        return 'Customer';
      case 'seller':
        return 'Seller';
      case 'delivery_partner':
        return 'Delivery Partner';
      default:
        return role;
    }
  }

  Widget _aurora(double size, Color color, double opacity) => Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [color, color.withValues(alpha: 0.0)]),
          ),
        ),
      );
}

// ── Animated Role Card ─────────────────────────────────────────────────────────
class _AnimatedRoleCard extends StatelessWidget {
  final Animation<double> anim;
  final String icon, title, subtitle, badge;
  final Color accentColor;
  final bool selected;
  final VoidCallback onTap;

  const _AnimatedRoleCard({
    required this.anim,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.badge,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: anim,
      builder: (_, child) => Transform.scale(
        scale: anim.value,
        child: Opacity(opacity: anim.value.clamp(0.0, 1.0), child: child),
      ),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: selected
                ? accentColor.withValues(alpha: 0.14)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected ? accentColor : Colors.white.withValues(alpha: 0.10),
              width: selected ? 2.0 : 1.0,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                        color: accentColor.withValues(alpha: 0.22),
                        blurRadius: 20,
                        offset: const Offset(0, 6))
                  ]
                : [],
          ),
          child: Row(
            children: [
              // Icon bubble
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: selected
                      ? accentColor.withValues(alpha: 0.20)
                      : Colors.white.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selected
                        ? accentColor.withValues(alpha: 0.40)
                        : Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Center(
                    child: Text(icon, style: const TextStyle(fontSize: 28))),
              ),
              const SizedBox(width: 16),
              // Text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          Text(
                            title,
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (selected)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: accentColor,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                badge,
                                style: GoogleFonts.outfit(
                                  color: title == 'Seller'
                                      ? Colors.black
                                      : Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: GoogleFonts.outfit(
                        color: Colors.white.withValues(alpha: 0.50),
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              // Check circle
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: selected ? accentColor : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color:
                        selected ? accentColor : Colors.white.withValues(alpha: 0.20),
                    width: 2,
                  ),
                ),
                child: selected
                    ? Center(
                        child: Icon(Icons.check,
                            size: 14,
                            color: title == 'Seller'
                                ? Colors.black
                                : Colors.white))
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// ── Subtle star field ─────────────────────────────────────────────────────────
class _StarPainter extends CustomPainter {
  final double t;
  _StarPainter(this.t);
  static final _rnd = math.Random(42);
  static final _stars = List.generate(
      45,
      (_) => [
            _rnd.nextDouble(),
            _rnd.nextDouble(),
            _rnd.nextDouble() * 1.4 + 0.4,
            _rnd.nextDouble() * math.pi * 2,
          ]);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..style = PaintingStyle.fill;
    for (final s in _stars) {
      final tw = (math.sin(t * math.pi * 2 + s[3]) + 1) / 2;
      p.color = Colors.white.withValues(alpha: 0.03 + tw * 0.13);
      canvas.drawCircle(Offset(s[0] * size.width, s[1] * size.height), s[2], p);
    }
  }

  @override
  bool shouldRepaint(_StarPainter o) => o.t != t;
}
