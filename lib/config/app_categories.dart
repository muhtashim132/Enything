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

  /// Customer-friendly description/subtitle for UI category exploration.
  static String getCustomerSubtitle(String categoryName) {
    switch (categoryName) {
      case 'Supermarket / Hypermarket':
        return 'Daily staples, pantry & household';
      case 'Grocery':
        return 'Fresh provisions & daily cooking needs';
      case 'Restaurant':
        return 'Dine-in meals, thalis & specials';
      case 'Fast Food':
        return 'Burgers, pizza, wraps & snacks';
      case 'Bakery':
        return 'Fresh bread, cakes & pastries';
      case 'Butcher':
        return 'Fresh cut chicken, mutton & meats';
      case 'Fish & Seafood':
        return 'Fresh catch, prawns & ocean fish';
      case 'Dairy & Eggs':
        return 'Fresh milk, butter, cheese & eggs';
      case 'Fruits & Vegs':
        return 'Farm-fresh fruits & vegetables';
      case 'Sweets & Mithai':
        return 'Traditional sweets, mithai & desserts';
      case 'Beverages':
        return 'Cold drinks, juices & shakes';
      case 'Pharmacy':
        return 'Medicines, vitamins & healthcare';
      case 'Medical Store':
        return 'Prescription drugs & first aid';
      case 'Electronics':
        return 'Smartphones, audio & accessories';
      case 'Mobile & Repair':
        return 'Phone cases, screen repairs & gadgets';
      case 'Clothing':
        return 'Fashion, ethnic wear & apparel';
      case 'Footwear':
        return 'Shoes, sandals & sneakers';
      case 'Jewellery':
        return 'Gold, silver & fashion jewellery';
      case 'Hardware Store':
        return 'Tools, paints, electricals & fittings';
      case 'Stationery':
        return 'Books, pens, art & office supplies';
      case 'Toys & Games':
        return 'Kids toys, board games & puzzles';
      case 'Sports':
        return 'Fitness gear, bats & sports equipment';
      case 'Pet Supplies':
        return 'Pet food, treats & accessories';
      case 'Cosmetics & Beauty':
        return 'Skincare, makeup & fragrances';
      case 'Salon & Beauty':
        return 'Hair care, grooming & salon products';
      case 'Flowers':
        return 'Fresh bouquets & floral arrangements';
      case 'Home Decor':
        return 'Curtains, lamps, vases & decor';
      case 'Furniture':
        return 'Chairs, tables, shelves & home setup';
      case 'Auto Parts':
        return 'Car & bike spares, oils & accessories';
      case 'Paan Shop':
        return 'Fresh paan, mouth fresheners & snacks';
      case 'Tea & Coffee':
        return 'Chai, coffee beans, premixes & cafe drinks';
      case 'Ice Cream':
        return 'Tubs, sundaes, cones & popsicles';
      case 'Organic':
        return 'Natural organic foods & cold-pressed oils';
      case 'Other':
      default:
        return 'Explore local products & stores';
    }
  }

  /// High-level customer collection groups for category filtering
  static const List<String> customerCollections = [
    'All',
    'Food & Dining',
    'Grocery & Fresh',
    'Pharmacy & Health',
    'Fashion & Lifestyle',
    'Electronics & Utilities',
    'Home & Living',
  ];

  /// Maps a category to its consumer collection
  static String getCustomerCollection(String categoryName) {
    switch (categoryName) {
      case 'Restaurant':
      case 'Fast Food':
      case 'Bakery':
      case 'Sweets & Mithai':
      case 'Tea & Coffee':
      case 'Ice Cream':
      case 'Beverages':
      case 'Paan Shop':
      case 'Food':
        return 'Food & Dining';
      case 'Supermarket / Hypermarket':
      case 'Grocery':
      case 'Fruits & Vegs':
      case 'Dairy & Eggs':
      case 'Butcher':
      case 'Fish & Seafood':
      case 'Organic':
        return 'Grocery & Fresh';
      case 'Pharmacy':
      case 'Medical Store':
        return 'Pharmacy & Health';
      case 'Clothing':
      case 'Footwear':
      case 'Jewellery':
      case 'Cosmetics & Beauty':
      case 'Salon & Beauty':
        return 'Fashion & Lifestyle';
      case 'Electronics':
      case 'Mobile & Repair':
      case 'Hardware Store':
      case 'Stationery':
      case 'Auto Parts':
        return 'Electronics & Utilities';
      case 'Home Decor':
      case 'Furniture':
      case 'Pet Supplies':
      case 'Toys & Games':
      case 'Sports':
      case 'Flowers':
      case 'Other':
      default:
        return 'Home & Living';
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
        return '${base}1607013251379-e6eecfffe234$params';
      case 'Food':
        return '${base}1607013251379-e6eecfffe234$params'; // Ultra close-up dripping gourmet smashburger with melted cheddar and sauce
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
        return '${base}1588508065123-287b28e013da$params';
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
        return '${base}1596462502278-27bfdc403348$params';
      case 'Salon & Beauty':
        return '${base}1560066984-138dadb4c035$params';
      case 'Flowers':
        return '${base}1563241527-3004b7be0ffd$params';
      case 'Home Decor':
        return '${base}1524758631624-e2822e304c36$params';
      case 'Furniture':
        return '${base}1555041469-a586c61ea9bc$params';
      case 'Auto Parts':
        return '${base}1530046339160-ce3e530c7d2f$params';
      case 'Paan Shop':
        return '${base}1615485290382-441e4d049cb5$params';
      case 'Tea & Coffee':
        return '${base}1497935586351-b67a49e012bf$params';
      case 'Ice Cream':
        return '${base}1497034825429-c343d7c6a68f$params';
      case 'Organic':
        return '${base}1542838132-92c53300491e$params';
      case 'More':
        return '${base}1441986300917-64674bd600d8$params';
      case 'Other':
        return '${base}1472851294608-062f824d29cc$params';
      default:
        return '${base}1472851294608-062f824d29cc$params';
    }
  }
}
