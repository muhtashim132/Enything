// Centralised list of business categories used across the app.
// Update this one file and the change propagates everywhere.

/// Broad bucket a category falls into — determines the extra fields
/// shown during seller sign-up.
enum CategoryGroup {
  food, // Prepared / packaged food — needs FSSAI + food type
  pharmacy, // Medicine — needs Drug Licence
  perishable, // Raw meat / fish / dairy — needs FSSAI + cutoff time
  retail, // General retail — needs GST + return policy
}

class AppCategories {
  static const List<Map<String, String>> all = [
    {'name': 'Supermarket / Hypermarket', 'emoji': '🏬'},
    {'name': 'Grocery', 'emoji': '🛒'},
    {'name': 'Restaurant', 'emoji': '🍽️'},
    {'name': 'Fast Food', 'emoji': '🍔'},
    {'name': 'Bakery', 'emoji': '🥖'},
    {'name': 'Butcher', 'emoji': '🥩'},
    {'name': 'Fish & Seafood', 'emoji': '🐟'},
    {'name': 'Dairy & Eggs', 'emoji': '🥛'},
    {'name': 'Fruits & Vegs', 'emoji': '🥬'},
    {'name': 'Sweets & Mithai', 'emoji': '🍬'},
    {'name': 'Beverages', 'emoji': '🧃'},
    {'name': 'Pharmacy', 'emoji': '💊'},
    {'name': 'Medical Store', 'emoji': '🏥'},
    {'name': 'Electronics', 'emoji': '📱'},
    {'name': 'Mobile & Repair', 'emoji': '🔧'},
    {'name': 'Clothing', 'emoji': '👕'},
    {'name': 'Footwear', 'emoji': '👟'},
    {'name': 'Jewellery', 'emoji': '💍'},
    {'name': 'Hardware Store', 'emoji': '🔨'},
    {'name': 'Stationery', 'emoji': '📚'},
    {'name': 'Toys & Games', 'emoji': '🧸'},
    {'name': 'Sports', 'emoji': '⚽'},
    {'name': 'Pet Supplies', 'emoji': '🐾'},
    {'name': 'Cosmetics & Beauty', 'emoji': '💄'},
    {'name': 'Salon & Beauty', 'emoji': '💇'},
    {'name': 'Flowers', 'emoji': '🌸'},
    {'name': 'Home Decor', 'emoji': '🏠'},
    {'name': 'Furniture', 'emoji': '🛋️'},
    {'name': 'Auto Parts', 'emoji': '🚗'},
    {'name': 'Paan Shop', 'emoji': '🌿'},
    {'name': 'Tea & Coffee', 'emoji': '☕'},
    {'name': 'Ice Cream', 'emoji': '🍦'},
    {'name': 'Organic', 'emoji': '🌱'},
    {'name': 'Other', 'emoji': '🏪'},
  ];

  // ── Group mapping ──────────────────────────────────────────────────────────

  static const Map<String, CategoryGroup> _groupMap = {
    // Food group
    'Restaurant': CategoryGroup.food,
    'Fast Food': CategoryGroup.food,
    'Bakery': CategoryGroup.food,
    'Sweets & Mithai': CategoryGroup.food,
    'Tea & Coffee': CategoryGroup.food,
    'Ice Cream': CategoryGroup.food,
    'Paan Shop': CategoryGroup.food,
    'Beverages': CategoryGroup.food,

    // Pharmacy group
    'Pharmacy': CategoryGroup.pharmacy,
    'Medical Store': CategoryGroup.pharmacy,

    // Perishable group
    'Supermarket / Hypermarket': CategoryGroup.perishable,
    'Butcher': CategoryGroup.perishable,
    'Fish & Seafood': CategoryGroup.perishable,
    'Dairy & Eggs': CategoryGroup.perishable,
    'Fruits & Vegs': CategoryGroup.perishable,
    'Grocery': CategoryGroup.perishable,
    'Organic': CategoryGroup.perishable,
  };

  /// Returns the group for [categoryName]. Defaults to [CategoryGroup.retail].
  static CategoryGroup groupFor(String categoryName) =>
      _groupMap[categoryName] ?? CategoryGroup.retail;

  /// Human-readable label and description for each group (used in UI hints).
  static Map<String, String> groupInfo(CategoryGroup group) {
    switch (group) {
      case CategoryGroup.food:
        return {
          'label': 'Food & Beverages',
          'hint': 'Requires FSSAI licence & food-type declaration',
          'emoji': '🍽️',
        };
      case CategoryGroup.pharmacy:
        return {
          'label': 'Pharmacy / Medical',
          'hint': 'Requires Drug Licence & registered pharmacist details',
          'emoji': '💊',
        };
      case CategoryGroup.perishable:
        return {
          'label': 'Fresh / Perishable',
          'hint': 'Requires FSSAI licence & daily order cut-off time',
          'emoji': '🥬',
        };
      case CategoryGroup.retail:
        return {
          'label': 'General Retail',
          'hint': 'GST number & return policy',
          'emoji': '🏪',
        };
    }
  }

  /// Flat list of category names (for Supabase queries / dropdowns).
  static List<String> get names => all.map((c) => c['name']!).toList();
}
