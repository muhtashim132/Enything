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

  /// Returns common variant suggestions for a given category.
  static List<String> getSuggestedVariants(String categoryName) {
    switch (categoryName) {
      case 'Clothing':
        return ['XS', 'S', 'M', 'L', 'XL', 'XXL'];
      case 'Footwear':
        return ['UK 6', 'UK 7', 'UK 8', 'UK 9', 'UK 10', 'UK 11'];
      case 'Restaurant':
      case 'Fast Food':
        return ['Half', 'Full', 'Regular', 'Medium', 'Large'];
      case 'Bakery':
      case 'Sweets & Mithai':
        return ['250g', '500g', '1kg', '1 Pound', '2 Pounds'];
      case 'Beverages':
      case 'Tea & Coffee':
      case 'Ice Cream':
        return ['Small', 'Medium', 'Large', 'Single', 'Double'];
      case 'Grocery':
      case 'Supermarket / Hypermarket':
      case 'Organic':
        return ['100g', '250g', '500g', '1kg', '5kg'];
      case 'Dairy & Eggs':
        return ['250ml', '500ml', '1L', 'Half Dozen', '1 Dozen'];
      case 'Butcher':
      case 'Fish & Seafood':
        return ['250g', '500g', '1kg'];
      case 'Pharmacy':
      case 'Medical Store':
        return [
          '1 Strip (10 tabs)',
          '1 Strip (15 tabs)',
          '100ml',
          '200ml',
          '1 Tube'
        ];
      case 'Electronics':
      case 'Mobile & Repair':
        return ['64GB', '128GB', '256GB', '512GB'];
      default:
        return ['Small', 'Large', 'Pack of 1', 'Pack of 2', 'Pack of 5'];
    }
  }

  /// Returns whether a category strictly requires the seller to add variants (e.g. sizes).
  static bool requiresVariant(String categoryName) {
    return categoryName == 'Clothing' || categoryName == 'Footwear';
  }

  /// Returns a high-quality Unsplash image URL for the given category name.
  /// All images are sourced from Unsplash, which is royalty-free and copyright-free.
  static String getImageUrl(String categoryName) {
    const base = 'https://images.unsplash.com/photo-';
    // Forced perfect 600x600 square crop via CDN to ensure flawless UI placement
    const params = '?q=80&w=600&h=600&auto=format&fit=crop';

    switch (categoryName) {
      case 'Supermarket / Hypermarket':
        return '${base}1643107242058-9391a7ba60d3$params';
      case 'Grocery':
        return '${base}1583258292688-d0213dc5a3a8$params';
      case 'Restaurant':
        return '${base}1550966871-3ed3cdb5ed0c$params';
      case 'Fast Food':
        return '${base}1568901346375-23c9450c58cd$params';
      case 'Food':
        return '${base}1568901346375-23c9450c58cd$params'; // Epic, perfectly centered, dripping smashburger
      case 'Bakery':
        return '${base}1509440159596-0249088772ff$params';
      case 'Butcher':
        return '${base}1628543108325-1c27cd7246b3$params';
      case 'Fish & Seafood':
        return '${base}1519708227418-c8fd9a32b7a2$params';
      case 'Dairy & Eggs':
        return '${base}1550583724-b2692b85b150$params';
      case 'Fruits & Vegs':
        return '${base}1610832958506-aa56368176cf$params';
      case 'Sweets & Mithai':
        return '${base}1582716401301-b2407dc7563d$params';
      case 'Beverages':
        return '${base}1513558161293-cdaf765ed2fd$params';
      case 'Pharmacy':
        return '${base}1696861308115-54a5e5a134b0$params';
      case 'Medical Store':
        return '${base}1576602976047-174e57a47881$params';
      case 'Electronics':
        return '${base}1585298723682-7115561c51b7$params';
      case 'Mobile & Repair':
        return '${base}1597740985671-2a8a3b805150$params';
      case 'Clothing':
        return 'https://plus.unsplash.com/premium_photo-1718913936342-eaafff98834b$params';
      case 'Footwear':
        return '${base}1542291026-7eec264c27ff$params';
      case 'Jewellery':
        return '${base}1515562141207-7a88fb7ce338$params';
      case 'Hardware Store':
        return '${base}1581783898377-1c85bf937427$params';
      case 'Stationery':
        return '${base}1513542789411-b6a5d4f31634$params';
      case 'Toys & Games':
        return '${base}1566576912321-d58ddd7a6088$params';
      case 'Sports':
        return '${base}1517649763962-0c623066013b$params';
      case 'Pet Supplies':
        return '${base}1583337130417-3346a1be7dee$params';
      case 'Cosmetics & Beauty':
        return '${base}1522335789203-aabd1fc54c28$params';
      case 'Salon & Beauty':
        return '${base}1527799820374-d64e9a66d03d$params';
      case 'Flowers':
        return '${base}1561181286-d3fee7d55ef6$params';
      case 'Home Decor':
        return '${base}1524758631624-e2822e304c36$params';
      case 'Furniture':
        return '${base}1505691938895-1758d7bef511$params';
      case 'Auto Parts':
        return '${base}1530046339160-ce3e530c7d2f$params';
      case 'Paan Shop':
        return '${base}1596649281783-5ec94a0d9baf$params';
      case 'Tea & Coffee':
        return '${base}1497935586351-b67a49e012bf$params';
      case 'Ice Cream':
        return '${base}1559703248-dcaaec9fac92$params';
      case 'Organic':
        return '${base}1464226184852-09419184df24$params';
      case 'Other':
        return '${base}1472851294608-062f824d29cc$params';
      default:
        return '${base}1472851294608-062f824d29cc$params';
    }
  }
}
