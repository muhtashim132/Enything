import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../utils/responsive_layout.dart';
import '../../utils/time_utils.dart';

class FaqSupportPage extends StatefulWidget {
  final int initialTabIndex;
  final bool openTicketSheet;

  const FaqSupportPage({
    super.key,
    this.initialTabIndex = 0,
    this.openTicketSheet = false,
  });

  @override
  State<FaqSupportPage> createState() => _FaqSupportPageState();
}

class _FaqSupportPageState extends State<FaqSupportPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _myTickets = [];
  bool _isLoadingTickets = true;

  List<Map<String, String>> _faqs = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: widget.initialTabIndex);
    _loadFaqs();
    _loadMyTickets();
    
    if (widget.openTicketSheet) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showSubmitTicketSheet();
      });
    }
  }

  void _loadFaqs() {
    // Role-aware FAQs
    final auth = context.read<AuthProvider>();
    final role = auth.user?.activeSessionRole ?? 'customer';

    if (role == 'customer') {
      _faqs = [
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
          'a': 'Under the Drugs and Cosmetics Act (India), certain medications legally require a valid prescription from a registered medical practitioner before they can be dispensed by our partner pharmacies.'
        },
        {
          'q': 'Can I change my delivery address after placing an order?',
          'a': 'Once an order is confirmed by the seller, the delivery address cannot be changed. Please ensure you have selected the correct address before checkout.'
        },
      ];
    } else if (role == 'seller') {
      _faqs = [
        {
          'q': 'When do I receive my payouts?',
          'a': 'Payouts are processed weekly. Any earnings from Monday to Sunday will be credited to your registered bank account by the following Wednesday.'
        },
        {
          'q': 'How do I add new products?',
          'a': 'Go to your Dashboard, tap "Add New Product" under Quick Actions. Fill in the details, upload an image, and submit.'
        },
        {
          'q': 'Can I reject an order?',
          'a': 'Yes, you can reject an order if an item is out of stock. However, frequent rejections may negatively impact your store rating.'
        },
      ];
    } else if (role == 'delivery_partner') {
      _faqs = [
        {
          'q': 'How are delivery earnings calculated?',
          'a': 'Earnings are based on base pay + distance pay. Wait time at restaurants (over 10 mins) is also compensated.'
        },
        {
          'q': 'What if the customer is unreachable?',
          'a': 'Please try calling them at least 3 times. If they still don\'t respond, contact Support to cancel the order. Do not mark it as delivered.'
        },
        {
          'q': 'How do I update my vehicle details?',
          'a': 'Go to Settings -> Vehicle Information to request a vehicle change. It requires admin approval.'
        },
      ];
    }
  }

  Future<void> _loadMyTickets() async {
    setState(() => _isLoadingTickets = true);
    final auth = context.read<AuthProvider>();
    if (auth.currentUserId == null) {
      setState(() => _isLoadingTickets = false);
      return;
    }

    try {
      final res = await _supabase
          .from('support_tickets')
          .select()
          .eq('user_id', auth.currentUserId!)
          .order('created_at', ascending: false);
      
      if (mounted) {
        setState(() {
          _myTickets = List<Map<String, dynamic>>.from(res);
          _isLoadingTickets = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingTickets = false);
    }
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

  void _showSubmitTicketSheet() {
    final subjectCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    String priority = 'normal';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return StatefulBuilder(builder: (context, setSheetState) {
          return Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Submit Support Ticket', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 24),
                
                TextField(
                  controller: subjectCtrl,
                  decoration: InputDecoration(
                    labelText: 'Subject',
                    hintText: 'Briefly describe your issue',
                    filled: true,
                    fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),
                
                DropdownButtonFormField<String>(
                  initialValue: priority,
                  decoration: InputDecoration(
                    labelText: 'Priority',
                    filled: true,
                    fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'normal', child: Text('Normal - General queries')),
                    DropdownMenuItem(value: 'high', child: Text('High - Payments / Missing items')),
                    DropdownMenuItem(value: 'urgent', child: Text('Urgent - App broken / Emergency')),
                  ],
                  onChanged: (val) {
                    if (val != null) setSheetState(() => priority = val);
                  },
                ),
                const SizedBox(height: 16),
                
                TextField(
                  controller: bodyCtrl,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: 'Message',
                    hintText: 'Please provide details about your issue...',
                    filled: true,
                    fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 24),
                
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (subjectCtrl.text.trim().isEmpty || bodyCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Please fill all fields')));
                        return;
                      }
                      
                      final auth = context.read<AuthProvider>();
                      final user = auth.user;
                      if (user == null) return;
                      
                      try {
                        await _supabase.from('support_tickets').insert({
                          'user_id': user.id,
                          'user_name': user.fullName,
                          'user_role': user.activeSessionRole,
                          'subject': subjectCtrl.text.trim(),
                          'body': bodyCtrl.text.trim(),
                          'priority': priority,
                          'status': 'open',
                        });
                        
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ticket submitted successfully!'), backgroundColor: AppColors.success));
                          _loadMyTickets();
                          _tabController.animateTo(2); // Go to My Tickets tab
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Failed to submit ticket: $e'), backgroundColor: AppColors.danger));
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text('Submit Ticket', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
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
            Tab(text: 'Contact'),
            Tab(text: 'My Tickets'),
          ],
        ),
      ),
      body: MaxWidthContainer(
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildFaqTab(isDark),
            _buildSupportTab(isDark),
            _buildMyTicketsTab(isDark),
          ],
        ),
      ),
      floatingActionButton: _tabController.index == 2 
        ? FloatingActionButton.extended(
            onPressed: _showSubmitTicketSheet,
            backgroundColor: AppColors.primary,
            icon: const Icon(Icons.add_comment_rounded, color: Colors.white),
            label: Text('New Ticket', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w700)),
          )
        : null,
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
            subtitle: 'Plan Bandipora, Ward No. 2\nBandipora, Jammu & Kashmir — 193502, India',
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

  Widget _buildMyTicketsTab(bool isDark) {
    if (_isLoadingTickets) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_myTickets.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.assignment_outlined, size: 64, color: isDark ? Colors.white24 : Colors.grey.shade300),
              const SizedBox(height: 16),
              Text('No Tickets Yet', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('If you have any issues, feel free to submit a support ticket.', 
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(color: AppColors.textSecondary)),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      itemCount: _myTickets.length,
      itemBuilder: (context, index) {
        final ticket = _myTickets[index];
        final status = ticket['status'] as String? ?? 'open';
        
        Color statusColor = AppColors.info;
        if (status == 'resolved' || status == 'closed') statusColor = AppColors.success;
        if (status == 'in_progress') statusColor = AppColors.warning;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: isDark ? 0 : 2,
          shadowColor: Colors.black.withValues(alpha: 0.05),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(status.toUpperCase(), 
                        style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w800, color: statusColor)),
                    ),
                    Text(
                      _formatDate(ticket['created_at']),
                      style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  ticket['subject'] ?? 'No Subject',
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700, color: isDark ? Colors.white : AppColors.textPrimary),
                ),
                const SizedBox(height: 8),
                Text(
                  ticket['body'] ?? '',
                  style: GoogleFonts.outfit(fontSize: 14, color: isDark ? Colors.white70 : AppColors.textSecondary),
                ),
                if (ticket['admin_reply'] != null && ticket['admin_reply'].toString().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Support Reply', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
                        const SizedBox(height: 4),
                        Text(ticket['admin_reply'], style: GoogleFonts.outfit(fontSize: 14, color: isDark ? Colors.white : AppColors.textPrimary)),
                      ],
                    ),
                  ),
                ]
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDate(String? isoString) {
    if (isoString == null) return '';
    try {
      final date = DateTime.parse(isoString).toIST();
      return '${date.day}/${date.month}/${date.year}';
    } catch (_) {
      return '';
    }
  }
}
