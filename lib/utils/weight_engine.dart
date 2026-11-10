import '../models/product_model.dart';

/// 100x Universal Intelligent Weight & Dimension Reasoning Engine
///
/// Resolves realistic logistical weight (in Kilograms) for any item across all
/// 35 categories in Enything with zero seller friction, unit sanity guards,
/// multi-pack regex parsing, variant size scaling, and direct weight overrides.
class WeightEngine {
  /// Resolves the unit logistical weight in Kilograms for 1 unit/serving of the item.
  static double resolveUnit({
    required ProductModel product,
    ProductVariant? selectedVariant,
  }) {
    final packMultiplier = _extractPackMultiplier(product.name);

    // ── Tier 1: Explicit Seller Weight Input & Unit Conversion ─────────────
    if (product.weightPerUnit != null && product.weightPerUnit! > 0) {
      final explicitKg = _normalizeExplicitWeight(
        product.weightPerUnit!,
        product.unitType,
        product.category,
      );
      if (explicitKg != null && explicitKg > 0) {
        // If the selected variant specifies an explicit weight in its title (e.g. variant "1kg"),
        // the variant's weight directly overrides the product's base weight:
        if (selectedVariant != null) {
          final vWeight = _extractWeightFromTitle(selectedVariant.name, product.category);
          if (vWeight != null && vWeight > 0) {
            return (vWeight * packMultiplier).clamp(0.0001, 100.0);
          }
          final factor = _variantPortionOrSizeFactor(selectedVariant.name);
          return (explicitKg * factor * packMultiplier).clamp(0.0001, 100.0);
        }
        return (explicitKg * packMultiplier).clamp(0.0001, 100.0);
      }
    }

    // ── Tier 2: Check if variant itself has explicit weight (e.g. "250g", "1 Litre")
    if (selectedVariant != null) {
      final vWeight = _extractWeightFromTitle(selectedVariant.name, product.category);
      if (vWeight != null && vWeight > 0) {
        return (vWeight * packMultiplier).clamp(0.001, 100.0);
      }
    }

    // ── Tier 2: Embedded weight in product title (e.g. "Basmati Rice 5kg") ──
    final titleWeight = _extractWeightFromTitle(product.name, product.category);
    if (titleWeight != null && titleWeight > 0) {
      double weight = titleWeight * packMultiplier;
      if (selectedVariant != null) {
        weight *= _variantPortionOrSizeFactor(selectedVariant.name);
      }
      return weight.clamp(0.001, 100.0);
    }

    // ── Tier 3: 35-Category Domain Heuristics Matrix ────────────────────────
    double baseWeightKg = _categoryBaselineKg(
      product.category,
      product.subCategory,
      product.name,
      product.description,
    );

    // ── Tier 4: Variant Size & Multiplier Scaling ───────────────────────────
    if (selectedVariant != null) {
      baseWeightKg *= _variantPortionOrSizeFactor(selectedVariant.name);
    }

    final totalUnitWeight = baseWeightKg * packMultiplier;
    return totalUnitWeight.clamp(0.005, 100.0);
  }

  /// Resolves the total logistical weight in KG for a given product line item.
  static double resolve({
    required ProductModel product,
    ProductVariant? selectedVariant,
    int quantity = 1,
  }) {
    if (quantity <= 0) return 0.0;
    final unitWeight = resolveUnit(product: product, selectedVariant: selectedVariant);
    return (unitWeight * quantity).clamp(0.005, 500.0);
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
    final cat = category.toLowerCase().trim();

    double weightKg;
    switch (unit) {
      case 'kg':
      case 'kilogram':
      case 'kilograms':
      case 'kgs':
        weightKg = rawWeight;
        break;
      case 'g':
      case 'gm':
      case 'gms':
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
      case 'millilitre':
      case 'millilitres':
        weightKg = (rawWeight / 1000.0) * 1.02;
        break;
      case 'pieces':
      case 'piece':
      case 'pcs':
      case 'pc':
      default:
        // If unit is pieces or generic, and raw weight is > 0, evaluate if it's already in grams or kg
        if (cat.contains('clothing') ||
            cat.contains('footwear') ||
            cat.contains('electronic')) {
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

    // Sanity Guard: Auto-correct absurd apparel, pharmacy, or cosmetic inputs
    if ((cat.contains('clothing') ||
            cat.contains('pharmacy') ||
            cat.contains('cosmetic') ||
            cat.contains('salon')) &&
        weightKg > 20.0) {
      weightKg = weightKg / 1000.0;
    }

    return weightKg;
  }

  // ---------------------------------------------------------------------------
  // Tier 2: Title Regex Parsing (Multi-Packs & Embedded Weights)
  // ---------------------------------------------------------------------------

  // Handles:
  // "Pack of 3", "Box of 10", "Combo of 2"
  // "2-Pack", "3-pack", "6 Pack", "2 Pack"
  // "2x500g", "2 x 500g"
  // "Buy 1 Get 1", "BOGO", "1+1 Free"
  static final RegExp _packOfRegex = RegExp(
    r'(?:pack\s*of|combo\s*of|set\s*of|\bpack\b|\bbox\s*of)\s*[:\-]?\s*(\d+)',
    caseSensitive: false,
  );

  static final RegExp _prefixPackRegex = RegExp(
    r'\b(\d+)\s*[- ]?(?:pack|combo|set|box|pcs|pieces)\b',
    caseSensitive: false,
  );

  static final RegExp _multiplierXRegex = RegExp(
    r'\b(\d+)\s*[xX]\s*\d+\s*(?:g|kg|ml|l|gm)\b',
    caseSensitive: false,
  );

  static final RegExp _bogoRegex = RegExp(
    r'\b(?:buy\s*1\s*get\s*1|bogo|1\s*\+\s*1|2\s*\+\s*1)\b',
    caseSensitive: false,
  );

  static int _extractPackMultiplier(String name) {
    // Check BOGO / 1+1
    if (_bogoRegex.hasMatch(name)) {
      if (name.toLowerCase().contains('2+1')) return 3;
      return 2;
    }

    // Check "2x500g"
    final matchX = _multiplierXRegex.firstMatch(name);
    if (matchX != null) {
      final count = int.tryParse(matchX.group(1) ?? '1');
      if (count != null && count > 1 && count <= 50) return count;
    }

    // Check "Pack of 3"
    final matchOf = _packOfRegex.firstMatch(name);
    if (matchOf != null) {
      final count = int.tryParse(matchOf.group(1) ?? '1');
      if (count != null && count > 1 && count <= 50) return count;
    }

    // Check "3-Pack" / "6 Pack"
    final matchPrefix = _prefixPackRegex.firstMatch(name);
    if (matchPrefix != null) {
      final count = int.tryParse(matchPrefix.group(1) ?? '1');
      if (count != null && count > 1 && count <= 50) return count;
    }

    return 1;
  }

  static final RegExp _titleWeightRegex = RegExp(
    r'(\d+(?:\.\d+)?)\s*(kg|g|gm|grams|l|ltr|liters|litres|litre|ml)\b',
    caseSensitive: false,
  );

  static double? _extractWeightFromTitle(String name, [String? category]) {
    final cat = (category ?? '').toLowerCase().trim();
    final matches = _titleWeightRegex.allMatches(name);

    for (final match in matches) {
      final rawVal = match.group(1) ?? '';
      final val = double.tryParse(rawVal);
      final unit = (match.group(2) ?? '').toLowerCase();

      if (val != null && val > 0) {
        // 100x FORENSIC GUARD: Exclude cellular network "5G", "4G", "3G", "2G" from matching as grams!
        if (unit == 'g') {
          // If in Electronics/Mobile or title contains phone/mobile/device indicators, "5G" and "4G" are telecom standards:
          final isTechContext = cat.contains('electronic') ||
              cat.contains('mobile') ||
              name.toLowerCase().contains('phone') ||
              name.toLowerCase().contains('smartphone') ||
              name.toLowerCase().contains('realme') ||
              name.toLowerCase().contains('redmi') ||
              name.toLowerCase().contains('oneplus') ||
              name.toLowerCase().contains('samsung') ||
              name.toLowerCase().contains('apple') ||
              name.toLowerCase().contains('motorola') ||
              name.toLowerCase().contains('sim') ||
              name.toLowerCase().contains('network');

          if ((val == 5.0 || val == 4.0 || val == 3.0 || val == 2.0) && isTechContext) {
            continue; // Skip false 5G/4G match
          }

          // Check if followed immediately by 'b' (as in 'gb') or 'hz' (as in 'ghz')
          final fullMatchEnd = match.end;
          if (fullMatchEnd < name.length) {
            final nextChar = name[fullMatchEnd].toLowerCase();
            if (nextChar == 'b' || nextChar == 'h') {
              continue; // 128GB, 2.4GHz
            }
          }
        }

        if (unit == 'kg') return val;
        if (unit == 'g' || unit == 'gm' || unit == 'grams') return val / 1000.0;
        if (unit == 'l' || unit == 'ltr' || unit == 'liters' || unit == 'litres' || unit == 'litre') {
          return val * 1.02;
        }
        if (unit == 'ml') {
          final liquidKg = (val / 1000.0) * 1.02;
          if ((cat.contains('cosmetic') || cat.contains('beauty')) &&
              (name.toLowerCase().contains('perfume') ||
                  name.toLowerCase().contains('parfum') ||
                  name.toLowerCase().contains('eau de') ||
                  name.toLowerCase().contains('cologne'))) {
            return liquidKg + 0.18; // Glass bottle + cap tare weight
          }
          return liquidKg;
        }
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Tier 3: Comprehensive 35-Category Domain Heuristics Matrix
  // ---------------------------------------------------------------------------

  static double _categoryBaselineKg(
    String category,
    String? subCategory,
    String name,
    String? description,
  ) {
    final cat = category.trim().toLowerCase();
    final n = name.toLowerCase();
    final sub = (subCategory ?? '').toLowerCase();
    final desc = (description ?? '').toLowerCase();

    // ── 1. Clothing / Apparel ────────────────────────────────────────────────
    if (cat.contains('clothing') || cat.contains('apparel') || cat.contains('fashion')) {
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
        return 0.08;
      }
      if (n.contains('saree') ||
          n.contains('lehenga') ||
          n.contains('ethnic') ||
          n.contains('kurta')) {
        return 0.70;
      }
      return 0.40; // Default apparel fallback
    }

    // ── 2. Footwear ──────────────────────────────────────────────────────────
    if (cat.contains('footwear') || cat.contains('shoes')) {
      if (n.contains('boot')) return 1.40;
      if (n.contains('slipper') ||
          n.contains('flip') ||
          n.contains('sandal')) {
        return 0.35;
      }
      return 0.90; // Standard sneakers / formal shoes with box = 900g
    }

    // ── 3. Pharmacy & Medical ────────────────────────────────────────────────
    if (cat.contains('pharmacy') || cat.contains('medical')) {
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
    }

    // ── 4. Food & Restaurant ─────────────────────────────────────────────────
    if (cat.contains('restaurant') ||
        cat.contains('fast food') ||
        cat == 'food' ||
        cat.contains('dining') ||
        cat.contains('cafe')) {
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
    }

    // ── 5. Bakery & Sweets ───────────────────────────────────────────────────
    if (cat.contains('bakery')) {
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
    }

    if (cat.contains('sweets') || cat.contains('mithai')) {
      if (n.contains('piece') || n.contains('single') || n.contains('rasgulla')) {
        return 0.06;
      }
      return 0.50; // Standard mithai box = 500g
    }

    // ── 6. Beverages, Tea, Coffee & Ice Cream ────────────────────────────────
    if (cat.contains('beverage') || cat.contains('tea') || cat.contains('coffee')) {
      if (n.contains('1l') || n.contains('1.5l') || n.contains('2l')) {
        return 1.20;
      }
      if (n.contains('large')) return 0.45;
      if (n.contains('small')) return 0.20;
      return 0.32; // Regular beverage ~320g
    }

    if (cat.contains('ice cream')) {
      if (n.contains('tub') ||
          n.contains('brick') ||
          n.contains('family') ||
          n.contains('700ml') ||
          n.contains('1l')) {
        return 0.55;
      }
      return 0.10; // Cone/Cup/Stick ~100g
    }

    // ── 7. Perishables, Supermarket & Groceries (INCL. Grocerylm) ────────────
    if (cat.contains('dairy') || cat.contains('eggs')) {
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
    }

    // 100x PARITY: Explicitly handle Grocery, Grocerylm, Supermarket / Hypermarket, and Organic
    if (cat.contains('grocery') ||
        cat.contains('supermarket') ||
        cat.contains('hypermarket') ||
        cat.contains('organic')) {
      // Staples
      if (n.contains('rice') || n.contains('atta') || n.contains('flour') || n.contains('dal')) {
        if (n.contains('5kg') || n.contains('5 kg')) return 5.0;
        if (n.contains('10kg') || n.contains('10 kg')) return 10.0;
        return 1.0;
      }
      // Cooking oils
      if (n.contains('oil') || n.contains('ghee')) {
        if (n.contains('5l') || n.contains('5 l')) return 4.6;
        return 0.95;
      }
      // Chewing gums, candy rolls, mints (Trident, Boomer, Mentos, Fruit-tella, Center Fresh, Orbit)
      if (n.contains('gum') ||
          n.contains('chew') ||
          n.contains('mentos') ||
          n.contains('dragee') ||
          n.contains('fruit-tella') ||
          n.contains('fruittella') ||
          n.contains('mint') ||
          n.contains('candy') ||
          n.contains('lollipop') ||
          n.contains('lozenge') ||
          n.contains('chupa')) {
        return 0.035; // 35g for roll/pack
      }
      // Sachets (masala, shampoo, conditioner, eno)
      if (n.contains('sachet') || n.contains('eno') || n.contains('maggi masala')) {
        return 0.015;
      }
      // Biscuits, noodles, chips, chocolates
      if (n.contains('chocolate') || n.contains('bar')) return 0.05;
      if (n.contains('biscuit') || n.contains('noodle') || n.contains('chip') || n.contains('wafer')) {
        return 0.12;
      }
      // Soap bars & toothpastes
      if (n.contains('soap') || n.contains('bar')) return 0.125;
      if (n.contains('toothpaste') || n.contains('paste') || n.contains('colgate')) return 0.15;
      // Spices & condiments
      if (n.contains('masala') || n.contains('chilli powder') || n.contains('turmeric') || n.contains('spice')) {
        return 0.10;
      }
      if (n.contains('ketchup') || n.contains('sauce') || n.contains('jam') || n.contains('spread')) {
        return 0.45;
      }
      return 0.35; // Balanced grocery fallback
    }

    // Produce (Fruits & Vegetables)
    if (cat.contains('fruit') || cat.contains('veg')) {
      // Micro produce (lemons, chillies, garlic, ginger, fresh herbs)
      if (n.contains('lemon') ||
          n.contains('lime') ||
          n.contains('chilli') ||
          n.contains('chili') ||
          n.contains('garlic') ||
          n.contains('ginger') ||
          n.contains('coriander') ||
          n.contains('mint') ||
          n.contains('pudina') ||
          n.contains('curry leave')) {
        return 0.05; // 50g
      }
      // Heavy produce
      if (n.contains('watermelon') || n.contains('pumpkin')) return 2.50;
      if (n.contains('papaya') || n.contains('pineapple') || n.contains('cabbage')) return 1.20;
      if (n.contains('coconut')) return 0.60;
      return 0.80; // Standard produce basket ~800g
    }

    if (cat.contains('butcher') || cat.contains('meat') || cat.contains('fish') || cat.contains('seafood')) {
      return 0.50; // Standard cut ~500g
    }

    // ── 8. Electronics & Mobile ──────────────────────────────────────────────
    if (cat.contains('electronic') || cat.contains('mobile')) {
      if (n.contains('laptop') || n.contains('macbook')) return 2.40;
      if (n.contains('tablet') || n.contains('ipad')) return 0.85;
      if (n.contains('phone') ||
          n.contains('mobile') ||
          n.contains('iphone') ||
          n.contains('smartphone') ||
          n.contains('realme') ||
          n.contains('redmi') ||
          n.contains('samsung') ||
          n.contains('oneplus') ||
          n.contains('pixel') ||
          n.contains('vivo') ||
          n.contains('oppo') ||
          n.contains('xiaomi')) {
        return 0.40; // Phone + retail box
      }
      if (n.contains('earphone') ||
          n.contains('airpod') ||
          n.contains('tws') ||
          n.contains('cable') ||
          n.contains('case') ||
          n.contains('cover') ||
          n.contains('adapter') ||
          n.contains('tempered')) {
        return 0.10;
      }
      if (n.contains('powerbank')) return 0.38;
      if (n.contains('speaker')) return 0.80;
      if (n.contains('smartwatch') || n.contains('watch')) return 0.15;
      return 0.50;
    }

    // ── 9. Other Lifestyle & Retail ──────────────────────────────────────────
    if (cat.contains('jewellery') || cat.contains('jewelry')) {
      return 0.08; // 80g with luxury box
    }

    if (cat.contains('hardware')) {
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
    }

    if (cat.contains('stationery') || cat.contains('book')) {
      if (n.contains('pen') || n.contains('pencil') || n.contains('eraser')) {
        return 0.05;
      }
      if (n.contains('register') || n.contains('book')) return 0.40;
      if (n.contains('notebook') || n.contains('diary')) return 0.22;
      return 0.20;
    }

    if (cat.contains('toy') || cat.contains('game')) {
      if (n.contains('board') || n.contains('puzzle')) return 0.70;
      return 0.40;
    }

    if (cat.contains('sport')) {
      if (n.contains('bat') || n.contains('racket')) return 1.10;
      if (n.contains('ball')) return 0.45;
      return 0.65;
    }

    if (cat.contains('pet')) {
      if (n.contains('food')) return 1.20;
      return 0.35;
    }

    if (cat.contains('cosmetic') || cat.contains('beauty') || cat.contains('salon')) {
      // Glass perfumes & Eau De Parfum (100ml liquid + heavy bottle + box)
      if (n.contains('perfume') ||
          n.contains('parfum') ||
          n.contains('eau de') ||
          n.contains('cologne') ||
          n.contains('attar')) {
        return 0.28; // 280g
      }
      // Deodorants / Body sprays (aerosol pressurized cans)
      if (n.contains('deo') || n.contains('deodorant') || n.contains('body spray')) {
        return 0.14; // 140g
      }
      if (n.contains('shampoo') ||
          n.contains('lotion') ||
          n.contains('wash') ||
          n.contains('conditioner')) {
        return 0.38;
      }
      if (n.contains('lipstick') ||
          n.contains('mascara') ||
          n.contains('kajal') ||
          n.contains('eyeliner') ||
          n.contains('lip balm') ||
          n.contains('nail polish')) {
        return 0.035;
      }
      if (n.contains('cream') || n.contains('serum') || n.contains('foundation')) {
        return 0.08;
      }
      return 0.15;
    }

    if (cat.contains('flower')) {
      return 0.30; // Bouquet ~300g
    }

    if (cat.contains('home decor') || cat.contains('furniture')) {
      if (n.contains('sheet') || n.contains('curtain')) return 0.85;
      return 0.75;
    }

    if (cat.contains('auto') || cat.contains('motor')) {
      if (n.contains('oil') || n.contains('lubricant')) return 0.95;
      return 0.45;
    }

    if (cat.contains('paan')) {
      return 0.03; // 30g
    }

    return 0.40; // Universal fallback
  }

  // ---------------------------------------------------------------------------
  // Tier 4: Variant Size & Portion Scaling Factor (Non-Explicit Weights)
  // ---------------------------------------------------------------------------

  static final RegExp _sizeS = RegExp(r'\bS\b');
  static final RegExp _sizeM = RegExp(r'\bM\b');
  static final RegExp _sizeL = RegExp(r'\bL\b');

  static double _variantPortionOrSizeFactor(String variantName) {
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

    // Apparel Sizes — ordered from most-specific to least-specific
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
    if (_sizeS.hasMatch(v) || v.contains('30')) return 0.94;
    if (_sizeM.hasMatch(v) ||
        _sizeL.hasMatch(v) ||
        v.contains('32') ||
        v.contains('34')) {
      return 1.00;
    }

    return 1.0;
  }
}
