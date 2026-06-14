// ============================================================================
// tax_config.dart — Enything India GST & Platform Payout Engine (ADD-ON MODEL)
// ============================================================================
//
// ── MODEL: ADD-ON GST ────────────────────────────────────────────────────────
//
//   Sellers enter their BASE price (pre-GST) in the app.
//   Enything adds the applicable GST % ON TOP at checkout.
//   The customer sees and pays:  Base Price + GST + Delivery + Platform Fee
//
//   This means:
//     • GST never comes out of Enything's or seller's margin.
//     • The customer pays their fair share of tax — legally transparent.
//     • Enything's 10% commission is always 10% of base price, clean.
//
// ── LEGAL FRAMEWORK ─────────────────────────────────────────────────────────
//
//   Enything is an E-Commerce Operator (ECO) under Section 2(45) of CGST Act.
//
//   RESTAURANT / FOOD (Section 9(5) + Notification 17/2021-CT(R)):
//     → Enything is the DEEMED SUPPLIER. Enything collects 5% GST from customer
//       and deposits it directly to the government.
//     → Individual food sellers do NOT need a separate GST registration for
//       these sales (if their annual turnover < ₹20 lakh).
//
//   GROCERY / RETAIL / PHARMACY etc.:
//     → The seller is the supplier. Enything collects GST from customer ON
//       BEHALF of the seller, then passes it to the seller as part of their
//       payout. The seller files their own GST returns.
//
//   ENYTHING'S OWN SERVICES (Delivery + Platform Fee):
//     → Both carry 18% GST. Enything deposits this to the government.
//     → SAC 9965/9967 for delivery, SAC 9985 for platform/handling fee.
//
// ── PAYMENT GATEWAY ─────────────────────────────────────────────────────────
//
//   Razorpay charges 2% + 18% GST on that 2% = 2.36% effective per transaction.
//   COD: zero gateway deduction (cash collected by rider).
//   UPI/Card: 2.36% deducted from the ENTIRE transaction amount.
//
//   Gateway fee is apportioned between Enything and seller proportionally:
//     - Seller absorbs 2.36% on THEIR portion (baseSubtotal - commission + GST passthrough)
//     - Enything absorbs 2.36% on ENYTHING'S portion (commission + delivery collected + platformFee)
//   This ensures no one cross-subsidises the other's gateway cost.
//
// ── ENYTHING COMMISSION ────────────────────────────────────────────────────────
//
//   Target: 10% of base item subtotal, NET after gateway.
//   Formula: grossRate = 10% / (1 - 2.36%) = 10.2418%
//   For COD: grossRate = exactly 10% (no gateway to compensate for).
//
// ── PROFIT SUMMARY (₹500 grocery order, 5 km, UPI) ─────────────────────────
//
//   Item base subtotal:          ₹500.00
//   Item GST (5%, added on top): ₹ 25.00   ← customer pays this
//   Delivery (5 km slab):        ₹ 35.00
//   Delivery discount (≥₹499):  -₹ 15.00
//   Platform fee:                ₹  5.00
//   ─────────────────────────────────────
//   Customer pays (Grand Total): ₹550.00
//
//   Razorpay takes (2.36%):     -₹ 12.98
//   Bank receives:               ₹537.02
//
//   Rider payout (earnings):    -₹ 35.00   (full delivery before discount)
//   Seller payout (base only):  -₹475.00   (₹500 - exactly 5% commission)
//   Seller GST passthrough:     -₹ 25.00   (grocery GST — seller remits to govt)
//   GST Enything remits (own svc): -₹  7.63   (18% inside ₹35 delivery + ₹15 platform)
//   ─────────────────────────────────────
//   Enything Net Profit:            ₹ 18.80
//     • Commission (pure 5%):   +₹ 25.00
//     • Platform net of GST:    +₹ 12.71
//     • Gateway absorbed:       -₹ 13.57
//     • Delivery net of GST:    -₹  5.34 (Enything remits ₹5.34 GST out of the ₹35)
//
//   NOTE: The seller receives exactly 95% of their base price. Zero hidden cuts.
//
// ============================================================================

import '../providers/platform_config_provider.dart';

class TaxConfig {
  // ── Payment Gateway ────────────────────────────────────────────────────────

  /// Razorpay/PhonePe/Cashfree standard fee: 2% of transaction value.
  static const double gatewayFeePercent = 0.02;

  /// GST on the gateway fee itself: 18%.
  static const double gatewayFeeGst = 0.18;

  /// Effective deduction per ₹100 collected online = 2% × 1.18 = 2.36%.
  static double get effectiveGatewayDeductionPercent =>
      gatewayFeePercent * (1 + gatewayFeeGst); // = 0.0236

  // ── Enything's Target Platform Commission ────────────────────────────────────

  /// Enything's pure commission % on base item subtotal.
  static double get enythingTargetMarginPercent =>
      PlatformConfigProvider.instance?.commissionRate ?? 0.05; // default 5%

  /// We no longer gross up the commission. Enything charges exactly 5%
  /// and absorbs the gateway fee itself (covered by the platform fee).
  static double get grossCommissionRateOnline => enythingTargetMarginPercent;

  // ── Rider Payout ─────────────────────────────────────────────────────────────

  /// Rider payout ratio: 80% means Rider gets 80% of the base delivery fee, Enything keeps 20%.
  static const double riderPayoutRatio = 0.80;

  // ── GST on Enything's OWN services ───────────────────────────────────────────

  /// Delivery charge GST rate (SAC 9965/9967): 18%.
  static const double deliveryGstRate = 0.18;

  /// Platform/handling fee GST rate (SAC 9985): 18%.
  static const double platformFeeGstRate = 0.18;

  // ── Item-Level GST Rates by Category (ADD-ON MODEL) ───────────────────────
  //   These rates are applied ON TOP of the seller's base price.
  //   The customer sees: base price + GST in their bill separately.

  static const Map<String, double> _categoryGstRate = {
    // ── Food: Enything is deemed supplier (Section 9(5)) ─────────────────────
    'Restaurant': 0.05, // 5% — no ITC for seller
    'Fast Food': 0.05,
    'Bakery': 0.05,
    'Sweets & Mithai': 0.05,
    'Tea & Coffee': 0.05,
    'Ice Cream': 0.05,
    'Paan Shop': 0.05, // blended (paan 5%, tobacco higher — use 5% avg)

    // ── Perishables / Raw ──────────────────────────────────────────────────
    'Fruits & Vegs': 0.00, // 0% — fresh produce
    'Butcher': 0.00, // 0% — fresh meat
    'Fish & Seafood': 0.00, // 0% — fresh fish
    'Dairy & Eggs': 0.05, // blended: eggs 0%, packaged milk 0%, butter 12%

    // ── Grocery / Organic ─────────────────────────────────────────────────
    'Grocery': 0.05, // 5% blended (staples 5%, loose items 0%)
    'Organic': 0.05,
    'Beverages': 0.12, // 12% — packaged drinks

    // ── Pharmacy ──────────────────────────────────────────────────────────
    'Pharmacy': 0.05, // 5% — life-saving & OTC medicines
    'Medical Store': 0.05,

    // ── Clothing & Footwear (price-slab — handled dynamically) ────────────
    'Clothing': 0.05, // 5% for ≤₹1,000 | 12% for >₹1,000
    'Footwear': 0.05, // same slab as clothing

    // ── Electronics ───────────────────────────────────────────────────────
    'Electronics': 0.18,
    'Mobile & Repair': 0.18,

    // ── Jewellery ─────────────────────────────────────────────────────────
    'Jewellery': 0.03, // 3% on gold/gem value

    // ── General Retail ─────────────────────────────────────────────────────
    'Stationery': 0.12,
    'Toys & Games': 0.12,
    'Sports': 0.12,
    'Pet Supplies': 0.18,
    'Salon & Beauty': 0.18,
    'Flowers': 0.05,
    'Home Decor': 0.18,
    'Furniture': 0.18,
    'Hardware Store': 0.18,
    'Auto Parts': 0.18,
    'Other': 0.18, // conservative default
  };

  /// Returns GST rate as a fraction (e.g. 0.05 = 5%) for a given [category].
  /// For Clothing/Footwear, pass [itemPrice] to get the correct price-based slab.
  static double gstRateForCategory(String category, {double? itemPrice}) {
    if ((category == 'Clothing' || category == 'Footwear') &&
        itemPrice != null) {
      return itemPrice > 1000 ? 0.12 : 0.05;
    }
    return _categoryGstRate[category] ?? 0.18;
  }

  /// Returns a human-readable GST label e.g. "GST 5%".
  static String gstLabel(String category, {double? itemPrice}) {
    final rate = gstRateForCategory(category, itemPrice: itemPrice);
    return 'GST ${(rate * 100).toStringAsFixed(0)}%';
  }

  /// True if Enything is the deemed supplier for this category (Section 9(5)).
  /// These are restaurant/food-service categories.
  /// Enything collects and deposits the GST for these — seller doesn't touch it.
  static bool isEnythingDeemedSupplier(String category) {
    const s9_5Categories = {
      'Restaurant',
      'Fast Food',
      'Bakery',
      'Sweets & Mithai',
      'Tea & Coffee',
      'Ice Cream',
      'Paan Shop',
    };
    return s9_5Categories.contains(category);
  }

  // ── GST Helpers for Enything's own services (delivery + platform) ────────────

  /// GST extracted from a delivery charge (18% inside).
  ///   e.g. ₹35 delivery: GST inside = ₹35 - ₹35/1.18 = ₹5.34
  static double gstInDeliveryCharge(double deliveryCharge) {
    if (deliveryCharge == 0) return 0;
    return deliveryCharge - (deliveryCharge / (1 + deliveryGstRate));
  }

  /// GST extracted from a platform fee (18% inside).
  static double gstInPlatformFee(double platformFee) {
    if (platformFee == 0) return 0;
    return platformFee - (platformFee / (1 + platformFeeGstRate));
  }
}

// =============================================================================
// OrderTaxBreakdown — Complete per-order tax and payout calculation
// =============================================================================

/// Encapsulates the full financial breakdown for one order in the ADD-ON model.
///
/// Call [OrderTaxBreakdown.calculate] once in checkout — it gives you:
///   • Exactly what the customer pays (grand total)
///   • Exactly what the seller receives
///   • Exactly what Enything nets
///   • All GST amounts split by who remits them
///
/// Usage:
///   final b = OrderTaxBreakdown.calculate(
///     items: cart.taxBreakdownItems,
///     deliveryCharge: totalDelivery,
///     platformFee: cart.platformFee,
///     paymentMethod: 'upi',
///   );
class OrderTaxBreakdown {
  // ── Item amounts ──────────────────────────────────────────────────────────

  /// Sum of seller's BASE prices × quantities (pre-GST). Stored as total_amount.
  final double itemBaseSubtotal;

  /// GST added ON TOP of base prices and charged to the customer.
  final double itemGstTotal;

  /// What customer pays for items: itemBaseSubtotal + itemGstTotal.
  final double itemGrossTotal;

  // ── GST split by remittance responsibility ────────────────────────────────

  /// GST on Section 9(5) categories (food/restaurant) — Enything remits to govt.
  final double s9_5GstToRemit;

  /// GST on non-food categories — Enything passes to seller (seller remits).
  final double nonFoodGstPassThrough;

  // ── Delivery & Platform ───────────────────────────────────────────────────

  /// Delivery charge collected from customer (GST-inclusive at 18%).
  final double deliveryCharge;

  /// GST embedded in deliveryCharge — Enything remits to govt.
  final double deliveryGst;

  /// Platform/handling fee (GST-inclusive at 18%).
  final double platformFee;

  /// GST embedded in platformFee — Enything remits to govt.
  final double platformFeeGst;

  // ── Rider Payout ──────────────────────────────────────────────────────────

  /// Amount paid to the rider.
  final double riderEarnings;

  // ── Totals ────────────────────────────────────────────────────────────────

  /// Total GST across items + delivery + platform.
  final double totalGst;

  /// Grand total charged to customer = itemGrossTotal + delivery + platformFee.
  final double grandTotal;

  // ── Gateway ───────────────────────────────────────────────────────────────

  /// Amount deducted by payment gateway (0 for COD).
  final double gatewayDeduction;

  /// Gateway deduction allocated to Enything's revenue portion.
  final double enythingGatewayShare;

  /// Gateway deduction allocated to seller's portion.
  final double sellerGatewayShare;

  // ── Enything P&L ─────────────────────────────────────────────────────────────

  /// Gross commission charged to seller on base subtotal.
  final double enythingGrossCommission;

  /// Net commission after Enything absorbs its share of gateway fees.
  final double enythingNetCommission;

  // ── Seller ────────────────────────────────────────────────────────────────

  /// Amount paid to seller:
  ///   (itemBaseSubtotal − enythingGrossCommission) + nonFoodGstPassThrough
  ///   minus seller's gateway share.
  final double sellerPayout;

  const OrderTaxBreakdown({
    required this.itemBaseSubtotal,
    required this.itemGstTotal,
    required this.itemGrossTotal,
    required this.s9_5GstToRemit,
    required this.nonFoodGstPassThrough,
    required this.deliveryCharge,
    required this.deliveryGst,
    required this.platformFee,
    required this.platformFeeGst,
    required this.totalGst,
    required this.grandTotal,
    required this.gatewayDeduction,
    required this.enythingGatewayShare,
    required this.sellerGatewayShare,
    required this.enythingGrossCommission,
    required this.enythingNetCommission,
    required this.sellerPayout,
    required this.riderEarnings,
  });

  // ---------------------------------------------------------------------------
  // Factory: Calculate everything from raw inputs
  // ---------------------------------------------------------------------------

  /// Calculates the complete breakdown for an order.
  ///
  /// [items] — List of maps with keys: 'category' (String), 'price' (num, BASE price), 'quantity' (num).
  /// [deliveryCharge] — Net delivery charged to customer (18% GST inside).
  /// [riderEarnings] — The amount paid to the rider.
  /// [platformFee] — Platform/handling fee (18% GST inside).
  /// [paymentMethod] — 'upi' / 'card' for gateway deduction, 'cod' for no deduction.
  factory OrderTaxBreakdown.calculate({
    required List<Map<String, dynamic>> items,
    required double deliveryCharge,
    required double riderEarnings,
    required double platformFee,
    required String paymentMethod,
  }) {
    // ── 1. Item base subtotal + GST addition ─────────────────────────────────
    double baseSubtotal = 0;
    double itemGst = 0;
    double s9_5Gst = 0; // food/restaurant GST — Enything remits
    double nonFoodGst = 0; // retail GST — passed to seller
    double pureCommission = 0; // total pure commission calculated per item

    for (final item in items) {
      final category = (item['category'] as String?) ?? 'Other';
      final price = (item['price'] as num).toDouble(); // BASE price, pre-GST
      final qty = (item['quantity'] as num).toInt();
      final lineBase = price * qty;
      final gstRate = TaxConfig.gstRateForCategory(category, itemPrice: price);
      final lineGst = lineBase * gstRate;

      baseSubtotal += lineBase;
      itemGst += lineGst;

      // Category-specific commission
      final commissionRate = PlatformConfigProvider.instance?.getCommissionRateForCategory(category) ?? 0.05;
      pureCommission += lineBase * commissionRate;

      if (TaxConfig.isEnythingDeemedSupplier(category)) {
        s9_5Gst += lineGst;
      } else {
        nonFoodGst += lineGst;
      }
    }

    final itemGross = baseSubtotal + itemGst; // what customer pays for items

    // ── 2. Delivery & Platform GST (extracted — these are Enything's services) ──
    final dGst = TaxConfig.gstInDeliveryCharge(deliveryCharge);
    final pGst = TaxConfig.gstInPlatformFee(platformFee);
    final totalGst = itemGst + dGst + pGst;

    // ── 3. Grand total ────────────────────────────────────────────────────────
    final grand = itemGross + deliveryCharge + platformFee;

    // ── 4. Gateway deduction ──────────────────────────────────────────────────
    final isOnline = paymentMethod != 'cod';
    final gwDeduct =
        isOnline ? grand * TaxConfig.effectiveGatewayDeductionPercent : 0.0;

    // ── 5. Enything commission ───────────────────────────────────────────────────
    //   Commission is on BASE item subtotal only (delivery + platform are
    //   100% Enything's revenue — no commission formula needed there).
    //   (Note: pureCommission is now calculated dynamically per-item in the loop above)

    // ── 6. Gateway split (Seller pays their share, Enything pays remainder) ──
    //   Seller pays 2.36% on their payout portion.
    final sellerBasePayout = baseSubtotal - pureCommission;
    final sellerGwShare = isOnline ? (sellerBasePayout + nonFoodGst) * TaxConfig.effectiveGatewayDeductionPercent : 0.0;
    final enythingGwShare = gwDeduct - sellerGwShare;

    // ── 7. Unified Commission ────────────────────────────────────────────────────
    //   Combine pure commission and gateway fee into one 'Total Commission' 
    //   so the seller sees 7.36% everywhere instead of 5% + 2.36%.
    final enythingGross = pureCommission + sellerGwShare;
    final enythingNet = pureCommission;

    // ── 8. Seller payout ─────────────────────────────────────────────────────
    //   Seller receives exactly 95% of base amount + their GST passthrough minus gateway share.
    final sellerPayout = baseSubtotal + nonFoodGst - enythingGross;

    return OrderTaxBreakdown(
      itemBaseSubtotal: baseSubtotal,
      itemGstTotal: itemGst,
      itemGrossTotal: itemGross,
      s9_5GstToRemit: s9_5Gst,
      nonFoodGstPassThrough: nonFoodGst,
      deliveryCharge: deliveryCharge,
      deliveryGst: dGst,
      platformFee: platformFee,
      platformFeeGst: pGst,
      totalGst: totalGst,
      grandTotal: grand,
      gatewayDeduction: gwDeduct,
      enythingGatewayShare: enythingGwShare,
      sellerGatewayShare: sellerGwShare,
      enythingGrossCommission: enythingGross,
      enythingNetCommission: enythingNet,
      sellerPayout: sellerPayout,
      riderEarnings: riderEarnings,
    );
  }

  // ── Enything's actual net profit on this order ───────────────────────────────

  /// Commission after absorbing Enything's gateway share + delivery/platform GST
  /// remittance. This is what Enything keeps after paying all obligations.
  ///
  /// Note: deliverySubsidy is included — if you gave a discount, you see it here.
  double get enythingNetProfit =>
      enythingNetCommission +
      (deliveryCharge - deliveryGst - riderEarnings) + // delivery net after GST remittance & rider payout
      (platformFee - platformFeeGst) - // platform net after GST remittance
      enythingGatewayShare; // Enything's gateway share

  @override
  String toString() => '''
╔══════════════════════════════════════════════════════╗
║         ENYTHING ORDER TAX & PAYOUT BREAKDOWN           ║
╠══════════════════════════════════════════════════════╣
║ CUSTOMER BILL                                        ║
║   Item base subtotal:      ₹${itemBaseSubtotal.toStringAsFixed(2).padLeft(8)}              ║
║   GST on items (added):  + ₹${itemGstTotal.toStringAsFixed(2).padLeft(8)}              ║
║   Item gross total:        ₹${itemGrossTotal.toStringAsFixed(2).padLeft(8)}              ║
║   Delivery charge:       + ₹${deliveryCharge.toStringAsFixed(2).padLeft(8)}              ║
║   Platform fee:          + ₹${platformFee.toStringAsFixed(2).padLeft(8)}              ║
║   ──────────────────────────────────────────         ║
║   GRAND TOTAL:             ₹${grandTotal.toStringAsFixed(2).padLeft(8)}              ║
╠══════════════════════════════════════════════════════╣
║ GATEWAY (UPI/Card only)                              ║
║   Razorpay deducts (2.36%):  ₹${gatewayDeduction.toStringAsFixed(2).padLeft(8)}           ║
║   Net in Enything bank:         ₹${(grandTotal - gatewayDeduction).toStringAsFixed(2).padLeft(8)}           ║
╠══════════════════════════════════════════════════════╣
║ ENYTHING P&L                                            ║
║   Gross commission (${(TaxConfig.grossCommissionRateOnline * 100).toStringAsFixed(2)}%): ₹${enythingGrossCommission.toStringAsFixed(2).padLeft(8)}           ║
║   Net commission (10% tgt): ₹${enythingNetCommission.toStringAsFixed(2).padLeft(8)}           ║
║   Delivery net of GST:      ₹${(deliveryCharge - deliveryGst).toStringAsFixed(2).padLeft(8)}           ║
║   Platform net of GST:      ₹${(platformFee - platformFeeGst).toStringAsFixed(2).padLeft(8)}           ║
║   Enything gateway share:    - ₹${enythingGatewayShare.toStringAsFixed(2).padLeft(8)}           ║
╠══════════════════════════════════════════════════════╣
║ SELLER PAYOUT                                        ║
║   Base (after commission):  ₹${(itemBaseSubtotal - enythingGrossCommission).toStringAsFixed(2).padLeft(8)}           ║
║   Non-food GST passthrough: ₹${nonFoodGstPassThrough.toStringAsFixed(2).padLeft(8)}           ║
║   Seller gateway share:   - ₹${sellerGatewayShare.toStringAsFixed(2).padLeft(8)}           ║
║   SELLER RECEIVES:          ₹${sellerPayout.toStringAsFixed(2).padLeft(8)}           ║
╠══════════════════════════════════════════════════════╣
║ GST TO REMIT TO GOVERNMENT                           ║
║   S9(5) food GST (Enything):   ₹${s9_5GstToRemit.toStringAsFixed(2).padLeft(8)}           ║
║   Delivery GST (Enything):     ₹${deliveryGst.toStringAsFixed(2).padLeft(8)}           ║
║   Platform GST (Enything):     ₹${platformFeeGst.toStringAsFixed(2).padLeft(8)}           ║
║   Non-food GST (→ Seller):  ₹${nonFoodGstPassThrough.toStringAsFixed(2).padLeft(8)}           ║
║   Total GST in order:       ₹${totalGst.toStringAsFixed(2).padLeft(8)}           ║
╚══════════════════════════════════════════════════════╝''';
}
