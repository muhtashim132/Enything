// ============================================================================
// app_version.dart — Centralized Version, Build & Release Metadata
// ============================================================================

class AppVersion {
  static const String appName = 'Enything';
  static const String version = '1.0.6';
  static const int buildNumber = 17;
  static const String releaseDate = '2026-09-30';

  static String get fullVersionString => 'Version $version (Build $buildNumber)';
  static String get displayString => 'v$version';

  /// What's New highlights for release notes and in-app display
  static const List<Map<String, String>> whatsNewHighlights = [
    {
      'icon': '⚡',
      'title': '100% Prepaid Zero-Friction Checkout',
      'description':
          'Instant online payments via UPI, Google Pay, PhonePe, and Cards with zero doorstep cash hassle.',
    },
    {
      'icon': '🗺️',
      'title': 'Master Multi-Stop Realtime Routing',
      'description':
          'Optimized nearest-neighbor GPS routing for seamless multi-shop pickups and stacked doorstep deliveries.',
    },
    {
      'icon': '🛡️',
      'title': 'Forensic Edge-Case Reliability',
      'description':
          'Hardened empty cart, address validation, coupon protections, and dynamic store availability.',
    },
    {
      'icon': '🏪',
      'title': 'Enhanced Merchant & Rider Dashboards',
      'description':
          'Live rider arrival countdowns, instant order alerts, and automatic capacity management.',
    },
    {
      'icon': '✨',
      'title': 'Performance & Smooth Animations',
      'description':
          'Polished iOS transitions, reduced battery consumption during live tracking, and instant UI updates.',
    },
  ];
}
