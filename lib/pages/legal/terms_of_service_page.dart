import 'package:flutter/material.dart';
import 'legal_page.dart';

class TermsOfServicePage extends StatelessWidget {
  const TermsOfServicePage({super.key});

  @override
  Widget build(BuildContext context) {
    return LegalPage(
      title: 'Terms of Service',
      sections: [
        LegalSection(
          heading: '1. Acceptance of Terms',
          content:
              'By accessing or using the Enything application, you agree to be bound by these Terms of Service. If you do not agree to all terms, please do not use the application.',
        ),
        LegalSection(
          heading: '2. Platform Role & E-Commerce Compliance',
          content:
              'Under the Consumer Protection (E-Commerce) Rules, 2020, Enything acts as a Marketplace E-Commerce Entity connecting Customers, Sellers, and Delivery Partners. Enything does not own the inventory and is not responsible for the quality, safety, or legality of items.',
        ),
        LegalSection(
          heading:
              '3. E-Pharmacy Specific Rules (Drugs and Cosmetics Act, 1940)',
          content:
              'The sale of Schedule H and H1 drugs requires a valid prescription from a Registered Medical Practitioner, which must be uploaded via the Platform. The sale of Schedule X drugs, Narcotic Drugs, and Psychotropic Substances (NDPS) is strictly prohibited. The registered pharmacy seller retains sole responsibility for verifying the authenticity of uploaded prescriptions.',
        ),
        LegalSection(
          heading: '4. Pricing, Payments & GST',
          content:
              'Enything charges a 5% platform commission on base prices. A fixed Handling/Platform Fee of ₹15 is charged per order. In accordance with Section 9(5) of the CGST Act, Enything collects and remits GST on behalf of restaurants for food deliveries. For non-food retail and pharmacy items, the seller is responsible for remitting GST, though Enything will collect 1% TCS as per Section 52.',
        ),
        LegalSection(
          heading: '5. Cancellation & Refunds',
          content:
              'Pre-Dispatch: Customers may cancel orders before the seller accepts the order for a full refund. Rejections: If a seller rejects an order (e.g., due to an invalid medical prescription), a full refund will be initiated automatically. Approved refunds will be processed back to the original payment method within 5-7 business days.',
        ),
        LegalSection(
          heading: '6. User Responsibilities',
          content:
              'Users are responsible for providing accurate delivery addresses and contact information. Any misuse of the platform, including fake orders or harassment of riders, will lead to immediate account termination.',
        ),
        LegalSection(
          heading: '7. Grievance Redressal Mechanism',
          content:
              'In accordance with the Information Technology Act, 2000 and rules made thereunder, the name and contact details of the Grievance Officer are provided below:\nName: Grievance Officer\nEmail: grievance@enything.in\nTime: Mon - Fri (9:00 AM - 6:00 PM).',
        ),
      ],
    );
  }
}
