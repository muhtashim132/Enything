import '../models/product_model.dart';

/// 100x Universal Intelligent Weight & Dimension Reasoning Engine
///
/// Resolves realistic logistical weight (in Kilograms) for any item across all
/// 34 categories in Enything with zero seller friction, unit sanity guards,
/// multi-pack regex parsing, and variant size scaling.
class WeightEngine {
  /// Resolves the total logistical weight in KG for a given product line item.
  static double resolve({
    required ProductModel product,
    ProductVariant? selectedVariant,
    int quantity = 1,
  }) {
    if (quantity <= 0) return 0.0;

    // ── Tier 1: Explicit Seller Weight Input & Unit Conversion ─────────────
    if (product.weightPerUnit != null && product.weightPerUnit! > 0) {
      final explicitKg = _normalizeExplicitWeight(
        product.weightPerUnit!,
        product.unitType,
        product.category,
      );
      if (explicitKg != null && explicitKg > 0) {
        return (explicitKg * quantity).clamp(0.001, 100.0);
      }
    }

    // ── Tier 2: Multi-Pack & Embedded Quantity Parser ───────────────────────
    final packMultiplier = _extractPackMultiplier(product.name);

    // Check if weight is explicitly embedded in product name (e.g. "Basmati Rice 5kg")
    final titleWeight = _extractWeightFromTitle(product.name);
    if (titleWeight != null && titleWeight > 0) {
      return (titleWeight * packMultiplier * quantity).clamp(0.001, 100.0);
    }

    // ── Tier 3: 34-Category Domain Heuristics Matrix ────────────────────────
    double baseWeightKg = _categoryBaselineKg(
      product.category,
      product.subCategory,
      product.name,
      product.description,
    );

    // ── Tier 4: Variant Size & Multiplier Scaling ───────────────────────────
    if (selectedVariant != null) {
      baseWeightKg *= _variantScalingFactor(selectedVariant.name);
    }

    final totalWeight = baseWeightKg * packMultiplier * quantity;
    return totalWeight.clamp(0.005, 100.0);
  }

  // ---------------------------------------------------------------------------
  // Tier 1: Unit Normalization & Sanity Guards
  // ---------------------------------------------------------------------------

  static double? _normalizeExplicitWeight(
    double rawWeight,
    String unitType,
    String category,
  ) {
    final unit = unitType.toLowerCase().trim();

    double weightKg;
    switch (unit) {
      case 'kg':
      case 'kilogram':
      case 'kilograms':
        weightKg = rawWeight;
        break;
      case 'g':
      case 'gm':
      case 'gram':
      case 'grams':
        weightKg = rawWeight / 1000.0;
        break;
      case 'mg':
      case 'milligram':
      case 'milligrams':
        weightKg = rawWeight / 1000000.0;
        break;
      case 'l':
      case 'ltr':
      case 'liter':
      case 'liters':
      case 'litre':
      case 'litres':
        weightKg = rawWeight * 1.02; // Avg liquid density ~1.02 kg/L
        break;
      case 'ml':
      case 'milliliter':
      case 'milliliters':
        weightKg = (rawWeight / 1000.0) * 1.02;
        break;
      case 'pieces':
      case 'piece':
      case 'pcs':
      case 'pc':
      default:
        // If unit is pieces or generic, and raw weight is > 0, evaluate if it's already in grams or kg
        if (category == 'Clothing' ||
            category == 'Footwear' ||
            category == 'Electronics') {
          if (rawWeight > 25.0) {
            // E.g. seller typed 650 with 'pieces' or 'kg' meaning 650 grams
            weightKg = rawWeight / 1000.0;
          } else {
            weightKg = rawWeight;
          }
        } else {
          weightKg = rawWeight <= 20.0 ? rawWeight : rawWeight / 1000.0;
        }
        break;
    }

    // Sanity Guard: Auto-correct absurd apparel / pharmacy inputs
    if ((category == 'Clothing' || category == 'Pharmacy') &&
        weightKg > 20.0) {
      weightKg = weightKg / 1000.0;
    }

    return weightKg;
  }

  // ---------------------------------------------------------------------------
  // Tier 2: Title Regex Parsing (Multi-Packs & Embedded Weights)
  // ---------------------------------------------------------------------------

  static final RegExp _packRegex = RegExp(
    r'(?:pack\s*of|pack|combo\s*of|set\s*of|\bpack\b|\bbox\s*of)\s*[:\-]?\s*(\d+)',
    caseSensitive: false,
  );

  static int _extractPackMultiplier(String name) {
    final match = _packRegex.firstMatch(name);
    if (match != null) {
      final count = int.tryParse(match.group(1) ?? '1');
      if (count != null && count > 1 && count <= 50) {
        return count;
      }
    }
    return 1;
  }

  static final RegExp _titleWeightRegex = RegExp(
    r'(\d+(?:\.\d+)?)\s*(kg|g|gm|grams|l|ltr|liters|ml)\b',
    caseSensitive: false,
  );

  static double? _extractWeightFromTitle(String name) {
    final match = _titleWeightRegex.firstMatch(name);
    if (match != null) {
      final val = double.tryParse(match.group(1) ?? '');
      final unit = (match.group(2) ?? '').toLowerCase();
      if (val != null && val > 0) {
        if (unit == 'kg') return val;
        if (unit == 'g' || unit == 'gm' || unit == 'grams') return val / 1000.0;
        if (unit == 'l' || unit == 'ltr' || unit == 'liters') return val * 1.02;
        if (unit == 'ml') return (val / 1000.0) * 1.02;
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Tier 3: Comprehensive 34-Category Domain Heuristics Matrix
  // ---------------------------------------------------------------------------

  static double _categoryBaselineKg(
    String category,
    String? subCategory,
    String name,
    String? description,
  ) {
    final n = name.toLowerCase();
    final sub = (subCategory ?? '').toLowerCase();
    final desc = (description ?? '').toLowerCase();

    switch (category) {
      // ── 1. Clothing / Apparel ──────────────────────────────────────────────
      case 'Clothing':
        if (n.contains('jean') ||
            n.contains('denim') ||
            sub.contains('jean') ||
            desc.contains('jeans')) {
          if (n.contains('kid') || n.contains('boy') || n.contains('girl')) {
            return 0.33; // Kids denim ~330g
          }
          if (n.contains('heavy') ||
              n.contains('raw') ||
              n.contains('winter') ||
              n.contains('selvedge')) {
            return 0.95; // Heavyweight raw denim ~950g
          }
          return 0.65; // Standard 1 piece jeans pants = 650g
        }
        if (n.contains('jacket') ||
            n.contains('coat') ||
            n.contains('blazer') ||
            n.contains('puffer')) {
          return 1.10;
        }
        if (n.contains('hoodie') ||
            n.contains('sweatshirt') ||
            n.contains('sweater')) {
          return 0.55;
        }
        if (n.contains('shirt') && !n.contains('t-shirt')) {
          return 0.25;
        }
        if (n.contains('t-shirt') || n.contains('tee') || n.contains('polo')) {
          return 0.18;
        }
        if (n.contains('trouser') ||
            n.contains('pant') ||
            n.contains('chino') ||
            n.contains('cargo')) {
          return 0.45;
        }
        if (n.contains('short') ||
            n.contains('boxer') ||
            n.contains('brief') ||
            n.contains('underwear') ||
            n.contains('sock')) {
          return 0.10;
        }
        if (n.contains('saree') ||
            n.contains('lehenga') ||
            n.contains('ethnic') ||
            n.contains('kurta')) {
          return 0.70;
        }
        return 0.40; // Default apparel fallback

      // ── 2. Footwear ────────────────────────────────────────────────────────
      case 'Footwear':
        if (n.contains('boot')) return 1.40;
        if (n.contains('slipper') ||
            n.contains('flip') ||
            n.contains('sandal')) {
          return 0.35;
        }
        return 0.90; // Standard sneakers / formal shoes with box = 900g

      // ── 3. Pharmacy & Medical ──────────────────────────────────────────────
      case 'Pharmacy':
      case 'Medical Store':
        if (n.contains('syrup') ||
            n.contains('suspension') ||
            n.contains('tonic') ||
            n.contains('drop')) {
          return 0.18;
        }
        if (n.contains('cream') ||
            n.contains('ointment') ||
            n.contains('gel') ||
            n.contains('tube')) {
          return 0.05;
        }
        if (n.contains('diaper') ||
            n.contains('sanitary') ||
            n.contains('pad') ||
            n.contains('wipe')) {
          return 0.65;
        }
        if (n.contains('device') ||
            n.contains('bp') ||
            n.contains('oximeter') ||
            n.contains('thermometer')) {
          return 0.28;
        }
        return 0.02; // Standard 1 strip (10 tablets/capsules) = 20g

      // ── 4. Food & Restaurant ───────────────────────────────────────────────
      case 'Restaurant':
      case 'Fast Food':
      case 'Food':
        if (n.contains('pizza')) {
          if (n.contains('large')) return 0.75;
          if (n.contains('medium')) return 0.55;
          return 0.35;
        }
        if (n.contains('burger') ||
            n.contains('sandwich') ||
            n.contains('wrap') ||
            n.contains('roll')) {
          return 0.25;
        }
        if (n.contains('biryani') ||
            n.contains('rice') ||
            n.contains('noodle')) {
          return 0.60;
        }
        if (n.contains('curry') ||
            n.contains('gravy') ||
            n.contains('dal') ||
            n.contains('soup')) {
          return 0.38;
        }
        if (n.contains('roti') || n.contains('naan') || n.contains('paratha')) {
          return 0.08;
        }
        return 0.35; // Default meal portion

      // ── 5. Bakery & Sweets ─────────────────────────────────────────────────
      case 'Bakery':
        if (n.contains('cake')) {
          if (n.contains('2') || n.contains('kg')) return 1.0;
          return 0.50; // 1 pound cake ~500g
        }
        if (n.contains('bread') || n.contains('loaf')) return 0.40;
        if (n.contains('pastry') ||
            n.contains('muffin') ||
            n.contains('cookie')) {
          return 0.12;
        }
        return 0.30;

      case 'Sweets & Mithai':
        return 0.50; // Standard mithai box = 500g

      // ── 6. Beverages, Tea, Coffee & Ice Cream ──────────────────────────────
      case 'Beverages':
      case 'Tea & Coffee':
        if (n.contains('1l') || n.contains('1.5l') || n.contains('2l')) {
          return 1.20;
        }
        if (n.contains('large')) return 0.45;
        if (n.contains('small')) return 0.20;
        return 0.32; // Regular beverage ~320g

      case 'Ice Cream':
        if (n.contains('tub') ||
            n.contains('brick') ||
            n.contains('family') ||
            n.contains('700ml')) {
          return 0.55;
        }
        return 0.10; // Cone/Cup/Stick ~100g

      // ── 7. Perishables & Groceries ─────────────────────────────────────────
      case 'Dairy & Eggs':
        if (n.contains('egg')) {
          if (n.contains('12') || n.contains('dozen')) return 0.70;
          if (n.contains('6') || n.contains('half')) return 0.35;
          return 0.50;
        }
        if (n.contains('milk') || n.contains('curd') || n.contains('dahi')) {
          if (n.contains('1l') || n.contains('1 l')) return 1.03;
          return 0.52;
        }
        if (n.contains('paneer') ||
            n.contains('cheese') ||
            n.contains('butter')) {
          return 0.22;
        }
        return 0.50;

      case 'Grocery':
      case 'Supermarket / Hypermarket':
      case 'Organic':
        if (n.contains('rice') || n.contains('atta') || n.contains('flour')) {
          if (n.contains('5kg') || n.contains('5 kg')) return 5.0;
          if (n.contains('10kg')) return 10.0;
          return 1.0;
        }
        if (n.contains('oil') || n.contains('ghee')) {
          if (n.contains('5l')) return 4.6;
          return 0.95;
        }
        if (n.contains('biscuit') || n.contains('noodle') || n.contains('chip')) {
          return 0.12;
        }
        return 0.50;

      case 'Fruits & Vegs':
        return 0.80; // Standard produce basket ~800g

      case 'Butcher':
      case 'Fish & Seafood':
        return 0.50; // Standard cut ~500g

      // ── 8. Electronics & Mobile ────────────────────────────────────────────
      case 'Electronics':
      case 'Mobile & Repair':
        if (n.contains('laptop') || n.contains('macbook')) return 2.40;
        if (n.contains('phone') || n.contains('mobile') || n.contains('iphone')) {
          return 0.45; // Phone + retail box
        }
        if (n.contains('earphone') ||
            n.contains('airpod') ||
            n.contains('tws') ||
            n.contains('cable') ||
            n.contains('case')) {
          return 0.12;
        }
        if (n.contains('powerbank')) return 0.38;
        if (n.contains('speaker')) return 0.80;
        return 0.50;

      // ── 9. Other Lifestyle & Retail ────────────────────────────────────────
      case 'Jewellery':
        return 0.08; // 80g with luxury box

      case 'Hardware Store':
        if (n.contains('hammer') ||
            n.contains('drill') ||
            n.contains('wrench') ||
            n.contains('saw')) {
          return 1.40;
        }
        if (n.contains('tape') ||
            n.contains('bulb') ||
            n.contains('screw') ||
            n.contains('plug')) {
          return 0.15;
        }
        return 0.60;

      case 'Stationery':
        if (n.contains('pen') || n.contains('pencil') || n.contains('eraser')) {
          return 0.06;
        }
        if (n.contains('register') || n.contains('book')) return 0.40;
        if (n.contains('notebook') || n.contains('diary')) return 0.22;
        return 0.20;

      case 'Toys & Games':
        if (n.contains('board') || n.contains('puzzle')) return 0.70;
        return 0.40;

      case 'Sports':
        if (n.contains('bat') || n.contains('racket')) return 1.10;
        if (n.contains('ball')) return 0.45;
        return 0.65;

      case 'Pet Supplies':
        if (n.contains('food')) return 1.20;
        return 0.35;

      case 'Cosmetics & Beauty':
      case 'Salon & Beauty':
        if (n.contains('shampoo') ||
            n.contains('lotion') ||
            n.contains('wash')) {
          return 0.38;
        }
        if (n.contains('lipstick') ||
            n.contains('mascara') ||
            n.contains('kajal')) {
          return 0.04;
        }
        return 0.15;

      case 'Flowers':
        return 0.30; // Bouquet ~300g

      case 'Home Decor':
      case 'Furniture':
        if (n.contains('sheet') || n.contains('curtain')) return 0.85;
        return 0.75;

      case 'Auto Parts':
        if (n.contains('oil')) return 0.95;
        return 0.45;

      case 'Paan Shop':
        return 0.03; // 30g

      default:
        return 0.40; // Universal fallback
    }
  }

  // ---------------------------------------------------------------------------
  // Tier 4: Variant Size & Portion Scaling Factor
  // ---------------------------------------------------------------------------

  static double _variantScalingFactor(String variantName) {
    final v = variantName.toUpperCase().trim();

    // Food Portions
    if (v.contains('HALF') || v.contains('SMALL') || v.contains('SINGLE')) {
      return 0.60;
    }
    if (v.contains('FULL') || v.contains('LARGE') || v.contains('DOUBLE')) {
      return 1.40;
    }
    if (v.contains('MEDIUM') || v.contains('REGULAR')) {
      return 1.0;
    }

    // Weight/Volume in Variant Name (e.g. "250g", "1kg", "500ml")
    final variantWeight = _extractWeightFromTitle(variantName);
    if (variantWeight != null && variantWeight > 0) {
      // Direct proportion factor against standard 500g baseline
      return variantWeight / 0.50;
    }

    // Apparel Sizes
    if (v.contains('XXS') ||
        v.contains('XS') ||
        v.contains('26') ||
        v.contains('28')) {
      return 0.88;
    }
    if (v.contains('XXL') ||
        v.contains('2XL') ||
        v.contains('3XL') ||
        v.contains('4XL') ||
        v.contains('38') ||
        v.contains('40') ||
        v.contains('42')) {
      return 1.18;
    }
    if (v.contains('XL') || v.contains('36')) return 1.08;
    if (v.contains('S') || v.contains('30')) return 0.94;
    if (v.contains('M') ||
        v.contains('L') ||
        v.contains('32') ||
        v.contains('34')) {
      return 1.00;
    }

    return 1.0;
  }
}
