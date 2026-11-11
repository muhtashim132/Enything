// ============================================================================
// app_version.dart — Centralized Version, Build & Release Metadata
// ============================================================================

class AppVersion {
  static const String appName = 'Enything';
  static const String version = '1.0.8';
  static const int buildNumber = 20;
  static const String releaseDate = '2026-11-12';

  static String get fullVersionString => 'Version $version (Build $buildNumber)';
  static String get displayString => 'v$version';

  /// What's New highlights for release notes and in-app display
  static const List<Map<String, String>> whatsNewHighlights = [
    {
      'icon': '🛡️',
      'title': '100x Forensic Stability & Performance',
      'description':
          'Hardened order lifecycle state machine, universal transaction isolation locks, and zero-leak memory management.',
    },
    {
      'icon': '🧾',
      'title': 'Statutory GST & Itemized Tax Compliance',
      'description':
          'Transparent statutory GST breakdowns under Section 9(5), accurate itemized tax slabs, and exact delivery fee calculations.',
    },
    {
      'icon': '📍',
      'title': 'Intelligent Route & Co-Located Clustering',
      'description':
          'Unified multi-merchant pickup stops, sub-5m route caching, and precision navigation with zero compass drift.',
    },
    {
      'icon': '💳',
      'title': '100% Prepaid Model with Zero COD Risk',
      'description':
          'Seamless online UPI and card payments ensuring instantaneous rider earnings and merchant ledger settlement.',
    },
    {
      'icon': '🔍',
      'title': 'Active Salt & Composition Medicine Search',
      'description':
          'Instant discovery for pharmaceuticals by salt composition, brand names, and active ingredients across verified stores.',
    },
  ];
}
