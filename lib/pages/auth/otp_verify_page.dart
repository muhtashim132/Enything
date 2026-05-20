import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/auth_provider.dart';
import '../../config/routes.dart';

class OtpVerifyPage extends StatefulWidget {
  const OtpVerifyPage({super.key});
  @override
  State<OtpVerifyPage> createState() => _OtpVerifyPageState();
}

class _OtpVerifyPageState extends State<OtpVerifyPage>
    with SingleTickerProviderStateMixin {
  final List<TextEditingController> _ctrlList =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusList = List.generate(6, (_) => FocusNode());

  bool _loading = false;
  int _resendTimer = 30;
  Timer? _timer;

  String _phone = '';
  String? _requestedRole; // role passed from PhoneAuthPage

  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;

  // Welcome splash state
  bool _showWelcome = false;
  String _welcomeRole = '';

  // Role-picker state (for existing users with multiple roles)
  bool _showRolePicker = false;
  List<String> _availableRoles = [];

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
        duration: const Duration(milliseconds: 500), vsync: this);
    _shakeAnim = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticIn));
    _startTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      setState(() {
        _phone = args?['phone'] ?? '';
        _requestedRole = args?['role'] as String?;
      });
      _focusList[0].requestFocus();
    });
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _resendTimer = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendTimer == 0) {
        t.cancel();
        return;
      }
      if (mounted) setState(() => _resendTimer--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _shakeCtrl.dispose();
    for (final c in _ctrlList) {
      c.dispose();
    }
    for (final f in _focusList) {
      f.dispose();
    }
    super.dispose();
  }

  String get _otp => _ctrlList.map((c) => c.text).join();

  void _onChanged(int i, String val) {
    if (val.length > 1) {
      final digits = val.replaceAll(RegExp(r'\D'), '').split('');
      for (int j = 0; j < 6 && j < digits.length; j++) {
        _ctrlList[j].text = digits[j];
      }
      _focusList[5].requestFocus();
      if (_otp.length == 6) _verify();
      return;
    }
    if (val.isNotEmpty && i < 5) _focusList[i + 1].requestFocus();
    if (_otp.length == 6) _verify();
  }

  void _onBackspace(int i) {
    if (_ctrlList[i].text.isEmpty && i > 0) {
      _ctrlList[i - 1].clear();
      _focusList[i - 1].requestFocus();
    }
  }

  Future<void> _verify() async {
    if (_otp.length < 6) return;
    setState(() => _loading = true);
    FocusScope.of(context).unfocus();

    final result = await context.read<AuthProvider>().verifyPhoneOtp(
          _phone,
          _otp,
          preferredRole: _requestedRole,
        );

    if (!mounted) return;
    setState(() => _loading = false);

    if (result == 'existing') {
      final auth = context.read<AuthProvider>();
      final allRoles = auth.user?.activeRoles ?? [];


      // ── Case A: requested role is NOT yet registered — add new role ────────
      if (_requestedRole != null && !allRoles.contains(_requestedRole)) {
        // User exists but chosen role is new for them → complete profile for new role
        _showSnack(
          '✅ Verified! Set up your ${_roleLabel(_requestedRole!)} profile.',
          isError: false,
        );
        await Future.delayed(const Duration(milliseconds: 800));
        if (!mounted) return;
        Navigator.pushNamedAndRemoveUntil(
          context,
          AppRoutes.completeProfile,
          (_) => false,
          arguments: {'role': _requestedRole, 'isAddingRole': true},
        );
        return;
      }

      // ── Case B: user has multiple roles — let them pick which session ───────
      if (allRoles.length > 1) {
        setState(() {
          _showRolePicker = true;
          _availableRoles = allRoles;
        });
        return;
      }

      // ── Case C: single role — go straight to that dashboard ────────────────
      final role = auth.user?.activeSessionRole ?? 'customer';
      _goToWelcomeThenDashboard(role);
    } else if (result == 'new') {
      // Brand-new user — go to profile setup with the selected role pre-filled
      Navigator.pushReplacementNamed(
        context,
        AppRoutes.completeProfile,
        arguments: {
          'role': _requestedRole,
          'isAddingRole': false,
        },
      );
    } else {
      _shakeCtrl.forward(from: 0);
      for (final c in _ctrlList) {
        c.clear();
      }
      _focusList[0].requestFocus();
      final err =
          context.read<AuthProvider>().error ?? 'Invalid OTP. Try again.';
      _showSnack(err, isError: true);
    }
  }

  void _selectRole(String role) {
    context.read<AuthProvider>().switchSessionRole(role);
    setState(() {
      _showRolePicker = false;
      _availableRoles = [];
    });
    _goToWelcomeThenDashboard(role);
  }

  Future<void> _goToWelcomeThenDashboard(String role) async {
    setState(() {
      _showWelcome = true;
      _welcomeRole = role;
    });
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    _navigateToDashboard(role);
  }

  void _navigateToDashboard(String role) {
    // Admin must pass 2nd-factor password gate first
    if (role == 'admin') {
      Navigator.pushNamedAndRemoveUntil(
          context, AppRoutes.adminPassword, (_) => false);
      return;
    }

    final auth = context.read<AuthProvider>();
    final status = auth.user?.verificationStatus ?? 'verified';

    if (role == 'seller') {
      if (status == 'verified') {
        Navigator.pushNamedAndRemoveUntil(
            context, AppRoutes.sellerDashboard, (_) => false);
      } else {
        Navigator.pushNamedAndRemoveUntil(
            context, AppRoutes.sellerPendingVerification, (_) => false);
      }
    } else if (role == 'delivery_partner') {
      if (status == 'verified') {
        Navigator.pushNamedAndRemoveUntil(
            context, AppRoutes.deliveryDashboard, (_) => false);
      } else {
        Navigator.pushNamedAndRemoveUntil(
            context, AppRoutes.deliveryPendingVerification, (_) => false);
      }
    } else {
      Navigator.pushNamedAndRemoveUntil(
          context, AppRoutes.customerHome, (_) => false);
    }
  }

  Future<void> _resend() async {
    if (_resendTimer > 0) return;
    setState(() => _loading = true);
    await context.read<AuthProvider>().sendPhoneOtp(_phone);
    if (!mounted) return;
    setState(() => _loading = false);
    _startTimer();
    for (final c in _ctrlList) {
      c.clear();
    }
    _focusList[0].requestFocus();
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.outfit()),
      backgroundColor:
          isError ? const Color(0xFFE03131) : const Color(0xFF2F9E44),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  String _roleLabel(String r) {
    switch (r) {
      case 'seller':           return 'Seller';
      case 'delivery_partner': return 'Delivery Partner';
      case 'customer':         return 'Customer';
      case 'admin':            return 'Admin';
      default:                 return r;
    }
  }

  String _roleEmoji(String r) {
    switch (r) {
      case 'seller':           return '🏪';
      case 'delivery_partner': return '🏍️';
      case 'admin':            return '👑';
      default:                 return '🛒';
    }
  }

  Color _roleColor(String r) {
    switch (r) {
      case 'seller':           return const Color(0xFFF4C542);
      case 'delivery_partner': return const Color(0xFF51CF66);
      case 'admin':            return const Color(0xFF8B2FC9);
      default:                 return const Color(0xFF4C6EF5);
    }
  }

  // ── Welcome splash ─────────────────────────────────────────────────────────
  Widget _buildWelcomeSplash() {
    final auth = context.read<AuthProvider>();
    final name = auth.user?.fullName.split(' ').first ?? 'there';
    return Scaffold(
      backgroundColor: const Color(0xFF02061A),
      body: Stack(children: [
        Positioned(
            top: -60,
            left: -80,
            child: _blob(280, const Color(0xFF1A35C8), 0.20)),
        Positioned(
            bottom: -80,
            right: -60,
            child: _blob(300, const Color(0xFF5E20D4), 0.18)),
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_roleEmoji(_welcomeRole),
                  style: const TextStyle(fontSize: 72)),
              const SizedBox(height: 24),
              Text(
                'Welcome back, $name! 👋',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: _roleColor(_welcomeRole).withOpacity(0.20),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                      color: _roleColor(_welcomeRole).withOpacity(0.50)),
                ),
                child: Text(
                  _roleLabel(_welcomeRole),
                  style: GoogleFonts.outfit(
                      color: _roleColor(_welcomeRole),
                      fontSize: 15,
                      fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 40),
              const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                      color: Color(0xFFF4C542), strokeWidth: 2.5)),
            ],
          ),
        ),
      ]),
    );
  }

  // ── Role Picker (multi-role users) ─────────────────────────────────────────
  Widget _buildRolePicker() {
    final auth = context.read<AuthProvider>();
    final name = auth.user?.fullName.split(' ').first ?? 'there';
    return Scaffold(
      backgroundColor: const Color(0xFF02061A),
      body: Stack(
        children: [
          Positioned(
              top: -60,
              left: -80,
              child: _blob(280, const Color(0xFF1A35C8), 0.18)),
          Positioned(
              bottom: -80,
              right: -60,
              child: _blob(300, const Color(0xFF5E20D4), 0.16)),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  const SizedBox(height: 48),

                  // Check icon
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2F9E44).withOpacity(0.20),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: const Color(0xFF51CF66).withOpacity(0.50),
                          width: 2),
                    ),
                    child: const Center(
                      child: Icon(Icons.verified_rounded,
                          color: Color(0xFF51CF66), size: 40),
                    ),
                  ),
                  const SizedBox(height: 24),

                  Text(
                    'Verified, $name! 🎉',
                    style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You have multiple roles. Choose how\nyou want to continue today:',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                        color: Colors.white54, fontSize: 14, height: 1.5),
                  ),
                  const SizedBox(height: 36),

                  // Role option cards
                  ..._availableRoles.map((role) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: GestureDetector(
                          onTap: () => _selectRole(role),
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: _roleColor(role).withOpacity(0.10),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: _roleColor(role).withOpacity(0.35),
                                  width: 1.5),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: _roleColor(role).withOpacity(0.18),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                        color: _roleColor(role)
                                            .withOpacity(0.40)),
                                  ),
                                  child: Center(
                                    child: Text(_roleEmoji(role),
                                        style:
                                            const TextStyle(fontSize: 26)),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _roleLabel(role),
                                        style: GoogleFonts.outfit(
                                          color: Colors.white,
                                          fontSize: 17,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        _roleDashboardHint(role),
                                        style: GoogleFonts.outfit(
                                            color: Colors.white38,
                                            fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.arrow_forward_ios_rounded,
                                    color: _roleColor(role), size: 18),
                              ],
                            ),
                          ),
                        ),
                      )),

                  const SizedBox(height: 16),

                  // Add new role option
                  GestureDetector(
                    onTap: () {
                      setState(() => _showRolePicker = false);
                      Navigator.pushNamedAndRemoveUntil(
                        context,
                        AppRoutes.roleSelect,
                        (_) => false,
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.10)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.add_circle_outline,
                              color: Color(0xFFF4C542), size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Add another role',
                            style: GoogleFonts.outfit(
                              color: const Color(0xFFF4C542),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _roleDashboardHint(String r) {
    switch (r) {
      case 'seller':           return 'Go to Seller Dashboard';
      case 'delivery_partner': return 'Go to Delivery Dashboard';
      case 'admin':            return 'Enter God Mode Control Tower';
      default:                 return 'Go to Customer Home';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showWelcome) return _buildWelcomeSplash();
    if (_showRolePicker) return _buildRolePicker();

    final maskedPhone = _phone.length > 4
        ? '${_phone.substring(0, _phone.length - 4).replaceAll(RegExp(r'\d'), '•')}${_phone.substring(_phone.length - 4)}'
        : _phone;

    // Role indicator colors
    final roleColor = _requestedRole != null
        ? _roleColor(_requestedRole!)
        : const Color(0xFF4C6EF5);

    return Scaffold(
      backgroundColor: const Color(0xFF02061A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                shape: BoxShape.circle),
            child: const Icon(Icons.arrow_back_ios_new,
                color: Colors.white, size: 16),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          Positioned(
              top: -60,
              left: -80,
              child: _blob(280, const Color(0xFF1A35C8), 0.16)),
          Positioned(
              bottom: -80,
              right: -60,
              child: _blob(300, const Color(0xFF5E20D4), 0.14)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  const _MiniLogo(size: 64),
                  const SizedBox(height: 20),

                  // Role badge
                  if (_requestedRole != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: roleColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(30),
                        border:
                            Border.all(color: roleColor.withOpacity(0.40)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_roleEmoji(_requestedRole!),
                              style: const TextStyle(fontSize: 14)),
                          const SizedBox(width: 6),
                          Text(
                            'As ${_roleLabel(_requestedRole!)}',
                            style: GoogleFonts.outfit(
                                color: roleColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),

                  Text(
                    'Verify your number',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(children: [
                      TextSpan(
                          text: 'OTP sent to ',
                          style: GoogleFonts.outfit(
                              color: Colors.white54, fontSize: 14)),
                      TextSpan(
                          text: maskedPhone,
                          style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                    ]),
                  ),
                  const SizedBox(height: 40),

                  // 6-box OTP input
                  AnimatedBuilder(
                    animation: _shakeAnim,
                    builder: (_, child) => Transform.translate(
                      offset: Offset(
                          _shakeAnim.value > 0
                              ? (8 * (0.5 - _shakeAnim.value).abs() * 4)
                              : 0,
                          0),
                      child: child,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                          6,
                          (i) => _OtpBox(
                                controller: _ctrlList[i],
                                focusNode: _focusList[i],
                                onChanged: (v) => _onChanged(i, v),
                                onBackspace: () => _onBackspace(i),
                                index: i,
                              )),
                    ),
                  ),

                  const SizedBox(height: 36),

                  // Verify button
                  GestureDetector(
                    onTap: _loading ? null : _verify,
                    child: Container(
                      width: double.infinity,
                      height: 58,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [Color(0xFFFFD700), Color(0xFFF4A800)]),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                              color: const Color(0xFFF4C542).withOpacity(0.40),
                              blurRadius: 20,
                              offset: const Offset(0, 8))
                        ],
                      ),
                      child: Center(
                        child: _loading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                    color: Colors.black, strokeWidth: 2.5))
                            : Text('Verify OTP',
                                style: GoogleFonts.outfit(
                                    color: Colors.black,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Resend
                  GestureDetector(
                    onTap: _resendTimer == 0 ? _resend : null,
                    child: RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(children: [
                        TextSpan(
                            text: "Didn't receive OTP? ",
                            style: GoogleFonts.outfit(
                                color: Colors.white38, fontSize: 14)),
                        TextSpan(
                          text: _resendTimer > 0
                              ? 'Resend in ${_resendTimer}s'
                              : 'Resend',
                          style: GoogleFonts.outfit(
                            color: _resendTimer == 0
                                ? const Color(0xFFF4C542)
                                : Colors.white30,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _blob(double size, Color color, double opacity) => Opacity(
        opacity: opacity,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient:
                RadialGradient(colors: [color, color.withOpacity(0)]),
          ),
        ),
      );
}

// ── OTP Input Box ──────────────────────────────────────────────────────────────
class _OtpBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onBackspace;
  final int index;
  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onBackspace,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 56,
      margin: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: Colors.white.withOpacity(0.12), width: 1.5),
      ),
      child: KeyboardListener(
        focusNode: FocusNode(),
        onKeyEvent: (e) {
          if (e is KeyDownEvent &&
              e.logicalKey == LogicalKeyboardKey.backspace) {
            onBackspace();
          }
        },
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          textAlign: TextAlign.center,
          textAlignVertical: TextAlignVertical.center,
          cursorColor: const Color(0xFFF4C542),
          keyboardType: TextInputType.number,
          maxLength: 1,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: GoogleFonts.outfit(
              color: const Color(0xFFF4C542),
              fontSize: 22,
              fontWeight: FontWeight.w800),
          decoration: const InputDecoration(
              counterText: '', 
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              filled: false),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ── Mini logo ──────────────────────────────────────────────────────────────────
class _MiniLogo extends StatelessWidget {
  final double size;
  const _MiniLogo({required this.size});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFFF4C542).withOpacity(0.20),
              blurRadius: 20,
              spreadRadius: 2)
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.28),
        child: Image.asset(
          'assets/images/Enything.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}
