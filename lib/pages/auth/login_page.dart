import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_colors.dart';
import '../../config/routes.dart';
import '../../utils/validators.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeIn);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    final error = await context.read<AuthProvider>().signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );

    if (!mounted) return;

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    final role = context.read<AuthProvider>().user?.role;
    if (role == 'seller') {
      Navigator.pushReplacementNamed(context, AppRoutes.sellerDashboard);
    } else if (role == 'delivery_partner') {
      Navigator.pushReplacementNamed(context, AppRoutes.deliveryDashboard);
    } else {
      Navigator.pushReplacementNamed(context, AppRoutes.customerHome);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────
            Container(
              height: size.height * 0.40,
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF0A2A9E),
                    Color(0xFF071D6B),
                    Color(0xFF050F3A),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(36)),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Gold logo
                    Container(
                      width: 82,
                      height: 82,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFFFFD700),
                            Color(0xFFF4C542),
                            Color(0xFFE5A800),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFF4C542).withOpacity(0.5),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                            spreadRadius: 2,
                          ),
                          BoxShadow(
                            color: Colors.black.withOpacity(0.25),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(Icons.bolt, color: Colors.white, size: 50),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Welcome Back!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Inter',
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Sign in to continue to Enything',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.75),
                        fontSize: 14,
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Form ────────────────────────────────────────────────────
            FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 36, 24, 32),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Email
                        _buildInputField(
                          controller: _emailController,
                          label: 'Email Address',
                          hint: 'you@example.com',
                          icon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                          validator: AppValidators.email,
                        ),
                        const SizedBox(height: 16),
                        // Password
                        _buildPasswordField(),
                        const SizedBox(height: 4),
                        // Forgot password
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () {},
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFFFF8A00),
                              padding: EdgeInsets.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              'Forgot Password?',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Sign In button
                        _buildCTAButton(
                          label: 'Sign In',
                          isLoading: auth.isLoading,
                          onPressed: _login,
                        ),
                        const SizedBox(height: 28),
                        // Sign up link
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "Don't have an account? ",
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                            ),
                            GestureDetector(
                              onTap: () => Navigator.pushReplacementNamed(
                                  context, AppRoutes.roleSelect),
                              child: const Text(
                                'Sign Up',
                                style: TextStyle(
                                  color: Color(0xFFFF8A00),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),
                        // Divider
                        Row(
                          children: [
                            Expanded(child: Divider(color: Colors.grey[300])),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                'OR',
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                            Expanded(child: Divider(color: Colors.grey[300])),
                          ],
                        ),
                        const SizedBox(height: 24),
                        // Feature badges
                        _buildFeatureBadges(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        validator: validator,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: Color(0xFF1A1A2E),
        ),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, size: 20),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF0A2A9E), width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFD32F2F)),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFD32F2F), width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        ),
      ),
    );
  }

  Widget _buildPasswordField() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextFormField(
        controller: _passwordController,
        obscureText: _obscurePassword,
        validator: AppValidators.password,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: Color(0xFF1A1A2E),
        ),
        decoration: InputDecoration(
          labelText: 'Password',
          hintText: '••••••••',
          prefixIcon: const Icon(Icons.lock_outline, size: 20),
          suffixIcon: IconButton(
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 20,
            ),
            onPressed: () =>
                setState(() => _obscurePassword = !_obscurePassword),
          ),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF0A2A9E), width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFD32F2F)),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFD32F2F), width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        ),
      ),
    );
  }

  Widget _buildCTAButton({
    required String label,
    required bool isLoading,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF9900), Color(0xFFFF6B00)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF8A00).withOpacity(0.45),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: isLoading
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
      ),
    );
  }

  Widget _buildFeatureBadges() {
    final badges = [
      {'icon': Icons.local_shipping_outlined, 'text': 'Fast Delivery'},
      {'icon': Icons.shield_outlined, 'text': 'Secure & Safe'},
      {'icon': Icons.store_outlined, 'text': 'Local Sellers'},
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: badges.map((b) {
        return Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF0A2A9E).withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                b['icon'] as IconData,
                color: const Color(0xFF0A2A9E),
                size: 22,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              b['text'] as String,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }
}
