import 'package:flutter/material.dart';
import 'legal_page.dart';
import '../../constants/legal_constants.dart';

class TermsOfServicePage extends StatelessWidget {
  final String? role;

  const TermsOfServicePage({super.key, this.role});

  @override
  Widget build(BuildContext context) {
    return LegalPage(
      title: 'Terms of Service',
      sections: LegalConstants.getTerms(role),
    );
  }
}
