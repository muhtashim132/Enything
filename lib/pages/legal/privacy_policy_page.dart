import 'package:flutter/material.dart';
import 'legal_page.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return LegalPage(
      title: 'Privacy Policy',
      sections: [
        LegalSection(
          heading: '1. Information We Collect (DPDPA 2023)',
          content: 'We collect personal information to fulfill hyperlocal orders. This includes Identity Data (Name, Phone, Email), Location Data (GPS coordinates), and Health Data (Prescription images uploaded for pharmacy orders).',
        ),
        LegalSection(
          heading: '2. Processing of Health Data (Sensitive)',
          content: 'Under the DPDPA 2023, prescriptions are treated as highly sensitive data. They are encrypted and transmitted directly to the licensed pharmacy fulfilling your order. We do not sell or mine medical data. Prescription data is securely purged once regulatory retention periods expire.',
        ),
        LegalSection(
          heading: '3. Data Fiduciary & Processors',
          content: 'Enything acts as the Data Fiduciary for your account data. Independent Sellers and Delivery Partners act as Data Processors granted temporary, restricted access to your phone and location solely for the active delivery duration.',
        ),
        LegalSection(
          heading: '4. Your Rights under DPDPA, 2023',
          content: 'As a Data Principal, you have the right to Access (request a summary), Correction (update via Profile), Erasure (delete account), and Grievance Redressal (contact our DPO at grievances@enything.in).',
        ),
        LegalSection(
          heading: '5. Security Measures',
          content: 'We employ strict Role-Based Access Control (RBAC), data encryption at rest via Supabase, and HTTPS transport layer security to prevent unauthorized access or disclosure.',
        ),
      ],
    );
  }
}
