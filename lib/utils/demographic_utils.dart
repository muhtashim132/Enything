import '../models/product_model.dart';
import '../config/app_categories.dart';

/// Target Demographic classification enum.
enum ProductDemographicType {
  women,
  men,
  girls,
  boys,
  kids,
  unisex,
  food,
  general,
}

/// Structured result from parsing demographic intent from a user's search query.
class DemographicQueryResult {
  final bool hasDemographicIntent;
  final String? canonicalDemographic; // 'Women', 'Men', 'Girls', 'Boys', 'Kids', 'Unisex'
  final bool isPureDemographic;
  final String strippedProductQuery; // e.g. "perfume" for "women perfume"

  const DemographicQueryResult({
    required this.hasDemographicIntent,
    this.canonicalDemographic,
    this.isPureDemographic = false,
    this.strippedProductQuery = '',
  });
}

/// 100x Forensic Target Demographic definitions, semantic keyword parsing,
/// tag expansion, and human-like classification engine.
///
/// Rules:
///   • Searching or filtering for Men, Women, Boys, Girls, or Kids MUST automatically include #Unisex.
///   • Searching for Unisex matches all #Unisex products.
///   • Standalone demographic queries (e.g. "woman", "women", "men", "boy", "girl")
///     dynamically classify products into Target Demographic and Unisex,
///     while strictly EXCLUDING Food / Perishables and conflicting opposite-gender items.
///   • Compound queries (e.g. "women perfume", "shoes for men") match the product keyword
///     and filter/rank by demographic alignment.
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
      RegExp(r"^(kids|kid|kid's|children|child|toddler|infant|baby|babies)$", caseSensitive: false);
  static final RegExp _unisexRegex =
      RegExp(r"^(unisex|all\s*gender|gender\s*neutral)$", caseSensitive: false);

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

  // ── Semantic Lexicon & Dictionaries ────────────────────────────────────────

  static final Set<String> _womenBrands = {
    'maybelline', 'lakme', 'lakmé', 'nykaa', 'colorbar', 'sugar cosmetics', 'sugar',
    'faces canada', 'whisper', 'stayfree', 'sofy', 'kotex', 'paree', 'veet', 'fem',
    'enamor', 'zivame', 'clovia', 'biba', 'w for woman', 'aurelia', 'global desi',
    'streax', 'loreal', "l'oreal", 'plum', 'biotique', 'lotus herbals', 'mamaearth',
    'kay beauty', 'just herbs', 'forest essentials', 'kama ayurveda', 'forever 21',
  };

  static final Set<String> _menBrands = {
    'beardo', 'the man company', 'ustraa', 'bombay shaving company', 'gillette',
    'old spice', 'park avenue', 'axe', 'denver', 'wild stone', 'fogg', 'dollar',
    'rupa', 'lux cozi', 'amul macho', 'vip', 'peter england', 'louis philippe',
    'van heusen', 'raymond', 'arrow', 'mufti', 'blackberrys', 'killer', 'flying machine',
  };

  static final Set<String> _kidsBrands = {
    'pampers', 'huggies', 'mamypoko', "johnson's", 'johnson', 'chicco',
    'sebamed baby', 'mothercare', 'firstcry', 'lego', 'barbie', 'hot wheels',
    'nerf', 'funskool', 'fisher-price', 'himalaya baby', 'mee mee',
  };

  static final Set<String> _unisexBrands = {
    'nivea', 'dove', 'vaseline', "pond's", 'ponds', 'garnier', 'himalaya',
    'cetaphil', 'cerave', 'minimalist', 'the ordinary', 'dot & key', 'neutrogena',
    'head & shoulders', 'pantene', 'sunsilk', 'clinic plus', 'dettol', 'savlon',
    'parachute', 'bajaj', 'puma', 'nike', 'adidas', 'reebok', 'skechers', 'bata',
    'sparx', 'fastrack', 'titan', 'boat', 'noise', 'jbl', 'sony', 'wildcraft',
    'american tourister', 'skybags', 'safari', 'casio',
  };

  static final RegExp _womenSemanticRegex = RegExp(
    r"\b(lipstick|lipsticks|lip\s*gloss|lip\s*liner|mascara|mascaras|kajal|eyeliner|eyeliners|foundation|foundations|blush|compact\s*powder|nail\s*polish|nail\s*paint|sanitary\s*pad|sanitary\s*pads|sanitary\s*napkin|sanitary\s*napkins|tampon|tampons|menstrual|panty\s*liner|intimate\s*wash|v-wash|vwash|prega\s*news|pregnancy\s*test|hair\s*removal|veet|wax\s*strip|wax\s*strips|bleach\s*cream|scrunchie|scrunchies|hair\s*clutcher|bobby\s*pin|hair\s*clips|saree|saris|sari|kurti|kurtis|kameez|salwar|lehenga|lehengas|dupatta|dupattas|saree\s*blouse|blouse|petticoat|anarkali|abaya|hijab|churidar|palazzo|palazzos|dress|dresses|frock|frocks|skirt|skirts|crop\s*top|crop\s*tops|tunic|jumpsuit|gown|gowns|nighty|nightdress|camisole|leggings|jeggings|bra|bras|brassiere|sports\s*bra|panty|panties|lingerie|thong|shapewear|corset|stockings|high\s*heels|heels|stiletto|stilettos|wedges|bellies|ballerinas|kolhapuris|handbag|handbags|tote\s*bag|clutch|clutches|sling\s*bag|purse|purses|vanity\s*bag|earring|earrings|jhumka|jhumkas|bangle|bangles|payal|anklet|anklets|mangalsutra|nose\s*pin|nose\s*ring|bindi|maang\s*tikka|pour\s*femme|for\s*women|women's|womens|women|woman|female|ladies|lady)\b",
    caseSensitive: false,
  );

  static final RegExp _menSemanticRegex = RegExp(
    r"\b(beard|beard\s*oil|beard\s*wash|beard\s*wax|beard\s*balm|beard\s*trimmer|shaving\s*foam|shaving\s*gel|aftershave|after\s*shave|mustache|hair\s*pomade|hair\s*clay|men's\s*razor|razor\s*blades|sherwani|lungi|dhoti|kurta\s*for\s*men|boxer|boxers|boxer\s*shorts|briefs|trunks|baniyan|men\s*vest|jockstrap|cufflinks|necktie|bowtie|pocket\s*square|lapel\s*pin|tie\s*clip|oxford\s*shoes|brogues|derby\s*shoes|monk\s*straps|men\s*formal\s*shoes|men's\s*wallet|men\s*wallet|pour\s*homme|for\s*men|men's|mens|men|man|male|gent|gents|gent's)\b",
    caseSensitive: false,
  );

  static final RegExp _kidsSemanticRegex = RegExp(
    r"\b(diaper|diapers|baby\s*wipes|baby\s*lotion|baby\s*powder|baby\s*wash|baby\s*soap|baby\s*shampoo|teether|pacifier|feeding\s*bottle|baby\s*cot|pram|stroller|rattle|rattles|doll|dolls|barbie|toy\s*car|hot\s*wheels|action\s*figure|board\s*game|cerelac|nestum|lactogen|kid|kids|child|children|toddler|baby|babies|infant)\b",
    caseSensitive: false,
  );

  static final RegExp _unisexSemanticRegex = RegExp(
    r"\b(sunscreen|sunblock|moisturizer|moisturising|face\s*wash|cleanser|face\s*scrub|scrub|sheet\s*mask|face\s*pack|toner|serum|serums|lip\s*balm|body\s*lotion|body\s*wash|shower\s*gel|bath\s*soap|soap\s*bar|hand\s*wash|hand\s*cream|foot\s*cream|shampoo|hair\s*oil|conditioner|hair\s*conditioner|hair\s*mask|anti-dandruff|sanitizer|cotton\s*buds|band-aid|thermometer|pain\s*balm|vaporub|inhaler|t-shirt|tshirt|tee|hoodie|hoodies|sweatshirt|sweatshirts|jacket|jackets|track\s*pants|trackpants|sweatpants|joggers|jeans|raincoat|windcheater|cap|caps|beanie|beanies|socks|scarf|muffler|sneaker|sneakers|running\s*shoes|sports\s*shoes|slippers|flip\s*flops|crocs|sliders|sandals|backpack|backpacks|laptop\s*bag|duffel\s*bag|gym\s*bag|luggage|trolley\s*bag|waist\s*pouch|sunglasses|shades|spectacles|watch|watches|smartwatch|smart\s*band|fitness\s*tracker|earphones|headphones|earbuds|airpods|speaker|charger|power\s*bank|water\s*bottle|flask|sipper|unisex|all\s*gender|gender\s*neutral)\b",
    caseSensitive: false,
  );

  static final RegExp _foodSemanticRegex = RegExp(
    r"\b(atta|flour|rice|dal|lentils|salt|sugar|cooking\s*oil|mustard\s*oil|sunflower\s*oil|ghee|butter|milk|paneer|cheese|curd|dahi|chips|crisps|biscuit|biscuits|cookie|cookies|namkeen|chocolate|chocolates|candy|candies|gum|chewing\s*gum|bread|cake|pastry|pastries|tea|chai|coffee|juice|juices|beverage|beverages|soda|soft\s*drink|cola|biryani|pizza|burger|burgers|noodle|noodles|pasta|sauce|ketchup|pickle|spices|masala|chicken|mutton|meat|fish|egg|eggs|fruit|fruits|vegetable|vegetables|ladyfinger|bhindi|okra|mother\s*dairy)\b",
    caseSensitive: false,
  );

  // ── Demographic Intent Parsing ─────────────────────────────────────────────

  /// Detects whether [query] contains demographic intent (e.g. "women", "men shoes", "girl dress").
  /// Extracts the canonical demographic and the stripped product query.
  static DemographicQueryResult detectDemographicIntent(String query) {
    final clean = query.trim().toLowerCase();
    if (clean.isEmpty) {
      return const DemographicQueryResult(hasDemographicIntent: false);
    }

    // False-positive food/brand safeguards
    if (clean == 'ladyfinger' ||
        clean == 'lady finger' ||
        clean.contains('mother dairy') ||
        clean.contains("fisherman's friend") ||
        clean.contains('old spice')) {
      return const DemographicQueryResult(hasDemographicIntent: false);
    }

    final tokens = clean
        .split(RegExp(r'[\s\-_/|,()\[\]"]+'))
        .where((t) => t.isNotEmpty)
        .toList();

    String? detectedDemographic;
    final nonDemoTokens = <String>[];

    for (final token in tokens) {
      if (token == 'for' || token == 'in' || token == 'of' || token == 'and' || token == '&') {
        continue;
      }
      final canonical = getCanonicalDemographicForTerm(token);
      if (canonical != null) {
        detectedDemographic ??= canonical;
      } else {
        nonDemoTokens.add(token);
      }
    }

    if (detectedDemographic == null) {
      return const DemographicQueryResult(hasDemographicIntent: false);
    }

    final stripped = nonDemoTokens.join(' ').trim();
    return DemographicQueryResult(
      hasDemographicIntent: true,
      canonicalDemographic: detectedDemographic,
      isPureDemographic: stripped.isEmpty,
      strippedProductQuery: stripped,
    );
  }

  /// Returns true if [query] is strictly a standalone demographic word (e.g. "woman", "women", "men", "boy", "girl").
  static bool isPureDemographicQuery(String query) {
    return detectDemographicIntent(query).isPureDemographic;
  }

  // ── Semantic Product Classification ────────────────────────────────────────

  /// Classifies a [ProductModel] into its inherent demographic category.
  static ProductDemographicType classifyProduct(ProductModel product) {
    // 1. Explicit Special Tags take precedence over category heuristics
    if (product.specialTags.contains('#Women')) return ProductDemographicType.women;
    if (product.specialTags.contains('#Men')) return ProductDemographicType.men;
    if (product.specialTags.contains('#Girls')) return ProductDemographicType.girls;
    if (product.specialTags.contains('#Boys')) return ProductDemographicType.boys;
    if (product.specialTags.contains('#Kids')) return ProductDemographicType.kids;
    if (product.specialTags.contains('#Unisex')) return ProductDemographicType.unisex;

    final cat = product.category.toLowerCase().trim();
    final brand = (product.brand ?? '').toLowerCase().trim();
    final text = '${product.name} ${product.description ?? ''} $cat ${product.subCategory ?? ''} ${product.menuCategory ?? ''}'.toLowerCase();

    // 2. Clear Food Ingredients / Edibles Check
    final isExplicitFoodText = _foodSemanticRegex.hasMatch(text);
    if (isExplicitFoodText) {
      return ProductDemographicType.food;
    }

    // 3. Brand & Semantic Analysis for Lifestyle Items
    // (Protects apparel, undergarments, cosmetics stocked in supermarkets/grocery from false food exclusion)
    if (_menBrands.contains(brand) || _menSemanticRegex.hasMatch(text)) {
      return ProductDemographicType.men;
    }
    if (_womenBrands.contains(brand) || _womenSemanticRegex.hasMatch(text)) {
      return ProductDemographicType.women;
    }
    if (_kidsBrands.contains(brand) || _kidsSemanticRegex.hasMatch(text)) {
      return ProductDemographicType.kids;
    }

    // 4. If category is Food, and no explicit apparel/cosmetic signal was found, it is Food
    if (AppCategories.isFoodCategory(product.category)) {
      return ProductDemographicType.food;
    }

    // D. Inherent Category Attributes
    if (cat.contains('cosmetic') || cat.contains('beauty') || cat.contains('salon')) {
      // Skincare/hair care in cosmetics is unisex; makeup is women
      if (text.contains('lipstick') ||
          text.contains('kajal') ||
          text.contains('mascara') ||
          text.contains('eyeliner') ||
          text.contains('foundation') ||
          text.contains('nail') ||
          text.contains('blush') ||
          text.contains('compact') ||
          text.contains('pad') ||
          text.contains('tampon') ||
          text.contains('wax')) {
        return ProductDemographicType.women;
      }
      return ProductDemographicType.unisex;
    }

    if (cat.contains('jewel')) {
      return ProductDemographicType.women;
    }

    // E. Unisex Keywords or Brands
    if (_unisexBrands.contains(brand) || _unisexSemanticRegex.hasMatch(text)) {
      return ProductDemographicType.unisex;
    }

    // F. Non-Food Lifestyle Departments default to Unisex
    if (cat.contains('electronic') ||
        cat.contains('mobile') ||
        cat.contains('stationery') ||
        cat.contains('sports') ||
        cat.contains('hardware') ||
        cat.contains('home decor') ||
        cat.contains('furniture') ||
        cat.contains('auto parts')) {
      return ProductDemographicType.unisex;
    }

    return ProductDemographicType.general;
  }

  /// Classifies a raw product Map into its inherent demographic category.
  static ProductDemographicType classifyRawProduct(Map<String, dynamic> product) {
    // 1. Explicit Special Tags take precedence over category heuristics
    final tagsRaw = product['special_tags'];
    final List<String> tags = (tagsRaw is List)
        ? tagsRaw.map((t) => t.toString().trim()).toList()
        : [];

    if (tags.contains('#Women')) return ProductDemographicType.women;
    if (tags.contains('#Men')) return ProductDemographicType.men;
    if (tags.contains('#Girls')) return ProductDemographicType.girls;
    if (tags.contains('#Boys')) return ProductDemographicType.boys;
    if (tags.contains('#Kids')) return ProductDemographicType.kids;
    if (tags.contains('#Unisex')) return ProductDemographicType.unisex;

    final cat = (product['category'] as String? ?? '').toLowerCase().trim();
    final brand = (product['brand'] as String? ?? '').toLowerCase().trim();
    final text = '${product['name']} ${product['description'] ?? ''} $cat ${product['sub_category'] ?? ''} ${product['menu_category'] ?? ''}'.toLowerCase();

    // 2. Clear Food Ingredients / Edibles Check
    final isExplicitFoodText = _foodSemanticRegex.hasMatch(text);
    if (isExplicitFoodText) {
      return ProductDemographicType.food;
    }

    // 3. Brand & Semantic Analysis for Lifestyle Items
    // (Protects apparel, undergarments, cosmetics stocked in supermarkets/grocery from false food exclusion)
    if (_menBrands.contains(brand) || _menSemanticRegex.hasMatch(text)) {
      return ProductDemographicType.men;
    }
    if (_womenBrands.contains(brand) || _womenSemanticRegex.hasMatch(text)) {
      return ProductDemographicType.women;
    }
    if (_kidsBrands.contains(brand) || _kidsSemanticRegex.hasMatch(text)) {
      return ProductDemographicType.kids;
    }

    // 4. If category is Food, and no explicit apparel/cosmetic signal was found, it is Food
    if (AppCategories.isFoodCategory(cat)) {
      return ProductDemographicType.food;
    }
    if (cat.contains('cosmetic') || cat.contains('beauty') || cat.contains('salon')) {
      if (text.contains('lipstick') ||
          text.contains('kajal') ||
          text.contains('mascara') ||
          text.contains('eyeliner') ||
          text.contains('foundation') ||
          text.contains('nail') ||
          text.contains('blush') ||
          text.contains('compact') ||
          text.contains('pad') ||
          text.contains('tampon') ||
          text.contains('wax')) {
        return ProductDemographicType.women;
      }
      return ProductDemographicType.unisex;
    }
    if (cat.contains('jewel')) return ProductDemographicType.women;
    if (_unisexBrands.contains(brand) || _unisexSemanticRegex.hasMatch(text)) {
      return ProductDemographicType.unisex;
    }
    if (cat.contains('electronic') ||
        cat.contains('mobile') ||
        cat.contains('stationery') ||
        cat.contains('sports') ||
        cat.contains('hardware') ||
        cat.contains('home decor') ||
        cat.contains('furniture') ||
        cat.contains('auto parts')) {
      return ProductDemographicType.unisex;
    }

    return ProductDemographicType.general;
  }

  // ── Demographic Compatibility Evaluator ────────────────────────────────────

  /// Returns true if [product] is semantically compatible with [targetDemographic].
  ///
  /// Rules:
  ///   • Food is NEVER compatible with a demographic search.
  ///   • Women search includes: Women, Girls, and Unisex lifestyle products.
  ///     Strictly excludes: Men-exclusive and Boys-exclusive products.
  ///   • Men search includes: Men, Boys, and Unisex lifestyle products.
  ///     Strictly excludes: Women-exclusive and Girls-exclusive products.
  ///   • Girls search includes: Girls, Kids, Women, and Unisex products.
  ///   • Boys search includes: Boys, Kids, Men, and Unisex products.
  ///   • Kids search includes: Kids, Boys, Girls, and Unisex baby/child products.
  ///   • Unisex search includes: All Unisex products.
  static bool isCompatibleWithDemographic({
    required ProductModel product,
    required String targetDemographic,
    bool isPureDemographic = false,
  }) {
    final target = targetDemographic.trim().toLowerCase();
    if (target.isEmpty || target == 'all') return true;

    final classification = classifyProduct(product);

    // Food exclusion
    if (classification == ProductDemographicType.food) return false;

    if (target == 'women' || target == 'female' || target == 'ladies' || target == 'woman') {
      if (classification == ProductDemographicType.men || classification == ProductDemographicType.boys) {
        return false;
      }
      return classification == ProductDemographicType.women ||
          classification == ProductDemographicType.girls ||
          classification == ProductDemographicType.unisex ||
          classification == ProductDemographicType.general;
    }

    if (target == 'men' || target == 'male' || target == 'gents' || target == 'man') {
      if (classification == ProductDemographicType.women || classification == ProductDemographicType.girls) {
        return false;
      }
      return classification == ProductDemographicType.men ||
          classification == ProductDemographicType.boys ||
          classification == ProductDemographicType.unisex ||
          classification == ProductDemographicType.general;
    }

    if (target == 'girls' || target == 'girl') {
      if (classification == ProductDemographicType.men || classification == ProductDemographicType.boys) {
        return false;
      }
      return classification == ProductDemographicType.girls ||
          classification == ProductDemographicType.kids ||
          classification == ProductDemographicType.women ||
          classification == ProductDemographicType.unisex;
    }

    if (target == 'boys' || target == 'boy') {
      if (classification == ProductDemographicType.women || classification == ProductDemographicType.girls) {
        return false;
      }
      return classification == ProductDemographicType.boys ||
          classification == ProductDemographicType.kids ||
          classification == ProductDemographicType.men ||
          classification == ProductDemographicType.unisex;
    }

    if (target == 'kids' || target == 'children') {
      if (classification == ProductDemographicType.men || classification == ProductDemographicType.women) {
        return false;
      }
      return classification == ProductDemographicType.kids ||
          classification == ProductDemographicType.boys ||
          classification == ProductDemographicType.girls ||
          classification == ProductDemographicType.unisex;
    }

    if (target == 'unisex') {
      return classification == ProductDemographicType.unisex;
    }

    return true;
  }

  // ── Product Term Matcher ───────────────────────────────────────────────────

  /// Checks whether a single search [term] matches a [ProductModel].
  ///
  /// If [term] is a demographic keyword:
  ///   1. Matches if any tag in [getAllowedTagsForTerm] is present in `product.specialTags`.
  ///   2. Matches if product is semantically compatible with the demographic and unisex.
  ///   3. Rejects food and conflicting gender products.
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

      // 2. Reject if explicitly tagged with conflicting demographic
      final hasConflictingTag = product.specialTags.any((t) =>
          ['#Men', '#Women', '#Boys', '#Girls', '#Kids', '#Unisex']
              .contains(t.trim()) &&
          !allowedTags.contains(t.trim()));
      if (hasConflictingTag) return false;

      // 3. 100x Semantic Demographic Evaluation for untagged items
      final canonical = getCanonicalDemographicForTerm(cleanTerm);
      if (canonical != null) {
        return isCompatibleWithDemographic(
          product: product,
          targetDemographic: canonical,
          isPureDemographic: true,
        );
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

      // 1. Direct tag match
      if (tags.any((t) => allowedTags.contains(t))) return true;

      // 2. Reject conflicting tag
      final hasConflictingTag = tags.any((t) =>
          ['#Men', '#Women', '#Boys', '#Girls', '#Kids', '#Unisex']
              .contains(t) &&
          !allowedTags.contains(t));
      if (hasConflictingTag) return false;

      // 3. 100x Semantic Demographic Evaluation for untagged items
      final canonical = getCanonicalDemographicForTerm(cleanTerm);
      if (canonical != null) {
        final classification = classifyRawProduct(product);
        if (classification == ProductDemographicType.food) return false;

        final target = canonical.toLowerCase();
        if (target == 'women') {
          if (classification == ProductDemographicType.men || classification == ProductDemographicType.boys) {
            return false;
          }
          return classification == ProductDemographicType.women ||
              classification == ProductDemographicType.girls ||
              classification == ProductDemographicType.unisex ||
              classification == ProductDemographicType.general;
        }
        if (target == 'men') {
          if (classification == ProductDemographicType.women || classification == ProductDemographicType.girls) {
            return false;
          }
          return classification == ProductDemographicType.men ||
              classification == ProductDemographicType.boys ||
              classification == ProductDemographicType.unisex ||
              classification == ProductDemographicType.general;
        }
        if (target == 'girls' || target == 'girl') {
          if (classification == ProductDemographicType.men || classification == ProductDemographicType.boys) {
            return false;
          }
          return classification == ProductDemographicType.girls ||
              classification == ProductDemographicType.kids ||
              classification == ProductDemographicType.women ||
              classification == ProductDemographicType.unisex;
        }
        if (target == 'boys' || target == 'boy') {
          if (classification == ProductDemographicType.women || classification == ProductDemographicType.girls) {
            return false;
          }
          return classification == ProductDemographicType.boys ||
              classification == ProductDemographicType.kids ||
              classification == ProductDemographicType.men ||
              classification == ProductDemographicType.unisex;
        }
        if (target == 'kids') {
          if (classification == ProductDemographicType.men || classification == ProductDemographicType.women) {
            return false;
          }
          return classification == ProductDemographicType.kids ||
              classification == ProductDemographicType.boys ||
              classification == ProductDemographicType.girls ||
              classification == ProductDemographicType.unisex;
        }
        if (target == 'unisex') {
          return classification == ProductDemographicType.unisex;
        }
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

    return isCompatibleWithDemographic(
      product: product,
      targetDemographic: selectedDemographic,
      isPureDemographic: true,
    );
  }
}
