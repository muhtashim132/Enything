import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../config/routes.dart';
import '../../providers/auth_provider.dart';

import '../../providers/notification_provider.dart';

class DeliveryPendingVerificationPage extends StatefulWidget {
  const DeliveryPendingVerificationPage({super.key});

  @override
  State<DeliveryPendingVerificationPage> createState() => _DeliveryPendingVerificationPageState();
}

class _DeliveryPendingVerificationPageState extends State<DeliveryPendingVerificationPage> with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(duration: const Duration(seconds: 2), vsync: this)..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.08).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut));
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      final userId = auth.currentUserId;
      if (userId != null) {
        context.read<NotificationProvider>().registerFcmToken(userId, 'delivery');
      }
    });
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isRejected = auth.user?.verificationStatus == 'rejected';
    final primaryColor = isRejected ? Colors.redAccent : const Color(0xFF51CF66);

    return Scaffold(
      backgroundColor: const Color(0xFF02061A),
      body: Stack(
        children: [
          // Background Glows
          Positioned(
            top: -100,
            left: -50,
            child: _buildGlow(primaryColor.withValues(alpha: 0.15), 300),
          ),
          Positioned(
            bottom: -50,
            right: -100,
            child: _buildGlow(primaryColor.withValues(alpha: 0.1), 400),
          ),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ScaleTransition(
                      scale: isRejected ? const AlwaysStoppedAnimation(1.0) : _pulseAnim,
                      child: Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                          border: Border.all(color: primaryColor.withValues(alpha: 0.3), width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: primaryColor.withValues(alpha: 0.2),
                              blurRadius: 40,
                              spreadRadius: 10,
                            ),
                          ],
                        ),
                        child: Icon(
                          isRejected ? Icons.gpp_bad_rounded : Icons.admin_panel_settings_rounded,
                          size: 80,
                          color: primaryColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 48),
                    Text(
                      isRejected ? 'Application Rejected' : 'Verification in Progress',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                      ),
                      child: Text(
                        isRejected
                            ? 'Unfortunately, your delivery partner verification was not successful. This is usually due to blurry document photos or mismatched details.\n\nPlease re-upload your documents to continue.'
                            : 'Your KYC documents have been successfully securely transmitted to our Back-Office Operations Team.\n\nYou will be notified and granted access to your Delivery Dashboard once your profile is verified.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          color: Colors.white70,
                          fontSize: 16,
                          height: 1.6,
                        ),
                      ),
                    ),
                    const SizedBox(height: 48),
                    if (isRejected)
                      _buildButton(
                        label: 'Re-upload Documents',
                        color: primaryColor,
                        onTap: () => Navigator.pushReplacementNamed(context, AppRoutes.deliveryKycUpload),
                        icon: Icons.upload_file_rounded,
                      )
                    else
                      _buildButton(
                        label: 'Return Home',
                        color: Colors.white.withValues(alpha: 0.1),
                        textColor: Colors.white,
                        onTap: () => Navigator.pushNamedAndRemoveUntil(context, AppRoutes.roleSelect, (_) => false),
                        icon: Icons.home_rounded,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlow(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color,
            blurRadius: size / 2,
            spreadRadius: size / 4,
          ),
        ],
      ),
    );
  }

  Widget _buildButton({required String label, required Color color, required VoidCallback onTap, required IconData icon, Color? textColor}) {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: textColor ?? Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: textColor ?? Colors.white),
            const SizedBox(width: 12),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: textColor ?? Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
