// ============================================================================
// quote_review_admin_page.dart — Admin Review, Price Quoting & Payment Collection
// ============================================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../theme/admin_theme.dart';
import '../../../models/quote_request_model.dart';
import '../../../providers/quote_request_provider.dart';
import '../../../providers/notification_provider.dart';
import '../../../services/bell_alert_service.dart';
import '../../../config/routes.dart';
import '../../../widgets/admin/catering_order_admin_card.dart';

class QuoteReviewAdminPage extends StatefulWidget {
  const QuoteReviewAdminPage({super.key});

  @override
  State<QuoteReviewAdminPage> createState() => _QuoteReviewAdminPageState();
}

class _QuoteReviewAdminPageState extends State<QuoteReviewAdminPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _activeTab = 'pending'; // 'pending', 'quoted', 'catering', 'done'

  List<Map<String, dynamic>> _cateringOrders = [];
  bool _loadingCatering = false;

  List<Map<String, dynamic>> get _activeCateringOrders => _cateringOrders
      .where((o) =>
          o['status'] != 'delivered' &&
          o['status'] != 'bulk_delivered' &&
          o['status'] != 'cancelled' &&
          o['status'] != 'seller_rejected')
      .toList();

  List<Map<String, dynamic>> get _deliveredCateringOrders => _cateringOrders
      .where((o) =>
          o['status'] == 'delivered' ||
          o['status'] == 'bulk_delivered')
      .toList();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        final tab = switch (_tabController.index) {
          1 => 'quoted',
          2 => 'catering',
          3 => 'done',
          _ => 'pending',
        };
        setState(() => _activeTab = tab);
        if (tab != 'catering') {
          context.read<QuoteRequestProvider>().setAdminTab(tab);
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final args = ModalRoute.of(context)?.settings.arguments;
        if (args is Map && args['initialTab'] is int) {
          final initTab = (args['initialTab'] as int).clamp(0, 3);
          _tabController.index = initTab;
          _activeTab = switch (initTab) {
            1 => 'quoted',
            2 => 'catering',
            3 => 'done',
            _ => 'pending',
          };
        }
        context.read<QuoteRequestProvider>().subscribeToAdminQuotes();
        _refresh();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCateringOrders() async {
    setState(() => _loadingCatering = true);
    try {
      final res = await Supabase.instance.client
          .from('orders')
          .select(
              '*, profiles:customer_id(full_name, phone), shops:shop_id(id, name, address, category), bulk_orders(*)')
          .inFilter('order_type', ['bulk', 'manual_quote'])
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _cateringOrders = List<Map<String, dynamic>>.from(res);
        });
      }
    } catch (e) {
      debugPrint('Error loading catering orders: $e');
    } finally {
      if (mounted) setState(() => _loadingCatering = false);
    }
  }

  Future<void> _refresh() async {
    await Future.wait([
      context.read<QuoteRequestProvider>().loadAdminQuotes(statusFilter: _activeTab),
      _loadCateringOrders(),
    ]);
  }

  Future<void> _callCustomer(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'\s+'), '');
    final uri = Uri.parse('tel:$cleanPhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open dialer for $phone')),
        );
      }
    }
  }

  void _openPriceModal(QuoteRequestModel quote) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161828),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return _SetPriceModalContent(
          quote: quote,
          onSubmit: (amount, notes, validHours, lineItems) async {
            Navigator.pop(sheetContext);
            try {
              await context.read<QuoteRequestProvider>().adminSubmitQuote(
                    quoteId: quote.id,
                    quotedAmount: amount,
                    notes: notes,
                    validHours: validHours,
                    lineItems: lineItems,
                  );
              // Dismiss bell if ringing for this quote
              BellAlertService.instance.removePendingOrder('quote_${quote.id}');
              BellAlertService.instance.removePendingOrder('quote_accepted_${quote.id}');

              // Send background push to customer
              try {
                if (mounted) {
                  context.read<NotificationProvider>().sendBackgroundPush(
                    targetUserId: quote.customerId,
                    title: '🧾 Your Catering Quote is Ready!',
                    body: '₹${amount.toStringAsFixed(0)} quoted for ${quote.eventName}. Tap to review and accept.',
                    data: {
                      'type': 'catering_quote_ready',
                      'quote_id': quote.id,
                    },
                  );
                }
              } catch (_) {}

              _refresh();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Quote of ₹$amount sent to customer!'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error: ${e.toString().replaceAll('Exception:', '').trim()}'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          },
        );
      },
    );
  }

  void _openMarkPaidModal(QuoteRequestModel quote) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161828),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return _MarkPaidModalContent(
          quote: quote,
          onSubmit: (paymentMethod, paymentRef) async {
            Navigator.pop(sheetContext);
            try {
              final res = await context.read<QuoteRequestProvider>().adminMarkPaid(
                    quoteId: quote.id,
                    paymentMethod: paymentMethod,
                    paymentReference: paymentRef,
                  );
              // Dismiss bell if ringing
              BellAlertService.instance.removePendingOrder('quote_${quote.id}');
              BellAlertService.instance.removePendingOrder('quote_accepted_${quote.id}');

              // Send background push to customer confirming payment
              try {
                if (mounted) {
                  context.read<NotificationProvider>().sendBackgroundPush(
                    targetUserId: quote.customerId,
                    title: '💳 Payment Confirmed!',
                    body: 'Payment of ₹${quote.quotedAmount?.toStringAsFixed(0) ?? ''} received for ${quote.eventName}. Your catering order is in preparation!',
                    data: {
                      'type': 'catering_payment_confirmed',
                      'order_id': res['order_id'] ?? '',
                    },
                  );
                }
              } catch (_) {}

              await _refresh();
              if (mounted) {
                _tabController.animateTo(2);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Payment confirmed! Order #${res['order_id']} moved to Active Catering 🎉'),
                    backgroundColor: Colors.green,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            } catch (e) {
              if (mounted) {
                String cleanError = e.toString().replaceAll('Exception:', '').trim();
                if (cleanError.contains('MAINTENANCE_MODE_ACTIVE')) {
                  final match = RegExp(r'MAINTENANCE_MODE_ACTIVE:\s*(.+)', caseSensitive: false).firstMatch(cleanError);
                  cleanError = match?.group(1)?.replaceAll('"', '') ?? 'Platform is temporarily under maintenance.';
                } else if (cleanError.contains('orders_payment_method_check')) {
                  cleanError = 'Invalid payment method selected.';
                } else if (cleanError.contains('QUOTE_NOT_FOUND')) {
                  cleanError = 'Quote not found.';
                } else if (cleanError.contains('INVALID_STATE')) {
                  cleanError = 'Quote is not ready for payment confirmation.';
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error: $cleanError'),
                    backgroundColor: Colors.red,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            }
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<QuoteRequestProvider>();
    final quotes = provider.adminQuotes;
    final isLoading = provider.isLoading;

    return Scaffold(
      backgroundColor: AdminColors.bg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          tooltip: 'Back',
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              Navigator.of(context).pushReplacementNamed(AppRoutes.adminDashboard);
            }
          },
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'Custom Event Quotes 🧾',
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFF141728),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            onPressed: _refresh,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AdminColors.primary,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          labelStyle: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold),
          tabs: [
            _buildTab(
              title: 'Requests',
              icon: Icons.hourglass_top_rounded,
              count: provider.adminPendingCount,
              badgeColor: const Color(0xFFF59E0B),
              badgeTextColor: Colors.black,
            ),
            _buildTab(
              title: 'Quoted',
              icon: Icons.payments_outlined,
              count: provider.adminQuotedCount,
              badgeColor: provider.adminAcceptedWaitingPaymentCount > 0
                  ? const Color(0xFF10B981)
                  : const Color(0xFF3B82F6),
              badgeTextColor: Colors.white,
              isUrgent: provider.adminAcceptedWaitingPaymentCount > 0,
            ),
            _buildTab(
              title: 'Catering 🎉',
              icon: Icons.celebration_rounded,
              count: _activeCateringOrders.length,
              badgeColor: Colors.purpleAccent,
              badgeTextColor: Colors.white,
              isUrgent: _activeCateringOrders.isNotEmpty,
            ),
            _buildTab(
              title: 'Done',
              icon: Icons.check_circle_outline_rounded,
              count: provider.adminDoneCount + _deliveredCateringOrders.length,
              badgeColor: Colors.white24,
              badgeTextColor: Colors.white70,
            ),
          ],
        ),
      ),
      body: _activeTab == 'catering'
          ? _buildCateringOrdersTab()
          : (isLoading
              ? const Center(child: CircularProgressIndicator())
              : quotes.isEmpty &&
                      (_activeTab != 'done' || _deliveredCateringOrders.isEmpty)
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      onRefresh: _refresh,
                      color: AdminColors.primary,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics(),
                        ),
                        itemCount: _activeTab == 'done'
                            ? quotes.length + _deliveredCateringOrders.length
                            : quotes.length,
                        itemBuilder: (context, index) {
                          if (_activeTab == 'done') {
                            if (index < _deliveredCateringOrders.length) {
                              return CateringOrderAdminCard(
                                order: _deliveredCateringOrders[index],
                                onRefresh: _refresh,
                                initiallyExpanded: false,
                              );
                            }
                            final quote =
                                quotes[index - _deliveredCateringOrders.length];
                            return _buildQuoteAdminCard(quote);
                          }
                          final quote = quotes[index];
                          return _buildQuoteAdminCard(quote);
                        },
                      ),
                    )),
    );
  }

  Widget _buildCateringOrdersTab() {
    if (_loadingCatering) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_activeCateringOrders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🎉', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 14),
              Text(
                'No Active Catering Orders',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Paid event orders requiring kitchen assignment, packaging, or dispatch will appear here.',
                style: GoogleFonts.outfit(color: Colors.white54, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AdminColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        itemCount: _activeCateringOrders.length,
        itemBuilder: (context, index) {
          final o = _activeCateringOrders[index];
          return CateringOrderAdminCard(
            order: o,
            onRefresh: _refresh,
            initiallyExpanded: index == 0,
          );
        },
      ),
    );
  }

  Widget _buildTab({
    required String title,
    required IconData icon,
    required int count,
    required Color badgeColor,
    required Color badgeTextColor,
    bool isUrgent = false,
  }) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (count > 0) ...[
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: badgeColor,
                borderRadius: BorderRadius.circular(10),
                boxShadow: isUrgent
                    ? [
                        BoxShadow(
                          color: badgeColor.withValues(alpha: 0.6),
                          blurRadius: 6,
                          spreadRadius: 1,
                        )
                      ]
                    : null,
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: badgeTextColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_rounded, size: 56, color: Colors.white.withValues(alpha: 0.2)),
          const SizedBox(height: 12),
          Text(
            'No quotes found in $_activeTab tab',
            style: GoogleFonts.outfit(color: Colors.white54, fontSize: 14),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AdminColors.primary),
            onPressed: _refresh,
            child: const Text('Refresh'),
          ),
        ],
      ),
    );
  }

  Widget _buildQuoteAdminCard(QuoteRequestModel quote) {
    final isPending = quote.isPendingReview;
    final isAccepted = quote.isAccepted;
    final isQuoted = quote.isQuoted;
    final isPlaced = quote.isOrderPlaced;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1E32),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isAccepted
              ? Colors.greenAccent.withValues(alpha: 0.6)
              : isPending
                  ? Colors.amberAccent.withValues(alpha: 0.4)
                  : Colors.white12,
          width: isAccepted ? 1.8 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Event Title + Event Type Badge + Status Chip
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            quote.eventName,
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildEventTypeBadge(quote.eventType),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${quote.estimatedGuestCount} Guests • ${DateFormat('EEE, MMM d, yyyy').format(quote.eventDate)}',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),
              _buildStatusBadge(quote),
            ],
          ),

          // Dietary Preferences chip
          if (quote.dietaryPreferences != null && quote.dietaryPreferences!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.restaurant_rounded, size: 14, color: Colors.greenAccent),
                  const SizedBox(width: 6),
                  Text(
                    quote.dietaryPreferences!,
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: Colors.greenAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),
          const Divider(color: Colors.white10),
          const SizedBox(height: 8),

          // Customer Phone Call Card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.person_pin_rounded, color: Colors.amberAccent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${quote.customerName ?? 'Customer'} • ${quote.customerPhone}',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.call, size: 14),
                  label: const Text('Call Customer'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amberAccent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () => _callCustomer(quote.customerPhone),
                ),
              ],
            ),
          ),

          // On-Site Coordinator / Event Host Card
          if (quote.contactPersonName.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.teal.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.badge_rounded, color: Colors.tealAccent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Event Host / On-Site Contact',
                          style: GoogleFonts.outfit(
                            fontSize: 10,
                            color: Colors.white38,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${quote.contactPersonName} • ${quote.contactPersonPhone}',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (quote.secondaryContactPhone != null && quote.secondaryContactPhone!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'Backup: ${quote.secondaryContactPhone}',
                              style: GoogleFonts.outfit(fontSize: 11, color: Colors.white54),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (quote.contactPersonPhone.isNotEmpty &&
                      quote.contactPersonPhone != quote.customerPhone)
                    IconButton(
                      icon: const Icon(Icons.call_rounded, size: 18, color: Colors.tealAccent),
                      tooltip: 'Call Coordinator',
                      onPressed: () => _callCustomer(quote.contactPersonPhone),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
                ],
              ),
            ),
          ],

          // Gate Pass Instructions
          if (quote.gatePassInstructions != null && quote.gatePassInstructions!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.security_rounded, size: 15, color: Colors.orangeAccent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Gate Pass: ${quote.gatePassInstructions}',
                    style: GoogleFonts.outfit(fontSize: 12, color: Colors.orangeAccent),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 12),

          // Requirements Text
          Text(
            'Requirements Description:',
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.white54,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              quote.requirementsDescription,
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.87),
                height: 1.35,
              ),
            ),
          ),

          // Venue & Preferred time
          if (quote.venueAddress != null) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on_rounded, size: 16, color: Colors.redAccent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${quote.venueAddress} ${quote.preferredDeliveryTime != null ? '• (${quote.preferredDeliveryTime})' : ''}',
                    style: GoogleFonts.outfit(fontSize: 12, color: Colors.white70),
                  ),
                ),
              ],
            ),
          ],

          // Venue Delivery Notes
          if (quote.venueDeliveryNotes != null && quote.venueDeliveryNotes!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(width: 22),
                Expanded(
                  child: Text(
                    '📋 ${quote.venueDeliveryNotes}',
                    style: GoogleFonts.outfit(fontSize: 11, color: Colors.white54, fontStyle: FontStyle.italic),
                  ),
                ),
              ],
            ),
          ],

          // Financial summary if already quoted
          if (quote.quotedAmount != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AdminColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AdminColors.primary.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Quoted Amount:',
                        style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13),
                      ),
                      Text(
                        '₹${quote.quotedAmount?.toStringAsFixed(2)}',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  if (quote.quotedLineItems.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    const Divider(color: Colors.white12, height: 1),
                    const SizedBox(height: 6),
                    ...quote.quotedLineItems.map((li) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '• ${li.item}',
                                style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12),
                              ),
                              Text(
                                li.price > 0 ? '₹${li.price.toStringAsFixed(0)}' : 'Included',
                                style: GoogleFonts.outfit(
                                  color: li.price > 0 ? Colors.white : Colors.greenAccent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        )),
                  ],
                ],
              ),
            ),
          ],

          // Resulting Order Id if placed
          if (isPlaced && quote.resultingOrderId != null) ...[
            const SizedBox(height: 8),
            Text(
              'Linked Order ID: ${quote.resultingOrderId}',
              style: GoogleFonts.outfit(color: Colors.greenAccent, fontSize: 11),
            ),
          ],

          const SizedBox(height: 14),

          // Action Buttons Row
          Row(
            children: [
              if (isPending || isQuoted) ...[
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.request_quote_rounded, size: 18),
                    label: Text(isQuoted ? 'Re-Price Quote' : 'Set Price & Send'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdminColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _openPriceModal(quote),
                  ),
                ),
              ],
              if (isAccepted) ...[
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check_circle_rounded, size: 18),
                    label: const Text('Confirm Payment & Create Order'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.greenAccent.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _openMarkPaidModal(quote),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(QuoteRequestModel quote) {
    Color color;
    String text;

    if (quote.isPendingReview) {
      color = Colors.amber;
      text = 'Pending Review';
    } else if (quote.isQuoted) {
      color = quote.isQuoteExpired ? Colors.grey : Colors.blueAccent;
      text = quote.isQuoteExpired ? 'Expired' : 'Quoted';
    } else if (quote.isAccepted) {
      color = Colors.greenAccent;
      text = 'Customer Accepted';
    } else if (quote.isOrderPlaced) {
      color = Colors.green;
      text = 'Order Placed';
    } else if (quote.isRejected) {
      color = Colors.redAccent;
      text = 'Declined';
    } else {
      color = Colors.grey;
      text = quote.quoteStatus;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildEventTypeBadge(String eventType) {
    final Map<String, (String, Color)> typeMap = {
      'birthday': ('🎂 Birthday', const Color(0xFFE91E63)),
      'wedding': ('💍 Wedding', const Color(0xFFAB47BC)),
      'corporate': ('💼 Corporate', const Color(0xFF42A5F5)),
      'house_party': ('🎉 House Party', const Color(0xFFFF7043)),
      'religious': ('🕊️ Religious', const Color(0xFF26A69A)),
      'school_event': ('🎓 School', const Color(0xFF66BB6A)),
      'custom': ('✨ Custom', const Color(0xFFBDBDBD)),
    };
    final entry = typeMap[eventType] ?? ('✨ $eventType', const Color(0xFFBDBDBD));
    final label = entry.$1;
    final color = entry.$2;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// ─── Modal for Admin to Set Price ─────────────────────────────────────────────
class _SetPriceModalContent extends StatefulWidget {
  final QuoteRequestModel quote;
  final Function(double amount, String? notes, int validHours, List<Map<String, dynamic>> lineItems) onSubmit;

  const _SetPriceModalContent({
    required this.quote,
    required this.onSubmit,
  });

  @override
  State<_SetPriceModalContent> createState() => _SetPriceModalContentState();
}

class _LineItemEntry {
  final TextEditingController nameCtrl;
  final TextEditingController priceCtrl;

  _LineItemEntry({String name = '', String price = ''})
      : nameCtrl = TextEditingController(text: name),
        priceCtrl = TextEditingController(text: price);

  void dispose() {
    nameCtrl.dispose();
    priceCtrl.dispose();
  }
}

class _SetPriceModalContentState extends State<_SetPriceModalContent> {
  final _amountController = TextEditingController();
  final _notesController = TextEditingController(text: 'Price includes delivery and warm service packaging.');
  int _validHours = 48;
  final List<_LineItemEntry> _lineItemEntries = [];

  @override
  void initState() {
    super.initState();
    if (widget.quote.quotedAmount != null) {
      _amountController.text = widget.quote.quotedAmount!.toStringAsFixed(0);
    }
    if (widget.quote.quotedLineItems.isNotEmpty) {
      for (final li in widget.quote.quotedLineItems) {
        _lineItemEntries.add(_LineItemEntry(
          name: li.item,
          price: li.price > 0 ? li.price.toStringAsFixed(0) : '',
        ));
      }
    } else {
      // Start with 1 entry ready for convenience
      _lineItemEntries.add(_LineItemEntry());
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    for (final e in _lineItemEntries) {
      e.dispose();
    }
    super.dispose();
  }

  void _addNewLineItem() {
    setState(() {
      _lineItemEntries.add(_LineItemEntry());
    });
  }

  void _removeLineItem(int index) {
    if (_lineItemEntries.length <= 1) {
      // If only one row, just clear its text fields
      _lineItemEntries[0].nameCtrl.clear();
      _lineItemEntries[0].priceCtrl.clear();
      setState(() {});
    } else {
      final removed = _lineItemEntries.removeAt(index);
      removed.dispose();
      setState(() {});
    }
  }

  double get _itemsTotalSum {
    double sum = 0.0;
    for (final e in _lineItemEntries) {
      final p = double.tryParse(e.priceCtrl.text.trim()) ?? 0.0;
      sum += p;
    }
    return sum;
  }

  List<Map<String, dynamic>> _collectLineItems() {
    final list = <Map<String, dynamic>>[];
    for (final entry in _lineItemEntries) {
      final name = entry.nameCtrl.text.trim();
      final price = double.tryParse(entry.priceCtrl.text.trim()) ?? 0.0;
      if (name.isNotEmpty) {
        list.add({'item': name, 'price': price});
      }
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Price Quote for Customer 💰',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.quote.eventName} • ${widget.quote.customerName ?? 'Customer'} (${widget.quote.customerPhone})',
              style: GoogleFonts.outfit(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 16),

            // Total Quoted Amount (Primary Field)
            Text(
              'Total Flat Quoted Amount (₹) *',
              style: GoogleFonts.outfit(color: Colors.amberAccent, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: GoogleFonts.poppins(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                prefixText: '₹ ',
                prefixStyle: const TextStyle(color: Colors.white, fontSize: 24),
                hintText: '18500',
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),

            // Optional Itemized Line Items Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Itemized Line Items (Optional):',
                  style: GoogleFonts.outfit(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextButton.icon(
                  onPressed: _addNewLineItem,
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 16, color: Colors.greenAccent),
                  label: const Text(
                    '+ Add Item',
                    style: TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Dynamic editable rows
            ..._lineItemEntries.asMap().entries.map((entry) {
              final idx = entry.key;
              final item = entry.value;
              final isLast = idx == _lineItemEntries.length - 1;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      flex: 5,
                      child: TextField(
                        controller: item.nameCtrl,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'e.g. Biryani x50',
                          hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.04),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: item.priceCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: '₹ Amount',
                          hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.04),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    if (_lineItemEntries.length > 1)
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline_rounded, color: Colors.redAccent, size: 20),
                        tooltip: 'Remove Item',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        onPressed: () => _removeLineItem(idx),
                      ),
                    if (isLast)
                      IconButton(
                        icon: const Icon(Icons.add_circle_rounded, color: Colors.greenAccent, size: 22),
                        tooltip: 'Add Another Item',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        onPressed: _addNewLineItem,
                      ),
                  ],
                ),
              );
            }),

            // Subtotal chip if amounts are entered
            if (_itemsTotalSum > 0) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Items Subtotal: ₹${_itemsTotalSum.toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        setState(() {
                          _amountController.text = _itemsTotalSum.toStringAsFixed(0);
                        });
                      },
                      child: Text(
                        'Copy to Flat Total ➔',
                        style: TextStyle(
                          color: Colors.amberAccent.shade200,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),

            // Notes to customer
            Text(
              'Notes / Conditions for Customer:',
              style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _notesController,
              maxLines: 2,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'e.g. Includes delivery. Direct UPI or cash payment.',
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 16),

            // Quote Validity Hours
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Quote Valid For:',
                  style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13),
                ),
                DropdownButton<int>(
                  value: _validHours,
                  dropdownColor: const Color(0xFF1E2138),
                  style: const TextStyle(color: Colors.white),
                  items: const [
                    DropdownMenuItem(value: 24, child: Text('24 Hours')),
                    DropdownMenuItem(value: 48, child: Text('48 Hours (2 Days)')),
                    DropdownMenuItem(value: 72, child: Text('72 Hours (3 Days)')),
                    DropdownMenuItem(value: 168, child: Text('7 Days')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _validHours = val);
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  final amount = double.tryParse(_amountController.text.trim());
                  if (amount == null || amount <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please enter a valid quoted amount')),
                    );
                    return;
                  }
                  final lineItems = _collectLineItems();
                  widget.onSubmit(amount, _notesController.text.trim(), _validHours, lineItems);
                },
                child: Text(
                  'SEND QUOTE TO CUSTOMER 📤',
                  style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Modal for Admin to Confirm Offline Payment ────────────────────────────────
class _MarkPaidModalContent extends StatefulWidget {
  final QuoteRequestModel quote;
  final Function(String paymentMethod, String? paymentReference) onSubmit;

  const _MarkPaidModalContent({
    required this.quote,
    required this.onSubmit,
  });

  @override
  State<_MarkPaidModalContent> createState() => _MarkPaidModalContentState();
}

class _MarkPaidModalContentState extends State<_MarkPaidModalContent> {
  String _paymentMethod = 'upi';
  final _refController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _refController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Confirm Offline Payment 💳',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.greenAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Amount to Confirm:',
                  style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13),
                ),
                Text(
                  '₹${widget.quote.quotedAmount?.toStringAsFixed(2)}',
                  style: GoogleFonts.poppins(
                    color: Colors.greenAccent,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Payment Method Used:',
            style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildMethodChip('upi', 'UPI (GPay/PhonePe)'),
              const SizedBox(width: 8),
              _buildMethodChip('bank_transfer', 'Bank Transfer'),
              const SizedBox(width: 8),
              _buildMethodChip('cash', 'Cash'),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'UPI Txn ID / Reference (Optional):',
            style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _refController,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'e.g. 405812948291 or Cheque #',
              hintStyle: const TextStyle(color: Colors.white30),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.amberAccent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This creates the catering order in the system with payment marked captured, and notifies the customer.',
                    style: GoogleFonts.outfit(color: Colors.amberAccent, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _isSubmitting
                  ? null
                  : () {
                      setState(() => _isSubmitting = true);
                      widget.onSubmit(_paymentMethod, _refController.text.trim());
                    },
              child: _isSubmitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'CONFIRM PAYMENT RECEIVED ✅',
                      style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMethodChip(String method, String label) {
    final isSel = _paymentMethod == method;
    return ChoiceChip(
      label: Text(label),
      selected: isSel,
      selectedColor: AdminColors.primary.withValues(alpha: 0.3),
      backgroundColor: Colors.white.withValues(alpha: 0.06),
      labelStyle: TextStyle(
        color: isSel ? Colors.white : Colors.white60,
        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      side: BorderSide(color: isSel ? AdminColors.primary : Colors.transparent),
      onSelected: (val) {
        if (val) setState(() => _paymentMethod = method);
      },
    );
  }
}
