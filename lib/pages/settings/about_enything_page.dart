import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_colors.dart';
import '../../config/routes.dart';
import '../../config/app_version.dart';
import '../../utils/responsive_layout.dart';

class AboutEnythingPage extends StatelessWidget {
  const AboutEnythingPage({super.key});

  Future<void> _launchEmail() async {
    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: 'support@enything.in',
      queryParameters: {'subject': 'Support Request: Enything App'},
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
        title: Text('About Enything',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      extendBodyBehindAppBar: true,
      body: MaxWidthContainer(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // ── Hero Header ───────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(
                    24, MediaQuery.of(context).padding.top + 56 + 24, 24, 40),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primaryDark, AppColors.primaryLight],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius:
                      BorderRadius.vertical(bottom: Radius.circular(40)),
                ),
                child: Column(
                  children: [
                    // New Enything logo
                    Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(30),
                        child: Image.asset(
                          'logo/Enything_modern.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Enything',
                      style: GoogleFonts.outfit(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      AppVersion.fullVersionString,
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Delivered at the speed of life! ⚡',
                        style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Main Content ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── App Updates / What's New ──────────────────────
                    _sectionTitle("What's New in v${AppVersion.version}", isDark),
                    const SizedBox(height: 16),
                    _buildListTile(
                      title: "Release Highlights (v${AppVersion.version})",
                      icon: Icons.auto_awesome_rounded,
                      isDark: isDark,
                      onTap: () => _showWhatsNewModal(context, isDark),
                    ),
                    const SizedBox(height: 32),

                    // ── Business Identity ─────────────────────────────
                    _sectionTitle('Business Identity', isDark),
                    const SizedBox(height: 16),
                    _identityCard(isDark),

                    const SizedBox(height: 32),

                    // ── Legal ─────────────────────────────────────────
                    _sectionTitle('Legal', isDark),
                    const SizedBox(height: 16),

                    _buildListTile(
                      title: 'Terms of Service',
                      icon: Icons.description_outlined,
                      isDark: isDark,
                      onTap: () =>
                          Navigator.pushNamed(context, AppRoutes.terms),
                    ),
                    const SizedBox(height: 12),
                    _buildListTile(
                      title: 'Privacy Policy',
                      icon: Icons.privacy_tip_outlined,
                      isDark: isDark,
                      onTap: () =>
                          Navigator.pushNamed(context, AppRoutes.privacy),
                    ),
                    const SizedBox(height: 12),
                    _buildListTile(
                      title: 'Refund & Cancellation Policy',
                      icon: Icons.receipt_long_outlined,
                      isDark: isDark,
                      onTap: () =>
                          Navigator.pushNamed(context, AppRoutes.refundPolicy),
                    ),
                    const SizedBox(height: 12),
                    _buildListTile(
                      title: 'Shipping & Delivery Policy',
                      icon: Icons.local_shipping_outlined,
                      isDark: isDark,
                      onTap: () => Navigator.pushNamed(
                          context, AppRoutes.shippingPolicy),
                    ),

                    const SizedBox(height: 32),

                    // ── Contact ───────────────────────────────────────
                    _sectionTitle('Contact Us', isDark),
                    const SizedBox(height: 16),

                    _buildListTile(
                      title: 'Contact Us',
                      icon: Icons.contact_support_rounded,
                      isDark: isDark,
                      onTap: () =>
                          Navigator.pushNamed(context, AppRoutes.contactUs),
                    ),
                    const SizedBox(height: 12),
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
                          Icon(Icons.favorite_rounded,
                              color: Colors.red.shade400, size: 28),
                          const SizedBox(height: 12),
                          Text(
                            'Made with ❤️ in India',
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Colors.white54
                                  : AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '© ${DateTime.now().year} Enything. All Rights Reserved.',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              color:
                                  isDark ? Colors.white38 : AppColors.textLight,
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

  Widget _sectionTitle(String title, bool isDark) {
    return Text(
      title,
      style: GoogleFonts.outfit(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: isDark ? Colors.white : AppColors.textPrimary,
      ),
    );
  }

  Widget _identityCard(bool isDark) {
    final cardBg = isDark ? const Color(0xFF1E1E2E) : Colors.white;
    final labelColor = isDark ? Colors.white54 : AppColors.textSecondary;
    final valueColor = isDark ? Colors.white : AppColors.textPrimary;

    Widget row(IconData icon, String label, String value) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: labelColor,
                          letterSpacing: 0.4)),
                  const SizedBox(height: 2),
                  Text(value,
                      style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: valueColor,
                          height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.black.withValues(alpha: 0.05),
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Column(
        children: [
          row(Icons.business_rounded, 'Business Name', 'Enything'),
          row(Icons.person_rounded, 'Proprietor', 'Muhtaashim Kamran Nazki'),
          row(Icons.verified_rounded, 'Udyam Registration No.',
              'UDYAM-JK-02-0019684'),
          row(Icons.receipt_rounded, 'GST Reg No.', '01CQQPN6775H1ZD'),
          row(Icons.assignment_rounded, 'Trade License No.',
              'JK-ULB-NOC/2026/08565'),
          row(Icons.location_on_rounded, 'Registered Address',
              'Plan Bandipora, Ward No. 2\nBandipora, Jammu & Kashmir — 193502, India'),
          row(Icons.email_rounded, 'Email', 'support@enything.in'),
          Padding(
            padding: const EdgeInsets.only(bottom: 0),
            child: row(Icons.phone_rounded, 'Phone', '+91 7006464241'),
          ),
        ],
      ),
    );
  }

  Widget _buildListTile({
    required String title,
    required IconData icon,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
          ],
          border:
              Border.all(color: isDark ? Colors.white12 : Colors.transparent),
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
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded,
                size: 16, color: isDark ? Colors.white38 : AppColors.textLight),
          ],
        ),
      ),
    );
  }

  void _showWhatsNewModal(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.5,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, scrollCtrl) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.black12,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.rocket_launch_rounded,
                            color: AppColors.primary, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "What's New in v${AppVersion.version}",
                              style: GoogleFonts.outfit(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: isDark ? Colors.white : AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              "Build ${AppVersion.buildNumber} · Latest Release",
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                color: isDark ? Colors.white54 : AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.separated(
                      controller: scrollCtrl,
                      itemCount: AppVersion.whatsNewHighlights.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 14),
                      itemBuilder: (context, idx) {
                        final item = AppVersion.whatsNewHighlights[idx];
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : const Color(0xFFF8F9FA),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item['icon'] ?? '✨', style: const TextStyle(fontSize: 24)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item['title'] ?? '',
                                      style: GoogleFonts.outfit(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: isDark ? Colors.white : AppColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      item['description'] ?? '',
                                      style: GoogleFonts.outfit(
                                        fontSize: 13,
                                        height: 1.4,
                                        color: isDark ? Colors.white70 : AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'Got It!',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
