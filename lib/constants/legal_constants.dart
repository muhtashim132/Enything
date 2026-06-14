import '../pages/legal/legal_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Business Identity (used across all policies)
//   Business Name  : Enything
//   Proprietor     : Muhtaashim Kamran Nazki
//   Udyam No.      : UDYAM-JK-02-0019684
//   Address        : Plan Bandipora, Ward No. 2, Bandipora,
//                    Jammu & Kashmir — 193502, India
//   Email          : support@enything.in
//   Phone          : +91 7006464241
// ─────────────────────────────────────────────────────────────────────────────

class LegalConstants {
  // ───────────────────────────────────────────────────────────── CUSTOMER ────
  static final List<LegalSection> customerTerms = [
    LegalSection(
      heading: '1. Platform Role & Intermediary Status',
      content:
          'Enything (a sole proprietorship owned by Muhtaashim Kamran Nazki, Udyam Registration No. UDYAM-JK-02-0019684) operates as an intermediary marketplace facilitating hyper-local logistics in Jammu & Kashmir, India. The contract of sale is strictly between you and the respective Seller listed on the platform. Enything is not the seller of record for any product.',
    ),
    LegalSection(
      heading: '2. Account Integrity & Eligibility',
      content:
          'You must provide accurate delivery locations and valid contact details at all times. You must be at least 18 years of age to create an account and use the platform. For restricted items (including certain medicines and age-restricted goods), you must comply with all applicable laws and provide proof of age or prescription where required.',
    ),
    LegalSection(
      heading: '3. Prohibited Use',
      content:
          'You agree not to order, list, or attempt to purchase illegal, hazardous, banned, or counterfeit items. You must not use the platform for any fraudulent, abusive, or unlawful purpose. Violation will result in immediate account termination and may be reported to relevant authorities.',
    ),
    LegalSection(
      heading: '4. Payment Terms',
      content:
          'All transactions are conducted exclusively in Indian Rupees (INR). Payments are processed by Razorpay Software Private Limited, a PCI DSS–compliant payment aggregator regulated under RBI guidelines. Enything does not store your card, UPI, or net-banking credentials at any time. The total amount shown at checkout is final; there are no hidden charges. A convenience or platform fee, if applicable, will be disclosed before order confirmation.',
    ),
    LegalSection(
      heading: '5. Order Acceptance & Fulfilment',
      content:
          'Once you place an order, it is forwarded to the Seller for acceptance. Payment is collected only after both the Seller and a Delivery Partner accept the order. If no Seller accepts within the stipulated time, your order is automatically cancelled and no payment is charged.',
    ),
    LegalSection(
      heading: '6. Limitation of Liability',
      content:
          'Enything is not liable for the quality, safety, or legality of the products delivered, including food items and medicines. Our maximum liability towards any customer shall not exceed the value of the transaction in dispute.',
    ),
    LegalSection(
      heading: '7. Governing Law & Dispute Resolution',
      content:
          'These Terms are governed by the laws of India. Any disputes arising out of or in connection with these Terms shall first be attempted to be resolved amicably by contacting support@enything.in. If unresolved within 30 days, disputes shall be subject to the exclusive jurisdiction of the courts at Bandipora, Jammu & Kashmir, India.',
    ),
    LegalSection(
      heading: '8. Changes to Terms',
      content:
          'Enything reserves the right to modify these Terms at any time. Continued use of the platform after changes constitutes acceptance of the revised Terms. The "Last Updated" date at the top of this page will reflect the most recent revision.',
    ),
  ];

  static final List<LegalSection> customerPrivacy = [
    LegalSection(
      heading: '1. Data Controller',
      content:
          'The data controller for your personal information is Enything, a sole proprietorship owned by Muhtaashim Kamran Nazki, located at Plan Bandipora, Ward No. 2, Bandipora, Jammu & Kashmir — 193502, India. For data-related queries, contact: support@enything.in.',
    ),
    LegalSection(
      heading: '2. Data We Collect',
      content:
          'We collect: (a) Identity data — name and phone number provided at registration; (b) Location data — your GPS coordinates to enable hyper-local delivery; (c) Order data — items ordered, delivery address, payment reference IDs; (d) Device data — device type, OS version, and app version for troubleshooting.',
    ),
    LegalSection(
      heading: '3. How We Use Your Data',
      content:
          'Your data is used to: process and deliver your orders; send transactional SMS/push notifications; resolve support tickets; improve platform quality; and comply with Indian tax and legal obligations.',
    ),
    LegalSection(
      heading: '4. Payment Data & PCI DSS',
      content:
          'We do not store, process, or transmit any payment card details directly. All payment data is handled by Razorpay Software Private Limited under PCI DSS Level 1 compliance. We only retain the Razorpay payment reference ID and order ID for reconciliation purposes.',
    ),
    LegalSection(
      heading: '5. Data Sharing',
      content:
          'Your information is shared on a need-to-know basis: Seller receives your name, delivery address, and phone number to prepare and hand over your order; Delivery Partner receives your name, live delivery location, and phone number to complete delivery; Razorpay receives order amount and reference for payment processing; Indian tax authorities receive transaction data as required by law. We do not sell your data to any third party for marketing.',
    ),
    LegalSection(
      heading: '6. Data Retention',
      content:
          'We retain your account data for as long as your account is active. Order records are retained for 7 years as required by Indian accounting standards. You may request account deletion by emailing support@enything.in; this will anonymise your personal data within 30 days while retaining transaction records for legal compliance.',
    ),
    LegalSection(
      heading: '7. Your Rights',
      content:
          'You have the right to: access the personal data we hold about you; correct inaccurate data; request deletion of your account and data (subject to legal retention requirements); withdraw consent for marketing communications at any time. To exercise these rights, contact support@enything.in.',
    ),
    LegalSection(
      heading: '8. Security',
      content:
          'We use industry-standard encryption (TLS 1.2+) for all data in transit. Our backend infrastructure is hosted on Supabase, which is SOC 2 Type II certified. Access to your data is restricted to authorised personnel only.',
    ),
  ];

  static final List<LegalSection> customerRefund = [
    LegalSection(
      heading: '1. Cancellation Before Order Acceptance',
      content:
          'You may cancel your order at no charge before the Seller accepts it. If payment has been collected (in rare edge cases), a full refund will be issued within 5–7 business days to the original payment method.',
    ),
    LegalSection(
      heading: '2. Cancellation After Seller Acceptance',
      content:
          'Once the Seller has accepted your order and begun preparation, cancellation requests are evaluated on a case-by-case basis. If approved by Enything support, a refund may be issued within 5–7 business days. If the order is already out for delivery, cancellation is not permitted.',
    ),
    LegalSection(
      heading: '3. Dispute — Missing or Damaged Items',
      content:
          'If your order arrives with missing or visibly damaged items, you must raise a dispute within 24 hours of delivery by contacting support@enything.in or calling +91 7006464241. Enything will investigate and, if the claim is verified, process a refund within 5–7 business days.',
    ),
    LegalSection(
      heading: '4. Non-Refundable Situations',
      content:
          'Refunds will NOT be issued for: orders where the customer was unavailable at the delivery address; perishable goods (food items) unless they are visibly spoiled or tampered with; incorrect delivery address provided by the customer; orders cancelled after preparation is complete.',
    ),
    LegalSection(
      heading: '5. Refund Method & Timeline',
      content:
          'All approved refunds are processed digitally to the original payment method (UPI, debit/credit card, or net banking) used at the time of purchase. We do not issue cash refunds under any circumstances. Refunds are typically reflected within 5–7 business days depending on your bank or payment provider.',
    ),
    LegalSection(
      heading: '6. How to Raise a Refund Request',
      content:
          'To request a refund, contact us at support@enything.in with your Order ID, a brief description of the issue, and supporting photos (if applicable). Our support team operates Monday to Saturday, 9 AM to 6 PM IST, and will respond within 24 hours.',
    ),
  ];

  // ────────────────────────────────────────────────────────────── SELLER ────
  static final List<LegalSection> sellerTerms = [
    LegalSection(
      heading: '1. Platform Intermediary',
      content:
          'You acknowledge that Enything (operated by Muhtaashim Kamran Nazki, Udyam No. UDYAM-JK-02-0019684) is an intermediary marketplace. You are the legal retailer and bear full liability for product quality, safety, regulatory compliance, and accurate descriptions.',
    ),
    LegalSection(
      heading: '2. Mandatory Licensing',
      content:
          'You must maintain valid licences applicable to your business category: FSSAI licence for food and grocery sellers; Drug Licence for pharmacies; GST registration if your turnover exceeds the prescribed threshold; any local trade or municipal licences required in your jurisdiction.',
    ),
    LegalSection(
      heading: '3. Pharmacy-Specific Regulations',
      content:
          'Pharmacies must require customer prescription uploads for Schedule H drugs before dispensing. Dispensing must occur under a registered pharmacist. Sale of Schedule X drugs and narcotics (NDPS Act) via the platform is strictly prohibited and will result in immediate deactivation and reporting to authorities.',
    ),
    LegalSection(
      heading: '4. Financial & Commission Terms',
      content:
          'You agree to the platform commission fee structure disclosed in your onboarding agreement. Tax Collection at Source (TCS) under the GST framework will be deducted from settlements as required by Indian law. Payouts are processed to your registered bank account on a weekly cycle (Monday–Sunday earnings credited by following Wednesday).',
    ),
    LegalSection(
      heading: '5. Fulfilment SLAs',
      content:
          'You must accept or reject incoming orders within the stipulated response window. Accepted orders must be prepared and handed to the Delivery Partner without unreasonable delay. Persistent SLA violations will negatively impact your store rating and may lead to suspension.',
    ),
    LegalSection(
      heading: '6. Governing Law',
      content:
          'This agreement is governed by Indian law. Disputes shall be subject to the exclusive jurisdiction of courts at Bandipora, Jammu & Kashmir.',
    ),
  ];

  static final List<LegalSection> sellerPrivacy = [
    LegalSection(
      heading: '1. Data We Collect from Sellers',
      content:
          'We collect: merchant legal name, trading name, store GPS coordinates, PAN card number, GSTIN, bank account details for payout, and copies of regulatory licences (FSSAI, Drug Licence, etc.) for KYC verification.',
    ),
    LegalSection(
      heading: '2. Data Usage',
      content:
          'Collected data is used for: KYC and merchant verification; automated payout routing to your bank account; calculating your store delivery radius; tax reporting under GST TCS provisions.',
    ),
    LegalSection(
      heading: '3. Data Sharing',
      content:
          'Your store name, location, and contact details are shared with Customers and assigned Delivery Partners. Financial and KYC data is shared with our payment processor (Razorpay) and Indian tax authorities for statutory compliance only.',
    ),
    LegalSection(
      heading: '4. Payment Data',
      content:
          'We do not store your bank account credentials beyond what is required for payout initiation. Bank account data is encrypted at rest and shared with Razorpay\'s payout service only.',
    ),
  ];

  static final List<LegalSection> sellerRefund = [
    LegalSection(
      heading: '1. Auto-Cancellation Policy',
      content:
          'Orders not accepted within the SLA window will be automatically cancelled. This will negatively impact your store\'s acceptance rate and search ranking. Persistent auto-cancellations may result in temporary suspension.',
    ),
    LegalSection(
      heading: '2. Seller Liability for Customer Refunds',
      content:
          'If a customer receives a refund due to missing items, spoiled goods, expired products, or incorrect fulfilment attributable to your store, the refund amount will be deducted from your next settlement payout. Repeated incidents may result in store suspension.',
    ),
    LegalSection(
      heading: '3. Out-of-Stock Cancellations',
      content:
          'You must keep your inventory updated in real time. Cancellations due to "Out of Stock" after an order has been accepted will incur a platform penalty. Three or more such incidents in a 30-day period will trigger a formal review.',
    ),
    LegalSection(
      heading: '4. Refund Timeline Impact on Seller',
      content:
          'When a customer refund is approved by Enything (within 5–7 business days), the equivalent amount is debited from your settlement account in the following payout cycle.',
    ),
  ];

  // ──────────────────────────────────────────────── DELIVERY PARTNER ────
  static final List<LegalSection> deliveryTerms = [
    LegalSection(
      heading: '1. Independent Contractor Status',
      content:
          'You are an independent contractor, not an employee of Enything. You are not entitled to employee benefits, health insurance, provident fund (PF), or gratuity under any applicable Indian labour law.',
    ),
    LegalSection(
      heading: '2. Earnings & Revenue Share',
      content:
          'You are entitled to a defined share of the delivery charge for each successfully completed delivery, as communicated during onboarding. Payout cycles are processed weekly to your registered bank account.',
    ),
    LegalSection(
      heading: '3. Vehicle & Document Compliance',
      content:
          'You are solely responsible for maintaining: a valid Driving Licence; current Vehicle Registration Certificate (RC); active third-party vehicle Insurance; and roadworthiness of your vehicle. Enything reserves the right to deactivate your account if documents expire.',
    ),
    LegalSection(
      heading: '4. Code of Conduct',
      content:
          'Zero tolerance for: theft, order tampering, or consumption of customer orders; unsafe or reckless driving; traffic violations; abusive or unprofessional behaviour towards Customers or Sellers. Any verified violation will result in immediate deactivation, withholding of pending payouts, and potential legal action.',
    ),
    LegalSection(
      heading: '5. Governing Law',
      content:
          'This agreement is governed by Indian law. Disputes shall be subject to the exclusive jurisdiction of courts at Bandipora, Jammu & Kashmir.',
    ),
  ];

  static final List<LegalSection> deliveryPrivacy = [
    LegalSection(
      heading: '1. Data We Collect from Delivery Partners',
      content:
          'We collect: Aadhaar card number (for identity verification), PAN card number (for tax compliance), Driving Licence number, Vehicle RC number, bank account details for payout, and continuous background GPS location data while you are on active duty.',
    ),
    LegalSection(
      heading: '2. Continuous Location Tracking',
      content:
          'By accepting delivery assignments, you explicitly consent to background GPS tracking, including when the app is minimised. This is strictly required for: routing active orders to your nearest location; optimising dispatch; and providing live tracking to Customers and Sellers during an active delivery.',
    ),
    LegalSection(
      heading: '3. Data Sharing',
      content:
          'Your name, live GPS location, and vehicle details are shared with the Customer and Seller during an active delivery cycle only. KYC documents (Aadhaar, PAN, DL, RC) are shared with statutory verification agencies as required by Indian regulations.',
    ),
    LegalSection(
      heading: '4. Payment Data',
      content:
          'Your bank account details are used solely for processing weekly payout settlements. This data is encrypted and shared with Razorpay\'s payout service only.',
    ),
  ];

  static final List<LegalSection> deliveryRefund = [
    LegalSection(
      heading: '1. Order Acceptance & Rejection',
      content:
          'You have the right to accept or reject assigned delivery orders. However, frequent cancellations after acceptance will lower your dispatch priority score and may result in fewer orders being assigned to you.',
    ),
    LegalSection(
      heading: '2. Penalty for Order Tampering',
      content:
          'Any verified instance of opening sealed packages, consuming food orders, stealing items, or misrepresenting delivery status will result in: immediate termination of your delivery partner account; withholding of all pending payouts; and potential civil and criminal legal action.',
    ),
    LegalSection(
      heading: '3. Account Deactivation',
      content:
          'Enything reserves the right to suspend or permanently deactivate your profile for: consistent late deliveries; poor customer ratings (below threshold); expired vehicular or identity documents; or any breach of the Code of Conduct. Disputes regarding deactivation can be raised at support@enything.in.',
    ),
  ];

  // ─────────────────────────────────────── PUBLIC / COMBINED (no role) ────
  // Used when role is null — e.g., when Razorpay's bot scans the page.
  static final List<LegalSection> publicTerms = [
    LegalSection(
      heading: 'About Enything',
      content:
          'Enything is a hyper-local marketplace app operated as a sole proprietorship by Muhtaashim Kamran Nazki (Udyam Registration No. UDYAM-JK-02-0019684), based in Bandipora, Jammu & Kashmir, India. We connect Customers with local Sellers and independent Delivery Partners.',
    ),
    ..._stripHeadingNumbers(customerTerms),
  ];

  static final List<LegalSection> publicPrivacy = [
    LegalSection(
      heading: 'About Enything',
      content:
          'Enything is operated by Muhtaashim Kamran Nazki (Udyam No. UDYAM-JK-02-0019684), Plan Bandipora, Ward No. 2, Bandipora, Jammu & Kashmir — 193502, India. Email: support@enything.in.',
    ),
    ..._stripHeadingNumbers(customerPrivacy),
  ];

  static final List<LegalSection> publicRefund = [
    LegalSection(
      heading: 'Overview',
      content:
          'This Refund & Cancellation Policy applies to all users of the Enything platform. Enything is operated by Muhtaashim Kamran Nazki (Udyam No. UDYAM-JK-02-0019684). For refund requests, contact support@enything.in.',
    ),
    ..._stripHeadingNumbers(customerRefund),
  ];

  static List<LegalSection> _stripHeadingNumbers(List<LegalSection> sections) {
    return sections;
  }

  // ─────────────────────────────────────────────────── Accessor Methods ────

  static List<LegalSection> getTerms(String? role) {
    if (role == 'seller') return sellerTerms;
    if (role == 'delivery_partner') return deliveryTerms;
    if (role == null) return publicTerms;
    return customerTerms;
  }

  static List<LegalSection> getPrivacy(String? role) {
    if (role == 'seller') return sellerPrivacy;
    if (role == 'delivery_partner') return deliveryPrivacy;
    if (role == null) return publicPrivacy;
    return customerPrivacy;
  }

  static List<LegalSection> getThirdPolicy(String? role) {
    if (role == 'seller') return sellerRefund;
    if (role == 'delivery_partner') return deliveryRefund;
    if (role == null) return publicRefund;
    return customerRefund;
  }

  static String getThirdPolicyTitle(String? role) {
    if (role == 'seller') return 'Seller Refund & Cancellation Policy';
    if (role == 'delivery_partner') return 'Delivery Partner Conduct & Deactivation Policy';
    return 'Refund & Cancellation Policy';
  }
}
