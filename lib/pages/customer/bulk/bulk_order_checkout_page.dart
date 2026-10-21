// ============================================================================
// bulk_order_checkout_page.dart — Bulk & Event Catering Checkout & Payment
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../../theme/app_theme.dart';
import '../../../config/routes.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/bulk_order_provider.dart';

class BulkOrderCheckoutPage extends StatefulWidget {
  const BulkOrderCheckoutPage({super.key});

  @override
  State<BulkOrderCheckoutPage> createState() => _BulkOrderCheckoutPageState();
}

class _BulkOrderCheckoutPageState extends State<BulkOrderCheckoutPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  late Razorpay _razorpay;
  bool _isProcessing = false;
  String? _placedOrderId;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    if (_placedOrderId == null) return;
    try {
      await _supabase.from('orders').update({
        'payment_status': 'captured',
        'razorpay_payment_id': response.paymentId,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', _placedOrderId!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment Successful! Bulk catering order placed 🎉'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pushNamedAndRemoveUntil(
          context,
          AppRoutes.bulkOrderTracking,
          (route) => route.isFirst,
          arguments: {'orderId': _placedOrderId},
        );
      }
    } catch (e) {
      debugPrint('Error updating captured payment: $e');
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    setState(() => _isProcessing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Payment failed: ${response.message ?? "Transaction cancelled"}'),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('External Wallet selected: ${response.walletName}')),
    );
  }

  Future<void> _processCheckout(BulkOrderProvider bulkProvider) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final idempotencyKey = const Uuid().v4();

      // 1. Place order in database via RPC
      final result = await bulkProvider.placeOrder(
        idempotencyKey: idempotencyKey,
      );

      final orderId = result['order_id']?.toString();
      if (orderId == null) {
        throw StateError('Failed to generate bulk order');
      }

      _placedOrderId = orderId;

      // 2. Launch Razorpay for 100% Prepaid payment
      final razorpayKeyId = dotenv.maybeGet('RAZORPAY_KEY_ID') ?? 'rzp_test_517t4q9z1029';
      if (!mounted) return;
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final user = auth.user;
      final amountInPaise = (bulkProvider.grandTotal * 100).round();

      final options = {
        'key': razorpayKeyId,
        'amount': amountInPaise,
        'currency': 'INR',
        'name': 'Enything Catering',
        'description': 'Bulk Catering: ${bulkProvider.eventName}',
        'prefill': {
          'contact': bulkProvider.contactPersonPhone.isNotEmpty
              ? bulkProvider.contactPersonPhone
              : (user?.phone ?? ''),
          'email': user?.email ?? 'customer@enything.app',
          'name': bulkProvider.contactPersonName.isNotEmpty
              ? bulkProvider.contactPersonName
              : (user?.fullName ?? 'Customer'),
        },
        'theme': {'color': '#4C6EF5'},
      };

      _razorpay.open(options);
    } catch (e) {
      debugPrint('Bulk checkout error: $e');
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception:', '').replaceAll('StateError:', '').trim()),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = AppTheme.primaryColor;
    final bulkProvider = Provider.of<BulkOrderProvider>(context);
    final shop = bulkProvider.selectedShop;

    if (shop == null || bulkProvider.items.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Checkout')),
        body: const Center(child: Text('No bulk items in cart')),
      );
    }

    final eventDateStr = bulkProvider.eventDate != null
        ? DateFormat('EEE, MMM d, yyyy').format(bulkProvider.eventDate!)
        : 'Date not set';

    final slotStr = (bulkProvider.slotStartTime != null && bulkProvider.slotEndTime != null)
        ? '${bulkProvider.slotStartTime!.format(context)} – ${bulkProvider.slotEndTime!.format(context)}'
        : 'Time not set';

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          'Order Summary & Payment 💳',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        elevation: 0,
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black87,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Kitchen & Event Banner
          _buildEventBanner(shop, eventDateStr, slotStr, bulkProvider, isDark, primary),
          const SizedBox(height: 16),

          // 2. Itemized List
          _buildItemizedDishes(bulkProvider, isDark, primary),
          const SizedBox(height: 16),

          // 3. Bill Breakdown
          _buildBillSummary(bulkProvider, isDark, primary),
          const SizedBox(height: 16),

          // 4. Cancellation Policy Notice
          _buildCancellationPolicyCard(isDark),
          const SizedBox(height: 24),

          // 5. 100% Prepaid Payment Button
          ElevatedButton(
            onPressed: _isProcessing ? null : () => _processCheckout(bulkProvider),
            style: ElevatedButton.styleFrom(
              backgroundColor: primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: _isProcessing
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.lock_outline_rounded, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Pay ₹${bulkProvider.grandTotal.toStringAsFixed(0)} & Confirm',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          const Center(
            child: Text(
              '🔒 100% Secure Payment via Razorpay · Zero COD Model',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildEventBanner(
    dynamic shop,
    String eventDateStr,
    String slotStr,
    BulkOrderProvider bulkProvider,
    bool isDark,
    Color primary,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primary.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'EVENT CATERING',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: primary,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '${bulkProvider.totalItems} Items',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            bulkProvider.eventName.isNotEmpty
                ? bulkProvider.eventName
                : 'Catering Event',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Kitchen: ${shop.name}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.grey[800],
            ),
          ),
          const Divider(height: 20),
          _buildInfoRow(Icons.calendar_today_rounded, eventDateStr, isDark),
          const SizedBox(height: 6),
          _buildInfoRow(Icons.schedule_rounded, slotStr, isDark),
          const SizedBox(height: 6),
          _buildInfoRow(Icons.location_on_rounded, bulkProvider.venueAddress, isDark),
          const SizedBox(height: 6),
          _buildInfoRow(
            Icons.person_outline_rounded,
            '${bulkProvider.contactPersonName} (${bulkProvider.contactPersonPhone})',
            isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text, bool isDark) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white70 : Colors.grey[700],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildItemizedDishes(BulkOrderProvider bulkProvider, bool isDark, Color primary) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Itemized Dishes (${bulkProvider.items.length})',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              Text(
                '${bulkProvider.totalWeightKg.toStringAsFixed(1)} kg est.',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...bulkProvider.items.values.map((item) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${item.quantity}×',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.product.name,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        if (item.specialInstructions?.isNotEmpty == true)
                          Text(
                            'Note: ${item.specialInstructions}',
                            style: const TextStyle(fontSize: 10.5, color: Colors.grey, fontStyle: FontStyle.italic),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    '₹${item.totalPrice.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildBillSummary(BulkOrderProvider bulkProvider, bool isDark, Color primary) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bill Summary',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          _buildBillRow('Item Subtotal', '₹${bulkProvider.subtotal.toStringAsFixed(0)}', isDark),
          _buildBillRow(
            'Fleet Delivery (${bulkProvider.estimatedPackages} packages)',
            '₹${bulkProvider.deliveryCharges.toStringAsFixed(0)}',
            isDark,
          ),
          _buildBillRow('Platform Handling Fee', '₹${bulkProvider.platformFee.toStringAsFixed(0)}', isDark),
          if (bulkProvider.heavyOrderFee > 0)
            _buildBillRow('Heavy Order Logistics', '₹${bulkProvider.heavyOrderFee.toStringAsFixed(0)}', isDark),
          _buildBillRow('Taxes & GST (5% Food GST)', '₹${bulkProvider.estimatedGst.toStringAsFixed(0)}', isDark),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Grand Total',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              Text(
                '₹${bulkProvider.grandTotal.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBillRow(String label, String amount, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              color: isDark ? Colors.white60 : Colors.grey[600],
            ),
          ),
          Text(
            amount,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCancellationPolicyCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E241E) : const Color(0xFFF1F8F4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.policy_rounded, size: 16, color: Colors.green),
              const SizedBox(width: 6),
              Text(
                'Tiered Cancellation & Refund Policy',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.greenAccent : Colors.green.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildPolicyRow('✅ >24 hours before event', '100% Refund on items + delivery', isDark),
          _buildPolicyRow('⚠️ 6–24 hours before event', '50% Refund on items + delivery', isDark),
          _buildPolicyRow('❌ <6 hours (kitchen prep)', '0% Refund on items (Delivery refunded)', isDark),
        ],
      ),
    );
  }

  Widget _buildPolicyRow(String condition, String policy, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            condition,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '→ $policy',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white60 : Colors.grey[700],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
