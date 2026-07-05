import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_colors.dart';
import '../../config/routes.dart';

/// Standalone Contact Us page — required by Razorpay compliance.
/// Contains full business identity and actionable contact methods.
class ContactUsPage extends StatelessWidget {
  const ContactUsPage({super.key});

  static const String _email = 'support@enything.in';
  static const String _phone = '+917006464241';
  static const String _phoneDisplay = '+91 7006464241';
  static const String _address =
      'Plan Bandipora, Ward No. 2\nBandipora, Jammu & Kashmir\n193502, India';
  static const String _businessName = 'Enything';
  static const String _proprietorName = 'Muhtaashim Kamran Nazki';
  static const String _udyam = 'UDYAM-JK-02-0019684';
  static const String _gst = '01CQQPN6775H1ZD';
  static const String _tradeLicense = 'JK-ULB-NOC/2026/08565';

  Future<void> _launchEmail(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: _email,
      queryParameters: {'subject': 'Support Request — Enything App'},
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Please email us at $_email',
                style: GoogleFonts.outfit()),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _launchPhone(BuildContext context) async {
    final uri = Uri(scheme: 'tel', path: _phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Please call us at $_phoneDisplay',
                style: GoogleFonts.outfit()),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard', style: GoogleFonts.outfit()),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF02061A) : AppColors.background;
    final cardBg = isDark ? const Color(0xFF1E1E2E) : Colors.white;
    final textPrimary = isDark ? Colors.white : AppColors.textPrimary;
    final textSecondary =
        isDark ? Colors.white70 : AppColors.textSecondary;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text('Contact Us',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new,
              color: textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Business Identity Card ──────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primaryDark, AppColors.primaryLight],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.asset(
                            'logo/Enything_modern.png',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _businessName,
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            'Sole Proprietorship',
                            style: GoogleFonts.outfit(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _infoRow(
                    Icons.person_rounded,
                    'Proprietor',
                    _proprietorName,
                  ),
                  const SizedBox(height: 10),
                  _infoRow(
                    Icons.verified_rounded,
                    'Udyam No.',
                    _udyam,
                  ),
                  const SizedBox(height: 10),
                  _infoRow(
                    Icons.receipt_rounded,
                    'GST Reg No.',
                    _gst,
                  ),
                  const SizedBox(height: 10),
                  _infoRow(
                    Icons.assignment_rounded,
                    'Trade License No.',
                    _tradeLicense,
                  ),
                  const SizedBox(height: 10),
                  _infoRow(
                    Icons.location_on_rounded,
                    'Registered Address',
                    _address,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // ── Contact Methods ─────────────────────────────────────────
            Text(
              'Get in Touch',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Our support team is available Monday–Saturday, 9 AM – 6 PM IST.',
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),

            _ContactCard(
              id: 'contact_email',
              icon: Icons.email_rounded,
              title: 'Email Support',
              subtitle: _email,
              actionLabel: 'Send Email',
              isDark: isDark,
              cardBg: cardBg,
              onTap: () => _launchEmail(context),
              onLongPress: () => _copyToClipboard(context, _email, 'Email'),
            ),
            const SizedBox(height: 16),

            _ContactCard(
              id: 'contact_phone',
              icon: Icons.phone_rounded,
              title: 'Phone Support',
              subtitle: _phoneDisplay,
              actionLabel: 'Call Now',
              isDark: isDark,
              cardBg: cardBg,
              onTap: () => _launchPhone(context),
              onLongPress: () =>
                  _copyToClipboard(context, _phoneDisplay, 'Phone number'),
            ),
            const SizedBox(height: 16),

            _ContactCard(
              id: 'contact_address',
              icon: Icons.location_on_rounded,
              title: 'Office Address',
              subtitle: _address,
              actionLabel: 'Copy Address',
              isDark: isDark,
              cardBg: cardBg,
              onTap: () => _copyToClipboard(context, _address, 'Address'),
              onLongPress: () =>
                  _copyToClipboard(context, _address, 'Address'),
            ),

            const SizedBox(height: 32),

            // ── Grievance Redressal ─────────────────────────────────────
            Text(
              'Grievance Redressal Mechanism',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'In compliance with the Consumer Protection (E-Commerce) Rules, 2020, and IT Rules, 2021, you can reach out to our Grievance Officer / Nodal Contact Person for any complaints. We will acknowledge your complaint within 48 hours with a ticket number and resolve it within 1 month.',
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.gavel_rounded,
                      color: AppColors.primary, size: 24),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Muhtaashim Kamran Nazki',
                          style: GoogleFonts.outfit(
                            color: AppColors.primary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Grievance Officer & Nodal Contact',
                          style: GoogleFonts.outfit(
                            color: textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$_email  |  $_phoneDisplay',
                          style: GoogleFonts.outfit(
                            color: textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // ── Support Hours ───────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.access_time_rounded,
                      color: AppColors.primary, size: 24),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Support Hours',
                          style: GoogleFonts.outfit(
                            color: AppColors.primary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Monday – Saturday\n9:00 AM – 6:00 PM IST',
                          style: GoogleFonts.outfit(
                            color: textSecondary,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Submit Ticket CTA ───────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pushNamed(
                  context,
                  AppRoutes.faqSupport,
                  arguments: {'initialIndex': 2, 'showTicketSheet': true},
                ),
                icon: const Icon(Icons.support_agent_rounded, size: 20),
                label: Text(
                  'Submit a Support Ticket',
                  style: GoogleFonts.outfit(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
              ),
            ),

            const SizedBox(height: 40),
            Center(
              child: Text(
                '© ${DateTime.now().year} Enything. All Rights Reserved.',
                style: GoogleFonts.outfit(
                  color: textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.white70, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '$label: ',
                  style: GoogleFonts.outfit(
                    color: Colors.white60,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(
                  text: value,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
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

// ── Contact Card Widget ───────────────────────────────────────────────────────
class _ContactCard extends StatelessWidget {
  final String id;
  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final bool isDark;
  final Color cardBg;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ContactCard({
    required this.id,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.isDark,
    required this.cardBg,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        key: ValueKey(id),
        padding: const EdgeInsets.all(18),
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
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: isDark ? Colors.white : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.outfit(
                      color: isDark ? Colors.white60 : AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                actionLabel,
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
