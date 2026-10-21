// ============================================================================
// catering_order_admin_card.dart — Dedicated Catering & Bulk Order Operations Card
// Pure Direct P2P Model: Customer <-> Admin (No forced kitchen picker, No micro-batches, No gig riders)
// ============================================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:provider/provider.dart';
import '../../theme/admin_theme.dart';
import '../../utils/time_utils.dart';
import '../../providers/notification_provider.dart';

Map<String, dynamic>? _extractMap(dynamic val) {
  if (val == null) return null;
  if (val is Map) return Map<String, dynamic>.from(val);
  if (val is List && val.isNotEmpty) {
    final first = val.first;
    if (first is Map) return Map<String, dynamic>.from(first);
  }
  return null;
}

class CateringOrderAdminCard extends StatefulWidget {
  final Map<String, dynamic> order;
  final VoidCallback onRefresh;
  final bool initiallyExpanded;

  const CateringOrderAdminCard({
    super.key,
    required this.order,
    required this.onRefresh,
    this.initiallyExpanded = false,
  });

  @override
  State<CateringOrderAdminCard> createState() => _CateringOrderAdminCardState();
}

class _CateringOrderAdminCardState extends State<CateringOrderAdminCard> {
  SupabaseClient get _db => Supabase.instance.client;
  late bool _expanded;
  bool _actioning = false;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  Future<void> _callPhone(String? phone) async {
    if (phone == null || phone.trim().isEmpty) return;
    final clean = phone.replaceAll(RegExp(r'\s+'), '');
    final uri = Uri.parse('tel:$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open phone dialer for $phone')),
        );
      }
    }
  }

  int _cateringTimelineStep(String status) {
    switch (status) {
      case 'bulk_pending':
        return 0; // Paid
      case 'bulk_confirmed':
      case 'bulk_preparing':
        return 1; // Kitchen Appointed
      case 'bulk_ready':
        return 2; // Food Ready
      case 'bulk_dispatched':
      case 'out_for_delivery':
      case 'picked_up':
        return 3; // Dispatched
      case 'delivered':
      case 'bulk_delivered':
        return 4; // Delivered
      default:
        return 0;
    }
  }

  (Color, String) _statusStyle(String status, bool isPaid) {
    switch (status) {
      case 'bulk_pending':
        return (
          isPaid ? Colors.purpleAccent : AdminColors.warning,
          isPaid ? 'Appoint Kitchen' : 'Unpaid'
        );
      case 'bulk_confirmed':
      case 'bulk_preparing':
        return (Colors.blueAccent, 'Kitchen In Prep');
      case 'bulk_ready':
        return (Colors.purpleAccent, 'Food Ready 🍱');
      case 'bulk_dispatched':
      case 'out_for_delivery':
        return (Colors.tealAccent, 'Out for Delivery 🚗');
      case 'delivered':
      case 'bulk_delivered':
        return (Colors.greenAccent, 'Delivered 🎉');
      case 'cancelled':
      case 'seller_rejected':
        return (Colors.redAccent, 'Cancelled');
      default:
        return (Colors.white54, status);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final status = (o['status'] ?? 'placed').toString();
    final profile = _extractMap(o['profiles']);
    final shop = _extractMap(o['shops']);
    final bulkMeta = _extractMap(o['bulk_orders']);
    final isPaid = (o['payment_status'] ?? '').toString() == 'captured';
    final amount = (o['grand_total_collected'] as num?)?.toDouble() ??
        (o['total_amount'] as num?)?.toDouble() ??
        0.0;
    final time = o['created_at'] != null
        ? DateFormat('dd MMM, hh:mm a')
            .format(DateTime.parse(o['created_at'].toString()).toIST())
        : '';

    final (statusColor, statusLabel) = _statusStyle(status, isPaid);
    final timelineStep = _cateringTimelineStep(status);
    final isManualQuote = o['order_type'] == 'manual_quote';

    final kitchenDisplay = shop?['name'] ??
        (status == 'bulk_pending'
            ? 'No Kitchen Appointed'
            : 'Kitchen Appointed 👨‍🍳');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF16192E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.purpleAccent.withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.purple.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Header Row ──────────────────────────────────────────────────────
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.celebration_rounded,
                      color: statusColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                '#${o['id'].toString().substring(0, 8).toUpperCase()}',
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.purple.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: Colors.purple.withValues(alpha: 0.5)),
                              ),
                              child: Text(
                                isManualQuote ? '🍽️ EVENT' : '🎉 BULK',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.purpleAccent,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${profile?['full_name'] ?? 'Customer'} • $kitchenDisplay',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          time,
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            color: Colors.white38,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '₹${amount.toStringAsFixed(0)}',
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.greenAccent,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: statusColor.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          statusLabel,
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: Colors.white54,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),

          // ── Expanded Console ────────────────────────────────────────────────
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 6),
                  _buildTimeline(timelineStep),
                  const SizedBox(height: 14),
                  _buildCateringConsole(o, bulkMeta, status, shop, profile),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTimeline(int currentStep) {
    const steps = [
      'Paid',
      'Kitchen In Prep',
      'Food Ready',
      'Dispatched',
      'Delivered',
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: List.generate(steps.length * 2 - 1, (index) {
          if (index.isOdd) {
            final prevStep = index ~/ 2;
            final isDone = prevStep < currentStep;
            return Expanded(
              child: Container(
                height: 2,
                color: isDone ? Colors.purpleAccent : Colors.white12,
              ),
            );
          }
          final stepIndex = index ~/ 2;
          final isDone = stepIndex <= currentStep;
          final isCurrent = stepIndex == currentStep;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCurrent
                      ? Colors.purpleAccent
                      : isDone
                          ? Colors.purpleAccent.withValues(alpha: 0.5)
                          : Colors.white12,
                  border: isCurrent
                      ? Border.all(color: Colors.white, width: 2)
                      : null,
                ),
                child: isDone
                    ? const Icon(Icons.check, size: 12, color: Colors.white)
                    : null,
              ),
              const SizedBox(height: 4),
              Text(
                steps[stepIndex],
                style: GoogleFonts.outfit(
                  fontSize: 8.5,
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                  color: isCurrent
                      ? Colors.white
                      : isDone
                          ? Colors.white70
                          : Colors.white30,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildCateringConsole(
    Map<String, dynamic> o,
    Map<String, dynamic>? bulk,
    String status,
    Map<String, dynamic>? shop,
    Map<String, dynamic>? profile,
  ) {
    final eventName =
        bulk?['event_name'] ?? o['address_label'] ?? 'Event Catering';
    final deliveryOtp = o['delivery_otp']?.toString() ?? '—';
    final isDelivered = status == 'delivered' || status == 'bulk_delivered';
    final isDispatched = status == 'bulk_dispatched' || status == 'out_for_delivery';
    final isFoodReady = status == 'bulk_ready' || isDispatched || isDelivered;
    final isKitchenAppointed = status != 'bulk_pending';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E2138),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Event Title & Details
          Row(
            children: [
              const Icon(Icons.celebration, color: Colors.purpleAccent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  eventName.toString(),
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              if (bulk?['total_guests'] != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '👥 ${bulk!['total_guests']} Guests',
                    style: GoogleFonts.outfit(color: Colors.white70, fontSize: 11),
                  ),
                ),
            ],
          ),

          if (bulk?['venue_address'] != null || o['address'] != null) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on_rounded, size: 15, color: Colors.redAccent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    (bulk?['venue_address'] ?? o['address']).toString(),
                    style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],

          if (bulk?['event_date'] != null || bulk?['delivery_slot'] != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                if (bulk?['event_date'] != null) ...[
                  const Icon(Icons.calendar_today_rounded, size: 14, color: Colors.blueAccent),
                  const SizedBox(width: 6),
                  Text(
                    bulk!['event_date'].toString().substring(0, 10),
                    style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(width: 14),
                ],
                if (bulk?['delivery_slot'] != null) ...[
                  const Icon(Icons.schedule_rounded, size: 14, color: Colors.amberAccent),
                  const SizedBox(width: 6),
                  Text(
                    bulk!['delivery_slot'].toString(),
                    style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ],
            ),
          ],

          const SizedBox(height: 14),
          const Divider(color: Colors.white10),
          const SizedBox(height: 8),

          // ── STEP 1: Appointed Kitchen (1-Tap Direct Appoint) ───────────────
          Text(
            '1. APPOINTED KITCHEN',
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: Colors.purpleAccent,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isKitchenAppointed
                    ? Colors.greenAccent.withValues(alpha: 0.3)
                    : Colors.amberAccent.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isKitchenAppointed
                          ? Icons.check_circle_rounded
                          : Icons.soup_kitchen_rounded,
                      color: isKitchenAppointed
                          ? Colors.greenAccent
                          : Colors.amberAccent,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isKitchenAppointed
                                ? (shop != null
                                    ? shop['name']?.toString() ?? 'Appointed Kitchen'
                                    : 'Kitchen Appointed & Confirmed 👨‍🍳')
                                : 'No Kitchen Appointed Yet',
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            isKitchenAppointed
                                ? 'Kitchen confirmed. Food preparation arranged.'
                                : '1-tap to appoint kitchen and begin food prep.',
                            style: GoogleFonts.outfit(
                                color: Colors.white60, fontSize: 11.5),
                          ),
                        ],
                      ),
                    ),
                    if (isKitchenAppointed)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.greenAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: Colors.greenAccent.withValues(alpha: 0.4)),
                        ),
                        child: const Text(
                          'Confirmed 👨‍🍳',
                          style: TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                if (!isKitchenAppointed && !isDelivered) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.soup_kitchen_rounded, size: 18),
                      label: const Text(
                        'Appoint Kitchen & Start Cooking 👨‍🍳',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purpleAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _actioning
                          ? null
                          : () => _appointKitchenDirectly(o['id'].toString()),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 14),

          // ── STEP 2: Food Preparation & Packaging (1-Tap Mark Ready) ────────
          Text(
            '2. FOOD PREPARATION & PACKAGING',
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: Colors.purpleAccent,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isFoodReady
                    ? Colors.greenAccent.withValues(alpha: 0.3)
                    : Colors.white10,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            isFoodReady
                                ? Icons.done_all_rounded
                                : Icons.outdoor_grill_rounded,
                            color: isFoodReady
                                ? Colors.greenAccent
                                : Colors.orangeAccent,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isFoodReady
                                  ? 'All Food Prepared & Ready 🍱'
                                  : 'Dishes Cooking & Packaging 🍳',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (isFoodReady)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.greenAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: Colors.greenAccent.withValues(alpha: 0.4)),
                        ),
                        child: const Text(
                          'Ready 🍱',
                          style: TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  isFoodReady
                    ? 'Containers packed and ready for transport.'
                    : 'Dishes are being prepared. Mark ready once fully packed.',
                  style: GoogleFonts.outfit(color: Colors.white54, fontSize: 11.5),
                ),
                if (!isFoodReady && !isDelivered && !isDispatched) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.done_all_rounded, size: 18),
                      label: const Text(
                        'Mark Food Ready 🍱',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.greenAccent.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _actioning
                          ? null
                          : () => _markFoodReady(o['id'].toString()),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 14),

          // ── STEP 3: Dispatch & Logistics (In-House Deliver Myself Only) ────
          Text(
            '3. DISPATCH & LOGISTICS',
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: Colors.purpleAccent,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDispatched
                    ? Colors.tealAccent.withValues(alpha: 0.3)
                    : Colors.white10,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            isDispatched
                                ? Icons.local_shipping_rounded
                                : Icons.directions_car_filled_rounded,
                            color: isDispatched ? Colors.tealAccent : Colors.tealAccent.shade200,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isDispatched
                                  ? 'Out for Delivery (In-House Team) 🚗'
                                  : isDelivered
                                      ? 'Status: Delivered Successfully 🎉'
                                      : 'Ready for Venue Dispatch',
                              style: GoogleFonts.outfit(
                                color: isDispatched
                                    ? Colors.tealAccent
                                    : isDelivered
                                        ? Colors.greenAccent
                                        : Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (isDispatched)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.tealAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: Colors.tealAccent.withValues(alpha: 0.4)),
                        ),
                        child: const Text(
                          'In Transit 🚗',
                          style: TextStyle(
                            color: Colors.tealAccent,
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  isDispatched
                      ? 'In-house catering team is delivering food to the venue.'
                      : isDelivered
                          ? 'Delivered to customer at event location.'
                          : 'Transport food directly using in-house catering team/vehicle.',
                  style: GoogleFonts.outfit(color: Colors.white54, fontSize: 11.5),
                ),
                if (!isDelivered && !isDispatched) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.directions_car_filled_rounded, size: 18),
                      label: const Text(
                        'Deliver Myself / Out for Delivery 🚗',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0D9488),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _actioning
                          ? null
                          : () => _deliverMyself(o['id'].toString()),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 14),

          // ── STEP 4: Handover & OTP Completion ───────────────────────────────
          Text(
            '4. DELIVERY HANDOVER & OTP',
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: Colors.purpleAccent,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDelivered ? Colors.green.withValues(alpha: 0.3) : Colors.white12,
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.key_rounded, color: Colors.amberAccent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Delivery Handover OTP: $deliveryOtp',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        isDelivered
                            ? 'Delivered & verified.'
                            : 'Enter customer OTP upon arrival at venue.',
                        style: GoogleFonts.outfit(color: Colors.white54, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                if (!isDelivered)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.greenAccent.shade700,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _actioning ? null : () => _showCompleteDeliveryDialog(o),
                    child: const Text('Complete 🎉'),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Contact Customer Bar
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.call, size: 14),
                  label: Text(
                    'Call Customer (${profile?['full_name'] ?? 'Client'})',
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => _callPhone(profile?['phone'] ?? o['customer_phone']),
                ),
              ),
              if (shop?['phone'] != null) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.store, size: 14),
                  label: const Text('Kitchen'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.amberAccent,
                    side: const BorderSide(color: Colors.amberAccent),
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => _callPhone(shop!['phone']),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ── 1-Tap P2P Operations ────────────────────────────────────────────────────

  Future<void> _appointKitchenDirectly(String orderId) async {
    setState(() => _actioning = true);
    try {
      await _db.rpc('admin_appoint_catering_kitchen', params: {
        'p_order_id': orderId,
        'p_auto_confirm': true,
        'p_total_batches': 1,
      });
      final customerId = widget.order['customer_id']?.toString();
      if (customerId != null && customerId.isNotEmpty && mounted) {
        context.read<NotificationProvider>().sendBackgroundPush(
          targetUserId: customerId,
          title: '👨‍🍳 Kitchen Confirmed & Cooking!',
          body: 'Your catering kitchen has confirmed your feast order #${orderId.substring(0, 8).toUpperCase()}. Preparation and cooking has started!',
          data: {'order_id': orderId, 'type': 'bulk_order'},
        );
      }
      widget.onRefresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Kitchen appointed & food prep started! 👨‍🍳'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error appointing kitchen: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
    if (mounted) setState(() => _actioning = false);
  }

  Future<void> _markFoodReady(String orderId) async {
    setState(() => _actioning = true);
    try {
      await _db.rpc('admin_update_catering_packaging', params: {
        'p_order_id': orderId,
        'p_batches_packed': 1,
        'p_total_batches': 1,
      });
      final customerId = widget.order['customer_id']?.toString();
      if (customerId != null && customerId.isNotEmpty && mounted) {
        context.read<NotificationProvider>().sendBackgroundPush(
          targetUserId: customerId,
          title: '🍱 All Food Prepared & Ready!',
          body: 'All dishes for your event feast #${orderId.substring(0, 8).toUpperCase()} are freshly prepared, packed, and awaiting dispatch!',
          data: {'order_id': orderId, 'type': 'bulk_order'},
        );
      }
      widget.onRefresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('All food marked prepared and packed ready! 🍱'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error marking ready: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
    if (mounted) setState(() => _actioning = false);
  }

  Future<void> _deliverMyself(String orderId) async {
    setState(() => _actioning = true);
    try {
      await _db.rpc('admin_dispatch_catering_order', params: {
        'p_order_id': orderId,
        'p_dispatch_type': 'admin_self_delivery',
        'p_driver_name': 'In-House Team',
      });
      final customerId = widget.order['customer_id']?.toString();
      final otp = widget.order['delivery_otp']?.toString() ?? '';
      if (customerId != null && customerId.isNotEmpty && mounted) {
        context.read<NotificationProvider>().sendBackgroundPush(
          targetUserId: customerId,
          title: '🚗 Feast Out for Delivery!',
          body: 'Your event catering feast #${orderId.substring(0, 8).toUpperCase()} is on its way with the in-house team! Handover OTP: $otp',
          data: {'order_id': orderId, 'type': 'bulk_order'},
        );
      }
      widget.onRefresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Order dispatched via In-House Team! 🚗'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error dispatching: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
    if (mounted) setState(() => _actioning = false);
  }

  Future<void> _showCompleteDeliveryDialog(Map<String, dynamic> o) async {
    final expectedOtp = o['delivery_otp']?.toString() ?? '';
    final otpCtrl = TextEditingController(text: expectedOtp);
    bool adminOverride = false;

    await showDialog(
      context: context,
      builder: (dlgCtx) {
        return StatefulBuilder(
          builder: (_, setDlgState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E2138),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  const Icon(Icons.verified_rounded, color: Colors.greenAccent),
                  const SizedBox(width: 8),
                  Text(
                    'Confirm Handover',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Verify the 4-digit Delivery Handover OTP from customer:',
                    style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: otpCtrl,
                    keyboardType: TextInputType.number,
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 6,
                    ),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      hintText: '••••',
                      hintStyle: const TextStyle(color: Colors.white24, letterSpacing: 6),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Checkbox(
                        value: adminOverride,
                        activeColor: Colors.amberAccent,
                        checkColor: Colors.black,
                        onChanged: (val) => setDlgState(() => adminOverride = val ?? false),
                      ),
                      Expanded(
                        child: Text(
                          'Super Admin Override (Bypass OTP check)',
                          style: GoogleFonts.outfit(color: Colors.amberAccent, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dlgCtx),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () async {
                    Navigator.pop(dlgCtx);
                    setState(() => _actioning = true);
                    try {
                      await _db.rpc('admin_complete_catering_delivery', params: {
                        'p_order_id': o['id'].toString(),
                        'p_otp': otpCtrl.text.trim(),
                        'p_admin_override': adminOverride,
                      });
                      final customerId = o['customer_id']?.toString();
                      if (customerId != null && customerId.isNotEmpty && mounted) {
                        context.read<NotificationProvider>().sendBackgroundPush(
                          targetUserId: customerId,
                          title: '🎉 Event Feast Delivered!',
                          body: 'Your catering feast has been successfully delivered and verified with OTP. Enjoy your event celebration!',
                          data: {'order_id': o['id'].toString(), 'type': 'bulk_order'},
                        );
                      }
                      widget.onRefresh();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Catering order delivered successfully! 🎉'),
                          backgroundColor: Colors.green,
                        ));
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Error completing delivery: $e'),
                          backgroundColor: Colors.red,
                        ));
                      }
                    }
                    if (mounted) setState(() => _actioning = false);
                  },
                  child: const Text('Confirm Handover ✅'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
