import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/rbac_provider.dart';
import '../../config/routes.dart';
import '../../theme/admin_theme.dart';

// ── Admin Password Gate ──────────────────────────────────────────
// Shown after OTP. Acts as a 2nd-factor "something you know" gate.

class AdminPasswordPage extends StatefulWidget {
  const AdminPasswordPage({super.key});
  @override
  State<AdminPasswordPage> createState() => _AdminPasswordPageState();
}

class _AdminPasswordPageState extends State<AdminPasswordPage>
    with TickerProviderStateMixin {
  final _passwordCtrl = TextEditingController();
  final _focusNode = FocusNode();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  late AnimationController _bgCtrl;
  late AnimationController _shakeCtrl;
  late Animation<double> _bgAnim;
  late Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();

    // Slow pulsing background
    _bgCtrl = AnimationController(
        duration: const Duration(seconds: 8), vsync: this)
      ..repeat(reverse: true);
    _bgAnim = CurvedAnimation(parent: _bgCtrl, curve: Curves.easeInOut);

    // Shake on error
    _shakeCtrl = AnimationController(
        duration: const Duration(milliseconds: 500), vsync: this);
    _shakeAnim = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticIn));
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    _shakeCtrl.dispose();
    _passwordCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _verifyPassword() async {
    final pw = _passwordCtrl.text.trim();
    if (pw.isEmpty) {
      _triggerError('Please enter your admin password.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    HapticFeedback.lightImpact();

    final auth = context.read<AuthProvider>();
    final success = await auth.verifyAdminPassword(pw);

    if (!mounted) return;
    setState(() => _loading = false);

    if (success) {
      HapticFeedback.heavyImpact();
      final userId = auth.currentUserId;
      if (userId != null) {
        await context.read<RbacProvider>().loadCurrentAdmin(userId);
      }
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
          context, AppRoutes.adminDashboard, (_) => false);
    } else {
      HapticFeedback.vibrate();
      _triggerError('Incorrect admin password. Access denied.');
    }
  }

  void _triggerError(String msg) {
    setState(() => _error = msg);
    _shakeCtrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: AdminColors.bg,
      body: Stack(
        children: [
          // ── Animated gradient auras ──────────────────────────
          AnimatedBuilder(
            animation: _bgCtrl,
            builder: (_, __) => Stack(children: [
              Positioned(
                top: -100 + (_bgAnim.value * 50),
                left: -80,
                child: _Aura(size.width * 0.8, AdminColors.primary, 0.18),
              ),
              Positioned(
                bottom: -150 - (_bgAnim.value * 40),
                right: -60,
                child: _Aura(size.width * 0.9, AdminColors.primaryEnd, 0.14),
              ),
              Positioned(
                top: size.height * 0.5 + (_bgAnim.value * 30),
                left: size.width * 0.2,
                child: const _Aura(200, AdminColors.info, 0.07),
              ),
            ]),
          ),

          // ── Subtle grid overlay ──────────────────────────────
          Positioned.fill(
            child: CustomPaint(painter: _GridPainter()),
          ),

          // ── Main content ─────────────────────────────────────
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: Column(
                children: [
                  const SizedBox(height: 24),

                  // Logo / Shield Icon
                  _buildLogo(),

                  const SizedBox(height: 36),

                  // Title block
                  Text(
                    'ENYTHING ADMIN',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      color: AdminColors.warning,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 3,
                    ),
                  ).animate().fadeIn(delay: 200.ms),

                  const SizedBox(height: 10),

                  ShaderMask(
                    shaderCallback: (bounds) =>
                        AdminGradients.primary.createShader(bounds),
                    child: Text(
                      'Control Tower',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 38,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                        height: 1.1,
                      ),
                    ),
                  ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.2),

                  const SizedBox(height: 12),

                  Text(
                    'Enter your admin password to access\nthe Enything back-office.',
                    textAlign: TextAlign.center,
                    style: AdminStyles.body(
                        size: 14, color: AdminColors.textSecondary),
                  ).animate().fadeIn(delay: 400.ms),

                  const SizedBox(height: 48),

                  // Password field with shake animation
                  AnimatedBuilder(
                    animation: _shakeAnim,
                    builder: (context, child) {
                      final offset =
                          (_shakeAnim.value * 8) * (_shakeCtrl.value < 0.5 ? -1 : 1);
                      return Transform.translate(
                        offset: Offset(offset, 0),
                        child: child,
                      );
                    },
                    child: _buildPasswordField(),
                  ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.15),

                  // Error message
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: AdminColors.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AdminColors.danger.withValues(alpha: 0.4)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.error_outline_rounded,
                            color: AdminColors.danger, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_error!,
                              style: AdminStyles.caption(
                                  color: AdminColors.danger)),
                        ),
                      ]),
                    ).animate().fadeIn().shakeX(),
                  ],

                  const SizedBox(height: 32),

                  // Unlock button
                  _buildUnlockButton()
                      .animate()
                      .fadeIn(delay: 600.ms)
                      .slideY(begin: 0.15),

                  const SizedBox(height: 20),

                  // Biometric hint
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.fingerprint_rounded,
                          color: AdminColors.textMuted, size: 18),
                      const SizedBox(width: 8),
                      Text('Biometric login available after first sign-in',
                          style: AdminStyles.caption()),
                    ],
                  ).animate().fadeIn(delay: 700.ms),

                  const SizedBox(height: 32),

                  TextButton.icon(
                    onPressed: () => Navigator.pushNamedAndRemoveUntil(
                        context, AppRoutes.roleSelect, (_) => false),
                    icon: const Icon(Icons.arrow_back_rounded,
                        size: 14, color: AdminColors.textMuted),
                    label: Text('Not you? Switch account',
                        style: AdminStyles.caption()),
                  ).animate().fadeIn(delay: 700.ms),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AdminColors.primary.withValues(alpha: 0.3),
            blurRadius: 40,
            spreadRadius: 4,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(48),
        child: Image.asset(
          'logo/Enything_modern.png',
          fit: BoxFit.cover,
        ),
      ),
    )
        .animate()
        .fadeIn(delay: 100.ms)
        .scale(begin: const Offset(0.7, 0.7), curve: Curves.easeOutBack);
  }

  Widget _buildPasswordField() {
    return Container(
      decoration: BoxDecoration(
        color: AdminColors.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _error != null
              ? AdminColors.danger.withValues(alpha: 0.6)
              : AdminColors.cardBorder,
        ),
        boxShadow: [
          BoxShadow(
            color: (_error != null ? AdminColors.danger : AdminColors.primary)
                .withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Row(children: [
        const Icon(Icons.lock_outline_rounded,
            color: AdminColors.textMuted, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: _passwordCtrl,
            focusNode: _focusNode,
            obscureText: _obscure,
            obscuringCharacter: '*',
            cursorColor: AdminColors.primary,
            style: GoogleFonts.poppins(
                color: AdminColors.textPrimary,
                fontSize: 17,
                letterSpacing: _obscure ? 4 : 0),
            decoration: InputDecoration(
              hintText: '* * * * * * * *',
              hintStyle: AdminStyles.body(
                  size: 16, color: AdminColors.textMuted),
              border: InputBorder.none,
              filled: false,
            ),
            onSubmitted: (_) => _verifyPassword(),
          ),
        ),
        IconButton(
          icon: Icon(
            _obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded,
            color: AdminColors.textMuted,
            size: 20,
          ),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ]),
    );
  }

  Widget _buildUnlockButton() {
    return GestureDetector(
      onTap: _loading ? null : _verifyPassword,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 58,
        decoration: BoxDecoration(
          gradient: _loading
              ? LinearGradient(colors: [
                  AdminColors.primary.withValues(alpha: 0.5),
                  AdminColors.primaryEnd.withValues(alpha: 0.5),
                ])
              : AdminGradients.primary,
          borderRadius: BorderRadius.circular(20),
          boxShadow: _loading
              ? []
              : [
                  BoxShadow(
                    color: AdminColors.primary.withValues(alpha: 0.45),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
        ),
        child: Center(
          child: _loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.5))
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.shield_rounded,
                        color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Text('Unlock Control Tower',
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────
class _Aura extends StatelessWidget {
  final double size;
  final Color color;
  final double opacity;
  const _Aura(this.size, this.color, this.opacity);

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: opacity,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
                colors: [color, color.withValues(alpha: 0.0)]),
          ),
        ),
      );
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.02)
      ..strokeWidth = 0.5;
    const spacing = 32.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter _) => false;
}
