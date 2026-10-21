// ============================================================================
// quote_response_page.dart — Customer Review, Accept & Offline Payment Status
// ============================================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../theme/app_theme.dart';
import '../../../config/routes.dart';
import '../../../models/quote_request_model.dart';
import '../../../providers/notification_provider.dart';
import '../../../providers/quote_request_provider.dart';

class QuoteResponsePage extends StatefulWidget {
  final String quoteId;
  const QuoteResponsePage({super.key, required this.quoteId});

  @override
  State<QuoteResponsePage> createState() => _QuoteResponsePageState();
}

class _QuoteResponsePageState extends State<QuoteResponsePage> {
  static const String _adminPhone = '+917006464241';
  static const String _adminPhoneDisplay = '+91 7006464241 (Muhtashim)';

  QuoteRequestModel? _quote;
  bool _isLoading = true;
  bool _isResponding = false;

  @override
  void initState() {
    super.initState();
    _fetchQuote();
  }

  Future<void> _fetchQuote() async {
    setState(() => _isLoading = true);
    final q = await context.read<QuoteRequestProvider>().getQuoteById(widget.quoteId);
    if (mounted) {
      setState(() {
        _quote = q;
        _isLoading = false;
      });
    }
  }

  Future<void> _callAdmin() async {
    final uri = Uri.parse('tel:$_adminPhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open dialer for $_adminPhone')),
        );
      }
    }
  }

  Future<void> _acceptQuote() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2138),
        title: Text(
          'Accept Quote of ₹${_quote?.quotedAmount?.toStringAsFixed(0)}?',
          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'After accepting, our team will call you to arrange offline payment (UPI, cash, or bank transfer).',
          style: GoogleFonts.outfit(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.greenAccent.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, Accept'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    final quoteProv = context.read<QuoteRequestProvider>();
    final notifProvider = context.read<NotificationProvider>();

    setState(() => _isResponding = true);
    try {
      await quoteProv.respondToQuote(
            quoteId: widget.quoteId,
            accept: true,
          );
      await _fetchQuote();

      // Dispatch background push to all active admins with customer's phone number!
      try {
        final adminRows = await Supabase.instance.client
            .from('admin_users')
            .select('id')
            .eq('is_active', true);
        final customerName = _quote?.customerName ?? 'Customer';
        final eventName = _quote?.eventName ?? 'Event';
        final amount = _quote?.quotedAmount?.toStringAsFixed(0) ?? '';
        final phone = _quote?.customerPhone ?? '';

        for (final admin in (adminRows as List)) {
          notifProvider.sendBackgroundPush(
            targetUserId: admin['id'] as String,
            title: '✅ Quote Accepted! Call to arrange payment',
            body: '$customerName accepted ₹$amount for $eventName. Call them at 📞 $phone',
            data: {
              'type': 'catering_quote_accepted',
              'role': 'admin',
              'action': 'quote_accepted',
              'quote_id': widget.quoteId,
            },
          );
        }
      } catch (err) {
        debugPrint('Failed to send admin push for quote acceptance: $err');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Quote Accepted! Our manager will call you shortly.'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString().replaceAll('Exception:', '').trim()}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isResponding = false);
    }
  }

  Future<void> _declineQuote() async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2138),
        title: Text(
          'Decline This Quote?',
          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Please tell us why you are declining so we can improve:',
              style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              maxLines: 2,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'e.g. Price too high, date changed...',
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Back', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Decline Quote'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _isResponding = true);
    try {
      await context.read<QuoteRequestProvider>().respondToQuote(
            quoteId: widget.quoteId,
            accept: false,
            rejectionReason: reasonController.text.trim(),
          );
      await _fetchQuote();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Quote declined.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString().replaceAll('Exception:', '').trim()}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isResponding = false);
    }
  }

  Future<void> _cancelRequest() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2138),
        title: const Text('Cancel Quote Request?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to cancel this quote request?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _isResponding = true);
    try {
      await context.read<QuoteRequestProvider>().cancelQuote(quoteId: widget.quoteId);
      await _fetchQuote();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isResponding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = AppTheme.primaryColor;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Quote Details')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_quote == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Quote Details')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 48, color: Colors.orangeAccent),
              const SizedBox(height: 12),
              const Text('Quote request not found'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    final quote = _quote!;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF101018) : const Color(0xFFF7F8FC),
      appBar: AppBar(
        title: Text(
          quote.eventName,
          style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        elevation: 0,
        backgroundColor: isDark ? const Color(0xFF171725) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _fetchQuote,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Status Banner ──
            _buildStatusHeader(quote, primary, isDark),
            const SizedBox(height: 16),

            // ── Direct Call Hotline Card ──
            _buildAdminContactCard(isDark),
            const SizedBox(height: 16),

            // ── Quoted Price Hero Card (if quoted or accepted) ──
            if (quote.quotedAmount != null) ...[
              _buildQuotedPriceCard(quote, primary, isDark),
              const SizedBox(height: 16),
            ],

            // ── Event & Requirements Summary Card ──
            _buildEventSummaryCard(quote, isDark),
            const SizedBox(height: 16),

            // ── Venue & Delivery Card ──
            _buildVenueCard(quote, isDark),
            const SizedBox(height: 24),

            // ── Action Buttons ──
            _buildBottomActions(quote, primary),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusHeader(QuoteRequestModel quote, Color primary, bool isDark) {
    Color bannerColor;
    IconData icon;
    String title;
    String subtitle;

    if (quote.isPendingReview) {
      bannerColor = Colors.amber.shade700;
      icon = Icons.hourglass_top_rounded;
      title = 'Under Review';
      subtitle = 'Muhtashim is reviewing your requirements and will call you with a custom quote.';
    } else if (quote.isQuoted) {
      if (quote.isQuoteExpired) {
        bannerColor = Colors.grey.shade700;
        icon = Icons.timer_off_rounded;
        title = 'Quote Expired';
        subtitle = 'This quote was valid until ${quote.quotedValidUntil != null ? DateFormat('MMM d, h:mm a').format(quote.quotedValidUntil!) : ''}.';
      } else {
        bannerColor = Colors.teal.shade600;
        icon = Icons.check_circle_outline_rounded;
        title = 'Quote Ready — Review & Accept';
        subtitle = 'Your custom price is ready! Review below and accept to confirm.';
      }
    } else if (quote.isAccepted) {
      bannerColor = Colors.green.shade700;
      icon = Icons.thumb_up_alt_rounded;
      title = 'Quote Accepted! ⏳ Awaiting Offline Payment';
      subtitle = 'You accepted this quote. Our team will call you to collect payment offline via UPI, cash, or bank transfer.';
    } else if (quote.isOrderPlaced) {
      bannerColor = Colors.blue.shade700;
      icon = Icons.local_shipping_rounded;
      title = 'Order Placed & Confirmed! 🚀';
      subtitle = 'Offline payment confirmed. Your catering order is in active preparation!';
    } else if (quote.isRejected) {
      bannerColor = Colors.red.shade700;
      icon = Icons.cancel_rounded;
      title = 'Quote Declined';
      subtitle = quote.customerRejectionReason != null
          ? 'Reason: ${quote.customerRejectionReason}'
          : 'You declined this quote.';
    } else {
      bannerColor = Colors.grey.shade700;
      icon = Icons.info_outline_rounded;
      title = quote.statusDisplay;
      subtitle = 'Status: ${quote.quoteStatus}';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bannerColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: bannerColor.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: bannerColor.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: bannerColor, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    color: isDark ? Colors.white70 : Colors.black87,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminContactCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2138) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.phone_in_talk_rounded, color: Colors.amberAccent, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Have Questions or Need Changes?',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
                Text(
                  _adminPhoneDisplay,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amberAccent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: _callAdmin,
            child: const Text('Call', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildQuotedPriceCard(QuoteRequestModel quote, Color primary, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF182238), const Color(0xFF131728)]
              : [const Color(0xFFEFF5FF), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: primary.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'QUOTED PRICE',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: primary,
                ),
              ),
              if (quote.quotedValidUntil != null && !quote.isQuoteExpired)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    'Valid until ${DateFormat('MMM d, h:mm a').format(quote.quotedValidUntil!)}',
                    style: const TextStyle(fontSize: 11, color: Colors.amber, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '₹${quote.quotedAmount?.toStringAsFixed(2)}',
            style: GoogleFonts.poppins(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'All-inclusive final price • Offline direct payment (Zero GST surcharge)',
            style: GoogleFonts.outfit(
              fontSize: 12,
              color: isDark ? Colors.white54 : Colors.black54,
            ),
          ),

          // Line items if available
          if (quote.quotedLineItems.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              'Itemized Estimate:',
              style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...quote.quotedLineItems.map((li) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          li.item,
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ),
                      Text(
                        li.price > 0 ? '₹${li.price.toStringAsFixed(2)}' : 'Included',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: li.price > 0
                              ? (isDark ? Colors.white : Colors.black87)
                              : (isDark ? Colors.greenAccent : Colors.green.shade700),
                        ),
                      ),
                    ],
                  ),
                )),
          ],

          // Admin notes
          if (quote.quotedNotes != null && quote.quotedNotes!.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Manager Notes:',
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    quote.quotedNotes!,
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      color: isDark ? Colors.white.withValues(alpha: 0.87) : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEventSummaryCard(QuoteRequestModel quote, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B1B2A) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_available_rounded, size: 20, color: Colors.blueAccent),
              const SizedBox(width: 8),
              Text(
                'Event & Menu Requirements',
                style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildInfoRow('Event Name', quote.eventName, isDark),
          _buildInfoRow('Event Type', _formatEventType(quote.eventType), isDark),
          _buildInfoRow('Date', DateFormat('EEEE, MMM d, yyyy').format(quote.eventDate), isDark),
          _buildInfoRow('Guest Count', '${quote.estimatedGuestCount} Guests', isDark),
          if (quote.dietaryPreferences != null)
            _buildInfoRow('Dietary Preference', quote.dietaryPreferences!, isDark),
          const SizedBox(height: 10),
          const Divider(),
          const SizedBox(height: 8),
          Text(
            'Requested Menu / Items:',
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white54 : Colors.black54,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              quote.requirementsDescription,
              style: GoogleFonts.outfit(
                fontSize: 13,
                height: 1.4,
                color: isDark ? Colors.white.withValues(alpha: 0.87) : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVenueCard(QuoteRequestModel quote, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B1B2A) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on_rounded, size: 20, color: Colors.redAccent),
              const SizedBox(width: 8),
              Text(
                'Venue & Contact Details',
                style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildInfoRow('Venue', quote.venueAddress ?? 'Not specified', isDark),
          if (quote.preferredDeliveryTime != null)
            _buildInfoRow('Preferred Window', quote.preferredDeliveryTime!, isDark),
          _buildInfoRow('Event Host / Contact', '${quote.contactPersonName} (${quote.contactPersonPhone})', isDark),
          if (quote.secondaryContactPhone != null && quote.secondaryContactPhone!.isNotEmpty)
            _buildInfoRow('Backup Phone', quote.secondaryContactPhone!, isDark),
          if (quote.venueDeliveryNotes != null && quote.venueDeliveryNotes!.isNotEmpty)
            _buildInfoRow('Venue Instructions', quote.venueDeliveryNotes!, isDark),
          if (quote.gatePassInstructions != null && quote.gatePassInstructions!.isNotEmpty)
            _buildInfoRow('Gate Pass', quote.gatePassInstructions!, isDark),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatEventType(String type) {
    const map = {
      'birthday': '🎂 Birthday',
      'wedding': '💍 Wedding',
      'corporate': '💼 Corporate',
      'house_party': '🎉 House Party',
      'religious': '🕊️ Religious',
      'school_event': '🎓 School / College',
      'custom': '✨ Custom Event',
    };
    return map[type] ?? type;
  }

  Widget _buildBottomActions(QuoteRequestModel quote, Color primary) {
    if (_isResponding) {
      return const Center(child: CircularProgressIndicator());
    }

    // 1. Quoted and not expired -> Customer can Accept or Decline
    if (quote.canAccept) {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 4,
              ),
              onPressed: _acceptQuote,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle_rounded, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    'ACCEPT THIS QUOTE (₹${quote.quotedAmount?.toStringAsFixed(0)})',
                    style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _declineQuote,
            child: Text(
              'Decline / Renegotiate',
              style: TextStyle(color: Colors.red.shade400, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      );
    }

    // 2. Customer accepted -> instructions for offline payment
    if (quote.isAccepted) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 36),
            const SizedBox(height: 8),
            Text(
              'Quote Accepted!',
              style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Our catering manager (Muhtashim) will call you shortly at ${quote.customerPhone} to arrange payment via UPI, bank transfer, or cash.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              icon: const Icon(Icons.phone, size: 18),
              label: const Text('Call Muhtashim: +91 7006464241'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amberAccent,
                foregroundColor: Colors.black,
              ),
              onPressed: _callAdmin,
            ),
          ],
        ),
      );
    }

    // 3. Order placed
    if (quote.isOrderPlaced && quote.resultingOrderId != null) {
      return SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          icon: const Icon(Icons.track_changes_rounded),
          label: const Text('TRACK CATERING ORDER'),
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: () {
            Navigator.pushNamed(
              context,
              AppRoutes.bulkOrderTracking,
              arguments: {'order_id': quote.resultingOrderId},
            );
          },
        ),
      );
    }

    // 4. Pending review -> can cancel
    if (quote.isPendingReview) {
      return Center(
        child: TextButton.icon(
          icon: const Icon(Icons.close_rounded, size: 18),
          label: const Text('Cancel Request'),
          style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
          onPressed: _cancelRequest,
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
