import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_colors.dart';

class FaqSupportPage extends StatefulWidget {
  const FaqSupportPage({super.key});

  @override
  State<FaqSupportPage> createState() => _FaqSupportPageState();
}

class _FaqSupportPageState extends State<FaqSupportPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final List<Map<String, String>> _faqs = [
    {
      'q': 'How do I track my order?',
      'a': 'You can track your order in real-time by navigating to the "Orders" tab and clicking on your active order. You will see the delivery partner\'s live location once they pick up your order.'
    },
    {
      'q': 'What is your refund policy?',
      'a': 'If an order is rejected by the seller or cancelled before preparation begins, your refund will be automatically processed within 3-5 business days. For delivered items, please contact support within 24 hours of delivery.'
    },
    {
      'q': 'Why do I need to upload a prescription?',
      'a': 'Under the Drugs and Cosmetics Act (India), certain medications (like Schedule H and H1) legally require a valid prescription from a registered medical practitioner before they can be dispensed by our partner pharmacies.'
    },
    {
      'q': 'Can I change my delivery address after placing an order?',
      'a': 'Once an order is confirmed by the seller, the delivery address cannot be changed. Please ensure you have selected the correct address (Home/Work) before checkout.'
    },
    {
      'q': 'How do I become a seller or delivery partner?',
      'a': 'You can sign out of your current account, go back to the role selection screen, and sign up as a Seller or Delivery Partner using the same phone number.'
    },
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

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
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open email client. Please email support@enything.in directly.')),
        );
      }
    }
  }

  Future<void> _launchPhone() async {
    final Uri phoneUri = Uri(scheme: 'tel', path: '+917006464241');
    if (await canLaunchUrl(phoneUri)) {
      await launchUrl(phoneUri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open phone dialer.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : AppColors.background,
      appBar: AppBar(
        title: Text('Help & Support', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
        backgroundColor: isDark ? const Color(0xFF1E1E2E) : Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w700),
          tabs: const [
            Tab(text: 'FAQ'),
            Tab(text: 'Contact Support'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFaqTab(isDark),
          _buildSupportTab(isDark),
        ],
      ),
    );
  }

  Widget _buildFaqTab(bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _faqs.length,
      itemBuilder: (context, index) {
        final faq = _faqs[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: isDark ? 0 : 2,
          shadowColor: Colors.black.withValues(alpha: 0.05),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              title: Text(
                faq['q']!,
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: isDark ? Colors.white : AppColors.textPrimary,
                ),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Text(
                  faq['a']!,
                  style: GoogleFonts.outfit(
                    color: isDark ? Colors.white70 : AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSupportTab(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.support_agent_rounded, size: 64, color: AppColors.primary),
          ),
          const SizedBox(height: 24),
          Text(
            'How can we help you?',
            style: GoogleFonts.outfit(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Our support team is available from 9 AM to 6 PM, Monday through Saturday.',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 14,
              color: isDark ? Colors.white70 : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 40),
          _buildContactCard(
            icon: Icons.email_outlined,
            title: 'Email Us',
            subtitle: 'support@enything.in',
            onTap: _launchEmail,
            isDark: isDark,
          ),
          const SizedBox(height: 16),
          _buildContactCard(
            icon: Icons.phone_outlined,
            title: 'Call Us',
            subtitle: '+91 7006464241',
            onTap: _launchPhone,
            isDark: isDark,
          ),
          const SizedBox(height: 16),
          _buildContactCard(
            icon: Icons.location_on_outlined,
            title: 'Our Address',
            subtitle: 'Ward No. 2, Bandipora\nJammu and Kashmir — 193502, India',
            onTap: () {},
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildContactCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.05)),
          boxShadow: [
            if (!isDark) BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4)),
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
              child: Icon(icon, color: AppColors.primary),
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
                      fontSize: 16,
                      color: isDark ? Colors.white : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.outfit(
                      color: isDark ? Colors.white70 : AppColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: isDark ? Colors.white54 : Colors.black26),
          ],
        ),
      ),
    );
  }
}
