// ============================================================================
// payment_config.dart — Enything App-Wide Payment & Fee Configuration
// ============================================================================
//
// ── HOW FEES WORK (for your reference) ──────────────────────────────────────
//
//  [platformFee] = ₹15 flat per order, shown as "Handling Fee" to customer.
//   → This covers Enything's app operations PLUS absorbs the Razorpay gateway fee.
//   → This allows sellers to receive exactly 95% of their item price with no hidden cuts.
//   → This is GST-INCLUSIVE at 18%. The GST inside = ₹15 - ₹15/1.18 = ₹2.29
//
//  Enything's commission on item sales is pure 5%.
//  It is exactly [TaxConfig.enythingTargetMarginPercent] (5%).
//  No gateway fees are deducted from the seller's payout.
//
// ============================================================================

class PaymentConfig {
  // ── Flat Fees (GST-inclusive, shown to customer) ──────────────────────────

  /// Handling / platform fee per order. Shown as "Handling Fee" in bill.
  /// 18% GST is embedded in this amount (extracted for accounting).
  static const double platformFee = 15.0;

  // ── Order Eligibility ─────────────────────────────────────────────────────

  /// Minimum order value to place an order at all.
  static const double minimumOrderValue = 1.0;

  /// Orders below this threshold attract a small-cart fee.
  static const double smallCartThreshold = 99.0;

  /// Small-cart surcharge (GST NOT applicable — it's a deterrent fee).
  static const double smallCartFee = 15.0;

  // ── Weight & Item Limits ──────────────────────────────────────────────────

  static const double maxDeliveryRadiusKm = 9.0;
  static const int maxItemsPerOrder = 50;

  /// Absolute weight cap per order.
  static const double maxWeightKg = 15.0;

  /// Orders heavier than this attract a heavy-order fee.
  static const double heavyOrderThreshold = 10.0;

  /// Heavy-order surcharge (GST NOT applicable — logistics fee).
  static const double heavyOrderFee = 20.0;

  // ── Timeouts ──────────────────────────────────────────────────────────────

  static const int sellerResponseTimeoutSeconds = 300;
  static const int partnerResponseTimeoutSeconds = 600;
}
