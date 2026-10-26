// ============================================================================
// app_version.dart — Centralized Version, Build & Release Metadata
// ============================================================================

class AppVersion {
  static const String appName = 'Enything';
  static const String version = '1.0.7';
  static const int buildNumber = 19;
  static const String releaseDate = '2026-10-27';

  static String get fullVersionString => 'Version $version (Build $buildNumber)';
  static String get displayString => 'v$version';

  /// What's New highlights for release notes and in-app display
  static const List<Map<String, String>> whatsNewHighlights = [
    {
      'icon': '🏬',
      'title': 'Supermart & Multi-Department Schedules',
      'description':
          'Transparent aisle-based commissions (Grocery 6%, Cosmetics 10%, Tech 10%, Produce 5%) with itemized settlement.',
    },
    {
      'icon': '🍏',
      'title': 'Live Activities & Dynamic Island',
      'description':
          'Glanceable real-time order tracking on iOS Lock Screen and Dynamic Island with seamless status transitions.',
    },
    {
      'icon': '🥗',
      'title': 'Dietary Filters & Category Isolation',
      'description':
          'Quick one-tap Veg/Non-Veg discovery for restaurants and groceries with strict prescription safeguards for pharmacy items.',
    },
    {
      'icon': '🕐',
      'title': 'Closed Store Discovery & Operating Hours',
      'description':
          'View upcoming opening times, pre-order from scheduled shops, and browse local stores even when temporarily closed.',
    },
    {
      'icon': '📱',
      'title': 'Modernized Ergonomic Navigation',
      'description':
          'Adaptive bottom navigation bar, edge-to-edge layout, and enhanced memory performance on all devices.',
    },
  ];
}
