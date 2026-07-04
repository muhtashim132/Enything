import 'package:share_plus/share_plus.dart';
import '../models/product_model.dart';
import '../models/shop_model.dart';

/// Utility class for sharing product and shop links via the native share sheet.
class ShareUtils {
  // ── Product share ──────────────────────────────────────────────────────────
  static Future<void> shareProduct(ProductModel product, {ShopModel? shop}) async {
    final shopName = shop?.name ?? 'a shop on Enything';
    // ProductModel uses price (current/discounted) and originalPrice (pre-discount)
    final hasDiscount = product.originalPrice != null && product.originalPrice! > product.price;
    final discountPct = hasDiscount
        ? ((product.originalPrice! - product.price) / product.originalPrice! * 100).round()
        : 0;
    final price = hasDiscount
        ? '₹${product.price.toStringAsFixed(0)} ($discountPct% off)'
        : '₹${product.price.toStringAsFixed(0)}';

    final text = StringBuffer()
      ..writeln('🛍️ Check out ${product.name}')
      ..writeln()
      ..writeln('💰 $price')
      ..writeln('🏪 From: $shopName')
      ..writeln()
      ..writeln('Order instantly on Enything — Everything, Everywhere, Instantly!')
      ..writeln()
      ..write('📲 Download the app: https://play.google.com/store/apps/details?id=com.enything.app');

    await Share.share(
      text.toString(),
      subject: '${product.name} on Enything',
    );
  }

  // ── Shop share ─────────────────────────────────────────────────────────────
  static Future<void> shareShop(ShopModel shop) async {
    final ratingStr = shop.totalReviews > 0
        ? '⭐ ${shop.rating.toStringAsFixed(1)} (${shop.totalReviews} reviews)'
        : '🆕 New on Enything';

    final text = StringBuffer()
      ..writeln('🏪 ${shop.name}')
      ..writeln()
      ..writeln(ratingStr)
      ..writeln('⏱️ ${shop.prepTimeMinutes} min prep time')
      ..writeln('📍 ${shop.address}')
      ..writeln()
      ..writeln('Order from them instantly on Enything — Everything, Everywhere, Instantly!')
      ..writeln()
      ..write('📲 Download the app: https://play.google.com/store/apps/details?id=com.enything.app');

    await Share.share(
      text.toString(),
      subject: '${shop.name} on Enything',
    );
  }
}
