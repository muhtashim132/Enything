import 'package:flutter/material.dart';
import 'legal_page.dart';
import '../../constants/legal_constants.dart';

class PrivacyPolicyPage extends StatelessWidget {
  final String? role;

  const PrivacyPolicyPage({super.key, this.role});

  @override
  Widget build(BuildContext context) {
    return LegalPage(
      title: 'Privacy Policy',
      sections: LegalConstants.getPrivacy(role),
    );
  }
}
