import 'package:flutter/material.dart';
import 'legal_page.dart';
import '../../constants/legal_constants.dart';

class RefundPolicyPage extends StatelessWidget {
  final String? role;

  const RefundPolicyPage({super.key, this.role});

  @override
  Widget build(BuildContext context) {
    return LegalPage(
      title: LegalConstants.getThirdPolicyTitle(role),
      sections: LegalConstants.getThirdPolicy(role),
    );
  }
}
