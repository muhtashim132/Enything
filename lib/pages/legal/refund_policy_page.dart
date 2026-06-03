import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Full Refund & Cancellation Policy page — required by Razorpay India for payment gateway approval.
/// Linked from checkout page and Terms of Service.
class RefundPolicyPage extends StatelessWidget {
  const RefundPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
        title: const Text('Refund & Cancellation Policy',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Effective Date: June 1, 2025',
              style: TextStyle(color: Colors.white38, fontSize: 12)),
          const SizedBox(height: 20),

          _Section(
            title: '1. Order Cancellation',
            content: [
              _Para('Before Confirmation (No Charge)', 'You may cancel your order at any time before both the shop and rider accept it. Because payment is only collected after confirmation, no money is deducted and no refund is needed.'),
              _Para('After Confirmation & Payment', 'Once both parties accept and you complete payment, the shop begins preparation. At this stage, cancellation is not available through the app. Please contact support immediately if you need assistance.'),
              _Para('Auto-Cancellation (2-Minute Rule)', 'If the shop or rider does not respond within 2 minutes, your order is automatically cancelled. You will not be charged.'),
              _Para('Shop Rejection', 'If the shop is unable to fulfill your order, they may decline it. No payment is taken, and you can easily retry your order with a different shop.'),
            ],
          ),

          _Section(
            title: '2. Refund Eligibility',
            content: [
              _Para('Pre-Paid Orders', 'Since payment is only collected after confirmation, full refunds apply primarily if:\n  • You paid, but the order was not delivered within the committed time frame.\n  • You received a wrong or defective item.\n  • The order was cancelled by support due to unforeseen issues after payment.'),
              _Para('Cash on Delivery (COD)', 'COD orders do not involve pre-payment, so no online refund applies. Disputes for COD orders are handled through our support team.'),
              _Para('Partial Refunds', 'If only part of your order is missing or incorrect, a partial refund equal to the affected item(s) value will be issued.'),
            ],
          ),

          _Section(
            title: '3. Refund Processing Timeline',
            content: [
              _Para('Online Payments (UPI / Card / Wallet)', 'Approved refunds are processed within 5–7 business days. The refund will appear in your original payment source (bank account, UPI ID, or card).'),
              _Para('Wallet Credits', 'Where applicable, refunds may be credited to your Enything wallet within 24 hours for faster resolution.'),
              _Para('Note', 'Razorpay (our payment gateway) processes refunds. Processing times may vary by bank. Enything is not responsible for delays caused by your bank or card network.'),
            ],
          ),

          _Section(
            title: '4. How to Request a Refund',
            content: [
              _Para('Step 1', 'Open the app → Go to Order History.'),
              _Para('Step 2', 'Tap the affected order → Select "Report an Issue."'),
              _Para('Step 3', 'Describe your issue. Our support team will review your request within 24 hours.'),
              _Para('Email', 'You may also write to us at support@enything.in with your Order ID.'),
            ],
          ),

          _Section(
            title: '5. Non-Refundable Cases',
            content: [
              _Para('Not Eligible', '• Orders cancelled after preparation has started.\n• Orders where incorrect address was provided by the customer.\n• Orders refused at the time of delivery without valid reason.\n• Items consumed partially and then returned.'),
            ],
          ),

          _Section(
            title: '6. Delivery Partner Disputes',
            content: [
              _Para('Delivery Issues', 'If your order was marked delivered but not received, contact support within 1 hour of the marked delivery time. We will investigate with our delivery partner and issue a refund if the complaint is validated.'),
            ],
          ),

          _Section(
            title: '7. Contact Us',
            content: [
              _Para('Email', 'support@enything.in'),
              _Para('Phone', '+91 7006464241'),
              _Para('Address', 'Ward No. 2, Bandipora, 193502, Jammu and Kashmir, India'),
              _Para('Hours', 'Monday – Saturday, 9:00 AM – 6:00 PM IST'),
            ],
          ),

          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: const Text(
              'This policy is subject to change. Continued use of the Enything app constitutes acceptance of the latest version of this policy.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<_Para> content;
  const _Section({required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(title,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700))
            .animate()
            .fadeIn(delay: 50.ms),
        const SizedBox(height: 10),
        ...content.map((p) => _ParaWidget(p)),
        const Divider(color: Colors.white12, height: 32),
      ],
    );
  }
}

class _Para {
  final String heading;
  final String body;
  const _Para(this.heading, this.body);
}

class _ParaWidget extends StatelessWidget {
  final _Para p;
  const _ParaWidget(this.p);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(p.heading,
              style: const TextStyle(
                  color: Color(0xFF4C6EF5),
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(p.body,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 13, height: 1.6)),
        ],
      ),
    );
  }
}
