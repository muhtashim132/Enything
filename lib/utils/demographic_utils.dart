import '../models/product_model.dart';

/// Target Demographic definitions, keyword parsing, and tag expansion engine.
///
/// Rules:
///   • Searching or filtering for Men, Women, Boys, Girls, or Kids MUST automatically include #Unisex.
///   • Searching for Unisex matches all #Unisex products.
///   • Free-text queries containing demographic keywords (e.g. "men shoes", "unisex hoodie")
///     dynamically evaluate both the demographic criteria and product keyword criteria.
class DemographicUtils {
  // ── Canonical Lists ────────────────────────────────────────────────────────

  /// Customer-facing demographic filter options for UI ChoiceChips.
  static const List<String> customerDemographics = [
    'All',
    'Men',
    'Women',
    'Boys',
    'Girls',
    'Kids',
    'Unisex',
  ];

  /// Seller-facing demographic options when creating/editing a product.
  static const List<String> sellerDemographics = [
    'Unisex',
    'Men',
    'Women',
    'Boys',
    'Girls',
    'Kids',
  ];

  // ── Tag Expansion ──────────────────────────────────────────────────────────

  /// Returns the set of allowed `#Tags` for a given demographic filter string.
  /// Always includes `#Unisex` for gendered and age-specific demographics.
  /// Returns `null` if [demographic] is `'All'` or empty (meaning no filter).
  static Set<String>? getAllowedTags(String? demographic) {
    if (demographic == null || demographic.trim().isEmpty) return null;
    final d = demographic.trim();
    if (d.toLowerCase() == 'all') return null;

    final lower = d.toLowerCase();
    if (lower == 'men' || lower == 'male' || lower == 'gents') {
      return {'#Men', '#Unisex'};
    } else if (lower == 'women' || lower == 'female' || lower == 'ladies') {
      return {'#Women', '#Unisex'};
    } else if (lower == 'boys' || lower == 'boy') {
      return {'#Boys', '#Kids', '#Unisex'};
    } else if (lower == 'girls' || lower == 'girl') {
      return {'#Girls', '#Kids', '#Unisex'};
    } else if (lower == 'kids' || lower == 'children' || lower == 'child') {
      return {'#Kids', '#Boys', '#Girls', '#Unisex'};
    } else if (lower == 'unisex') {
      return {'#Unisex'};
    } else if (lower == 'men/boys') {
      return {'#Men', '#Boys', '#Kids', '#Unisex'};
    } else if (lower == 'women/girls') {
      return {'#Women', '#Girls', '#Kids', '#Unisex'};
    }

    // Default tag fallback: always pair with #Unisex
    final normalized = d.startsWith('#') ? d : '#$d';
    return {normalized, '#Unisex'};
  }

  // ── Keyword Matching ───────────────────────────────────────────────────────

  /// Regular expression for detecting and matching demographic keywords in search terms.
  static final RegExp _menRegex =
      RegExp(r"^(men|mens|men's|man|male|gents|gent|gent's)$", caseSensitive: false);
  static final RegExp _womenRegex =
      RegExp(r"^(women|womens|women's|woman|female|ladies|lady)$", caseSensitive: false);
  static final RegExp _boysRegex =
      RegExp(r"^(boys|boy|boy's)$", caseSensitive: false);
  static final RegExp _girlsRegex =
      RegExp(r"^(girls|girl|girl's)$", caseSensitive: false);
  static final RegExp _kidsRegex =
      RegExp(r"^(kids|kid|kid's|children|child|toddler|infant)$", caseSensitive: false);
  static final RegExp _unisexRegex =
      RegExp(r"^(unisex)$", caseSensitive: false);

  /// Returns true if [term] is a recognised demographic keyword.
  static bool isDemographicKeyword(String term) {
    final clean = term.trim().toLowerCase();
    return _menRegex.hasMatch(clean) ||
        _womenRegex.hasMatch(clean) ||
        _boysRegex.hasMatch(clean) ||
        _girlsRegex.hasMatch(clean) ||
        _kidsRegex.hasMatch(clean) ||
        _unisexRegex.hasMatch(clean);
  }

  /// Returns the set of allowed `#Tags` for a recognized demographic search term.
  /// Always includes `#Unisex` for Men, Women, Boys, Girls, and Kids.
  static Set<String>? getAllowedTagsForTerm(String term) {
    final clean = term.trim().toLowerCase();
    if (_menRegex.hasMatch(clean)) {
      return {'#Men', '#Unisex'};
    } else if (_womenRegex.hasMatch(clean)) {
      return {'#Women', '#Unisex'};
    } else if (_boysRegex.hasMatch(clean)) {
      return {'#Boys', '#Kids', '#Unisex'};
    } else if (_girlsRegex.hasMatch(clean)) {
      return {'#Girls', '#Kids', '#Unisex'};
    } else if (_kidsRegex.hasMatch(clean)) {
      return {'#Kids', '#Boys', '#Girls', '#Unisex'};
    } else if (_unisexRegex.hasMatch(clean)) {
      return {'#Unisex'};
    }
    return null;
  }

  /// Returns the canonical demographic name (e.g. `'Men'`, `'Women'`, `'Kids'`, `'Unisex'`)
  /// for a search term, or null if it's not a demographic keyword.
  static String? getCanonicalDemographicForTerm(String term) {
    final clean = term.trim().toLowerCase();
    if (_menRegex.hasMatch(clean)) return 'Men';
    if (_womenRegex.hasMatch(clean)) return 'Women';
    if (_boysRegex.hasMatch(clean)) return 'Boys';
    if (_girlsRegex.hasMatch(clean)) return 'Girls';
    if (_kidsRegex.hasMatch(clean)) return 'Kids';
    if (_unisexRegex.hasMatch(clean)) return 'Unisex';
    return null;
  }

  // ── Product Term Matcher ───────────────────────────────────────────────────

  /// Checks whether a single search [term] matches a [ProductModel].
  ///
  /// If [term] is a demographic keyword:
  ///   1. Matches if any tag in [getAllowedTagsForTerm] is present in `product.specialTags`.
  ///   2. If untagged, uses text heuristics on `product.name` and `product.description`.
  /// If [term] is a standard keyword:
  ///   Matches if [searchableText] contains [term].
  static bool productMatchesTerm({
    required ProductModel product,
    required String term,
    required String searchableText,
  }) {
    final cleanTerm = term.trim().toLowerCase();
    if (cleanTerm.isEmpty) return true;

    final allowedTags = getAllowedTagsForTerm(cleanTerm);
    if (allowedTags != null) {
      // 1. Direct tag match (handles #Unisex automatically)
      final hasMatchingTag =
          product.specialTags.any((t) => allowedTags.contains(t.trim()));
      if (hasMatchingTag) return true;

      // 2. If the product has explicit demographic tags that don't match, reject
      final hasOtherDemographicTag = product.specialTags.any((t) =>
          t == '#Men' ||
          t == '#Women' ||
          t == '#Boys' ||
          t == '#Girls' ||
          t == '#Kids' ||
          t == '#Unisex');
      if (hasOtherDemographicTag) return false;

      // 3. Fallback to name/description text heuristics for untagged items
      final text = '${product.name} ${product.description ?? ''}'.toLowerCase();
      if (_menRegex.hasMatch(cleanTerm)) {
        if (RegExp(r"\b(women|womens|women's|ladies|lady|female|kurti|saree|lehenga|bra)\b")
            .hasMatch(text)) {
          return false;
        }
        return RegExp(r"\b(men|mens|men's|man|male|gent|gents|gent's|boy|boys)\b")
            .hasMatch(text);
      } else if (_womenRegex.hasMatch(cleanTerm)) {
        if (RegExp(r"\b(men|mens|men's|man|male|gent|gents|gent's)\b")
            .hasMatch(text)) {
          return false;
        }
        return RegExp(r"\b(women|womens|women's|woman|female|ladies|lady|girl|girls|kurti|saree|lehenga|dress)\b")
            .hasMatch(text);
      } else if (_kidsRegex.hasMatch(cleanTerm) ||
          _boysRegex.hasMatch(cleanTerm) ||
          _girlsRegex.hasMatch(cleanTerm)) {
        return RegExp(r"\b(kid|kids|child|children|boy|boys|girl|girls|toddler|baby|infant)\b")
            .hasMatch(text);
      } else if (_unisexRegex.hasMatch(cleanTerm)) {
        return RegExp(r"\b(unisex|all gender|gender neutral)\b").hasMatch(text);
      }
    }

    // Standard non-demographic keyword: substring match on searchableText
    return searchableText.contains(cleanTerm);
  }

  /// Same as [productMatchesTerm], but for raw JSON map representations of products.
  static bool rawProductMatchesTerm({
    required Map<String, dynamic> product,
    required String term,
    required String searchableText,
  }) {
    final cleanTerm = term.trim().toLowerCase();
    if (cleanTerm.isEmpty) return true;

    final allowedTags = getAllowedTagsForTerm(cleanTerm);
    if (allowedTags != null) {
      final tagsRaw = product['special_tags'];
      final List<String> tags = (tagsRaw is List)
          ? tagsRaw.map((t) => t.toString().trim()).toList()
          : [];

      // 1. Tag match (handles #Unisex automatically)
      if (tags.any((t) => allowedTags.contains(t))) return true;

      // 2. Reject if explicitly tagged with conflicting demographic
      final hasOtherDemographicTag = tags.any((t) =>
          t == '#Men' ||
          t == '#Women' ||
          t == '#Boys' ||
          t == '#Girls' ||
          t == '#Kids' ||
          t == '#Unisex');
      if (hasOtherDemographicTag) return false;

      // 3. Fallback for untagged items
      final name = (product['name'] as String?)?.toLowerCase() ?? '';
      final desc = (product['description'] as String?)?.toLowerCase() ?? '';
      final text = '$name $desc';

      if (_menRegex.hasMatch(cleanTerm)) {
        if (RegExp(r"\b(women|womens|women's|ladies|lady|female|kurti|saree|lehenga|bra)\b")
            .hasMatch(text)) {
          return false;
        }
        return RegExp(r"\b(men|mens|men's|man|male|gent|gents|gent's|boy|boys)\b")
            .hasMatch(text);
      } else if (_womenRegex.hasMatch(cleanTerm)) {
        if (RegExp(r"\b(men|mens|men's|man|male|gent|gents|gent's)\b")
            .hasMatch(text)) {
          return false;
        }
        return RegExp(r"\b(women|womens|women's|woman|female|ladies|lady|girl|girls|kurti|saree|lehenga|dress)\b")
            .hasMatch(text);
      } else if (_kidsRegex.hasMatch(cleanTerm) ||
          _boysRegex.hasMatch(cleanTerm) ||
          _girlsRegex.hasMatch(cleanTerm)) {
        return RegExp(r"\b(kid|kids|child|children|boy|boys|girl|girls|toddler|baby|infant)\b")
            .hasMatch(text);
      } else if (_unisexRegex.hasMatch(cleanTerm)) {
        return RegExp(r"\b(unisex|all gender|gender neutral)\b").hasMatch(text);
      }
    }

    return searchableText.contains(cleanTerm);
  }

  // ── Demographic Filter Evaluator ──────────────────────────────────────────

  /// Evaluates whether [product] satisfies the active [selectedDemographic] filter.
  /// Automatically includes `#Unisex` products for Men, Women, Boys, Girls, and Kids.
  static bool matchesDemographic(ProductModel product, String? selectedDemographic) {
    if (selectedDemographic == null ||
        selectedDemographic.trim().isEmpty ||
        selectedDemographic.trim().toLowerCase() == 'all') {
      return true;
    }

    final allowedTags = getAllowedTags(selectedDemographic);
    if (allowedTags == null) return true;

    // Positive tag match
    if (product.specialTags.any((t) => allowedTags.contains(t.trim()))) {
      return true;
    }

    // If explicitly tagged with conflicting demographic, reject
    final hasConflictingTag = product.specialTags.any((t) =>
        ['#Men', '#Women', '#Boys', '#Girls', '#Kids', '#Unisex']
            .contains(t.trim()) &&
        !allowedTags.contains(t.trim()));
    if (hasConflictingTag) return false;

    // Text heuristic fallback for untagged items
    final text = '${product.name} ${product.description ?? ''}'.toLowerCase();
    final d = selectedDemographic.trim().toLowerCase();

    if (d == 'men' || d == 'men/boys') {
      if (RegExp(r"\b(women|womens|women's|ladies|lady|female|kurti|saree|lehenga|bra|makeup)\b")
          .hasMatch(text)) {
        return false;
      }
      return RegExp(r"\b(men|mens|men's|boy|boys|gent|gents|male)\b").hasMatch(text);
    } else if (d == 'women' || d == 'women/girls') {
      if (RegExp(r"\b(men|mens|men's|boys|boy's|gents|gent's|male)\b").hasMatch(text)) {
        return false;
      }
      return RegExp(r"\b(women|womens|women's|girl|girls|ladies|lady|female|kurti|saree|lehenga|dress|beauty|cosmetics)\b")
          .hasMatch(text);
    } else if (d == 'kids' || d == 'boys' || d == 'girls') {
      return RegExp(r"\b(kid|kids|child|children|boy|boys|girl|girls|toddler|baby|infant)\b")
          .hasMatch(text);
    } else if (d == 'unisex') {
      return RegExp(r"\b(unisex|all gender|gender neutral)\b").hasMatch(text);
    }

    return true;
  }
}

