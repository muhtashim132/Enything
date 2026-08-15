/// 100x Universal Currency Formatting Utilities
///
/// Handles Indian numbering system comma separation (e.g. ₹5,999, ₹1,50,000),
/// compact representations (e.g. ₹1.5 L, ₹2.5 Cr), and discount calculations.
class CurrencyUtils {
  /// Formats a number with Indian currency symbol (₹) and Indian comma grouping.
  /// Example: 5999 -> "₹5,999", 150000 -> "₹1,50,000", 0 -> "₹0"
  static String format(num? amount, {bool showSymbol = true}) {
    if (amount == null) return showSymbol ? '₹0' : '0';
    final isNegative = amount < 0;
    final absAmount = amount.abs().round();

    final formatted = _formatIndianGrouping(absAmount);
    final prefix = isNegative ? '-₹' : (showSymbol ? '₹' : '');
    return '$prefix$formatted';
  }

  /// Formats a number with decimals (paise) if present.
  /// Example: 59.50 -> "₹59.50", 100.0 -> "₹100"
  static String formatPaisa(num? amount, {bool showSymbol = true}) {
    if (amount == null) return showSymbol ? '₹0' : '0';
    final isNegative = amount < 0;
    final absAmount = amount.abs();

    if (absAmount % 1 == 0) {
      return format(amount, showSymbol: showSymbol);
    }

    final intPart = absAmount.truncate();
    final decPart = (absAmount - intPart).toStringAsFixed(2).substring(2);
    final formattedInt = _formatIndianGrouping(intPart);
    final prefix = isNegative ? '-₹' : (showSymbol ? '₹' : '');
    return '$prefix$formattedInt.$decPart';
  }

  /// Compact representation for large amounts (Lakhs / Crores / Thousands).
  /// Example: 150000 -> "₹1.5 L", 25000000 -> "₹2.5 Cr", 4500 -> "₹4.5 K"
  static String formatCompact(num? amount, {bool showSymbol = true}) {
    if (amount == null) return showSymbol ? '₹0' : '0';
    final absVal = amount.abs();
    final prefix = amount < 0 ? '-₹' : (showSymbol ? '₹' : '');

    if (absVal >= 10000000) {
      final cr = absVal / 10000000.0;
      return '$prefix${cr.toStringAsFixed(cr % 1 == 0 ? 0 : 1)} Cr';
    } else if (absVal >= 100000) {
      final l = absVal / 100000.0;
      return '$prefix${l.toStringAsFixed(l % 1 == 0 ? 0 : 1)} L';
    } else if (absVal >= 10000) {
      final k = absVal / 1000.0;
      return '$prefix${k.toStringAsFixed(k % 1 == 0 ? 0 : 1)} K';
    }

    return format(amount, showSymbol: showSymbol);
  }

  /// Calculates percentage discount between original price and selling price.
  /// Example: original 6500, price 5999 -> 8 (%)
  static double calculateDiscountPercent(double? originalPrice, double currentPrice) {
    if (originalPrice == null || originalPrice <= currentPrice || originalPrice <= 0) {
      return 0.0;
    }
    return ((originalPrice - currentPrice) / originalPrice) * 100.0;
  }

  /// Calculates total monetary savings.
  /// Example: original 6500, price 5999 -> 501.0
  static double calculateSavings(double? originalPrice, double currentPrice) {
    if (originalPrice == null || originalPrice <= currentPrice) {
      return 0.0;
    }
    return originalPrice - currentPrice;
  }

  // ---------------------------------------------------------------------------
  // Internal Indian comma grouping algorithm (2,2,3 format)
  // ---------------------------------------------------------------------------
  static String _formatIndianGrouping(int number) {
    final str = number.toString();
    if (str.length <= 3) return str;

    final lastThree = str.substring(str.length - 3);
    final rest = str.substring(0, str.length - 3);

    final buffer = StringBuffer();
    for (int i = 0; i < rest.length; i++) {
      if (i > 0 && (rest.length - i) % 2 == 0) {
        buffer.write(',');
      }
      buffer.write(rest[i]);
    }
    buffer.write(',');
    buffer.write(lastThree);

    return buffer.toString();
  }
}
