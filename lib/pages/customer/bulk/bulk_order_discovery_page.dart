// ============================================================================
// bulk_order_discovery_page.dart — Bulk & Event Catering Hub (Custom Menu Quotes)
// ============================================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../theme/app_theme.dart';
import '../../../config/routes.dart';
import '../../../models/quote_request_model.dart';
import '../../../providers/bulk_order_provider.dart';
import '../../../providers/quote_request_provider.dart';

class BulkOrderDiscoveryPage extends StatefulWidget {
  const BulkOrderDiscoveryPage({super.key});

  @override
  State<BulkOrderDiscoveryPage> createState() => _BulkOrderDiscoveryPageState();
}

class _BulkOrderDiscoveryPageState extends State<BulkOrderDiscoveryPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<QuoteRequestProvider>().loadCustomerQuotes();
      context.read<QuoteRequestProvider>().subscribeToCustomerQuotes();
      context.read<BulkOrderProvider>().loadCustomerBulkOrders();
    });
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      context.read<QuoteRequestProvider>().loadCustomerQuotes(),
      context.read<BulkOrderProvider>().loadCustomerBulkOrders(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = AppTheme.primaryColor;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          'Bulk & Event Catering 🎉',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        elevation: 0,
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        actions: [
          Consumer<QuoteRequestProvider>(
            builder: (context, qp, _) {
              final activeCount = qp.customerQuotes.where((q) => !q.isTerminal).length;
              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.receipt_long_rounded),
                    tooltip: 'My Event Quotes',
                    onPressed: () => _showMyQuotesSheet(context, qp.customerQuotes),
                  ),
                  if (activeCount > 0)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.amber,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '$activeCount',
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'Track Catering Orders',
            onPressed: () {
              Navigator.pushNamed(context, AppRoutes.bulkOrderTracking);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        color: primary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.only(bottom: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Hero Banner
              _buildHeroBanner(isDark, primary),

              // Custom Event Quote Centerpiece Card
              _buildCustomQuoteCard(isDark, primary),

              // Track Live Orders Quick Card
              _buildTrackOrdersCard(isDark, primary),

              // Active Customer Quotes Section
              _buildActiveQuotesSection(isDark, primary),

              // How It Works Stepper
              _buildHowItWorksSection(isDark, primary),

              // Catering Guarantee Badges
              _buildGuaranteesCard(isDark, primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroBanner(bool isDark, Color primary) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF2C1E3A), const Color(0xFF1E2840)]
              : [const Color(0xFFFFF0F5), const Color(0xFFE8F0FE)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: primary.withValues(alpha: 0.15),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('✨', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 4),
                    Text(
                      'EVENT & BULK CATERING',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: primary,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              const Text('🍕 🍔 🍰 🍛', style: TextStyle(fontSize: 20)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Order Food in Bulk for Any Occasion',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Weddings, birthdays, corporate lunches, or parties. Get transparent negotiated pricing, zero GST surcharges, and dedicated fleet delivery.',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.grey[300] : Colors.grey[700],
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildFeaturePill('💰 Negotiated Pricing', isDark),
              _buildFeaturePill('🛡️ Zero GST / Surcharges', isDark),
              _buildFeaturePill('⏰ Advance Slot Scheduling', isDark),
              _buildFeaturePill('🚚 Dedicated Fleet Delivery', isDark),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturePill(String label, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isDark ? Colors.black26 : Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black12,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white70 : Colors.black87,
        ),
      ),
    );
  }

  Widget _buildCustomQuoteCard(bool isDark, Color primary) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E2138), const Color(0xFF141728)]
              : [const Color(0xFFFFF7ED), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.amber.withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withValues(alpha: 0.1),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.edit_note_rounded, color: Colors.amber, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Need a Custom Menu? 📝',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    Text(
                      'Free-text quote with zero GST surcharge',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Write down your catering requirements freely. Our team will review, calculate a negotiated offline price, and call you directly within 10 minutes.',
            style: GoogleFonts.outfit(
              fontSize: 13.5,
              color: isDark ? Colors.white70 : Colors.black87,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.draw_rounded, size: 16),
                  label: const Text('Request Quote ✍️'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pushNamed(context, AppRoutes.manualQuoteRequest);
                  },
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.phone, size: 16, color: Colors.amber),
                label: Text(
                  'Call Us',
                  style: GoogleFonts.outfit(
                    color: isDark ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.amber.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () async {
                  final uri = Uri.parse('tel:+917006464241');
                  if (await canLaunchUrl(uri)) await launchUrl(uri);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTrackOrdersCard(bool isDark, Color primary) {
    return Consumer<BulkOrderProvider>(
      builder: (context, bulkProv, _) {
        final hasActiveOrders = bulkProv.customerBulkOrders.any((o) =>
            o.status != 'delivered' &&
            o.status != 'cancelled' &&
            o.status != 'seller_rejected');

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1B2236) : const Color(0xFFF0F4FF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: hasActiveOrders
                  ? Colors.blueAccent.withValues(alpha: 0.4)
                  : (isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06)),
              width: 1.5,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () {
                Navigator.pushNamed(context, AppRoutes.bulkOrderTracking);
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.track_changes_rounded,
                          color: Colors.blueAccent, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Track Catering Orders',
                                style: GoogleFonts.outfit(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              if (hasActiveOrders) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'ACTIVE',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Live preparation progress & dedicated fleet delivery',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded,
                        size: 14, color: Colors.blueAccent),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildActiveQuotesSection(bool isDark, Color primary) {
    return Consumer<QuoteRequestProvider>(
      builder: (context, qp, _) {
        final activeQuotes = qp.customerQuotes.where((q) => !q.isTerminal).toList();
        if (activeQuotes.isEmpty) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Your Active Quotes (${activeQuotes.length})',
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  TextButton(
                    onPressed: () => _showMyQuotesSheet(context, qp.customerQuotes),
                    child: const Text('View All', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
              ...activeQuotes.map((q) {
                return InkWell(
                  onTap: () {
                    Navigator.pushNamed(
                      context,
                      AppRoutes.quoteResponse,
                      arguments: {'quote_id': q.id},
                    );
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1B1B2A) : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: q.isQuoted
                            ? Colors.tealAccent.withValues(alpha: 0.5)
                            : (q.isOrderPlaced
                                ? Colors.greenAccent.withValues(alpha: 0.5)
                                : (isDark ? Colors.white12 : Colors.black12)),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: (q.isOrderPlaced
                                    ? Colors.green
                                    : (q.isQuoted ? Colors.teal : Colors.amber))
                                .withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            q.isOrderPlaced
                                ? Icons.check_circle_rounded
                                : (q.isQuoted
                                    ? Icons.receipt_rounded
                                    : Icons.hourglass_top_rounded),
                            size: 18,
                            color: q.isOrderPlaced
                                ? Colors.greenAccent
                                : (q.isQuoted
                                    ? Colors.tealAccent
                                    : Colors.amberAccent),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                q.eventName,
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              Text(
                                '${q.statusDisplay} • ${q.quotedAmount != null ? '₹${q.quotedAmount!.toStringAsFixed(0)}' : 'Under Review'}',
                                style: GoogleFonts.outfit(
                                  fontSize: 11,
                                  color: q.isOrderPlaced
                                      ? Colors.green
                                      : (q.isQuoted
                                          ? Colors.tealAccent
                                          : (isDark
                                              ? Colors.white60
                                              : Colors.black54)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded,
                            size: 14, color: Colors.white38),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHowItWorksSection(bool isDark, Color primary) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How Event Catering Works 📋',
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 14),
          _buildStepRow(
            '1',
            'Submit Custom Menu Request',
            'List your desired dishes, guest count, and event date in free text.',
            isDark,
            primary,
          ),
          const SizedBox(height: 12),
          _buildStepRow(
            '2',
            'Direct Call & Negotiated Pricing',
            'Our manager reviews the prep capacity and quotes an all-inclusive price within 10 minutes.',
            isDark,
            primary,
          ),
          const SizedBox(height: 12),
          _buildStepRow(
            '3',
            'Payment Verification',
            'Complete payment online via UPI or bank transfer with zero platform markups.',
            isDark,
            primary,
          ),
          const SizedBox(height: 12),
          _buildStepRow(
            '4',
            'Kitchen Preparation & Fleet Delivery',
            'Dedicated food preparation in verified kitchens with scheduled fleet handover.',
            isDark,
            primary,
          ),
        ],
      ),
    );
  }

  Widget _buildStepRow(String number, String title, String description,
      bool isDark, Color primary) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: TextStyle(
                color: primary,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  fontSize: 11.5,
                  color: isDark ? Colors.white60 : Colors.grey[600],
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGuaranteesCard(bool isDark, Color primary) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF191924) : const Color(0xFFF6F8FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.blue.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildGuaranteeBadge('🛡️ 100% Verified', 'Partner Kitchens', isDark),
          Container(height: 30, width: 1, color: isDark ? Colors.white12 : Colors.black12),
          _buildGuaranteeBadge('⏰ On-Time Slot', 'Guaranteed Arrival', isDark),
          Container(height: 30, width: 1, color: isDark ? Colors.white12 : Colors.black12),
          _buildGuaranteeBadge('📞 Direct Help', 'Manager Support', isDark),
        ],
      ),
    );
  }

  Widget _buildGuaranteeBadge(String top, String bottom, bool isDark) {
    return Column(
      children: [
        Text(
          top,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 11.5,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          bottom,
          style: TextStyle(
            fontSize: 10,
            color: isDark ? Colors.white54 : Colors.grey[600],
          ),
        ),
      ],
    );
  }

  void _showMyQuotesSheet(BuildContext context, List<QuoteRequestModel> quotes) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF161828) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.85,
          minChildSize: 0.35,
          expand: false,
          builder: (_, scrollCtrl) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'My Event Quotes 🧾',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (quotes.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Column(
                          children: [
                            const Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey),
                            const SizedBox(height: 10),
                            const Text('No quotes requested yet'),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () {
                                Navigator.pop(ctx);
                                Navigator.pushNamed(context, AppRoutes.manualQuoteRequest);
                              },
                              child: const Text('Request a Quote'),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        controller: scrollCtrl,
                        itemCount: quotes.length,
                        itemBuilder: (context, idx) {
                          final q = quotes[idx];
                          return Card(
                            color: isDark ? const Color(0xFF1F2238) : const Color(0xFFF7F8FC),
                            margin: const EdgeInsets.only(bottom: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              title: Text(
                                q.eventName,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                '${q.statusDisplay} • ${DateFormat('MMM d, yyyy').format(q.eventDate)}',
                              ),
                              trailing: q.quotedAmount != null
                                  ? Text(
                                      '₹${q.quotedAmount!.toStringAsFixed(0)}',
                                      style: GoogleFonts.poppins(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.greenAccent,
                                      ),
                                    )
                                  : const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                              onTap: () {
                                Navigator.pop(ctx);
                                Navigator.pushNamed(
                                  context,
                                  AppRoutes.quoteResponse,
                                  arguments: {'quote_id': q.id},
                                );
                              },
                            ),
                          );
                        },
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
