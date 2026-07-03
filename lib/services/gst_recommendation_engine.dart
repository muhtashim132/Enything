// ===========================================================================
// gst_recommendation_engine.dart — Smart product-level GST recommendation
// ===========================================================================
//
// ARCHITECTURE:
//   1. On first use, loads DB-driven admin overrides from `product_gst_overrides`.
//   2. Falls back to built-in keyword map (mirrors the migration seed data).
//   3. Falls back to category-level rate from TaxConfig (existing unchanged logic).
//
// Usage in AddProductPage:
//   final engine = GstRecommendationEngine.instance;
//   await engine.ensureLoaded();
//   final rec = engine.recommend('Head and Shoulders Shampoo', 'Cosmetics & Beauty');
//   // rec.rate = 0.05, rec.reason = 'Shampoo — 5% FMCG Merit Rate', rec.isAmbiguous = false
//
// ===========================================================================

import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/tax_config.dart';

// ---------------------------------------------------------------------------
// GstRecommendation — result returned per product name lookup
// ---------------------------------------------------------------------------
class GstRecommendation {
  /// The recommended GST rate (e.g. 0.05 = 5%).
  final double rate;

  /// Human-readable reason shown to seller (e.g. "Shampoo — 5% FMCG Merit Rate").
  final String reason;

  /// True if multiple plausible rates exist and seller should confirm.
  /// False when the engine is confident — rate is auto-applied.
  final bool isAmbiguous;

  /// All standard slab rates available as alternatives (always shown in picker).
  final List<double> alternatives;

  const GstRecommendation({
    required this.rate,
    required this.reason,
    required this.isAmbiguous,
    this.alternatives = const [0.0, 0.05, 0.18, 0.40],
  });

  /// Display string for the recommendation chip, e.g. "5%".
  String get rateLabel => '${(rate * 100).toStringAsFixed(0)}%';

  @override
  String toString() => 'GstRecommendation(rate=$rateLabel, reason=$reason, ambiguous=$isAmbiguous)';
}

// ---------------------------------------------------------------------------
// GstRecommendationEngine — singleton
// ---------------------------------------------------------------------------
class GstRecommendationEngine {
  GstRecommendationEngine._();
  static final GstRecommendationEngine instance = GstRecommendationEngine._();

  bool _loaded = false;
  bool _loading = false;

  // DB-driven keyword overrides (admin-editable).
  // key = "keyword|categoryHint" (categoryHint = '' if null)
  final Map<String, _KeywordRule> _dbRules = {};

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Ensures DB rules are loaded. Safe to call multiple times — loads only once.
  Future<void> ensureLoaded() async {
    if (_loaded || _loading) return;
    _loading = true;
    try {
      final rows = await Supabase.instance.client
          .from('product_gst_overrides')
          .select('keyword, category_hint, gst_rate, reason')
          .eq('is_active', true);

      _dbRules.clear();
      for (final row in (rows as List)) {
        final kw = (row['keyword'] as String).toLowerCase().trim();
        final cat = (row['category_hint'] as String?) ?? '';
        final rate = double.tryParse(row['gst_rate'].toString()) ?? 0.18;
        final reason = (row['reason'] as String?) ?? '';
        _dbRules['$kw|$cat'] = _KeywordRule(
          keyword: kw,
          categoryHint: cat.isEmpty ? null : cat,
          rate: rate,
          reason: reason,
        );
      }
      _loaded = true;
    } catch (e) {
      // Non-fatal: fall back to built-in rules
      _loaded = true; // Mark loaded so we don't keep retrying
    } finally {
      _loading = false;
    }
  }

  /// Force-reload DB rules (call after admin adds/edits a keyword rule).
  Future<void> reload() async {
    _loaded = false;
    await ensureLoaded();
  }

  /// Returns a [GstRecommendation] based on product [name] and [category].
  ///
  /// Lookup order:
  ///   1. DB-driven keyword rules (admin overrides) — most specific first
  ///   2. Built-in keyword map (seed rules)
  ///   3. Category-level rate from [TaxConfig] (existing logic, unchanged)
  GstRecommendation recommend(String name, String category) {
    final nameLower = name.toLowerCase().trim();
    if (nameLower.isEmpty) {
      // No name yet — return category default
      return _categoryFallback(category);
    }

    // ── Step 1: DB rules (category-specific match first, then any-category) ──
    final dbMatch = _matchRules(_dbRules.values.toList(), nameLower, category);
    if (dbMatch != null) {
      // DB rules are admin-curated → high confidence, not ambiguous unless sin goods
      final isAmbiguous = _isSlabCategory(category);
      return GstRecommendation(
        rate: dbMatch.rate,
        reason: dbMatch.reason,
        isAmbiguous: isAmbiguous,
        alternatives: _alternativesFor(category),
      );
    }

    // ── Step 2: Built-in keyword map ─────────────────────────────────────────
    final builtInMatch = _matchRules(_builtInRules, nameLower, category);
    if (builtInMatch != null) {
      final isAmbiguous = _isSlabCategory(category);
      return GstRecommendation(
        rate: builtInMatch.rate,
        reason: builtInMatch.reason,
        isAmbiguous: isAmbiguous,
        alternatives: _alternativesFor(category),
      );
    }

    // ── Step 3: Category fallback ────────────────────────────────────────────
    return _categoryFallback(category);
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  _KeywordRule? _matchRules(List<_KeywordRule> rules, String nameLower, String category) {
    // Category-specific match has priority
    for (final rule in rules) {
      if (rule.categoryHint != null &&
          rule.categoryHint!.toLowerCase() == category.toLowerCase() &&
          nameLower.contains(rule.keyword)) {
        return rule;
      }
    }
    // Any-category match
    for (final rule in rules) {
      if (rule.categoryHint == null && nameLower.contains(rule.keyword)) {
        return rule;
      }
    }
    return null;
  }

  GstRecommendation _categoryFallback(String category) {
    final rate = TaxConfig.gstRateForCategory(category);
    final rateLabel = '${(rate * 100).toStringAsFixed(0)}%';
    final isAmbiguous = _isSlabCategory(category);
    return GstRecommendation(
      rate: rate,
      reason: '$category — $rateLabel (Category Default)',
      isAmbiguous: isAmbiguous || rate == 0.18, // 18% is often right but worth confirming
      alternatives: _alternativesFor(category),
    );
  }

  /// True for Clothing/Footwear which have price-based slabs.
  bool _isSlabCategory(String category) =>
      category == 'Clothing' || category == 'Footwear';

  /// Standard slab alternatives. All four slabs always shown.
  List<double> _alternativesFor(String category) {
    // For Clothing/Footwear show slab info
    if (_isSlabCategory(category)) {
      return [0.05, 0.18]; // low slab and high slab
    }
    return const [0.00, 0.05, 0.18, 0.40];
  }

  // ---------------------------------------------------------------------------
  // Built-in keyword rules (mirrors migration seed data)
  // These are the baseline that always work even without DB.
  // ---------------------------------------------------------------------------
  static final List<_KeywordRule> _builtInRules = [
    // ── Sin Goods / Tobacco — 40% ──────────────────────────────────────────
    _r('cigarette',      null,                   0.40, 'Tobacco Products — 40% (Budget 2026)'),
    _r('cigarettes',     null,                   0.40, 'Tobacco Products — 40% (Budget 2026)'),
    _r('marlboro',       null,                   0.40, 'Cigarettes — 40% (Budget 2026)'),
    _r('gold flake',     null,                   0.40, 'Cigarettes — 40% (Budget 2026)'),
    _r('classic milds',  null,                   0.40, 'Cigarettes — 40% (Budget 2026)'),
    _r('wills navy',     null,                   0.40, 'Cigarettes — 40% (Budget 2026)'),
    _r('dunhill',        null,                   0.40, 'Cigarettes — 40% (Budget 2026)'),
    _r('cigar',          null,                   0.40, 'Cigars — 40% (Budget 2026)'),
    _r('bidi',           null,                   0.40, 'Bidis — 40% (Budget 2026)'),
    _r('tobacco',        null,                   0.40, 'Tobacco — 40% (Budget 2026)'),
    _r('gutka',          null,                   0.40, 'Gutka — 40% (Budget 2026)'),
    _r('pan masala',     null,                   0.40, 'Pan Masala — 40% (Budget 2026)'),
    _r('khaini',         null,                   0.40, 'Tobacco Products — 40%'),
    _r('hookah',         null,                   0.40, 'Hookah Tobacco — 40%'),
    _r('shisha',         null,                   0.40, 'Shisha — 40%'),
    _r('zarda',          null,                   0.40, 'Zarda — 40%'),
    _r('aerated drink',  'Beverages',            0.40, 'Aerated Drinks — 40%'),
    _r('cola',           'Beverages',            0.40, 'Cola Drinks — 40%'),
    _r('energy drink',   'Beverages',            0.40, 'Energy Drinks — 40%'),
    _r('red bull',       'Beverages',            0.40, 'Energy Drinks — 40%'),
    _r('monster energy', 'Beverages',            0.40, 'Energy Drinks — 40%'),
    _r('pepsi',          'Beverages',            0.40, 'Aerated Drink — 40%'),
    _r('sprite',         'Beverages',            0.40, 'Aerated Drink — 40%'),
    _r('thums up',       'Beverages',            0.40, 'Aerated Drink — 40%'),
    _r('coca cola',      'Beverages',            0.40, 'Aerated Drink — 40%'),
    _r('mountain dew',   'Beverages',            0.40, 'Aerated Drink — 40%'),
    _r('fanta',          'Beverages',            0.40, 'Aerated Drink — 40%'),
    _r('limca',          'Beverages',            0.40, 'Aerated Drink — 40%'),
    _r('7up',            'Beverages',            0.40, 'Aerated Drink — 40%'),
    _r('carbonated',     'Beverages',            0.40, 'Carbonated Drinks — 40%'),

    // ── Hair Care / FMCG — 5% ────────────────────────────────────────────
    _r('shampoo',             null,              0.05, 'Shampoo — 5% FMCG Merit Rate (GST 2.0)'),
    _r('head and shoulders',  null,              0.05, 'Shampoo — 5% FMCG Merit Rate'),
    _r('head & shoulders',    null,              0.05, 'Shampoo — 5% FMCG Merit Rate'),
    _r('pantene',             null,              0.05, 'Hair Care — 5% FMCG Merit Rate'),
    _r('sunsilk',             null,              0.05, 'Shampoo — 5% FMCG Merit Rate'),
    _r('clinic plus',         null,              0.05, 'Shampoo — 5% FMCG Merit Rate'),
    _r('tresemme',            null,              0.05, 'Shampoo — 5% FMCG Merit Rate'),
    _r('dove shampoo',        null,              0.05, 'Shampoo — 5% FMCG Merit Rate'),
    _r('clear shampoo',       null,              0.05, 'Shampoo — 5% FMCG Merit Rate'),
    _r('hair oil',            null,              0.05, 'Hair Oil — 5% FMCG Merit Rate'),
    _r('coconut oil',         null,              0.05, 'Hair/Cooking Oil — 5%'),
    _r('parachute',           null,              0.05, 'Hair Oil — 5% FMCG Merit Rate'),
    _r('dabur amla',          null,              0.05, 'Hair Oil — 5% FMCG Merit Rate'),
    _r('vatika',              null,              0.05, 'Hair Oil — 5% FMCG Merit Rate'),
    _r('hair conditioner',    null,              0.05, 'Hair Conditioner — 5% Merit Rate'),
    _r('conditioner',         null,              0.05, 'Hair Conditioner — 5% Merit Rate'),
    _r('hair colour',         null,              0.05, 'Hair Colour — 5% Merit Rate'),
    _r('hair color',          null,              0.05, 'Hair Colour — 5% Merit Rate'),
    _r('hair dye',            null,              0.05, 'Hair Dye — 5% Merit Rate'),
    _r('mehendi',             null,              0.05, 'Mehendi/Henna — 5%'),
    _r('henna',               null,              0.05, 'Henna — 5%'),
    _r('toothpaste',          null,              0.05, 'Toothpaste — 5% FMCG Merit Rate'),
    _r('colgate',             null,              0.05, 'Toothpaste — 5% FMCG Merit Rate'),
    _r('pepsodent',           null,              0.05, 'Toothpaste — 5% FMCG Merit Rate'),
    _r('oral b',              null,              0.05, 'Toothpaste — 5% FMCG Merit Rate'),
    _r('sensodyne',           null,              0.05, 'Toothpaste — 5% FMCG Merit Rate'),
    _r('toothbrush',          null,              0.05, 'Toothbrush — 5% FMCG Merit Rate'),
    _r('mouthwash',           null,              0.05, 'Mouthwash — 5%'),
    _r('listerine',           null,              0.05, 'Mouthwash — 5%'),
    _r('soap',                null,              0.05, 'Soap — 5% FMCG Merit Rate'),
    _r('bathing soap',        null,              0.05, 'Soap — 5% FMCG Merit Rate'),
    _r('lux',                 null,              0.05, 'Soap — 5% FMCG Merit Rate'),
    _r('lifebuoy',            null,              0.05, 'Soap — 5% FMCG Merit Rate'),
    _r('dettol soap',         null,              0.05, 'Soap — 5% FMCG Merit Rate'),
    _r('dove soap',           null,              0.05, 'Soap — 5% FMCG Merit Rate'),
    _r('body wash',           null,              0.05, 'Body Wash — 5% Merit Rate'),
    _r('face wash',           null,              0.05, 'Face Wash — 5% Merit Rate'),
    _r('hand wash',           null,              0.05, 'Hand Wash — 5% Merit Rate'),
    _r('sanitizer',           null,              0.05, 'Sanitizer — 5% Merit Rate'),
    _r('hand sanitizer',      null,              0.05, 'Hand Sanitizer — 5%'),
    _r('moisturiser',         null,              0.05, 'Moisturiser — 5% Merit Rate'),
    _r('moisturizer',         null,              0.05, 'Moisturiser — 5% Merit Rate'),
    _r('fairness cream',      null,              0.05, 'Skin Cream — 5% Merit Rate'),
    _r('sunscreen',           null,              0.05, 'Sunscreen — 5% Merit Rate'),
    _r('cold cream',          null,              0.05, 'Cold Cream — 5% Merit Rate'),
    _r('vaseline',            null,              0.05, 'Skin Care — 5% Merit Rate'),
    _r('petroleum jelly',     null,              0.05, 'Petroleum Jelly — 5%'),
    _r('talcum powder',       null,              0.05, 'Talcum Powder — 5% Merit Rate'),
    _r('baby powder',         null,              0.05, 'Baby Powder — 5%'),
    _r('johnson baby',        null,              0.05, 'Baby Product — 5%'),
    _r('deodorant',           null,              0.05, 'Deodorant — 5% Merit Rate'),
    _r('deo spray',           null,              0.05, 'Deodorant — 5% Merit Rate'),
    _r('axe',                 null,              0.05, 'Deodorant — 5% Merit Rate'),
    _r('fogg',                null,              0.05, 'Deodorant — 5% Merit Rate'),
    _r('shaving cream',       null,              0.05, 'Shaving Cream — 5% Merit Rate'),
    _r('shaving gel',         null,              0.05, 'Shaving Gel — 5% Merit Rate'),
    _r('aftershave',          null,              0.05, 'Aftershave — 5% Merit Rate'),
    _r('razor',               null,              0.05, 'Razor — 5% Merit Rate'),
    _r('gillette',            null,              0.05, 'Razor/Shaving — 5% Merit Rate'),
    _r('veet',                null,              0.05, 'Hair Removal Cream — 5%'),
    _r('hair removal',        null,              0.05, 'Hair Removal — 5%'),
    _r('sanitary pad',        null,              0.05, 'Sanitary Napkins — 5%'),
    _r('sanitary napkin',     null,              0.05, 'Sanitary Napkins — 5%'),
    _r('whisper',             null,              0.05, 'Sanitary Napkins — 5%'),
    _r('stayfree',            null,              0.05, 'Sanitary Napkins — 5%'),
    _r('diaper',              null,              0.05, 'Diapers — 5%'),
    _r('pampers',             null,              0.05, 'Diapers — 5%'),
    _r('huggies',             null,              0.05, 'Diapers — 5%'),

    // ── Cosmetics / Makeup — 18% ─────────────────────────────────────────
    _r('lipstick',            null,              0.18, 'Lipstick — 18% Standard Rate'),
    _r('lip gloss',           null,              0.18, 'Lip Gloss — 18%'),
    _r('foundation',          null,              0.18, 'Foundation — 18%'),
    _r('compact powder',      null,              0.18, 'Compact Powder — 18%'),
    _r('kajal',               null,              0.18, 'Kajal — 18%'),
    _r('eyeliner',            null,              0.18, 'Eyeliner — 18%'),
    _r('mascara',             null,              0.18, 'Mascara — 18%'),
    _r('eyeshadow',           null,              0.18, 'Eye Shadow — 18%'),
    _r('blush',               null,              0.18, 'Blush — 18%'),
    _r('concealer',           null,              0.18, 'Concealer — 18%'),
    _r('highlighter',         null,              0.18, 'Highlighter — 18%'),
    _r('primer',              null,              0.18, 'Makeup Primer — 18%'),
    _r('bb cream',            null,              0.18, 'BB Cream — 18%'),
    _r('nail polish',         null,              0.18, 'Nail Polish — 18%'),
    _r('nail paint',          null,              0.18, 'Nail Paint — 18%'),
    _r('nail remover',        null,              0.18, 'Nail Remover — 18%'),
    _r('perfume',             null,              0.18, 'Perfume — 18%'),
    _r('cologne',             null,              0.18, 'Cologne — 18%'),
    _r('attar',               null,              0.18, 'Attar/Ittar — 18%'),
    _r('face pack',           null,              0.18, 'Face Pack — 18%'),
    _r('face mask',           null,              0.18, 'Face Mask — 18%'),
    _r('scrub',               null,              0.18, 'Skin Scrub — 18%'),
    _r('toner',               null,              0.18, 'Face Toner — 18%'),
    _r('serum',               null,              0.18, 'Face Serum — 18%'),
    _r('eye cream',           null,              0.18, 'Eye Cream — 18%'),
    _r('retinol',             null,              0.18, 'Retinol Serum — 18%'),
    _r('vitamin c serum',     null,              0.18, 'Vitamin C Serum — 18%'),
    _r('hyaluronic',          null,              0.18, 'Skin Care — 18%'),
    _r('niacinamide',         null,              0.18, 'Skin Care — 18%'),
    _r('sunscreen spf',       null,              0.18, 'Sunscreen SPF — 18%'),
    _r('makeup remover',      null,              0.18, 'Makeup Remover — 18%'),
    _r('micellar water',      null,              0.18, 'Micellar Water — 18%'),
    _r('lip balm',            null,              0.18, 'Lip Balm — 18%'),
    _r('bronzer',             null,              0.18, 'Bronzer — 18%'),
    _r('makeup brush',        null,              0.18, 'Makeup Brush — 18%'),
    _r('body spray',          null,              0.18, 'Body Spray — 18%'),

    // ── Pharmacy / Medicines — 5% ────────────────────────────────────────
    _r('paracetamol',         'Pharmacy',        0.05, 'OTC Medicine — 5%'),
    _r('paracetamol',         'Medical Store',   0.05, 'OTC Medicine — 5%'),
    _r('crocin',              null,              0.05, 'Paracetamol — 5%'),
    _r('dolo',                null,              0.05, 'Paracetamol — 5%'),
    _r('combiflam',           null,              0.05, 'OTC Medicine — 5%'),
    _r('ibuprofen',           null,              0.05, 'OTC Medicine — 5%'),
    _r('aspirin',             null,              0.05, 'OTC Medicine — 5%'),
    _r('antacid',             null,              0.05, 'Antacid — 5%'),
    _r('eno',                 null,              0.05, 'Antacid — 5%'),
    _r('gelusil',             null,              0.05, 'Antacid — 5%'),
    _r('cough syrup',         null,              0.05, 'Cough Syrup — 5%'),
    _r('benadryl',            null,              0.05, 'Cough Syrup — 5%'),
    _r('vicks',               null,              0.05, 'OTC Medicine — 5%'),
    _r('nasal spray',         null,              0.05, 'Nasal Spray — 5%'),
    _r('eye drop',            null,              0.05, 'Eye Drops — 5%'),
    _r('ear drop',            null,              0.05, 'Ear Drops — 5%'),
    _r('bandage',             null,              0.05, 'Bandage — 5%'),
    _r('band-aid',            null,              0.05, 'Band-Aid — 5%'),
    _r('antiseptic',          null,              0.05, 'Antiseptic — 5%'),
    _r('dettol liquid',       null,              0.05, 'Antiseptic — 5%'),
    _r('thermometer',         null,              0.05, 'Medical Device — 5%'),
    _r('ors',                 null,              0.05, 'ORS/Electrolytes — 5%'),
    _r('electrolyte',         null,              0.05, 'Electrolyte — 5%'),
    _r('multivitamin',        null,              0.05, 'Multivitamin — 5%'),
    _r('vitamin tablet',      null,              0.05, 'Vitamins — 5%'),
    _r('ayurvedic',           null,              0.05, 'Ayurvedic Medicine — 5%'),
    _r('homeopathic',         null,              0.05, 'Homeopathic Medicine — 5%'),
    _r('chyawanprash',        null,              0.05, 'Ayurvedic — 5%'),
    _r('insulin',             null,              0.00, 'Life-Saving Drug — 0% (Exempt)'),

    // ── Electronics — 18% ────────────────────────────────────────────────
    _r('mobile phone',        null,              0.18, 'Mobile Phone — 18%'),
    _r('smartphone',          null,              0.18, 'Smartphone — 18%'),
    _r('iphone',              null,              0.18, 'Smartphone — 18%'),
    _r('samsung phone',       null,              0.18, 'Smartphone — 18%'),
    _r('oneplus',             null,              0.18, 'Smartphone — 18%'),
    _r('laptop',              null,              0.18, 'Laptop — 18%'),
    _r('earphone',            null,              0.18, 'Earphone — 18%'),
    _r('earbuds',             null,              0.18, 'Earbuds — 18%'),
    _r('airpods',             null,              0.18, 'Earbuds — 18%'),
    _r('headphone',           null,              0.18, 'Headphone — 18%'),
    _r('bluetooth speaker',   null,              0.18, 'Bluetooth Speaker — 18%'),
    _r('power bank',          null,              0.18, 'Power Bank — 18%'),
    _r('mobile charger',      null,              0.18, 'Mobile Charger — 18%'),
    _r('usb cable',           null,              0.18, 'USB Cable — 18%'),
    _r('screen guard',        null,              0.18, 'Screen Guard — 18%'),
    _r('tempered glass',      null,              0.18, 'Screen Protector — 18%'),
    _r('phone case',          null,              0.18, 'Phone Case — 18%'),
    _r('mobile cover',        null,              0.18, 'Mobile Cover — 18%'),
    _r('back cover',          null,              0.18, 'Back Cover — 18%'),
    _r('smart watch',         null,              0.18, 'Smartwatch — 18%'),
    _r('fitness band',        null,              0.18, 'Fitness Band — 18%'),
    _r('pendrive',            null,              0.18, 'Pen Drive — 18%'),
    _r('sd card',             null,              0.18, 'Memory Card — 18%'),
    _r('memory card',         null,              0.18, 'Memory Card — 18%'),
    _r('hard disk',           null,              0.18, 'Hard Disk — 18%'),
    _r('wifi router',         null,              0.18, 'Wi-Fi Router — 18%'),
    _r('led tv',              null,              0.18, 'LED TV — 18%'),
    _r('smart tv',            null,              0.18, 'Smart TV — 18%'),

    // ── Grocery ───────────────────────────────────────────────────────────
    _r('rice',                'Grocery',         0.00, 'Staple Food — 0%'),
    _r('wheat',               'Grocery',         0.00, 'Staple Food — 0%'),
    _r('atta',                'Grocery',         0.00, 'Wheat Flour — 0%'),
    _r('maida',               'Grocery',         0.00, 'Flour — 0%'),
    _r('dal',                 'Grocery',         0.00, 'Lentils — 0%'),
    _r('salt',                'Grocery',         0.00, 'Salt — 0%'),
    _r('bread',               'Grocery',         0.00, 'Bread — 0%'),
    _r('sugar',               'Grocery',         0.05, 'Sugar — 5%'),
    _r('ghee',                'Grocery',         0.05, 'Ghee — 5%'),
    _r('spices',              'Grocery',         0.05, 'Spices — 5%'),
    _r('masala',              'Grocery',         0.05, 'Masala — 5%'),
    _r('biscuit',             'Grocery',         0.05, 'Biscuit — 5%'),
    _r('chocolate',           'Grocery',         0.18, 'Chocolate — 18%'),
    _r('chips',               'Grocery',         0.18, 'Chips — 18%'),
    _r('noodles',             'Grocery',         0.18, 'Noodles — 18%'),
    _r('maggi',               null,              0.18, 'Instant Noodles — 18%'),
    _r('juice',               'Beverages',       0.18, 'Packaged Juice — 18%'),
    _r('mineral water',       'Beverages',       0.18, 'Packaged Water — 18%'),
    _r('packaged water',      'Beverages',       0.18, 'Packaged Water — 18%'),

    // ── Jewellery — 3% ────────────────────────────────────────────────────
    _r('gold ring',           'Jewellery',       0.03, 'Gold Jewellery — 3%'),
    _r('gold necklace',       'Jewellery',       0.03, 'Gold Jewellery — 3%'),
    _r('gold chain',          'Jewellery',       0.03, 'Gold Jewellery — 3%'),
    _r('gold earring',        'Jewellery',       0.03, 'Gold Earrings — 3%'),
    _r('diamond ring',        'Jewellery',       0.03, 'Diamond Jewellery — 3%'),
    _r('silver ring',         'Jewellery',       0.03, 'Silver Jewellery — 3%'),
    _r('silver chain',        'Jewellery',       0.03, 'Silver Jewellery — 3%'),
    _r('artificial jewellery','Jewellery',       0.03, 'Artificial Jewellery — 3%'),
    _r('imitation jewellery', 'Jewellery',       0.03, 'Imitation Jewellery — 3%'),
  ];
}

// ---------------------------------------------------------------------------
// Internal model
// ---------------------------------------------------------------------------
class _KeywordRule {
  final String keyword;
  final String? categoryHint;
  final double rate;
  final String reason;

  const _KeywordRule({
    required this.keyword,
    required this.categoryHint,
    required this.rate,
    required this.reason,
  });
}

/// Shorthand factory for built-in rules.
_KeywordRule _r(String kw, String? cat, double rate, String reason) =>
    _KeywordRule(keyword: kw, categoryHint: cat, rate: rate, reason: reason);
