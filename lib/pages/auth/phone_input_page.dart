import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/auth_provider.dart';
import '../../config/routes.dart';
import '../../utils/responsive_layout.dart';

class PhoneAuthPage extends StatefulWidget {
  const PhoneAuthPage({super.key});
  @override
  State<PhoneAuthPage> createState() => _PhoneAuthPageState();
}

class _PhoneAuthPageState extends State<PhoneAuthPage>
    with SingleTickerProviderStateMixin {
  final _phoneCtrl = TextEditingController();
  String _countryCode = '+91';
  bool _loading = false;
  bool _agreedToTerms = false;
  String? _selectedRole; // passed from RoleSelectionPage args

  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        duration: const Duration(milliseconds: 800), vsync: this)
      ..forward();
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Read the selected role passed from RoleSelectionPage
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    _selectedRole = args?['role'] as String?;
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.length < 10) {
      _showSnack('Enter a valid 10-digit number', isError: true);
      return;
    }
    setState(() => _loading = true);
    final fullPhone = '$_countryCode$phone';
    final err =
        await context.read<AuthProvider>().sendPhoneOtp(fullPhone);
    if (!mounted) return;
    setState(() => _loading = false);
    if (err != null) {
      _showSnack(err, isError: true);
    } else {
      Navigator.pushNamed(
        context,
        AppRoutes.otpVerify,
        arguments: {
          'phone': fullPhone,
          'role': _selectedRole, // forward the role to OTP page
        },
      );
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.outfit()),
      backgroundColor:
          isError ? const Color(0xFFE03131) : const Color(0xFF2F9E44),
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  String get _roleLabel {
    switch (_selectedRole) {
      case 'customer':         return 'Customer';
      case 'seller':           return 'Seller';
      case 'delivery_partner': return 'Delivery Partner';
      default:                 return '';
    }
  }

  String get _roleEmoji {
    switch (_selectedRole) {
      case 'customer':         return '🛍️';
      case 'seller':           return '🏪';
      case 'delivery_partner': return '🏍️';
      default:                 return '⚡';
    }
  }

  Color get _roleColor {
    switch (_selectedRole) {
      case 'seller':           return const Color(0xFFF4C542);
      case 'delivery_partner': return const Color(0xFF51CF66);
      default:                 return const Color(0xFF4C6EF5);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF02061A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle),
            child: const Icon(Icons.arrow_back_ios_new,
                color: Colors.white, size: 16),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Stack(
          children: [
            // Background blobs
            Positioned(
                top: -80,
                left: -60,
                child: _blob(300, const Color(0xFF1A35C8), 0.18)),
            Positioned(
                bottom: -100,
                right: -80,
                child: _blob(350, const Color(0xFF5E20D4), 0.15)),

            SafeArea(
              child: MaxWidthContainer(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 8),

                    // Logo mark
                    const _MiniLogo(size: 80),
                    const SizedBox(height: 16),

                    // Role badge
                    if (_selectedRole != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: _roleColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                              color: _roleColor.withValues(alpha: 0.40)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_roleEmoji,
                                style: const TextStyle(fontSize: 18)),
                            const SizedBox(width: 8),
                            Text(
                              'Joining as $_roleLabel',
                              style: GoogleFonts.outfit(
                                color: _roleColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    Text(
                      'Enter your number',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'We\'ll send a one-time password\nto verify your identity',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                          color: Colors.white54, fontSize: 14, height: 1.5),
                    ),
                    const SizedBox(height: 24),

                    // Phone input card
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.10)),
                      ),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Mobile Number',
                              style: GoogleFonts.outfit(
                                color: Colors.white54,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.8,
                              )),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              // Country code selector
                              GestureDetector(
                                onTap: _showCountryCodes,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 14),
                                  decoration: BoxDecoration(
                                    color:
                                        Colors.white.withValues(alpha: 0.08),
                                    borderRadius:
                                        BorderRadius.circular(14),
                                  ),
                                  child: Row(children: [
                                    const Text('🇮🇳',
                                        style: TextStyle(fontSize: 18)),
                                    const SizedBox(width: 6),
                                    Text(_countryCode,
                                        style: GoogleFonts.outfit(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700)),
                                    const Icon(Icons.arrow_drop_down,
                                        color: Colors.white54, size: 18),
                                  ]),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: IgnorePointer(
                                  ignoring: !_agreedToTerms,
                                  child: Opacity(
                                    opacity: _agreedToTerms ? 1.0 : 0.3,
                                    child: TextField(
                                      controller: _phoneCtrl,
                                      keyboardType: TextInputType.phone,
                                      maxLength: 10,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly
                                      ],
                                      onChanged: (val) {
                                        if (val.length == 10) {
                                          FocusScope.of(context).unfocus();
                                          if (_agreedToTerms && !_loading) {
                                            _sendOtp();
                                          }
                                        }
                                      },
                                      style: GoogleFonts.outfit(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 1,
                                      ),
                                      decoration: InputDecoration(
                                        hintText: '9876543210',
                                        hintStyle: GoogleFonts.outfit(
                                            color: Colors.white24,
                                            fontSize: 18),
                                        counterText: '',
                                        border: InputBorder.none,
                                        filled: false,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // CTA Button
                    GestureDetector(
                      onTap: (_loading || !_agreedToTerms) ? null : _sendOtp,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: double.infinity,
                        height: 58,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: _agreedToTerms
                                ? [const Color(0xFFFFD700), const Color(0xFFF4A800)]
                                : [Colors.grey.shade700, Colors.grey.shade800],
                          ),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: _agreedToTerms ? [
                            BoxShadow(
                                color: const Color(0xFFF4C542)
                                    .withValues(alpha: 0.40),
                                blurRadius: 20,
                                offset: const Offset(0, 8))
                          ] : [],
                        ),
                        child: Center(
                          child: _loading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                      color: Colors.black, strokeWidth: 2.5))
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('Send OTP',
                                        style: GoogleFonts.outfit(
                                          color: Colors.black,
                                          fontSize: 17,
                                          fontWeight: FontWeight.w800,
                                        )),
                                    const SizedBox(width: 10),
                                    const Icon(
                                        Icons.arrow_forward_rounded,
                                        color: Colors.black,
                                        size: 20),
                                  ],
                                ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Checkbox(
                            value: _agreedToTerms,
                            onChanged: (val) => setState(() => _agreedToTerms = val ?? false),
                            activeColor: const Color(0xFFF4C542),
                            checkColor: Colors.black,
                            side: const BorderSide(color: Colors.white54, width: 1.5),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: RichText(
                            textAlign: TextAlign.center,
                            text: TextSpan(
                              style: GoogleFonts.outfit(
                                color: Colors.white54,
                                fontSize: 13,
                                height: 1.5,
                              ),
                              children: [
                                const TextSpan(text: 'I agree to the '),
                                if (_selectedRole == 'seller')
                                  const TextSpan(text: 'Seller ')
                                else if (_selectedRole == 'delivery_partner')
                                  const TextSpan(text: 'Delivery Partner ')
                                else
                                  const TextSpan(text: 'Customer '),
                                WidgetSpan(
                                  child: GestureDetector(
                                    onTap: () => Navigator.pushNamed(context, AppRoutes.terms, arguments: {'role': _selectedRole}),
                                    child: Text(
                                      'Terms & Conditions',
                                      style: GoogleFonts.outfit(
                                        color: const Color(0xFFF4C542),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ),
                                ),
                                const TextSpan(text: ', '),
                                WidgetSpan(
                                  child: GestureDetector(
                                    onTap: () => Navigator.pushNamed(context, AppRoutes.privacy, arguments: {'role': _selectedRole}),
                                    child: Text(
                                      'Privacy Policy',
                                      style: GoogleFonts.outfit(
                                        color: const Color(0xFFF4C542),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ),
                                ),
                                const TextSpan(text: ', and '),
                                WidgetSpan(
                                  child: GestureDetector(
                                    onTap: () => Navigator.pushNamed(context, AppRoutes.refundPolicy, arguments: {'role': _selectedRole}),
                                    child: Text(
                                      _selectedRole == 'seller' 
                                          ? 'Fulfillment Policy'
                                          : (_selectedRole == 'delivery_partner' 
                                              ? 'Conduct Rules'
                                              : 'Refund Policy'),
                                      style: GoogleFonts.outfit(
                                        color: const Color(0xFFF4C542),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ),
                                ),
                                if (_selectedRole == 'customer') ...[
                                  const TextSpan(text: ', and '),
                                  WidgetSpan(
                                    child: GestureDetector(
                                      onTap: () => Navigator.pushNamed(context, AppRoutes.shippingPolicy),
                                      child: Text(
                                        'Shipping Policy',
                                        style: GoogleFonts.outfit(
                                          color: const Color(0xFFF4C542),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Want to switch role?
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Text(
                        '← Choose a different role',
                        style: GoogleFonts.outfit(
                          color: const Color(0xFFF4C542).withValues(alpha: 0.70),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
              ),
            ),
          ],
        ),
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
                RadialGradient(colors: [color, color.withValues(alpha: 0)]),
          ),
        ),
      );

  void _showCountryCodes() {
    final codes = [
      ['🇮🇳', '+91', 'India'],
      ['🇺🇸', '+1', 'USA'],
      ['🇬🇧', '+44', 'UK'],
      ['🇦🇪', '+971', 'UAE'],
      ['🇸🇬', '+65', 'Singapore'],
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0D1440),
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: codes
              .map((c) => ListTile(
                    leading:
                        Text(c[0], style: const TextStyle(fontSize: 24)),
                    title: Text(c[2],
                        style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontWeight: FontWeight.w600)),
                    trailing: Text(c[1],
                        style:
                            GoogleFonts.outfit(color: Colors.white54)),
                    onTap: () {
                      setState(() => _countryCode = c[1]);
                      Navigator.pop(context);
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }
}

// ── Mini logo reused across auth screens ───────────────────────────────────────
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
              color: const Color(0xFFF4C542).withValues(alpha: 0.20),
              blurRadius: 20,
              spreadRadius: 2)
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.28),
        child: Image.asset(
          'logo/Enything_modern.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}
