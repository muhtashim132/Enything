import 'dart:math' as math;
import '../models/product_model.dart';
import '../models/shop_model.dart';
import 'demographic_utils.dart';

/// 100x Forensic Search Relevance Engine for Enything Platform.
///
/// Implements deterministic, multi-tiered search scoring across product name,
/// brand, tokens, medicine salts, description, metadata, and human-like
/// semantic demographic intelligence.
///
/// Score Tiers:
/// - Demographic Inherent Tier 1 (90,000 - 100,000+): Exact persona match (e.g. lipstick/saree for "woman").
/// - Tier 1 (100,000+): Exact product name match.
/// - Tier 2 (60,000 - 80,000): Name starts with query as a distinct word/boundary (e.g. "Dew 750 ml", "dew 250").
/// - Demographic Unisex Tier 2 (45,000 - 55,000): Unisex lifestyle products (e.g. sunscreen/sneakers for "woman").
/// - Tier 3 (40,000): Name starts with query without space (e.g. "Dewdrop").
/// - Tier 4 (30,000): Query is an isolated distinct word within title (e.g. "Mountain Dew 750ml").
/// - Tier 5 (25,000): Exact brand match.
/// - Tier 6 (15,000): Multi-token complete match / Brand starts with query.
/// - Tier 7 (12,000): Word in name starts with query (e.g. "Dewy" in "Vaseline Healthy Bright Gluta-Hya Dewy Radiance").
/// - Tier 8 (4,000): Infix / substring inside a compound word (e.g. "Dermadew").
/// - Tier 9 (1,500): Description whole-word match.
/// - Tier 10 (400): Description substring match.
/// - Tier 11 (200 - 300): Category / Store name match.
/// - Tie-breaker (+0 to +50): Rating and compactness bonus.
/// - Disqualification (-1,000,000): Opposite-gender products or Food items in pure demographic searches.
class SearchRelevanceEngine {
  /// Computes a comprehensive relevance score for [product] relative to [query].
  /// Higher score = more relevant. Score < 0 = disqualified / excluded.
  static double computeScore({
    required ProductModel product,
    required String query,
    ShopModel? shop,
  }) {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) return product.rating;

    // ── 0. DEMOGRAPHIC INTENT EVALUATION ─────────────────────────────────────
    final demoIntent = DemographicUtils.detectDemographicIntent(cleanQuery);
    if (demoIntent.hasDemographicIntent) {
      final isCompatible = DemographicUtils.isCompatibleWithDemographic(
        product: product,
        targetDemographic: demoIntent.canonicalDemographic!,
        isPureDemographic: demoIntent.isPureDemographic,
      );
      if (!isCompatible) {
        return -1000000.0; // Strictly disqualified
      }

      final classification = DemographicUtils.classifyProduct(product);

      // Pure Demographic Search (e.g. user typed "woman", "women", "men", "boy", "girl")
      if (demoIntent.isPureDemographic) {
        if (classification == ProductDemographicType.food) {
          return -1000000.0; // Food strictly excluded on lifestyle persona query
        }

        final target = demoIntent.canonicalDemographic!.toLowerCase();
        final isPrimaryTarget =
            (target == 'women' && classification == ProductDemographicType.women) ||
            (target == 'men' && classification == ProductDemographicType.men) ||
            (target == 'girls' && classification == ProductDemographicType.girls) ||
            (target == 'boys' && classification == ProductDemographicType.boys) ||
            (target == 'kids' && classification == ProductDemographicType.kids);

        if (isPrimaryTarget) {
          double score = 90000.0;
          score += (product.rating * 100.0);
          if (product.isAvailable) score += 500.0;
          return score;
        }

        if (classification == ProductDemographicType.unisex) {
          double score = 45000.0;
          score += (product.rating * 100.0);
          if (product.isAvailable) score += 500.0;
          return score;
        }

        double score = 20000.0;
        score += (product.rating * 100.0);
        return score;
      }

      // Compound Demographic Query (e.g. "women perfume", "shoes for men")
      final productQuery = demoIntent.strippedProductQuery;
      if (productQuery.isNotEmpty) {
        final textScore = _computeTextRelevance(
          product: product,
          cleanQuery: productQuery,
          shop: shop,
        );

        if (textScore <= 0.0) return 0.0;

        final target = demoIntent.canonicalDemographic!.toLowerCase();
        final isPrimaryTarget =
            (target == 'women' && classification == ProductDemographicType.women) ||
            (target == 'men' && classification == ProductDemographicType.men) ||
            (target == 'girls' && classification == ProductDemographicType.girls) ||
            (target == 'boys' && classification == ProductDemographicType.boys) ||
            (target == 'kids' && classification == ProductDemographicType.kids);

        if (isPrimaryTarget) {
          return textScore + 50000.0;
        } else if (classification == ProductDemographicType.unisex) {
          return textScore + 20000.0;
        }
        return textScore;
      }
    }

    // ── STANDARD TEXT RELEVANCE COMPUTATION ────────────────────────────────────
    return _computeTextRelevance(
      product: product,
      cleanQuery: cleanQuery,
      shop: shop,
    );
  }

  /// Internal deterministic 11-tier text relevance calculator.
  static double _computeTextRelevance({
    required ProductModel product,
    required String cleanQuery,
    ShopModel? shop,
  }) {
    final cleanName = product.name.trim().toLowerCase();
    final cleanBrand = (product.brand ?? '').trim().toLowerCase();
    final cleanDesc = (product.description ?? '').trim().toLowerCase();
    final cleanMedType = product.medicineType.trim().toLowerCase();

    double score = 0.0;

    // ── 1. EXACT FULL NAME MATCH (Highest possible relevance) ─────────────────
    if (cleanName == cleanQuery) {
      score += 100000.0;
    }

    // ── 2. NAME STARTS WITH QUERY AS A DISTINCT WORD / PHRASE ─────────────────
    // e.g. Query "dew" -> "Dew 750 ml", "dew 250", "Dew-Drop"
    final startsWithWordBoundary = cleanName.startsWith(cleanQuery) &&
        (cleanName.length == cleanQuery.length ||
            RegExp(r'^[\s\-_/|,()\[\]"]').hasMatch(cleanName.substring(cleanQuery.length)));

    if (startsWithWordBoundary) {
      score += 60000.0;
      // Compactness bonus: shorter names closer to query rank higher
      final lengthDiff = cleanName.length - cleanQuery.length;
      score += math.max(0.0, 1000.0 - (lengthDiff * 10.0));
    } else if (cleanName.startsWith(cleanQuery)) {
      // Starts with query but no word boundary (e.g. "dewdrop", "dewy")
      score += 40000.0;
    }

    // ── 3. DISTINCT WHOLE WORD IN PRODUCT NAME ────────────────────────────────
    // e.g. Query "dew" -> "Mountain Dew 750ml"
    final nameTokens = cleanName
        .split(RegExp(r'[\s\-_/|,()\[\]"]+'))
        .where((t) => t.isNotEmpty)
        .toList();

    if (nameTokens.contains(cleanQuery)) {
      score += 30000.0;
      // Position bonus: earlier in the title = higher relevance
      final tokenIdx = nameTokens.indexOf(cleanQuery);
      score += math.max(0.0, 500.0 - (tokenIdx * 50.0));
    }

    // ── 4. BRAND RELEVANCE ────────────────────────────────────────────────────
    if (cleanBrand.isNotEmpty) {
      if (cleanBrand == cleanQuery) {
        score += 25000.0;
      } else if (cleanBrand.startsWith(cleanQuery)) {
        score += 15000.0;
      } else {
        final brandTokens = cleanBrand
            .split(RegExp(r'[\s\-_/|,()\[\]"]+'))
            .where((t) => t.isNotEmpty)
            .toList();
        if (brandTokens.contains(cleanQuery)) {
          score += 12000.0;
        } else if (cleanBrand.contains(cleanQuery)) {
          score += 5000.0;
        }
      }
    }

    // ── 5. WORD PREFIX IN PRODUCT NAME ────────────────────────────────────────
    // e.g. Query "dew" -> Word "Dewy" in "Vaseline Healthy Bright Gluta-Hya Dewy Radiance"
    final hasWordStartingWithQuery = nameTokens.any((t) =>
        t.length > cleanQuery.length && t.startsWith(cleanQuery));
    if (hasWordStartingWithQuery && !startsWithWordBoundary) {
      score += 12000.0;
    }

    // ── 6. MULTI-TOKEN QUERIES (e.g. "Mountain Dew", "Dot & Key Serum") ───────
    final queryTokens = cleanQuery
        .split(RegExp(r'[\s\-_/|,()\[\]"]+'))
        .where((t) => t.isNotEmpty)
        .toList();

    if (queryTokens.length > 1) {
      final matchingTokensInName =
          queryTokens.where((qt) => nameTokens.contains(qt)).length;
      if (matchingTokensInName == queryTokens.length) {
        score += 35000.0; // All tokens present in title!
      } else if (matchingTokensInName > 0) {
        score += (matchingTokensInName / queryTokens.length) * 15000.0;
      }

      // Check phrase sequence (consecutive tokens)
      if (cleanName.contains(cleanQuery)) {
        score += 20000.0;
      }
    }

    // ── 7. SUBSTRING INSIDE A SINGLE WORD IN NAME ─────────────────────────────
    // e.g. Query "dew" inside "Dermadew" (contains "dew" but starts with "derma")
    if (cleanName.contains(cleanQuery) &&
        !startsWithWordBoundary &&
        !nameTokens.contains(cleanQuery) &&
        !hasWordStartingWithQuery) {
      score += 4000.0;
    }

    // ── 7B. COMMON SYNONYMS (e.g. "perfume" <-> "parfum", "pants" <-> "trousers") ───
    if (cleanQuery == 'perfume' && (cleanName.contains('parfum') || cleanDesc.contains('parfum'))) {
      score += 25000.0;
    } else if (cleanQuery == 'parfum' && (cleanName.contains('perfume') || cleanDesc.contains('perfume'))) {
      score += 25000.0;
    }

    // ── 8. MEDICINE SALT / COMPOSITION MATCH ──────────────────────────────────
    final isPharmacy = product.category.toLowerCase().contains('pharmacy') ||
        product.category.toLowerCase().contains('medical') ||
        product.requiresPrescription ||
        cleanMedType.isNotEmpty;
    if (cleanMedType.isNotEmpty) {
      if (cleanMedType == cleanQuery || cleanMedType.startsWith(cleanQuery)) {
        score += 15000.0;
      } else if (cleanMedType.contains(cleanQuery)) {
        score += 6000.0;
      }
    }
    // Boost chemical salt composition described in pharmacy description
    if (isPharmacy && cleanDesc.isNotEmpty && cleanDesc.contains(cleanQuery)) {
      final descTokens = cleanDesc
          .split(RegExp(r'[\s\-_/|,()\[\]"]+'))
          .where((t) => t.isNotEmpty)
          .toList();
      if (descTokens.contains(cleanQuery)) {
        score += 15000.0; // Exact active salt token match
      } else {
        score += 6000.0; // Infix salt substring match
      }
    }

    // ── 9. DESCRIPTION MATCH (Lowest product text tier) ───────────────────────
    if (cleanDesc.isNotEmpty) {
      if (cleanDesc.contains(cleanQuery)) {
        final descTokens = cleanDesc
            .split(RegExp(r'[\s\-_/|,()\[\]"]+'))
            .where((t) => t.isNotEmpty)
            .toList();
        if (descTokens.contains(cleanQuery)) {
          score += 1500.0;
        } else {
          score += 400.0;
        }
      }
    }

    // ── 10. CATEGORY / SHOP / SPECIAL TAGS MATCH ──────────────────────────────
    if (product.category.toLowerCase().contains(cleanQuery)) {
      score += 300.0;
    }
    if (shop != null && shop.name.toLowerCase().contains(cleanQuery)) {
      score += 200.0;
    }

    // ── 11. QUALITY TIE-BREAKER ───────────────────────────────────────────────
    // Rating adds up to 50 points; never overrides any relevance tier!
    score += (product.rating * 10.0);

    return score;
  }

  /// Sorts a list of [ProductModel] by query relevance in-place and returns it.
  /// Automatically filters out disqualified items (negative score) for demographic queries.
  static List<ProductModel> sortProducts({
    required List<ProductModel> products,
    required String query,
    Map<String, ShopModel>? shops,
  }) {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return products;

    // Cache scores during sorting to ensure O(N log N) performance
    final scoreCache = <String, double>{};
    double getCachedScore(ProductModel p) {
      return scoreCache.putIfAbsent(
        p.id,
        () => computeScore(
          product: p,
          query: cleanQuery,
          shop: shops?[p.shopId] ?? shops?[p.id],
        ),
      );
    }

    // Filter out strictly disqualified items (score < 0) when query has demographic intent
    final hasDemo = DemographicUtils.detectDemographicIntent(cleanQuery).hasDemographicIntent;
    if (hasDemo) {
      products.removeWhere((p) => getCachedScore(p) < 0);
    }

    products.sort((a, b) {
      final scoreA = getCachedScore(a);
      final scoreB = getCachedScore(b);
      if (scoreA != scoreB) {
        return scoreB.compareTo(scoreA); // Highest relevance first
      }
      return b.rating.compareTo(a.rating);
    });

    return products;
  }
}
