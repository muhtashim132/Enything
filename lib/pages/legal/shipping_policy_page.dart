import 'package:flutter/material.dart';
import 'legal_page.dart';

class ShippingPolicyPage extends StatelessWidget {
  const ShippingPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return LegalPage(
      title: 'Shipping & Delivery Policy',
      sections: [
        LegalSection(
          heading: '1. Delivery Area',
          content: 'Enything operates as a hyper-local delivery service. Deliveries are currently restricted to the Bandipora district and a strict radius of 15 kilometers from our registered operating centers.',
        ),
        LegalSection(
          heading: '2. Delivery Timeframes',
          content: 'We strive to provide the fastest possible delivery within our hyper-local zones. Under normal circumstances, orders are fulfilled and delivered within 30 to 60 minutes. However, during peak hours, bad weather, or other unforeseen circumstances, delivery may take up to a maximum of 2 hours.',
        ),
        LegalSection(
          heading: '3. Delivery Charges',
          content: 'Delivery charges are calculated dynamically based on the exact distance between the shop and the delivery address, as well as the total weight of the items. The final delivery charge will always be displayed transparently on the checkout screen before you confirm your payment.',
        ),
        LegalSection(
          heading: '4. Delivery Partners',
          content: 'All deliveries are handled by our verified independent delivery partners. You will be able to track your delivery partner\'s location in real-time through the Enything app once the order is picked up from the shop.',
        ),
        LegalSection(
          heading: '5. Non-Availability at Delivery Address',
          content: 'Our delivery partners will attempt to contact you via the phone number provided at checkout. If you are unreachable or unavailable at the specified address after multiple attempts, the order may be cancelled. In such cases, refunds are subject to our Refund and Cancellation Policy.',
        ),
      ],
    );
  }
}
