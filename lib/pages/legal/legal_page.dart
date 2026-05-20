import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_colors.dart';

class LegalPage extends StatelessWidget {
  final String title;
  final List<LegalSection> sections;

  const LegalPage({
    super.key,
    required this.title,
    required this.sections,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF02061A) : Colors.white,
      appBar: AppBar(
        title: Text(title,
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : AppColors.textPrimary,
            )),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new,
              color: isDark ? Colors.white : AppColors.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Last Updated: May 2026',
              style: GoogleFonts.outfit(
                color: Colors.grey,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 24),
            ...sections.map((section) => _buildSection(section, isDark)),
            const SizedBox(height: 40),
            Center(
              child: Text(
                '© 2026 Enything Technologies. All Rights Reserved.',
                style: GoogleFonts.outfit(
                  color: Colors.grey,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(LegalSection section, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  section.heading,
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            section.content,
            style: GoogleFonts.outfit(
              fontSize: 14,
              height: 1.6,
              color: isDark ? Colors.white70 : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class LegalSection {
  final String heading;
  final String content;

  LegalSection({required this.heading, required this.content});
}
