import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_colors.dart';
import '../../config/routes.dart';
import '../../utils/responsive_layout.dart';

class AboutEnythingPage extends StatelessWidget {
  const AboutEnythingPage({super.key});

  Future<void> _launchEmail() async {
    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: 'support@enything.in',
      queryParameters: {
        'subject': 'Support Request: Enything App'
      },
    );
    if (await canLaunchUrl(emailLaunchUri)) {
      await launchUrl(emailLaunchUri);
    }
  }

  Future<void> _launchPhone() async {
    final Uri phoneUri = Uri(scheme: 'tel', path: '+917006464241');
    if (await canLaunchUrl(phoneUri)) {
      await launchUrl(phoneUri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF080812) : AppColors.background,
      appBar: AppBar(
        title: Text('About Enything', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      extendBodyBehindAppBar: true,
      body: MaxWidthContainer(
        child: SingleChildScrollView(
          child: Column(
          children: [
            // Hero Header
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(24, MediaQuery.of(context).padding.top + 56 + 24, 24, 40),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primaryDark, AppColors.primaryLight],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(40)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 20, offset: const Offset(0, 10))
                      ],
                    ),
                    child: Center(
                      child: Text(
                        'E',
                        style: GoogleFonts.outfit(
                          fontSize: 56,
                          fontWeight: FontWeight.w900,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Enything',
                    style: GoogleFonts.outfit(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Version 1.0.0',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Delivered at the speed of life! ⚡',
                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),

            // Main Content
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Legal', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: isDark ? Colors.white : AppColors.textPrimary)),
                  const SizedBox(height: 16),
                  
                  _buildListTile(
                    title: 'Terms of Service',
                    icon: Icons.description_outlined,
                    isDark: isDark,
                    onTap: () => Navigator.pushNamed(context, AppRoutes.terms),
                  ),
                  const SizedBox(height: 12),
                  _buildListTile(
                    title: 'Privacy Policy',
                    icon: Icons.privacy_tip_outlined,
                    isDark: isDark,
                    onTap: () => Navigator.pushNamed(context, AppRoutes.privacy),
                  ),
                  const SizedBox(height: 12),
                  _buildListTile(
                    title: 'Refund Policy',
                    icon: Icons.receipt_long_outlined,
                    isDark: isDark,
                    onTap: () => Navigator.pushNamed(context, AppRoutes.refundPolicy),
                  ),

                  const SizedBox(height: 32),
                  Text('Contact Info', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: isDark ? Colors.white : AppColors.textPrimary)),
                  const SizedBox(height: 16),

                  _buildListTile(
                    title: 'support@enything.in',
                    icon: Icons.email_outlined,
                    isDark: isDark,
                    onTap: _launchEmail,
                  ),
                  const SizedBox(height: 12),
                  _buildListTile(
                    title: '+91 7006464241',
                    icon: Icons.phone_outlined,
                    isDark: isDark,
                    onTap: _launchPhone,
                  ),

                  const SizedBox(height: 48),
                  
                  Center(
                    child: Column(
                      children: [
                        Icon(Icons.favorite_rounded, color: Colors.red.shade400, size: 28),
                        const SizedBox(height: 12),
                        Text(
                          'Made with ❤️ in India',
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white54 : AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '© ${DateTime.now().year} Enything Technologies.',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            color: isDark ? Colors.white38 : AppColors.textLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildListTile({required String title, required IconData icon, required bool isDark, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            if (!isDark) BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4)),
          ],
          border: Border.all(color: isDark ? Colors.white12 : Colors.transparent),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 16, color: isDark ? Colors.white38 : AppColors.textLight),
          ],
        ),
      ),
    );
  }
}
