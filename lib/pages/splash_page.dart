import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/routes.dart';
import '../providers/auth_provider.dart';
import '../providers/subscription_provider.dart'; // FIX BUG-7: init subscription on startup
import '../main.dart' show pendingNotificationData, handleNotificationClick;

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});
  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with TickerProviderStateMixin {
  late AnimationController _bgCtrl;
  late AnimationController _ringCtrl;
  late AnimationController _logoCtrl;
  late AnimationController _textCtrl;
  late AnimationController _shimmerCtrl;
  late AnimationController _pulseCtrl;

  late Animation<double> _bgAnim;
  late Animation<double> _ring1, _ring2, _ring3;
  late Animation<double> _logoScale, _logoFade;
  late Animation<double> _textSlide, _textFade, _taglineFade;
  late Animation<double> _shimmerAnim;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();

    _bgCtrl = AnimationController(duration: const Duration(seconds: 4), vsync: this)..repeat(reverse: true);
    _bgAnim = CurvedAnimation(parent: _bgCtrl, curve: Curves.easeInOut);

    _ringCtrl = AnimationController(duration: const Duration(milliseconds: 1600), vsync: this);
    _ring1 = CurvedAnimation(parent: _ringCtrl, curve: const Interval(0.0, 0.65, curve: Curves.easeOut));
    _ring2 = CurvedAnimation(parent: _ringCtrl, curve: const Interval(0.15, 0.80, curve: Curves.easeOut));
    _ring3 = CurvedAnimation(parent: _ringCtrl, curve: const Interval(0.30, 1.00, curve: Curves.easeOut));

    _logoCtrl = AnimationController(duration: const Duration(seconds: 2), vsync: this);
    _logoScale = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _logoCtrl, curve: Curves.elasticOut));
    _logoFade = CurvedAnimation(parent: _logoCtrl, curve: const Interval(0.0, 0.5, curve: Curves.easeIn));

    _shimmerCtrl = AnimationController(duration: const Duration(milliseconds: 1800), vsync: this)..repeat();
    _shimmerAnim = Tween<double>(begin: -1.5, end: 2.5).animate(CurvedAnimation(parent: _shimmerCtrl, curve: Curves.linear));

    _pulseCtrl = AnimationController(duration: const Duration(milliseconds: 2000), vsync: this)..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.055).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _textCtrl = AnimationController(duration: const Duration(milliseconds: 700), vsync: this);
    _textSlide = Tween<double>(begin: 36, end: 0).animate(CurvedAnimation(parent: _textCtrl, curve: Curves.easeOut));
    _textFade = CurvedAnimation(parent: _textCtrl, curve: Curves.easeIn);
    _taglineFade = CurvedAnimation(parent: _textCtrl, curve: const Interval(0.4, 1.0, curve: Curves.easeIn));

    _runSequence();
  }

  Future<void> _runSequence() async {
    _ringCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 350));
    await _logoCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 80));
    await _textCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 1800));
    if (mounted) _navigate();
  }

  Future<void> _navigate() async {
    if (!mounted) return;
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      final auth = context.read<AuthProvider>();
      // Wait for profile to load after session restore
      for (int i = 0; i < 40; i++) {
        if (auth.isProfileFetched) break;
        if (auth.error != null) {
          if (mounted) _showNetworkErrorRetry();
          return;
        }
        await Future.delayed(const Duration(milliseconds: 250));
      }
      if (!mounted) return;

      if (auth.user == null) {
        // Active session exists, but profile wasn't created yet!
        Navigator.pushReplacementNamed(context, AppRoutes.roleSelect);
        return;
      }

      // FIX BUG-7: Initialize SubscriptionProvider so Pass features work.
      // Must be called here because SubscriptionProvider.init() requires userId
      // which is only available after auth profile is fetched.
      if (auth.currentUserId != null && mounted) {
        context.read<SubscriptionProvider>().init(auth.currentUserId!);
      }

      final role = auth.user?.activeSessionRole ?? auth.user?.role;
      final status = auth.user?.verificationStatus ?? 'verified';

      if (role == 'seller') {
        if (status == 'verified' || status == 'approved') {
          Navigator.pushReplacementNamed(context, AppRoutes.sellerDashboard);
        } else if (status == 'pending' || status == 'rejected') {
          Navigator.pushReplacementNamed(context, AppRoutes.sellerPendingVerification);
        } else {
          Navigator.pushReplacementNamed(context, AppRoutes.sellerKycUpload);
        }
        // Process any terminated-app notification for seller
        _processPendingNotification();
      } else if (role == 'delivery_partner') {
        if (status == 'verified' || status == 'approved') {
          Navigator.pushReplacementNamed(context, AppRoutes.deliveryDashboard);
        } else if (status == 'pending' || status == 'rejected') {
          Navigator.pushReplacementNamed(context, AppRoutes.deliveryPendingVerification);
        } else {
          Navigator.pushReplacementNamed(context, AppRoutes.deliveryKycUpload);
        }
        // Process any terminated-app notification for rider
        _processPendingNotification();
      } else if (role == 'admin') {
        // Admin must re-pass 2FA password gate on every app restart
        Navigator.pushReplacementNamed(context, AppRoutes.adminPassword);
        // No deep-link for admin via notifications — security gate must be passed first
        pendingNotificationData = null;
      } else {
        // Customer (default role)
        Navigator.pushReplacementNamed(context, AppRoutes.customerHome);
        // Process any terminated-app notification for customer — this is the main fix.
        // addPostFrameCallback ensures customerHome is fully mounted before we push
        // trackOrder on top of it, preventing a race where pushNamed fires on an
        // unready navigator.
        _processPendingNotification();
      }
    } else {
      // No active session — show onboarding on first launch, else role selection
      final prefs = await SharedPreferences.getInstance();
      final hasSeenOnboarding = prefs.getBool('hasSeenOnboarding') ?? false;
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        hasSeenOnboarding ? AppRoutes.roleSelect : AppRoutes.onboarding,
      );
      // No deep-link for unauthenticated users — clear any stale pending data
      pendingNotificationData = null;
    }
  }

  /// Consumes [pendingNotificationData] (set during a terminated-app launch)
  /// and deep-links the user to the correct screen.
  ///
  /// Must be called AFTER [Navigator.pushReplacementNamed] so the destination
  /// route is already on the stack. Uses [addPostFrameCallback] to defer the
  /// additional push until the new route's frame is fully rendered.
  ///
  /// IMPORTANT: For customers, we push [AppRoutes.trackOrder] directly on top
  /// of [AppRoutes.customerHome] (which was just pushed by pushReplacementNamed)
  /// instead of calling [handleNotificationClick] — doing so would re-push
  /// customerHome unnecessarily via pushNamedAndRemoveUntil.
  void _processPendingNotification() {
    final data = pendingNotificationData;
    if (data == null || data.isEmpty) return;
    // Consume immediately — prevent any chance of double-processing
    pendingNotificationData = null;

    final role = data['role'] as String?;
    final orderId = data['order_id'] as String?;

    // For customer: customerHome is already on the stack. Just push trackOrder on top.
    // For seller/rider: delegate to handleNotificationClick — their pushNamedAndRemoveUntil
    // correctly replaces the splash-navigated route with their own dashboard.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if ((role == 'customer' || (role == null && orderId != null)) && orderId != null) {
        // customerHome is already on stack — push trackOrder on top
        Navigator.of(context).pushNamed(
          AppRoutes.trackOrder,
          arguments: {'orderId': orderId},
        );
      } else {
        // seller / rider / other: let handleNotificationClick do full routing
        handleNotificationClick(data);
      }
    });
  }


  void _showNetworkErrorRetry() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Connection Error', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('Failed to load profile data. Please check your internet connection.', style: GoogleFonts.outfit(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<AuthProvider>().retryProfileFetch();
              _navigate();
            },
            child: Text('Retry', style: GoogleFonts.outfit(color: const Color(0xFF4C6EF5), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _bgCtrl.dispose(); _ringCtrl.dispose(); _logoCtrl.dispose();
    _shimmerCtrl.dispose(); _pulseCtrl.dispose(); _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      body: AnimatedBuilder(
        animation: Listenable.merge([_bgCtrl, _ringCtrl, _logoCtrl, _textCtrl, _shimmerCtrl, _pulseCtrl]),
        builder: (_, __) => Container(
          width: size.width,
          height: size.height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(const Color(0xFF04091E), const Color(0xFF07124A), _bgAnim.value)!,
                const Color(0xFF02061A),
                Color.lerp(const Color(0xFF08043E), const Color(0xFF120860), _bgAnim.value)!,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // ── Aurora blobs ──────────────────────────────────────────────
              Positioned(
                top: -size.height * 0.08,
                left: -size.width * 0.25,
                child: _aurora(size.width * 0.85, const Color(0xFF2B4FD4), 0.18 + _bgAnim.value * 0.12),
              ),
              Positioned(
                bottom: -size.height * 0.12,
                right: -size.width * 0.25,
                child: _aurora(size.width * 0.95, const Color(0xFF6230C8), 0.15 + (1 - _bgAnim.value) * 0.12),
              ),
              // Blue center glow behind logo
              Opacity(
                opacity: (_logoFade.value * 0.20).clamp(0.0, 1.0),
                child: _aurora(size.shortestSide * 0.70, const Color(0xFF5B8BFF), 1.0),
              ),

              // ── Expanding rings ──────────────────────────────────────────
              ...[
                (_ring1, size.shortestSide * 0.42, const Color(0xFF5B8BFF), 2.0),
                (_ring2, size.shortestSide * 0.30, const Color(0xFF4C6EF5), 1.4),
                (_ring3, size.shortestSide * 0.22, const Color(0xFF5B8BFF), 0.9),
              ].map((r) => _RingWidget(progress: r.$1.value, maxRadius: r.$2, color: r.$3, strokeW: r.$4)),

              // ── Star field ───────────────────────────────────────────────
              CustomPaint(size: size, painter: _StarPainter(_bgCtrl.value)),

              // ── Central content — visually centered ────────────────────────
              Align(
                alignment: const Alignment(0, -0.12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                  // Logo
                  FadeTransition(
                    opacity: _logoFade,
                    child: ScaleTransition(
                      scale: _logoScale,
                      child: ScaleTransition(
                        scale: _pulseAnim,
                        child: _EnythingLogo(
                          logoSize: size.shortestSide * 0.22,
                          shimmer: _shimmerAnim,
                          assemblyAnim: _logoCtrl,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Text block
                  FadeTransition(
                    opacity: _textFade,
                    child: Transform.translate(
                      offset: Offset(0, _textSlide.value),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // ENYTHING wordmark
                          ShaderMask(
                            shaderCallback: (b) => const LinearGradient(
                              colors: [Color(0xFF8BAAFF), Color(0xFF5B8BFF), Color(0xFF4C6EF5)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ).createShader(b),
                            child: Text('ENYTHING',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(
                                color: Colors.white, fontSize: 52,
                                fontWeight: FontWeight.w900, letterSpacing: 8, height: 1.0,
                              ),
                            ),
                          ),

                          const SizedBox(height: 14),

                          FadeTransition(
                            opacity: _taglineFade,
                            child: Text(
                              'Everything. Everywhere. Instantly.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(
                                color: Colors.white.withValues(alpha: 0.55),
                                fontSize: 15, fontWeight: FontWeight.w400, letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              ),

              // ── Bottom loading indicator ─────────────────────────────────
              Positioned(
                bottom: 52,
                child: FadeTransition(
                  opacity: _taglineFade,
                  child: AnimatedBuilder(
                    animation: _bgCtrl,
                    builder: (_, __) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(3, (i) {
                        final wave = (math.sin((_bgCtrl.value * 6) - i * 1.0) + 1) / 2;
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: i == 1 ? 9 : 5.5,
                          height: i == 1 ? 9 : 5.5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color.lerp(Colors.white.withValues(alpha: 0.15), const Color(0xFF5B8BFF), wave),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _aurora(double size, Color color, double opacity) => Opacity(
    opacity: opacity.clamp(0.0, 1.0),
    child: Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0.0)]),
      ),
    ),
  );
}

// ─── Enything Logo Widget ─────────────────────────────────────────────────────
class _EnythingLogo extends StatelessWidget {
  final double logoSize;
  final Animation<double> shimmer;
  final Animation<double> assemblyAnim;
  const _EnythingLogo({required this.logoSize, required this.shimmer, required this.assemblyAnim});

  @override
  Widget build(BuildContext context) {
    final r = logoSize * 0.28;
    return Stack(
      alignment: Alignment.center,
      children: [
        // Outer glow
        Container(
          width: logoSize + 48, height: logoSize + 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: const Color(0xFF5B8BFF).withValues(alpha: 0.35), blurRadius: 60, spreadRadius: 12),
              BoxShadow(color: const Color(0xFF4C6EF5).withValues(alpha: 0.20), blurRadius: 30, spreadRadius: 4),
            ],
          ),
        ),
        // Inner glow ring
        Container(
          width: logoSize + 16, height: logoSize + 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: const Color(0xFF8BAAFF).withValues(alpha: 0.22), blurRadius: 20, spreadRadius: 2),
            ],
          ),
        ),
        // Main logo container with frosted-glass border
        Container(
          width: logoSize, height: logoSize,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1A2A6C), Color(0xFF0D1B4A), Color(0xFF07103A)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(r),
            border: Border.all(
              color: const Color(0xFF5B8BFF).withValues(alpha: 0.40),
              width: 2.0,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(r),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Animated Vector Logo instead of PNG
                AnimatedBuilder(
                  animation: assemblyAnim,
                  builder: (_, __) => Padding(
                    padding: EdgeInsets.all(logoSize * 0.10),
                    child: CustomPaint(
                      size: Size(logoSize * 0.80, logoSize * 0.80),
                      painter: _LogoPartsPainter(progress: assemblyAnim.value),
                    ),
                  ),
                ),
                // Shimmer sweep overlay
                AnimatedBuilder(
                  animation: shimmer,
                  builder: (_, __) => Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                        stops: [
                          (shimmer.value - 0.45).clamp(0.0, 1.0),
                          shimmer.value.clamp(0.0, 1.0),
                          (shimmer.value + 0.45).clamp(0.0, 1.0),
                        ],
                        colors: [Colors.transparent, Colors.white.withValues(alpha: 0.09), Colors.transparent],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LogoPartsPainter extends CustomPainter {
  final double progress;
  _LogoPartsPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final radius = Radius.circular(h * 0.12);
    final thickness = h * 0.24;

    final topBox = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, thickness), radius);
    final botBox = RRect.fromRectAndRadius(Rect.fromLTWH(0, h - thickness, w, thickness), radius);
    final stemBox = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, thickness, h), radius);
    final midBox = RRect.fromRectAndRadius(Rect.fromLTWH(0, h / 2 - thickness / 2, w * 0.8, thickness), radius);

    double ease(double t) => Curves.easeOutCubic.transform(t.clamp(0.0, 1.0));

    final tTop   = ease((progress - 0.1) / 0.3);
    final tStem  = ease((progress - 0.3) / 0.3);
    final tBot   = ease((progress - 0.5) / 0.3);
    final tMid   = ease((progress - 0.7) / 0.3);

    void drawPart(RRect box, double t, Offset translation, Color color) {
      if (t <= 0) return;
      canvas.save();
      final currentOffset = Offset(translation.dx * (1 - t), translation.dy * (1 - t));
      canvas.translate(currentOffset.dx, currentOffset.dy);
      
      final paint = Paint()
        ..color = color.withValues(alpha: t * color.a)
        ..style = PaintingStyle.fill;
      
      canvas.drawRRect(box, paint);
      canvas.restore();
    }

    const colorTop = Color(0xCC00DCFF); // Cyan
    const colorBot = Color(0xCC6432FF); // Purple/Indigo
    const colorStem = Color(0xCC4664FF); // Blue
    const colorMid = Color(0xCC00FFC8); // Mint/Teal

    drawPart(botBox, tBot, Offset(0, h), colorBot);
    drawPart(topBox, tTop, Offset(0, -h), colorTop);
    drawPart(stemBox, tStem, Offset(-w, 0), colorStem);
    drawPart(midBox, tMid, Offset(w, 0), colorMid);
  }

  @override
  bool shouldRepaint(_LogoPartsPainter oldDelegate) => oldDelegate.progress != progress;
}

// ─── Custom Painters ──────────────────────────────────────────────────────────
class _RingWidget extends StatelessWidget {
  final double progress, maxRadius, strokeW;
  final Color color;
  const _RingWidget({required this.progress, required this.maxRadius, required this.color, required this.strokeW});
  @override
  Widget build(BuildContext context) {
    if (progress <= 0) return const SizedBox.shrink();
    return SizedBox.expand(
      child: CustomPaint(
        painter: _RingPainter(radius: maxRadius * progress, opacity: (1 - progress).clamp(0.0, 1.0) * 0.5, color: color, strokeWidth: strokeW),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double radius, opacity, strokeWidth;
  final Color color;
  const _RingPainter({required this.radius, required this.opacity, required this.color, required this.strokeWidth});
  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0 || radius <= 0) return;
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      radius,
      Paint()..color = color.withValues(alpha: opacity)..style = PaintingStyle.stroke..strokeWidth = strokeWidth,
    );
  }
  @override
  bool shouldRepaint(_RingPainter o) => o.radius != radius || o.opacity != opacity;
}

class _StarPainter extends CustomPainter {
  final double t;
  _StarPainter(this.t);
  static final _rnd = math.Random(13);
  static final _stars = List.generate(55, (_) => [
    _rnd.nextDouble(), _rnd.nextDouble(),
    _rnd.nextDouble() * 1.6 + 0.5,
    _rnd.nextDouble() * math.pi * 2,
  ]);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..style = PaintingStyle.fill;
    for (final s in _stars) {
      final tw = (math.sin(t * math.pi * 2 + s[3]) + 1) / 2;
      p.color = Colors.white.withValues(alpha: 0.03 + tw * 0.15);
      canvas.drawCircle(Offset(s[0] * size.width, s[1] * size.height), s[2], p);
    }
  }
  @override
  bool shouldRepaint(_StarPainter o) => o.t != t;
}

