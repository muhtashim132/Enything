// ============================================================================
// gst_recommendation_engine.dart — Enything India GST Recommendation Engine
// ============================================================================
//
// ── ARCHITECTURE ─────────────────────────────────────────────────────────────
//
//   Enything operates strictly on an ADD-ON GST model.
//   Sellers enter their BASE price in the app. Enything adds GST on top.
//
//   This engine recommends the statutory GST slab as the seller types the
//   product name in AddProductPage.
//
//   Precedence:
//     1. Unstitched fabric/saree check in Clothing (Flat 5% statutory rule)
//     2. Price-dependent statutory slab for Clothing / Footwear (≤₹2,500 = 5%, >₹2,500 = 18%)
//     3. DB-driven keyword rules (`product_gst_overrides` table, admin-curated)
//     4. Built-in statutory keyword rules (300+ product-level rules covering all categories)
//     5. Category default from [TaxConfig.gstRateForCategory]
//
//   Statutory Foundations:
//     • CGST Act 2017 (§9(5), §52), IGST Act 2017
//     • Legal Metrology Act 2009 & Packaged Commodities Rules 2011 (≤25 kg rule)
//     • Notification 01/2017-CT(R), 02/2017-CT(R), 06/2022-CT(R), 07/2022-CT(R)
//     • Notification 09/2025-CT(R) (GST 2.0 Reform — Sept 22, 2025)
//     • 54th GST Council Meeting Directives (Extruded snacks 12%, Water 5%)
//     • CBIC Circulars 163, 164, 167, 177, 179
//
// ============================================================================

import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/tax_config.dart';

/// Represents a GST recommendation for a product name + category.
class GstRecommendation {
  /// Recommended rate as a decimal (e.g. 0.05 = 5%, 0.18 = 18%, 0.40 = 40%).
  final double rate;

  /// Plain-English reason shown on the recommendation chip.
  final String reason;

  /// True when the engine is guessing from category default or price slab applies.
  final bool isAmbiguous;

  /// Valid alternative slabs for this category to render as quick-tap chips.
  final List<double> alternatives;

  const GstRecommendation({
    required this.rate,
    required this.reason,
    required this.isAmbiguous,
    this.alternatives = const [],
  });

  /// Percentage string e.g. "5%", "18%", "40%".
  String get ratePercentString => '${(rate * 100).toStringAsFixed(0)}%';

  /// Label alias used across test suites and UI chips.
  String get rateLabel => ratePercentString;
}

/// Singleton recommendation engine that caches DB rules and falls back to built-ins.
class GstRecommendationEngine {
  GstRecommendationEngine._();
  static final GstRecommendationEngine instance = GstRecommendationEngine._();

  final List<_KeywordRule> _dbRules = [];
  bool _loaded = false;
  bool _loading = false;

  /// Ensures DB rules are cached in memory. Called on seller page open.
  Future<void> ensureLoaded() async {
    if (_loaded || _loading) return;
    _loading = true;
    try {
      final client = Supabase.instance.client;
      final rows = await client
          .from('product_gst_overrides')
          .select('keyword, category_hint, gst_rate, reason')
          .order('keyword');

      _dbRules.clear();
      for (final r in rows as List<dynamic>) {
        final kw = (r['keyword'] as String? ?? '').toLowerCase().trim();
        if (kw.isEmpty) continue;
        final catHint = (r['category_hint'] as String?)?.trim();
        final rate = (r['gst_rate'] as num).toDouble();
        final reason = r['reason'] as String? ?? 'Admin keyword rule';
        final ruleCat = (catHint == null || catHint.isEmpty) ? null : catHint;

        // SANITIZATION GUARD: Drop stale/invalid DB rules that attempt to tax 0% exempt goods
        if (rate > 0.0 && _isUniversalExempt(kw, ruleCat)) {
          continue; // Discard corrupted DB row
        }

        _dbRules.add(_KeywordRule(
          keyword: kw,
          categoryHint: ruleCat,
          rate: rate,
          reason: reason,
        ));
      }
      _loaded = true;
    } catch (_) {
      // Offline or table not ready — built-in rules will serve as fallback
    } finally {
      _loading = false;
    }
  }

  /// Force-reload DB rules (call after admin adds/edits a keyword rule).
  Future<void> reload() async {
    _loaded = false;
    await ensureLoaded();
  }

  /// Returns a [GstRecommendation] based on product [name], [category], and optional [itemPrice].
  ///
  /// Lookup order:
  ///   1. Inviolable Statutory Legal Firewall (0% Educational Stationery, Sanitary Pads, Fresh Produce, Contraceptives)
  ///   2. Unstitched fabric/saree check in Clothing (Flat 5% statutory rule)
  ///   3. Price-dependent statutory slab for Clothing / Footwear (≤₹2,500 = 5%, >₹2,500 = 18%)
  ///   4. Disambiguation check for "notebook" (Exercise books in non-tech categories vs Laptops in Electronics)
  ///   5. DB-driven keyword rules (sanitized admin overrides) — most specific first
  ///   6. Built-in statutory keyword rules (350+ product-level rules covering all categories)
  ///   7. Category-level rate from [TaxConfig]
  GstRecommendation recommend(String name, String category, {double? itemPrice}) {
    final nameLower = name.toLowerCase().trim();

    if (nameLower.isEmpty) {
      // No name yet — return category default
      return _categoryFallback(category, itemPrice: itemPrice);
    }

    // ── LAYER 1: Inviolable Statutory Legal Firewall (0% Universal Exemptions) ──
    final exemptMatch = _matchRules(_inviolableStatutoryExemptions, nameLower, category);
    if (exemptMatch != null) {
      return GstRecommendation(
        rate: 0.00,
        reason: exemptMatch.reason,
        isAmbiguous: false,
        alternatives: _alternativesFor(category),
      );
    }

    // ── LAYER 2: Unstitched fabrics / sarees in Clothing are flat 5% (no price ceiling) ──
    if (category == 'Clothing') {
      final isUnstitched = nameLower.contains('unstitched') ||
          nameLower.contains('saree') ||
          nameLower.contains('sari') ||
          nameLower.contains('fabric') ||
          nameLower.contains('dress material') ||
          nameLower.contains('cloth piece') ||
          nameLower.contains('than');
      if (isUnstitched) {
        return GstRecommendation(
          rate: 0.05,
          reason: 'Unstitched Fabric / Saree — Flat 5% (No Price Threshold)',
          isAmbiguous: false,
          alternatives: _alternativesFor(category),
        );
      }
    }

    // ── LAYER 2B: Stitched apparel / footwear with known price ──────────────
    if (_isSlabCategory(category) && itemPrice != null) {
      const threshold = TaxConfig.defaultSlabThreshold; // ₹2,500
      final isHigh = itemPrice > threshold;
      final rate = isHigh ? TaxConfig.defaultSlabHighRate : 0.05;
      final slabLabel = isHigh
          ? '>₹${threshold.toInt()} Statutory Standard Slab — 18%'
          : '≤₹${threshold.toInt()} Statutory Concessional Slab — 5%';
      return GstRecommendation(
        rate: rate,
        reason: '$category ($slabLabel)',
        isAmbiguous: false,
        alternatives: _alternativesFor(category),
      );
    }

    // ── LAYER 2C: Disambiguate "notebook" (School/Exercise Notebook 0% vs Laptop 18%) ──
    if (nameLower.contains('notebook')) {
      final isTechCategory = category == 'Electronics' ||
          category == 'Computers' ||
          category == 'Mobile & Electronics' ||
          category == 'IT Equipment';
      final hasLaptopKeyword = nameLower.contains('laptop') ||
          nameLower.contains('macbook') ||
          nameLower.contains('chromebook') ||
          nameLower.contains('thinkpad') ||
          nameLower.contains('dell') ||
          nameLower.contains('hp') ||
          nameLower.contains('lenovo') ||
          nameLower.contains('asus') ||
          nameLower.contains('intel') ||
          nameLower.contains('ryzen');
      if (isTechCategory || hasLaptopKeyword) {
        return GstRecommendation(
          rate: 0.18,
          reason: 'Laptop / Notebook Computer — 18% (HSN 8471)',
          isAmbiguous: false,
          alternatives: _alternativesFor(category),
        );
      } else {
        // School / office / department store exercise notebook — strictly 0%
        return GstRecommendation(
          rate: 0.00,
          reason: 'Exercise Notebooks — 0% (Universal Statutory Exemption HSN 4820)',
          isAmbiguous: false,
          alternatives: _alternativesFor(category),
        );
      }
    }

    // ── LAYER 3: Sanitized DB Rules (Category-specific match first, then any-category) ──
    final dbMatch = _matchRules(_dbRules, nameLower, category);
    if (dbMatch != null) {
      final isAmbiguous = _isSlabCategory(category) && itemPrice == null;
      return GstRecommendation(
        rate: dbMatch.rate,
        reason: dbMatch.reason,
        isAmbiguous: isAmbiguous,
        alternatives: _alternativesFor(category),
      );
    }

    // ── LAYER 4: Built-in Statutory Master Rules (350+ product-level rules) ──
    final builtInMatch = _matchRules(_builtInRules, nameLower, category);
    if (builtInMatch != null) {
      final isAmbiguous = _isSlabCategory(category) && itemPrice == null;
      return GstRecommendation(
        rate: builtInMatch.rate,
        reason: builtInMatch.reason,
        isAmbiguous: isAmbiguous,
        alternatives: _alternativesFor(category),
      );
    }

    // ── LAYER 5: Category Fallback ──────────────────────────────────────────
    return _categoryFallback(category, itemPrice: itemPrice);
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  _KeywordRule? _matchRules(
      List<_KeywordRule> rules, String nameLower, String category) {
    _KeywordRule? bestCategoryMatch;
    int bestCategoryLen = 0;
    _KeywordRule? bestGlobalMatch;
    int bestGlobalLen = 0;

    for (final rule in rules) {
      if (nameLower.contains(rule.keyword)) {
        if (rule.categoryHint != null &&
            rule.categoryHint!.toLowerCase() == category.toLowerCase()) {
          if (rule.keyword.length > bestCategoryLen) {
            bestCategoryMatch = rule;
            bestCategoryLen = rule.keyword.length;
          }
        } else if (rule.categoryHint == null) {
          if (rule.keyword.length > bestGlobalLen) {
            bestGlobalMatch = rule;
            bestGlobalLen = rule.keyword.length;
          }
        }
      }
    }
    return bestCategoryMatch ?? bestGlobalMatch;
  }

  GstRecommendation _categoryFallback(String category, {double? itemPrice}) {
    final rate = TaxConfig.gstRateForCategory(category, itemPrice: itemPrice);
    final rateLabel = '${(rate * 100).toStringAsFixed(0)}%';
    final isAmbiguous = _isSlabCategory(category) && itemPrice == null;
    final reason = _isSlabCategory(category) && itemPrice != null
        ? '$category (${itemPrice > TaxConfig.defaultSlabThreshold ? ">₹2,500 High Slab" : "≤₹2,500 Low Slab"}) — $rateLabel'
        : '$category — $rateLabel (Category Default)';
    return GstRecommendation(
      rate: rate,
      reason: reason,
      isAmbiguous: isAmbiguous ||
          (rate == 0.18 && !_isSlabCategory(category)),
      alternatives: _alternativesFor(category),
    );
  }

  /// True for Clothing/Footwear which have price-based slabs.
  bool _isSlabCategory(String category) =>
      category == 'Clothing' || category == 'Footwear';

  /// Complete Indian statutory GST slabs tailored by category.
  List<double> _alternativesFor(String category) {
    if (_isSlabCategory(category)) {
      return const [0.05, 0.12, 0.18]; // low slab (5%), legacy (12%), and high slab (18%)
    }
    if (category == 'Jewellery') {
      return const [0.00, 0.0025, 0.015, 0.03, 0.05, 0.18]; // 0.25% rough diamonds, 1.5% cut gems, 3% gold
    }
    if (category == 'Pharmacy' || category == 'Medical Store') {
      return const [0.00, 0.05, 0.12, 0.18]; // exempt, 5% essential, 12% ayurvedic, 18% cosmetics
    }
    if (category == 'Beverages' || category == 'Paan Shop') {
      return const [0.00, 0.05, 0.12, 0.18, 0.40]; // includes 40% sin goods
    }
    if (category == 'Snacks' ||
        category == 'Bakery' ||
        category == 'Dairy & Eggs' ||
        category == 'Grocery' ||
        category == 'Supermarket / Hypermarket') {
      return const [0.00, 0.05, 0.12, 0.18]; // includes 12% for namkeen, chips, butter, ghee, cheese
    }
    if (category == 'Electronics' || category == 'Hardware Store' || category == 'Auto Parts') {
      return const [0.05, 0.18, 0.28]; // solar/merit, 18% standard, 28% luxury/peak
    }
    return const [0.00, 0.03, 0.05, 0.12, 0.18, 0.28, 0.40];
  }

  // ---------------------------------------------------------------------------
  // Layer 1: Inviolable Statutory Legal Firewall
  // Under Indian GST law (Notification 02/2017-CT(R), 19/2018-CT(R), HSN 02-08, 48, 96),
  // these goods have statutory 0% NIL rating. No DB row, admin error, or client config
  // can ever override these rates.
  // ---------------------------------------------------------------------------
  static final List<_KeywordRule> _inviolableStatutoryExemptions = [
    // ── Student Educational Stationery (HSN 9609, 4820, 4016, 8214, 4901) ──
    _r('pencil', null, 0.00, 'Pencils — 0% (Universal Statutory Exemption HSN 9609)'),
    _r('writing pencil', null, 0.00, 'Pencils — 0% (Universal Statutory Exemption HSN 9609)'),
    _r('lead pencil', null, 0.00, 'Pencils — 0% (Universal Statutory Exemption HSN 9609)'),
    _r('color pencil', null, 0.00, 'Student Color Pencils — 0% (Universal Statutory Exemption HSN 9609)'),
    _r('colored pencil', null, 0.00, 'Student Color Pencils — 0% (Universal Statutory Exemption HSN 9609)'),
    _r('slate pencil', null, 0.00, 'Slate Pencils — 0% (Universal Statutory Exemption HSN 9609)'),
    _r('mechanical pencil', null, 0.00, 'Mechanical Pencils — 0% (Universal Statutory Exemption HSN 9609)'),
    _r('apsara pencil', null, 0.00, 'Pencils — 0% (Universal Statutory Exemption HSN 9609)'),
    _r('nataraj pencil', null, 0.00, 'Pencils — 0% (Universal Statutory Exemption HSN 9609)'),
    _r('doms pencil', null, 0.00, 'Pencils — 0% (Universal Statutory Exemption HSN 9609)'),
    _r('camlin pencil', null, 0.00, 'Pencils — 0% (Universal Statutory Exemption HSN 9609)'),
    _r('crayons', null, 0.00, 'Student Crayons — 0% (Universal Statutory Exemption HSN 9609)'),
    _r('crayon', null, 0.00, 'Student Crayons — 0% (Universal Statutory Exemption HSN 9609)'),
    _r('oil pastels', null, 0.00, 'Oil Pastels — 0% (Universal Statutory Exemption HSN 9609)'),
    _r('wax crayons', null, 0.00, 'Wax Crayons — 0% (Universal Statutory Exemption HSN 9609)'),
    _r('eraser', null, 0.00, 'Erasers — 0% (Universal Statutory Exemption HSN 4016)'),
    _r('rubber eraser', null, 0.00, 'Erasers — 0% (Universal Statutory Exemption HSN 4016)'),
    _r('apsara eraser', null, 0.00, 'Erasers — 0% (Universal Statutory Exemption HSN 4016)'),
    _r('nataraj eraser', null, 0.00, 'Erasers — 0% (Universal Statutory Exemption HSN 4016)'),
    _r('sharpener', null, 0.00, 'Sharpeners — 0% (Universal Statutory Exemption HSN 8214)'),
    _r('pencil sharpener', null, 0.00, 'Sharpeners — 0% (Universal Statutory Exemption HSN 8214)'),
    _r('exercise book', null, 0.00, 'Exercise Books — 0% (Universal Statutory Exemption HSN 4820)'),
    _r('classmate notebook', null, 0.00, 'Exercise Books — 0% (Universal Statutory Exemption HSN 4820)'),
    _r('drawing book', null, 0.00, 'Drawing Books — 0% (Universal Statutory Exemption HSN 4820)'),
    _r('graph book', null, 0.00, 'Graph Books — 0% (Universal Statutory Exemption HSN 4820)'),
    _r('lab notebook', null, 0.00, 'Laboratory Notebooks — 0% (Universal Statutory Exemption HSN 4820)'),
    _r('textbook', null, 0.00, 'Printed Educational Books — 0% (Universal Statutory Exemption HSN 4901)'),
    _r('ncert', null, 0.00, 'Educational Textbooks — 0% (Universal Statutory Exemption HSN 4901)'),
    _r('chalk', null, 0.00, 'Writing Chalk — 0% (Universal Statutory Exemption HSN 9609)'),
    _r('slate', null, 0.00, 'Educational Slates — 0% (Universal Statutory Exemption HSN 9608/9609)'),

    // ── Female Sanitary Hygiene (HSN 9619 — 0% since Notification 19/2018-CT(R)) ──
    _r('sanitary pad', null, 0.00, 'Sanitary Napkins — 0% (Universal Statutory Exemption HSN 9619)'),
    _r('sanitary napkin', null, 0.00, 'Sanitary Napkins — 0% (Universal Statutory Exemption HSN 9619)'),
    _r('whisper', null, 0.00, 'Sanitary Napkins — 0% (Universal Statutory Exemption HSN 9619)'),
    _r('stayfree', null, 0.00, 'Sanitary Napkins — 0% (Universal Statutory Exemption HSN 9619)'),
    _r('sofy', null, 0.00, 'Sanitary Napkins — 0% (Universal Statutory Exemption HSN 9619)'),
    _r('tampon', null, 0.00, 'Tampons — 0% (Universal Statutory Exemption HSN 9619)'),
    _r('menstrual cup', null, 0.00, 'Menstrual Hygiene — 0% (Universal Statutory Exemption HSN 9619)'),

    // ── Contraceptives (HSN 4014) ──────────────────────────────────────────
    _r('condom', null, 0.00, 'Contraceptives — 0% (Universal Statutory Exemption HSN 4014)'),
    _r('durex', null, 0.00, 'Contraceptives — 0% (Universal Statutory Exemption HSN 4014)'),
    _r('moods condom', null, 0.00, 'Contraceptives — 0% (Universal Statutory Exemption HSN 4014)'),
    _r('manforce', null, 0.00, 'Contraceptives — 0% (Universal Statutory Exemption HSN 4014)'),
    _r('skore', null, 0.00, 'Contraceptives — 0% (Universal Statutory Exemption HSN 4014)'),

    // ── Life-Saving Oncology Medications (Notification 09/2025-CT(R)) ───────
    _r('trastuzumab', null, 0.00, 'Life-Saving Cancer Drug — 0% (Universal Statutory Exemption)'),
    _r('osimertinib', null, 0.00, 'Life-Saving Cancer Drug — 0% (Universal Statutory Exemption)'),
    _r('durvalumab', null, 0.00, 'Life-Saving Cancer Drug — 0% (Universal Statutory Exemption)'),
    _r('cancer medicine', null, 0.00, 'Life-Saving Oncology Drug — 0% (Universal Statutory Exemption)'),

    // ── Fresh Produce & Raw Perishables (HSN 02, 03, 04, 07, 08) ─────────────
    // Fresh vegetables and fruits: category-scoped to prevent collisions with tech brands (Apple) and savory snacks (Potato chips)
    _r('fresh potato', null, 0.00, 'Fresh Vegetables — 0% (Universal Statutory Exemption HSN 0701)'),
    _r('raw potato', null, 0.00, 'Fresh Vegetables — 0% (Universal Statutory Exemption HSN 0701)'),
    _r('potato', 'Fruits & Vegs', 0.00, 'Fresh Vegetables — 0% (Universal Statutory Exemption HSN 0701)'),
    _r('potato', 'Grocery', 0.00, 'Fresh Vegetables — 0% (Universal Statutory Exemption HSN 0701)'),
    _r('fresh onion', null, 0.00, 'Fresh Vegetables — 0% (Universal Statutory Exemption HSN 0703)'),
    _r('onion', 'Fruits & Vegs', 0.00, 'Fresh Vegetables — 0% (Universal Statutory Exemption HSN 0703)'),
    _r('onion', 'Grocery', 0.00, 'Fresh Vegetables — 0% (Universal Statutory Exemption HSN 0703)'),
    _r('fresh tomato', null, 0.00, 'Fresh Vegetables — 0% (Universal Statutory Exemption HSN 0702)'),
    _r('tomato', 'Fruits & Vegs', 0.00, 'Fresh Vegetables — 0% (Universal Statutory Exemption HSN 0702)'),
    _r('tomato', 'Grocery', 0.00, 'Fresh Vegetables — 0% (Universal Statutory Exemption HSN 0702)'),
    _r('fresh apple', null, 0.00, 'Fresh Fruits — 0% (Universal Statutory Exemption HSN 0808)'),
    _r('apple fruit', null, 0.00, 'Fresh Fruits — 0% (Universal Statutory Exemption HSN 0808)'),
    _r('apple', 'Fruits & Vegs', 0.00, 'Fresh Fruits — 0% (Universal Statutory Exemption HSN 0808)'),
    _r('apple', 'Grocery', 0.00, 'Fresh Fruits — 0% (Universal Statutory Exemption HSN 0808)'),
    _r('fresh banana', null, 0.00, 'Fresh Fruits — 0% (Universal Statutory Exemption HSN 0803)'),
    _r('banana', 'Fruits & Vegs', 0.00, 'Fresh Fruits — 0% (Universal Statutory Exemption HSN 0803)'),
    _r('banana', 'Grocery', 0.00, 'Fresh Fruits — 0% (Universal Statutory Exemption HSN 0803)'),
    _r('fresh mango', null, 0.00, 'Fresh Fruits — 0% (Universal Statutory Exemption HSN 0804)'),
    _r('mango', 'Fruits & Vegs', 0.00, 'Fresh Fruits — 0% (Universal Statutory Exemption HSN 0804)'),
    _r('mango', 'Grocery', 0.00, 'Fresh Fruits — 0% (Universal Statutory Exemption HSN 0804)'),
    _r('spinach', null, 0.00, 'Fresh Vegetables — 0% (Universal Statutory Exemption)'),
    _r('palak', null, 0.00, 'Fresh Vegetables — 0% (Universal Statutory Exemption)'),
    _r('coriander', null, 0.00, 'Fresh Herbs — 0% (Universal Statutory Exemption)'),
    _r('ginger', null, 0.00, 'Fresh Produce — 0% (Universal Statutory Exemption)'),
    _r('garlic', null, 0.00, 'Fresh Produce — 0% (Universal Statutory Exemption)'),
    _r('fresh milk', null, 0.00, 'Fresh Milk — 0% (Universal Statutory Exemption HSN 0401)'),
    _r('loose milk', null, 0.00, 'Loose Milk — 0% (Universal Statutory Exemption HSN 0401)'),
    _r('fresh egg', null, 0.00, 'Fresh Eggs in Shell — 0% (Universal Statutory Exemption HSN 0407)'),
    _r('farm eggs', null, 0.00, 'Fresh Eggs in Shell — 0% (Universal Statutory Exemption HSN 0407)'),
    _r('fresh chicken', null, 0.00, 'Fresh Unprocessed Meat — 0% (Universal Statutory Exemption HSN 0207)'),
    _r('fresh mutton', null, 0.00, 'Fresh Unprocessed Meat — 0% (Universal Statutory Exemption HSN 0204)'),
    _r('fresh fish', null, 0.00, 'Fresh Fish — 0% (Universal Statutory Exemption Chapter 3)'),

    // ── Fresh Cut Flowers & Garlands (HSN 0603) ─────────────────────────────
    _r('rose', 'Flowers', 0.00, 'Natural Cut Flowers — 0% (Universal Statutory Exemption HSN 0603)'),
    _r('marigold', 'Flowers', 0.00, 'Natural Cut Flowers — 0% (Universal Statutory Exemption HSN 0603)'),
    _r('jasmine', 'Flowers', 0.00, 'Natural Cut Flowers — 0% (Universal Statutory Exemption HSN 0603)'),
    _r('bouquet', 'Flowers', 0.00, 'Fresh Flower Bouquet — 0% (Universal Statutory Exemption HSN 0603)'),
    _r('garland', 'Flowers', 0.00, 'Fresh Flower Garland — 0% (Universal Statutory Exemption HSN 0603)'),
    _r('gajra', 'Flowers', 0.00, 'Fresh Jasmine Gajra — 0% (Universal Statutory Exemption)'),
    _r('fresh cut flowers', 'Flowers', 0.00, 'Natural Cut Flowers — 0% (Universal Statutory Exemption HSN 0603)'),

    // ── Plain Bread, Pav, Papad & Unprocessed Salt (HSN 1905, 2501) ──────────
    _r('bread', 'Bakery', 0.00, 'Plain Bread / Pav — 0% (Universal Statutory Exemption HSN 1905)'),
    _r('white bread', 'Bakery', 0.00, 'Plain Bread — 0% (Universal Statutory Exemption)'),
    _r('brown bread', 'Bakery', 0.00, 'Plain Bread — 0% (Universal Statutory Exemption)'),
    _r('ladi pav', 'Bakery', 0.00, 'Plain Pav — 0% (Universal Statutory Exemption)'),
    _r('papad', null, 0.00, 'Uncooked Dry Papad — 0% (Universal Statutory Exemption HSN 1905)'),
    _r('lijjat papad', null, 0.00, 'Uncooked Dry Papad — 0% (Universal Statutory Exemption)'),
    _r('salt', 'Grocery', 0.00, 'Salt — 0% (Universal Statutory Exemption HSN 2501)'),
    _r('rock salt', 'Grocery', 0.00, 'Rock Salt — 0% (Universal Statutory Exemption HSN 2501)'),
  ];

  /// Tests whether a given keyword and optional category hint match an inviolable 0% exemption.
  static bool _isUniversalExempt(String kw, String? catHint) {
    for (final rule in _inviolableStatutoryExemptions) {
      if (kw.contains(rule.keyword)) {
        if (rule.categoryHint == null ||
            (catHint != null && rule.categoryHint!.toLowerCase() == catHint.toLowerCase())) {
          return true;
        }
      }
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // Built-in keyword rules (mirrors statutory research & migration seed data)
  // These are the baseline that always work even without DB.
  // ---------------------------------------------------------------------------
  static final List<_KeywordRule> _builtInRules = [
    // ── 1. Sin Goods / Tobacco / Demerit — 40% (Peak Slabs) ──────────────────
    _r('cigarette', null, 0.40, 'Tobacco Products — 40% (Budget 2026)'),
    _r('cigarettes', null, 0.40, 'Tobacco Products — 40% (Budget 2026)'),
    _r('marlboro', null, 0.40, 'Cigarettes — 40% (Budget 2026)'),
    _r('gold flake', null, 0.40, 'Cigarettes — 40% (Budget 2026)'),
    _r('classic milds', null, 0.40, 'Cigarettes — 40% (Budget 2026)'),
    _r('wills navy', null, 0.40, 'Cigarettes — 40% (Budget 2026)'),
    _r('dunhill', null, 0.40, 'Cigarettes — 40% (Budget 2026)'),
    _r('cigar', null, 0.40, 'Cigars — 40% (Budget 2026)'),
    _r('bidi', null, 0.40, 'Bidis — 40% (Budget 2026)'),
    _r('tobacco', null, 0.40, 'Tobacco — 40% (Budget 2026)'),
    _r('gutka', null, 0.40, 'Gutka — 40% (Budget 2026)'),
    _r('pan masala', null, 0.40, 'Pan Masala — 40% (Budget 2026)'),
    _r('rajnigandha', null, 0.40, 'Pan Masala — 40%'),
    _r('vimal pan masala', null, 0.40, 'Pan Masala — 40%'),
    _r('khaini', null, 0.40, 'Tobacco Products — 40%'),
    _r('hookah', null, 0.40, 'Hookah Tobacco — 40%'),
    _r('shisha', null, 0.40, 'Shisha — 40%'),
    _r('zarda', null, 0.40, 'Zarda — 40%'),
    _r('aerated drink', 'Beverages', 0.40, 'Aerated Drinks — 40% Peak Slab'),
    _r('cola', 'Beverages', 0.40, 'Cola Drinks — 40% Peak Slab'),
    _r('energy drink', 'Beverages', 0.40, 'Energy Drinks — 40% Peak Slab'),
    _r('red bull', 'Beverages', 0.40, 'Energy Drinks — 40% Peak Slab'),
    _r('monster energy', 'Beverages', 0.40, 'Energy Drinks — 40% Peak Slab'),
    _r('sting energy', 'Beverages', 0.40, 'Energy Drinks — 40% Peak Slab'),
    _r('pepsi', 'Beverages', 0.40, 'Aerated Soft Drink — 40%'),
    _r('sprite', 'Beverages', 0.40, 'Aerated Soft Drink — 40%'),
    _r('thums up', 'Beverages', 0.40, 'Aerated Soft Drink — 40%'),
    _r('coca cola', 'Beverages', 0.40, 'Aerated Soft Drink — 40%'),
    _r('coca-cola', 'Beverages', 0.40, 'Aerated Soft Drink — 40%'),
    _r('coke', 'Beverages', 0.40, 'Aerated Soft Drink — 40%'),
    _r('mountain dew', 'Beverages', 0.40, 'Aerated Soft Drink — 40%'),
    _r('fanta', 'Beverages', 0.40, 'Aerated Soft Drink — 40%'),
    _r('limca', 'Beverages', 0.40, 'Aerated Soft Drink — 40%'),
    _r('7up', 'Beverages', 0.40, 'Aerated Soft Drink — 40%'),
    _r('carbonated', 'Beverages', 0.40, 'Carbonated Drinks — 40%'),
    _r('appy fizz', 'Beverages', 0.40, 'Carbonated Fruit Drink — 40% (Notif 8/2021)'),
    _r('b-fizz', 'Beverages', 0.40, 'Carbonated Fruit Drink — 40%'),
    _r('nimbooz masala soda', 'Beverages', 0.40, 'Carbonated Fruit Drink — 40%'),

    // ── 2. Fresh Produce & Perishables — 0% Universal Statutory Exemption ─────
    _r('onion', null, 0.00, 'Fresh Vegetables — 0% (Universal Statutory Exemption)'),
    _r('potato', null, 0.00, 'Fresh Vegetables — 0% (Universal Statutory Exemption)'),
    _r('tomato', null, 0.00, 'Fresh Vegetables — 0% (Universal Statutory Exemption)'),
    _r('spinach', null, 0.00, 'Fresh Vegetables — 0% (Universal Statutory Exemption)'),
    _r('palak', null, 0.00, 'Fresh Vegetables — 0% (Universal Statutory Exemption)'),
    _r('broccoli', null, 0.00, 'Fresh Vegetables — 0% (Universal Statutory Exemption)'),
    _r('cauliflower', null, 0.00, 'Fresh Vegetables — 0% (Universal Statutory Exemption)'),
    _r('gobi', null, 0.00, 'Fresh Vegetables — 0% (Universal Statutory Exemption)'),
    _r('cabbage', null, 0.00, 'Fresh Vegetables — 0% (Universal Statutory Exemption)'),
    _r('carrot', null, 0.00, 'Fresh Vegetables — 0% (Universal Statutory Exemption)'),
    _r('gajar', null, 0.00, 'Fresh Vegetables — 0% (Universal Statutory Exemption)'),
    _r('capsicum', null, 0.00, 'Fresh Vegetables — 0% (Universal Statutory Exemption)'),
    _r('cucumber', null, 0.00, 'Fresh Vegetables — 0% (Universal Statutory Exemption)'),
    _r('kheera', null, 0.00, 'Fresh Vegetables — 0% (Universal Statutory Exemption)'),
    _r('garlic', null, 0.00, 'Fresh Vegetables — 0% (Universal Statutory Exemption)'),
    _r('ginger', null, 0.00, 'Fresh Produce — 0% (Universal Statutory Exemption)'),
    _r('lemon', null, 0.00, 'Fresh Fruits — 0% (Universal Statutory Exemption)'),
    _r('nimbu', null, 0.00, 'Fresh Fruits — 0% (Universal Statutory Exemption)'),
    _r('green chilli', null, 0.00, 'Fresh Vegetables — 0% (Universal Statutory Exemption)'),
    _r('coriander', null, 0.00, 'Fresh Herbs — 0% (Universal Statutory Exemption)'),
    _r('mint', null, 0.00, 'Fresh Herbs — 0% (Universal Statutory Exemption)'),
    _r('apple', null, 0.00, 'Fresh Fruits — 0% (Universal Statutory Exemption)'),
    _r('banana', null, 0.00, 'Fresh Fruits — 0% (Universal Statutory Exemption)'),
    _r('mango', null, 0.00, 'Fresh Fruits — 0% (Universal Statutory Exemption)'),
    _r('orange', null, 0.00, 'Fresh Fruits — 0% (Universal Statutory Exemption)'),
    _r('papaya', null, 0.00, 'Fresh Fruits — 0% (Universal Statutory Exemption)'),
    _r('grapes', null, 0.00, 'Fresh Fruits — 0% (Universal Statutory Exemption)'),
    _r('pomegranate', null, 0.00, 'Fresh Fruits — 0% (Universal Statutory Exemption)'),
    _r('watermelon', null, 0.00, 'Fresh Fruits — 0% (Universal Statutory Exemption)'),
    _r('pineapple', null, 0.00, 'Fresh Fruits — 0% (Universal Statutory Exemption)'),
    _r('guava', null, 0.00, 'Fresh Fruits — 0% (Universal Statutory Exemption)'),
    _r('coconut tender', null, 0.00, 'Fresh Tender Coconut — 0% (Universal Statutory Exemption)'),
    _r('tender coconut', null, 0.00, 'Fresh Tender Coconut — 0% (Universal Statutory Exemption)'),
    _r('fresh chicken', null, 0.00, 'Fresh Unprocessed Meat — 0% (Universal Statutory Exemption)'),
    _r('raw chicken', null, 0.00, 'Fresh Unprocessed Meat — 0% (Universal Statutory Exemption)'),
    _r('chicken curry cut', null, 0.00, 'Fresh Meat — 0% (Universal Statutory Exemption)'),
    _r('chicken breast', null, 0.00, 'Fresh Meat — 0% (Universal Statutory Exemption)'),
    _r('fresh mutton', null, 0.00, 'Fresh Meat — 0% (Universal Statutory Exemption)'),
    _r('goat meat', null, 0.00, 'Fresh Meat — 0% (Universal Statutory Exemption)'),
    _r('fresh fish', null, 0.00, 'Fresh Fish — 0% (Universal Statutory Exemption)'),
    _r('pomfret', null, 0.00, 'Fresh Fish — 0% (Universal Statutory Exemption)'),
    _r('surmai', null, 0.00, 'Fresh Fish — 0% (Universal Statutory Exemption)'),
    _r('rohu', null, 0.00, 'Fresh Fish — 0% (Universal Statutory Exemption)'),
    _r('fresh prawns', null, 0.00, 'Fresh Seafood — 0% (Universal Statutory Exemption)'),
    _r('fresh egg', null, 0.00, 'Fresh Eggs in Shell — 0% (Universal Statutory Exemption)'),
    _r('farm eggs', null, 0.00, 'Fresh Eggs in Shell — 0% (Universal Statutory Exemption)'),
    _r('farm fresh brown eggs', null, 0.00, 'Fresh Eggs in Shell — 0% (Universal Statutory Exemption)'),
    _r('egg carton', null, 0.00, 'Fresh Eggs in Shell — 0% (Universal Statutory Exemption)'),
    _r('fresh milk', null, 0.00, 'Fresh Milk — 0% (Universal Statutory Exemption)'),
    _r('toned milk', null, 0.00, 'Pasteurised Milk — 0% (Universal Statutory Exemption)'),
    _r('cow milk', null, 0.00, 'Fresh Milk — 0% (Universal Statutory Exemption)'),
    _r('uht milk', null, 0.00, 'UHT Milk — 0% (Universal Statutory Exemption)'),
    _r('amul taaza', null, 0.00, 'Fresh Milk — 0% (Universal Statutory Exemption)'),
    _r('amul gold', null, 0.00, 'Fresh Milk — 0% (Universal Statutory Exemption)'),
    _r('mother dairy milk', null, 0.00, 'Fresh Milk — 0% (Universal Statutory Exemption)'),
    _r('loose salt', null, 0.00, 'Loose Unbranded Salt — 0% (Universal Statutory Exemption)'),
    _r('fresh paneer', null, 0.00, 'Fresh Unpackaged Paneer — 0% (Universal Statutory Exemption)'),
    _r('fresh curd', null, 0.00, 'Fresh Unpackaged Curd/Dahi — 0% (Universal Statutory Exemption)'),

    // ── 3. Educational & Healthcare Universal Exemptions — 0% ────────────────
    _r('notebook', 'Stationery', 0.00, 'Exercise Notebooks — 0% (Exempt HSN 4820)'),
    _r('exercise book', 'Stationery', 0.00, 'Exercise Books — 0% (Exempt)'),
    _r('classmate notebook', 'Stationery', 0.00, 'Exercise Books — 0% (Exempt)'),
    _r('drawing book', 'Stationery', 0.00, 'Drawing Books — 0% (Exempt)'),
    _r('graph book', 'Stationery', 0.00, 'Graph Books — 0% (Exempt)'),
    _r('lab notebook', 'Stationery', 0.00, 'Laboratory Notebooks — 0% (Exempt)'),
    _r('pencil', 'Stationery', 0.00, 'Pencils — 0% (Exempt HSN 9609)'),
    _r('pencil', null, 0.00, 'Pencils — 0% (Exempt HSN 9609)'),
    _r('writing pencil', null, 0.00, 'Pencils — 0% (Exempt HSN 9609)'),
    _r('lead pencil', null, 0.00, 'Pencils — 0% (Exempt HSN 9609)'),
    _r('color pencil', 'Stationery', 0.00, 'Student Color Pencils — 0% (Exempt HSN 9609)'),
    _r('color pencil', null, 0.00, 'Student Color Pencils — 0% (Exempt HSN 9609)'),
    _r('colored pencil', null, 0.00, 'Student Color Pencils — 0% (Exempt HSN 9609)'),
    _r('slate pencil', null, 0.00, 'Slate Pencils — 0% (Exempt HSN 9609)'),
    _r('mechanical pencil', null, 0.00, 'Mechanical Pencils — 0% (Exempt HSN 9609)'),
    _r('apsara pencil', 'Stationery', 0.00, 'Pencils — 0% (Exempt)'),
    _r('nataraj pencil', 'Stationery', 0.00, 'Pencils — 0% (Exempt)'),
    _r('doms pencil', null, 0.00, 'Pencils — 0% (Exempt)'),
    _r('eraser', 'Stationery', 0.00, 'Erasers — 0% (Exempt HSN 4016)'),
    _r('eraser', null, 0.00, 'Erasers — 0% (Exempt HSN 4016)'),
    _r('rubber eraser', null, 0.00, 'Erasers — 0% (Exempt HSN 4016)'),
    _r('sharpener', 'Stationery', 0.00, 'Sharpeners — 0% (Exempt HSN 8214)'),
    _r('sharpener', null, 0.00, 'Sharpeners — 0% (Exempt HSN 8214)'),
    _r('pencil sharpener', null, 0.00, 'Sharpeners — 0% (Exempt HSN 8214)'),
    _r('textbook', 'Stationery', 0.00, 'Printed Books — 0% (Exempt HSN 4901)'),
    _r('ncert', 'Stationery', 0.00, 'Educational Books — 0% (Exempt)'),
    _r('crayons', 'Stationery', 0.00, 'Crayons — 0% (Exempt HSN 9609)'),
    _r('crayon', 'Stationery', 0.00, 'Crayons — 0% (Exempt HSN 9609)'),
    _r('crayons', null, 0.00, 'Crayons — 0% (Exempt HSN 9609)'),
    _r('crayon', null, 0.00, 'Crayons — 0% (Exempt HSN 9609)'),
    _r('oil pastels', null, 0.00, 'Oil Pastels — 0% (Exempt HSN 9609)'),
    _r('wax crayons', null, 0.00, 'Wax Crayons — 0% (Exempt HSN 9609)'),
    _r('chalk', null, 0.00, 'Writing Chalk — 0% (Exempt HSN 9609)'),
    _r('slate', null, 0.00, 'Educational Slates — 0% (Exempt HSN 9609)'),
    _r('sanitary pad', null, 0.00, 'Sanitary Napkins — 0% (Universal Exemption HSN 9619)'),
    _r('sanitary napkin', null, 0.00, 'Sanitary Napkins — 0% (Universal Exemption HSN 9619)'),
    _r('whisper', null, 0.00, 'Sanitary Napkins — 0% (Exempt)'),
    _r('stayfree', null, 0.00, 'Sanitary Napkins — 0% (Exempt)'),
    _r('sofy', null, 0.00, 'Sanitary Napkins — 0% (Exempt)'),
    _r('tampon', null, 0.00, 'Tampons — 0% (Exempt HSN 9619)'),
    _r('condom', null, 0.00, 'Contraceptives — 0% (Exempt HSN 4014)'),
    _r('durex', null, 0.00, 'Contraceptives — 0% (Exempt)'),
    _r('moods condom', null, 0.00, 'Contraceptives — 0% (Exempt)'),
    _r('trastuzumab', 'Pharmacy', 0.00, 'Life-Saving Cancer Drug — 0% (GST 2.0)'),
    _r('osimertinib', 'Pharmacy', 0.00, 'Life-Saving Cancer Drug — 0% (GST 2.0)'),
    _r('fresh cut flowers', 'Flowers', 0.00, 'Natural Cut Flowers — 0% (Exempt HSN 0603)'),
    _r('rose garland', 'Flowers', 0.00, 'Fresh Flower Garland — 0% (Exempt)'),
    _r('marigold garland', 'Flowers', 0.00, 'Fresh Flower Garland — 0% (Exempt)'),
    _r('gajra', 'Flowers', 0.00, 'Fresh Jasmine Gajra — 0% (Exempt)'),
    _r('betel leaf', 'Paan Shop', 0.00, 'Fresh Betel Leaves — 0% (Exempt HSN 1404)'),
    _r('paan patta', 'Paan Shop', 0.00, 'Fresh Betel Leaves — 0% (Exempt)'),
    _r('papad', null, 0.00, 'Uncooked Dry Papad — 0% (Exempt HSN 1905)'),
    _r('lijjat papad', null, 0.00, 'Uncooked Dry Papad — 0% (Exempt)'),
    _r('bread', 'Bakery', 0.00, 'Plain Bread / Pav — 0% (Exempt HSN 1905)'),
    _r('white bread', 'Bakery', 0.00, 'Plain Bread — 0% (Exempt)'),
    _r('brown bread', 'Bakery', 0.00, 'Plain Bread — 0% (Exempt)'),
    _r('ladi pav', 'Bakery', 0.00, 'Plain Pav — 0% (Exempt)'),
    _r('salt', 'Grocery', 0.00, 'Salt — 0% (Exempt HSN 2501)'),
    _r('tata salt', 'Grocery', 0.00, 'Salt — 0% (Exempt)'),
    _r('rock salt', 'Grocery', 0.00, 'Rock Salt — 0% (Exempt)'),

    // ── 4. Savory Snacks & Processed Foods — 12% (54th GST Council & Sched II) ──
    _r('kurkure', null, 0.12, 'Extruded Savoury Snacks — 12% (54th GST Council)'),
    _r('cheetos', null, 0.12, 'Extruded Savoury Snacks — 12% (54th GST Council)'),
    _r('puffcorn', null, 0.12, 'Extruded Savoury Snacks — 12% (54th GST Council)'),
    _r('fun flips', null, 0.12, 'Extruded Savoury Snacks — 12% (54th GST Council)'),
    _r('namkeen', null, 0.12, 'Pre-packaged Namkeen — 12% (HSN 2106 90)'),
    _r('bhujia', null, 0.12, 'Pre-packaged Bhujia — 12% (HSN 2106 90)'),
    _r('aloo bhujia', null, 0.12, 'Pre-packaged Bhujia — 12%'),
    _r('haldiram bhujia', null, 0.12, 'Pre-packaged Bhujia — 12%'),
    _r('bikaji bhujia', null, 0.12, 'Pre-packaged Bhujia — 12%'),
    _r('chivda', null, 0.12, 'Pre-packaged Namkeen — 12%'),
    _r('khatta meetha', null, 0.12, 'Pre-packaged Namkeen — 12%'),
    _r('potato chips', null, 0.12, 'Savory Potato Chips — 12% (HSN 2005/2106)'),
    _r('chips', 'Grocery', 0.12, 'Savory Potato Chips — 12%'),
    _r('lays', null, 0.12, 'Potato Chips — 12% (HSN 2005 20)'),
    _r('uncle chipps', null, 0.12, 'Potato Chips — 12%'),
    _r('bingo chips', null, 0.12, 'Savory Chips — 12%'),
    _r('pringles', null, 0.12, 'Savory Crisps — 12%'),
    _r('butter', 'Dairy & Eggs', 0.12, 'Butter & Dairy Spreads — 12% (HSN 0405)'),
    _r('amul butter', 'Dairy & Eggs', 0.12, 'Butter — 12% (HSN 0405 10)'),
    _r('ghee', 'Dairy & Eggs', 0.12, 'Desi Ghee — 12% (HSN 0405 90)'),
    _r('cow ghee', 'Dairy & Eggs', 0.12, 'Desi Ghee — 12%'),
    _r('cheese', 'Dairy & Eggs', 0.12, 'Processed Cheese / Mozzarella — 12% (HSN 0406)'),
    _r('amul cheese', 'Dairy & Eggs', 0.12, 'Processed Cheese — 12%'),
    _r('cheese slices', 'Dairy & Eggs', 0.12, 'Processed Cheese — 12%'),
    _r('mozzarella', 'Dairy & Eggs', 0.12, 'Cheese — 12%'),
    _r('condensed milk', 'Dairy & Eggs', 0.12, 'Condensed Milk — 12% (HSN 0402 91)'),
    _r('milkmaid', 'Dairy & Eggs', 0.12, 'Condensed Milk — 12%'),
    _r('flavoured milk', 'Dairy & Eggs', 0.12, 'Flavoured Milk Beverage — 12% (Circular 163)'),
    _r('amul kool', 'Dairy & Eggs', 0.12, 'Flavoured Milk — 12% (HSN 2202 99 30)'),
    _r('cavin milkshake', 'Dairy & Eggs', 0.12, 'Flavoured Milk — 12%'),
    _r('badam milk', 'Dairy & Eggs', 0.12, 'Flavoured Milk — 12%'),
    _r('fruit juice', 'Beverages', 0.12, 'Packaged Fruit Juice — 12% (HSN 2009)'),
    _r('real juice', 'Beverages', 0.12, 'Fruit Juice — 12%'),
    _r('tropicana', 'Beverages', 0.12, 'Fruit Juice — 12%'),
    _r('frooti', 'Beverages', 0.12, 'Fruit Pulp Drink — 12% (HSN 2202 99 20)'),
    _r('maaza', 'Beverages', 0.12, 'Fruit Pulp Drink — 12%'),
    _r('slice', 'Beverages', 0.12, 'Fruit Pulp Drink — 12%'),
    _r('sausage', 'Butcher', 0.12, 'Processed Cured Meat — 12% (HSN 1601)'),
    _r('salami', 'Butcher', 0.12, 'Processed Meat — 12%'),
    _r('bacon', 'Butcher', 0.12, 'Processed Meat — 12%'),
    _r('canned tuna', 'Fish & Seafood', 0.12, 'Preserved Fish — 12% (HSN 1604)'),
    _r('menstrual cup', 'Pharmacy', 0.12, 'Menstrual Cups — 12% (HSN 9619)'),

    // ── 5. Packaged Food & Groceries — 5% Merit Rate (GST 2.0 Rationalized) ───
    _r('rice', 'Grocery', 0.05, 'Pre-packaged Basmati/Grain — 5% (HSN 1006)'),
    _r('basmati rice', 'Grocery', 0.05, 'Pre-packaged Rice — 5%'),
    _r('daawat', 'Grocery', 0.05, 'Pre-packaged Rice — 5%'),
    _r('india gate', 'Grocery', 0.05, 'Pre-packaged Rice — 5%'),
    _r('atta', 'Grocery', 0.05, 'Pre-packaged Wheat Flour — 5% (HSN 1101)'),
    _r('aashirvaad atta', 'Grocery', 0.05, 'Pre-packaged Atta — 5%'),
    _r('maida', 'Grocery', 0.05, 'Pre-packaged Flour — 5%'),
    _r('sooji', 'Grocery', 0.05, 'Pre-packaged Sooji/Rava — 5%'),
    _r('besan', 'Grocery', 0.05, 'Pre-packaged Besan — 5% (HSN 1106)'),
    _r('dal', 'Grocery', 0.05, 'Pre-packaged Pulses — 5% (HSN 0713)'),
    _r('toor dal', 'Grocery', 0.05, 'Pre-packaged Pulses — 5%'),
    _r('moong dal', 'Grocery', 0.05, 'Pre-packaged Pulses — 5%'),
    _r('chana dal', 'Grocery', 0.05, 'Pre-packaged Pulses — 5%'),
    _r('urad dal', 'Grocery', 0.05, 'Pre-packaged Pulses — 5%'),
    _r('rajma', 'Grocery', 0.05, 'Pre-packaged Kidney Beans — 5%'),
    _r('chhole', 'Grocery', 0.05, 'Pre-packaged Chickpeas — 5%'),
    _r('cooking oil', 'Grocery', 0.05, 'Edible Cooking Oil — 5% (HSN 1507-1515)'),
    _r('mustard oil', 'Grocery', 0.05, 'Edible Mustard Oil — 5%'),
    _r('sunflower oil', 'Grocery', 0.05, 'Edible Sunflower Oil — 5%'),
    _r('fortune oil', 'Grocery', 0.05, 'Edible Cooking Oil — 5%'),
    _r('saffola', 'Grocery', 0.05, 'Edible Cooking Oil — 5%'),
    _r('sugar', 'Grocery', 0.05, 'Refined Sugar — 5% (HSN 1701)'),
    _r('jaggery', 'Grocery', 0.05, 'Pre-packaged Gur/Jaggery — 5% (HSN 1701)'),
    _r('honey', 'Grocery', 0.05, 'Natural Honey — 5% (HSN 0409)'),
    _r('dabur honey', 'Grocery', 0.05, 'Honey — 5%'),
    _r('spices', 'Grocery', 0.05, 'Spices & Condiments — 5% (Chapter 9)'),
    _r('masala', 'Grocery', 0.05, 'Blended Masalas — 5% (HSN 0910 91)'),
    _r('garam masala', 'Grocery', 0.05, 'Blended Masalas — 5%'),
    _r('sambar masala', 'Grocery', 0.05, 'Blended Masalas — 5%'),
    _r('biryani masala', 'Grocery', 0.05, 'Blended Masalas — 5%'),
    _r('haldi powder', 'Grocery', 0.05, 'Turmeric Powder — 5%'),
    _r('red chilli powder', 'Grocery', 0.05, 'Chilli Powder — 5%'),
    _r('ginger garlic paste', 'Grocery', 0.05, 'Cooking Pastes — 5% (HSN 2103 90)'),
    _r('tomato ketchup', 'Grocery', 0.05, 'Sauces & Ketchups — 5% (Notif 9/2025)'),
    _r('ketchup', 'Grocery', 0.05, 'Sauces & Ketchups — 5%'),
    _r('sauce', 'Grocery', 0.05, 'Table Sauces — 5% (HSN 2103)'),
    _r('mayonnaise', 'Grocery', 0.05, 'Mayonnaise & Dressings — 5% (HSN 2103 90)'),
    _r('pickle', 'Grocery', 0.05, 'Pickles / Achaar — 5% (Notif 9/2025 HSN 2001)'),
    _r('achaar', 'Grocery', 0.05, 'Pickles / Achaar — 5%'),
    _r('almonds', 'Grocery', 0.05, 'Edible Nuts — 5% (HSN 0802)'),
    _r('cashews', 'Grocery', 0.05, 'Edible Cashews — 5% (HSN 0801)'),
    _r('kaju', 'Grocery', 0.05, 'Edible Cashews — 5%'),
    _r('badam', 'Grocery', 0.05, 'Edible Almonds — 5%'),
    _r('walnuts', 'Grocery', 0.05, 'Edible Walnuts — 5%'),
    _r('raisins', 'Grocery', 0.05, 'Dried Grapes / Kishmish — 5%'),
    _r('dates', 'Grocery', 0.05, 'Edible Dates / Khajoor — 5%'),
    _r('packaged water', 'Beverages', 0.05, 'Packaged Drinking Water — 5% (54th GST Council)'),
    _r('mineral water', 'Beverages', 0.05, 'Packaged Drinking Water — 5% (HSN 2201)'),
    _r('bisleri', 'Beverages', 0.05, 'Packaged Drinking Water — 5%'),
    _r('kinley', 'Beverages', 0.05, 'Packaged Drinking Water — 5%'),
    _r('aquafina', 'Beverages', 0.05, 'Packaged Drinking Water — 5%'),
    _r('water 20l', 'Beverages', 0.05, '20 Litre Bulk Water Jar — 5% (54th Council)'),
    _r('tea', 'Beverages', 0.05, 'Tea Leaves & Bags — 5% (HSN 0902)'),
    _r('chai', 'Beverages', 0.05, 'Tea — 5%'),
    _r('green tea', 'Beverages', 0.05, 'Green Tea — 5%'),
    _r('tata tea', 'Beverages', 0.05, 'Tea — 5%'),
    _r('coffee', 'Beverages', 0.05, 'Coffee — 5% (HSN 0901)'),
    _r('instant coffee', 'Beverages', 0.05, 'Instant Coffee — 5% (Notif 9/2025 HSN 2101)'),
    _r('nescafe', 'Beverages', 0.05, 'Instant Coffee — 5%'),
    _r('bru', 'Beverages', 0.05, 'Instant Coffee — 5%'),
    _r('curd', 'Dairy & Eggs', 0.05, 'Pre-packaged Curd / Dahi — 5% (HSN 0403)'),
    _r('dahi', 'Dairy & Eggs', 0.05, 'Pre-packaged Dahi — 5%'),
    _r('amul masti dahi', 'Dairy & Eggs', 0.05, 'Pre-packaged Dahi — 5%'),
    _r('lassi', 'Dairy & Eggs', 0.05, 'Pre-packaged Lassi — 5% (HSN 0403)'),
    _r('buttermilk', 'Dairy & Eggs', 0.05, 'Pre-packaged Buttermilk — 5%'),
    _r('chach', 'Dairy & Eggs', 0.05, 'Pre-packaged Buttermilk — 5%'),
    _r('paneer', 'Dairy & Eggs', 0.05, 'Pre-packaged Paneer — 5% (HSN 0406)'),
    _r('amul paneer', 'Dairy & Eggs', 0.05, 'Pre-packaged Paneer — 5%'),
    _r('dairy whitener', 'Dairy & Eggs', 0.05, 'Dairy Whitener — 5% (HSN 0402)'),
    _r('amulya', 'Dairy & Eggs', 0.05, 'Dairy Whitener — 5%'),
    _r('everyday milk powder', 'Dairy & Eggs', 0.05, 'Dairy Whitener — 5%'),
    _r('milk powder', 'Dairy & Eggs', 0.05, 'Milk Powder — 5% (HSN 0402)'),
    _r('infant milk food', 'Dairy & Eggs', 0.05, 'Infant Baby Milk Formula — 5% (HSN 0402)'),
    _r('lactogen', 'Dairy & Eggs', 0.05, 'Baby Formula — 5%'),
    _r('nan pro', 'Dairy & Eggs', 0.05, 'Baby Formula — 5%'),
    _r('similac', 'Dairy & Eggs', 0.05, 'Baby Formula — 5%'),
    _r('rusk', 'Bakery', 0.05, 'Rusks & Toast — 5% (HSN 1905 40)'),
    _r('toast', 'Bakery', 0.05, 'Rusks & Toast — 5%'),
    _r('pizza base', 'Bakery', 0.05, 'Pizza Base — 5% (HSN 1905 90 80)'),
    _r('biscuit', 'Bakery', 0.05, 'Packaged Biscuits — 5% (Notif 9/2025 HSN 1905)'),
    _r('cookies', 'Bakery', 0.05, 'Cookies & Biscuits — 5%'),
    _r('parle g', 'Bakery', 0.05, 'Biscuits — 5%'),
    _r('good day', 'Bakery', 0.05, 'Biscuits — 5%'),
    _r('marie gold', 'Bakery', 0.05, 'Biscuits — 5%'),
    _r('oreo', 'Bakery', 0.05, 'Biscuits — 5%'),
    _r('cake', 'Bakery', 0.05, 'Cakes & Pastries — 5% (Notif 9/2025 HSN 1905)'),
    _r('pastry', 'Bakery', 0.05, 'Pastries — 5%'),
    _r('muffin', 'Bakery', 0.05, 'Muffins — 5%'),
    _r('chocolate', null, 0.05, 'Chocolates & Cocoa Bars — 5% (Notif 9/2025 HSN 1806)'),
    _r('cadbury', null, 0.05, 'Chocolates — 5%'),
    _r('dairy milk', null, 0.05, 'Chocolates — 5%'),
    _r('kitkat', null, 0.05, 'Chocolates — 5%'),
    _r('5 star', null, 0.05, 'Chocolates — 5%'),
    _r('snickers', null, 0.05, 'Chocolates — 5%'),
    _r('mithai', 'Sweets & Mithai', 0.05, 'Traditional Indian Sweets — 5% (HSN 2106)'),
    _r('kaju katli', 'Sweets & Mithai', 0.05, 'Traditional Sweets — 5%'),
    _r('gulab jamun', 'Sweets & Mithai', 0.05, 'Traditional Sweets — 5%'),
    _r('rasgulla', 'Sweets & Mithai', 0.05, 'Traditional Sweets — 5%'),
    _r('laddu', 'Sweets & Mithai', 0.05, 'Traditional Sweets — 5%'),
    _r('barfi', 'Sweets & Mithai', 0.05, 'Traditional Sweets — 5%'),
    _r('soan papdi', 'Sweets & Mithai', 0.05, 'Traditional Sweets — 5%'),
    _r('noodles', 'Grocery', 0.05, 'Instant Convenience Noodles — 5% (HSN 1902)'),
    _r('maggi', null, 0.05, 'Instant Noodles — 5% (HSN 1902 30)'),
    _r('yippee', null, 0.05, 'Instant Noodles — 5%'),
    _r('pasta', 'Grocery', 0.05, 'Dry Pasta / Macaroni — 5% (HSN 1902)'),
    _r('macaroni', 'Grocery', 0.05, 'Dry Pasta — 5%'),
    _r('vermicelli', 'Grocery', 0.05, 'Dry Vermicelli / Seviyan — 5% (HSN 1902)'),
    _r('supari', 'Paan Shop', 0.05, 'Edible Betel Nut Products — 5% (HSN 2106 90 30)'),
    _r('snack pellets', 'Grocery', 0.05, 'Un-fried Extruded Snack Pellets — 5%'),
    _r('raw fryums', 'Grocery', 0.05, 'Un-fried Snack Pellets — 5%'),

    // ── 6. Personal Hygiene & Healthcare Merit FMCG — 5% (GST 2.0) ───────────
    _r('diaper', null, 0.05, 'Baby & Adult Diapers — 5% (Reduced from 12% HSN 9619)'),
    _r('pampers', null, 0.05, 'Baby Diapers — 5% (GST 2.0)'),
    _r('huggies', null, 0.05, 'Baby Diapers — 5% (GST 2.0)'),
    _r('mamypoko', null, 0.05, 'Baby Diapers — 5% (GST 2.0)'),
    _r('adult diaper', null, 0.05, 'Adult Diapers — 5% (GST 2.0)'),
    _r('friends adult', null, 0.05, 'Adult Diapers — 5% (GST 2.0)'),
    _r('soap', null, 0.05, 'Toilet Bathing Soap Bars — 5% FMCG Merit Rate'),
    _r('bathing soap', null, 0.05, 'Toilet Soap — 5% FMCG Merit Rate'),
    _r('lux', null, 0.05, 'Toilet Soap — 5% FMCG Merit Rate'),
    _r('lifebuoy', null, 0.05, 'Toilet Soap — 5% FMCG Merit Rate'),
    _r('dettol soap', null, 0.05, 'Toilet Soap — 5% FMCG Merit Rate'),
    _r('dove soap', null, 0.05, 'Toilet Soap — 5% FMCG Merit Rate'),
    _r('shampoo', null, 0.05, 'Shampoo — 5% FMCG Merit Rate (GST 2.0)'),
    _r('head and shoulders', null, 0.05, 'Shampoo — 5% FMCG Merit Rate'),
    _r('head & shoulders', null, 0.05, 'Shampoo — 5% FMCG Merit Rate'),
    _r('pantene', null, 0.05, 'Shampoo — 5% FMCG Merit Rate'),
    _r('sunsilk', null, 0.05, 'Shampoo — 5% FMCG Merit Rate'),
    _r('clinic plus', null, 0.05, 'Shampoo — 5% FMCG Merit Rate'),
    _r('tresemme', null, 0.05, 'Shampoo — 5% FMCG Merit Rate'),
    _r('dove shampoo', null, 0.05, 'Shampoo — 5% FMCG Merit Rate'),
    _r('hair oil', null, 0.05, 'Hair Oil — 5% FMCG Merit Rate'),
    _r('coconut oil', null, 0.05, 'Hair/Cooking Oil — 5% (HSN 1513)'),
    _r('parachute', null, 0.05, 'Hair/Edible Coconut Oil — 5%'),
    _r('dabur amla', null, 0.05, 'Hair Oil — 5% FMCG Merit Rate'),
    _r('vatika', null, 0.05, 'Hair Oil — 5% FMCG Merit Rate'),
    _r('toothpaste', null, 0.05, 'Toothpaste — 5% Dental Hygiene (GST 2.0)'),
    _r('colgate', null, 0.05, 'Toothpaste — 5% Dental Hygiene'),
    _r('pepsodent', null, 0.05, 'Toothpaste — 5% Dental Hygiene'),
    _r('sensodyne', null, 0.05, 'Toothpaste — 5% Dental Hygiene'),
    _r('oral b', null, 0.05, 'Toothpaste / Toothbrush — 5%'),
    _r('toothbrush', null, 0.05, 'Manual Toothbrush — 5% (HSN 9603 21)'),
    _r('talcum powder', null, 0.05, 'Talcum Powder — 5% Merit Rate'),
    _r('baby powder', null, 0.05, 'Baby Talcum Powder — 5%'),
    _r('johnson baby', null, 0.05, 'Baby Care Essentials — 5%'),
    _r('insulin', 'Pharmacy', 0.05, 'Insulin Formulations — 5% (HSN 3004 31 10)'),
    _r('insulin', null, 0.05, 'Insulin Formulations — 5% (HSN 3004 31 10)'),
    _r('paracetamol', 'Pharmacy', 0.05, 'Prescription & OTC Medicine — 5% (HSN 3004)'),
    _r('paracetamol', 'Medical Store', 0.05, 'Prescription & OTC Medicine — 5%'),
    _r('crocin', null, 0.05, 'Paracetamol Formulations — 5%'),
    _r('dolo', null, 0.05, 'Paracetamol Formulations — 5%'),
    _r('combiflam', null, 0.05, 'Pain Relief Medicine — 5%'),
    _r('ibuprofen', null, 0.05, 'Anti-inflammatory Medicine — 5%'),
    _r('aspirin', null, 0.05, 'Analgesic Medicine — 5%'),
    _r('antacid', null, 0.05, 'Antacid — 5%'),
    _r('eno', null, 0.05, 'Antacid — 5%'),
    _r('gelusil', null, 0.05, 'Antacid — 5%'),
    _r('cough syrup', null, 0.05, 'Cough Syrup — 5%'),
    _r('benadryl', null, 0.05, 'Cough Syrup — 5%'),
    _r('vicks', null, 0.05, 'Vaporub / OTC Medicine — 5%'),
    _r('nasal spray', null, 0.05, 'Nasal Decongestant — 5%'),
    _r('eye drop', null, 0.05, 'Eye Drops — 5%'),
    _r('ear drop', null, 0.05, 'Ear Drops — 5%'),
    _r('bandage', null, 0.05, 'Medical Bandage — 5% (HSN 3005)'),
    _r('band-aid', null, 0.05, 'First Aid Band-Aid — 5%'),
    _r('antiseptic', null, 0.05, 'Antiseptic Liquid — 5%'),
    _r('dettol liquid', null, 0.05, 'Antiseptic Liquid — 5%'),
    _r('thermometer', null, 0.05, 'Clinical Thermometer — 5% (HSN 9025)'),
    _r('glucometer', null, 0.05, 'Blood Glucose Monitor — 5% (HSN 9027)'),
    _r('accu chek', null, 0.05, 'Blood Glucose Monitor & Strips — 5%'),
    _r('test strips', null, 0.05, 'Diagnostic Test Strips — 5%'),
    _r('bp monitor', null, 0.05, 'Blood Pressure Monitor — 5% (HSN 9018)'),
    _r('omron bp', null, 0.05, 'Blood Pressure Monitor — 5%'),
    _r('surgical gloves', null, 0.05, 'Medical Examination Gloves — 5% (HSN 4015)'),
    _r('surgical mask', null, 0.05, 'Medical Masks — 5% (HSN 6307)'),
    _r('n95 mask', null, 0.05, 'Protective Respiratory Masks — 5%'),
    _r('ors', null, 0.05, 'Oral Rehydration Salts — 5%'),
    _r('electral', null, 0.05, 'Oral Rehydration Salts — 5%'),
    _r('multivitamin', null, 0.05, 'Therapeutic Multivitamin Formulations — 5%'),
    _r('ayurvedic', null, 0.05, 'Ayurvedic Formulations — 5% (HSN 3004 90)'),
    _r('chyawanprash', null, 0.05, 'Ayurvedic Formulations — 5%'),
    _r('zandu balm', null, 0.05, 'Pain Relief Balm — 5%'),
    _r('tiger balm', null, 0.05, 'Pain Relief Balm — 5%'),
    _r('moov', null, 0.05, 'Pain Relief Ointment — 5%'),
    _r('volini', null, 0.05, 'Pain Relief Spray / Gel — 5%'),

    // ── 7. Hardware, Toys & Sports Merit Items — 5% ──────────────────────────
    _r('led bulb', 'Hardware Store', 0.05, 'LED Lamp / Bulb — 5% Merit Rate (HSN 8539 50)'),
    _r('led tube light', 'Hardware Store', 0.05, 'LED Tube Light — 5% Merit Rate'),
    _r('board game', 'Toys & Games', 0.05, 'Traditional Board Games — 5% (HSN 9504)'),
    _r('chess', 'Toys & Games', 0.05, 'Traditional Chess Board & Pieces — 5%'),
    _r('carrom', 'Toys & Games', 0.05, 'Carrom Board & Coins — 5%'),
    _r('ludo', 'Toys & Games', 0.05, 'Traditional Board Games — 5%'),
    _r('jigsaw puzzle', 'Toys & Games', 0.05, 'Puzzles & Traditional Toys — 5% (HSN 9503)'),
    _r('wooden toys', 'Toys & Games', 0.05, 'Non-electronic Traditional Toys — 5%'),
    _r('building blocks', 'Toys & Games', 0.05, 'Non-electronic Construction Toys — 5%'),
    _r('teddy bear', 'Toys & Games', 0.05, 'Soft Toys — 5% (HSN 9503)'),
    _r('cricket bat', 'Sports', 0.05, 'Outdoor Sports Equipment — 5% (HSN 9506)'),
    _r('cricket ball', 'Sports', 0.05, 'Sports Balls — 5%'),
    _r('football', 'Sports', 0.05, 'Sports Balls — 5% (HSN 9506)'),
    _r('badminton racket', 'Sports', 0.05, 'Sports Rackets — 5%'),
    _r('shuttlecock', 'Sports', 0.05, 'Sports Requisites — 5%'),

    // ── 8. Cosmetics, Premium Skincare & Hair Styling — 18% Standard ──────────
    _r('lipstick', null, 0.18, 'Decorative Cosmetics — 18% (HSN 3304)'),
    _r('lip gloss', null, 0.18, 'Decorative Cosmetics — 18%'),
    _r('foundation', null, 0.18, 'Face Makeup Foundation — 18% (HSN 3304)'),
    _r('compact powder', null, 0.18, 'Face Makeup Powder — 18%'),
    _r('kajal', null, 0.18, 'Eye Makeup — 18%'),
    _r('eyeliner', null, 0.18, 'Eye Makeup — 18%'),
    _r('mascara', null, 0.18, 'Eye Makeup — 18%'),
    _r('eyeshadow', null, 0.18, 'Eye Makeup — 18%'),
    _r('blush', null, 0.18, 'Cosmetics — 18%'),
    _r('concealer', null, 0.18, 'Cosmetics — 18%'),
    _r('highlighter', null, 0.18, 'Cosmetics — 18%'),
    _r('primer', null, 0.18, 'Makeup Primer — 18%'),
    _r('bb cream', null, 0.18, 'Cosmetic Creams — 18%'),
    _r('nail polish', null, 0.18, 'Nail Lacquer — 18% (HSN 3304)'),
    _r('nail paint', null, 0.18, 'Nail Lacquer — 18%'),
    _r('nail remover', null, 0.18, 'Nail Polish Remover — 18%'),
    _r('perfume', null, 0.18, 'Fragrances & Perfumes — 18% (HSN 3307)'),
    _r('cologne', null, 0.18, 'Fragrances — 18%'),
    _r('attar', null, 0.18, 'Fragrances — 18%'),
    _r('body spray', null, 0.18, 'Deodorant & Body Sprays — 18% (HSN 3307)'),
    _r('deodorant', null, 0.18, 'Deodorants & Antiperspirants — 18%'),
    _r('axe', null, 0.18, 'Deodorant Spray — 18%'),
    _r('fogg', null, 0.18, 'Body Spray — 18%'),
    _r('face wash', null, 0.18, 'Liquid Skin Cleanser — 18% (HSN 3402/3304)'),
    _r('body wash', null, 0.18, 'Liquid Body Wash & Shower Gel — 18%'),
    _r('shower gel', null, 0.18, 'Shower Gel — 18%'),
    _r('face scrub', null, 0.18, 'Skin Scrub — 18%'),
    _r('face pack', null, 0.18, 'Cosmetic Face Pack — 18%'),
    _r('face mask', null, 0.18, 'Cosmetic Face Mask — 18%'),
    _r('face serum', null, 0.18, 'Skincare Serum — 18% (HSN 3304)'),
    _r('serum', null, 0.18, 'Skincare Serum — 18%'),
    _r('vitamin c serum', null, 0.18, 'Skincare Serum — 18%'),
    _r('hyaluronic', null, 0.18, 'Skincare Formulation — 18%'),
    _r('niacinamide', null, 0.18, 'Skincare Formulation — 18%'),
    _r('retinol', null, 0.18, 'Skincare Formulation — 18%'),
    _r('sunscreen lotion', null, 0.18, 'Cosmetic Sunscreen Lotions — 18%'),
    _r('sunscreen spf', null, 0.18, 'Cosmetic Sunscreen — 18%'),
    _r('body lotion', null, 0.18, 'Cosmetic Body Lotion — 18% (HSN 3304)'),
    _r('moisturizer', null, 0.18, 'Cosmetic Moisturising Creams — 18%'),
    _r('cold cream', null, 0.18, 'Cosmetic Skin Creams — 18%'),
    _r('micellar water', null, 0.18, 'Makeup Cleanser — 18%'),
    _r('lip balm', null, 0.18, 'Cosmetic Lip Care — 18%'),
    _r('shaving cream', null, 0.18, 'Shaving Preparations — 18% (HSN 3307)'),
    _r('shaving gel', null, 0.18, 'Shaving Preparations — 18%'),
    _r('aftershave', null, 0.18, 'Aftershave Lotions — 18%'),
    _r('razor', null, 0.18, 'Safety Razors & Blades — 18% (HSN 8212)'),
    _r('gillette', null, 0.18, 'Razors & Blades — 18%'),
    _r('hair removal', null, 0.18, 'Depilatory Creams — 18% (HSN 3307)'),
    _r('veet', null, 0.18, 'Depilatory Creams — 18%'),
    _r('hair conditioner', null, 0.18, 'Hair Conditioner & Preparations — 18% (HSN 3305)'),
    _r('conditioner', null, 0.18, 'Hair Conditioner — 18% (HSN 3305)'),
    _r('hair serum', null, 0.18, 'Hair Serum — 18% (HSN 3305)'),
    _r('hair dye', null, 0.18, 'Hair Dyes & Color — 18% (HSN 3305)'),
    _r('hair color', null, 0.18, 'Hair Color — 18% (HSN 3305)'),
    _r('hair gel', null, 0.18, 'Hair Styling Gel — 18% (HSN 3305)'),
    _r('whey protein', null, 0.18, 'Nutraceuticals & Dietary Supplements — 18% (HSN 2106 90)'),
    _r('protein powder', null, 0.18, 'Nutraceuticals — 18%'),
    _r('optimum nutrition', null, 0.18, 'Dietary Protein Supplements — 18%'),
    _r('muscleblaze', null, 0.18, 'Dietary Protein Supplements — 18%'),
    _r('chewing gum', null, 0.18, 'Chewing Gum & Bubble Gum — 18% (HSN 1704 10)'),
    _r('center fresh', null, 0.18, 'Chewing Gum — 18%'),
    _r('happydent', null, 0.18, 'Chewing Gum — 18%'),
    _r('orbit', null, 0.18, 'Chewing Gum — 18%'),
    _r('lollipop', null, 0.18, 'Sugar Confectionery — 18% (HSN 1704 90)'),
    _r('toffee', null, 0.18, 'Sugar Confectionery — 18%'),
    _r('alpenliebe', null, 0.18, 'Sugar Candies — 18%'),
    _r('squash', 'Beverages', 0.18, 'Beverage Concentrates & Squashes — 18% (HSN 2106)'),
    _r('syrup', 'Beverages', 0.18, 'Flavoured Syrups — 18% (HSN 2106)'),
    _r('rooh afza', 'Beverages', 0.18, 'Beverage Concentrate Syrup — 18% (HSN 2106)'),
    _r('tang', 'Beverages', 0.18, 'Drink Mix Powder — 18%'),
    _r('rasna', 'Beverages', 0.18, 'Drink Concentrate Mix — 18%'),

    // ── 9. Consumer Electronics & Durables — 18% Standard ────────────────────
    _r('mobile phone', null, 0.18, 'Cellular Mobile Phones — 18% (HSN 8517)'),
    _r('smartphone', null, 0.18, 'Smartphones — 18%'),
    _r('iphone', null, 0.18, 'Smartphones — 18%'),
    _r('samsung galaxy', null, 0.18, 'Smartphones — 18%'),
    _r('oneplus', null, 0.18, 'Smartphones — 18%'),
    _r('tablet', null, 0.18, 'Tablets — 18% (HSN 8471)'),
    _r('ipad', null, 0.18, 'Tablets — 18%'),
    _r('laptop', null, 0.18, 'Laptops & Computers — 18% (HSN 8471)'),
    _r('macbook', null, 0.18, 'Laptops — 18%'),
    _r('earphone', null, 0.18, 'Audio Equipment — 18% (HSN 8518)'),
    _r('earbuds', null, 0.18, 'Audio Earbuds — 18%'),
    _r('airpods', null, 0.18, 'Audio Earbuds — 18%'),
    _r('headphones', null, 0.18, 'Audio Headphones — 18%'),
    _r('bluetooth speaker', null, 0.18, 'Audio Speakers — 18%'),
    _r('soundbar', null, 0.18, 'Audio Soundbar — 18%'),
    _r('smartwatch', null, 0.18, 'Smartwatches — 18% (HSN 8517 62)'),
    _r('smart watch', null, 0.18, 'Smartwatches — 18%'),
    _r('fitness band', null, 0.18, 'Wearable Tech — 18%'),
    _r('power bank', null, 0.18, 'Power Banks — 18% (HSN 8507)'),
    _r('charger', null, 0.18, 'Adapters & Chargers — 18% (HSN 8504)'),
    _r('usb cable', null, 0.18, 'Cables & Wiring — 18% (HSN 8544)'),
    _r('screen guard', null, 0.18, 'Mobile Accessories — 18%'),
    _r('tempered glass', null, 0.18, 'Mobile Screen Protectors — 18%'),
    _r('phone case', null, 0.18, 'Mobile Cases & Covers — 18%'),
    _r('mobile cover', null, 0.18, 'Mobile Covers — 18%'),
    _r('pendrive', null, 0.18, 'Flash Memory Drives — 18% (HSN 8523)'),
    _r('sd card', null, 0.18, 'Memory Cards — 18%'),
    _r('hard disk', null, 0.18, 'External Storage Drives — 18% (HSN 8471)'),
    _r('wifi router', null, 0.18, 'Networking Routers — 18% (HSN 8517)'),
    _r('led tv', null, 0.18, 'LED Television — 18% (GST 2.0 Reform)'),
    _r('smart tv', null, 0.18, 'Smart Television — 18% (GST 2.0 Reform)'),
    _r('refrigerator', null, 0.18, 'Refrigerators — 18% (GST 2.0 Reform HSN 8418)'),
    _r('washing machine', null, 0.18, 'Washing Machines — 18% (GST 2.0 Reform HSN 8450)'),
    _r('air conditioner', null, 0.18, 'Air Conditioners — 18% (GST 2.0 Reform HSN 8415)'),
    _r('split ac', null, 0.18, 'Air Conditioners — 18%'),
    _r('microwave oven', null, 0.18, 'Microwave Ovens — 18% (HSN 8516)'),
    _r('water purifier', null, 0.18, 'Water Purifiers — 18% (HSN 8421)'),

    // ── 10. Office Stationery, Tools, Auto Parts & Toys — 18% Standard ────────
    _r('ball pen', 'Stationery', 0.18, 'Ballpoint Pens — 18% (HSN 9608)'),
    _r('ballpoint pen', 'Stationery', 0.18, 'Ballpoint Pens — 18%'),
    _r('gel pen', 'Stationery', 0.18, 'Gel Pens — 18%'),
    _r('pilot pen', 'Stationery', 0.18, 'Writing Pens — 18%'),
    _r('marker', 'Stationery', 0.18, 'Markers & Highlighters — 18% (HSN 9608)'),
    _r('whiteboard marker', 'Stationery', 0.18, 'Markers — 18%'),
    _r('office register', 'Stationery', 0.18, 'Office Registers & Account Books — 18% (HSN 4820)'),
    _r('diary', 'Stationery', 0.18, 'Diaries & Organizers — 18% (HSN 4820)'),
    _r('stapler', 'Stationery', 0.18, 'Staplers & Office Hardware — 18% (HSN 8472)'),
    _r('hand tools', 'Hardware Store', 0.18, 'Hand Tools — 18% (HSN 8203/8205)'),
    _r('spanner', 'Hardware Store', 0.18, 'Hand Tools — 18%'),
    _r('screwdriver', 'Hardware Store', 0.18, 'Hand Tools — 18%'),
    _r('hammer', 'Hardware Store', 0.18, 'Hand Tools — 18%'),
    _r('cutting pliers', 'Hardware Store', 0.18, 'Hand Tools — 18%'),
    _r('power tools', 'Hardware Store', 0.18, 'Power Tools — 18% (HSN 8467)'),
    _r('electric drill', 'Hardware Store', 0.18, 'Power Tools — 18%'),
    _r('screws', 'Hardware Store', 0.18, 'Steel Fasteners & Screws — 18% (HSN 7318)'),
    _r('nails', 'Hardware Store', 0.18, 'Steel Nails — 18% (HSN 7317)'),
    _r('paints', 'Hardware Store', 0.18, 'Paints & Enamels — 18% (HSN 3208/3209)'),
    _r('varnish', 'Hardware Store', 0.18, 'Varnishes — 18%'),
    _r('modular switch', 'Hardware Store', 0.18, 'Electrical Switches — 18% (HSN 8536)'),
    _r('socket', 'Hardware Store', 0.18, 'Electrical Sockets — 18%'),
    _r('mcb', 'Hardware Store', 0.18, 'Circuit Breakers & MCB — 18% (HSN 8536)'),
    _r('electronic toy', 'Toys & Games', 0.18, 'Electronic / Battery Toys — 18% (HSN 9503)'),
    _r('remote control car', 'Toys & Games', 0.18, 'Electronic Toys — 18%'),
    _r('rc car', 'Toys & Games', 0.18, 'Electronic Toys — 18%'),
    _r('drone toy', 'Toys & Games', 0.18, 'Electronic Toys — 18%'),
    _r('video game console', 'Toys & Games', 0.18, 'Video Game Consoles — 18% (HSN 9504 50)'),
    _r('playstation', 'Toys & Games', 0.18, 'Video Game Consoles — 18%'),
    _r('ps5', 'Toys & Games', 0.18, 'Video Game Consoles — 18%'),
    _r('xbox', 'Toys & Games', 0.18, 'Video Game Consoles — 18%'),
    _r('nintendo switch', 'Toys & Games', 0.18, 'Video Game Consoles — 18%'),
    _r('treadmill', 'Sports', 0.18, 'Gym & Fitness Equipment — 18% (HSN 9506 91)'),
    _r('exercise bike', 'Sports', 0.18, 'Gym & Fitness Equipment — 18%'),
    _r('dumbbells', 'Sports', 0.18, 'Gym & Fitness Equipment — 18%'),
    _r('helmet', null, 0.18, 'Motorcycle Safety Helmets — 18% (HSN 6506 10)'),
    _r('tyre', 'Auto Parts', 0.18, 'Motor Vehicle Tyres — 18% (HSN 4011)'),
    _r('engine oil', 'Auto Parts', 0.18, 'Motor Lubricating Oils — 18% (HSN 2710)'),
    _r('car battery', 'Auto Parts', 0.18, 'Lead-Acid Storage Batteries — 18% (HSN 8507)'),
    _r('leather belt', 'Clothing', 0.18, 'Leather Accessories — 18% (HSN 4203)'),
    _r('wallet', 'Clothing', 0.18, 'Leather Wallets & Articles — 18% (HSN 4202)'),
    _r('sunglasses', 'Clothing', 0.18, 'Eyewear & Sunglasses — 18% (HSN 9004)'),
    _r('umbrella', 'Clothing', 0.18, 'Umbrellas — 18% (HSN 6601)'),
    _r('dog food', 'Pet Supplies', 0.18, 'Retail Dog Food — 18% (HSN 2309 10)'),
    _r('cat food', 'Pet Supplies', 0.18, 'Retail Cat Food — 18% (HSN 2309 10)'),
    _r('pedigree', 'Pet Supplies', 0.18, 'Retail Pet Food — 18%'),
    _r('whiskas', 'Pet Supplies', 0.18, 'Retail Pet Food — 18%'),
    _r('royal canin', 'Pet Supplies', 0.18, 'Retail Pet Food — 18%'),
    _r('artificial flowers', 'Flowers', 0.18, 'Artificial Flowers & Foliage — 18% (HSN 6702)'),

    // ── 11. Precious Metals & Jewellery — 3% Statutory Slabs ─────────────────
    _r('gold ring', 'Jewellery', 0.03, 'Gold Jewellery — 3% Statutory Slab'),
    _r('gold necklace', 'Jewellery', 0.03, 'Gold Jewellery — 3% Statutory Slab'),
    _r('gold chain', 'Jewellery', 0.03, 'Gold Jewellery — 3% Statutory Slab'),
    _r('gold earring', 'Jewellery', 0.03, 'Gold Jewellery — 3% Statutory Slab'),
    _r('gold coin', 'Jewellery', 0.03, 'Gold Articles — 3% Statutory Slab'),
    _r('diamond ring', 'Jewellery', 0.03, 'Diamond Jewellery — 3% Statutory Slab'),
    _r('diamond necklace', 'Jewellery', 0.03, 'Diamond Jewellery — 3% Statutory Slab'),
    _r('silver ring', 'Jewellery', 0.03, 'Silver Jewellery — 3% Statutory Slab'),
    _r('silver chain', 'Jewellery', 0.03, 'Silver Jewellery — 3% Statutory Slab'),
    _r('silver coin', 'Jewellery', 0.03, 'Silver Articles — 3% Statutory Slab'),
    _r('artificial jewellery', 'Jewellery', 0.03, 'Imitation Jewellery — 3% Statutory Slab'),
    _r('imitation jewellery', 'Jewellery', 0.03, 'Imitation Jewellery — 3% Statutory Slab'),
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
