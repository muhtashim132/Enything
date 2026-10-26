import '../config/app_categories.dart';
import '../models/order_model.dart';

enum OrderFulfillmentCategory {
  food,
  pharmacy,
  grocery,
  retail,
  mixed,
  cateringFood,
  cateringSupplies,
}

class OrderNotificationContent {
  final String title;
  final String body;

  const OrderNotificationContent({
    required this.title,
    required this.body,
  });
}

class CateringBannerInfo {
  final String label;
  final String emoji;

  const CateringBannerInfo({
    required this.label,
    required this.emoji,
  });
}

class OrderMessagingHelper {
  /// Resolves the fulfillment category for an order or group of orders.
  static OrderFulfillmentCategory resolveCategory(
    OrderModel? order,
    List<OrderModel> groupOrders,
  ) {
    final activeOrders = groupOrders.isNotEmpty
        ? groupOrders
            .where((o) =>
                o.status != 'cancelled' &&
                o.status != 'seller_rejected' &&
                o.status != 'partner_rejected' &&
                o.status != 'rejected')
            .toList()
        : (order != null ? [order] : <OrderModel>[]);

    if (activeOrders.isEmpty && order != null) {
      activeOrders.add(order);
    }

    if (activeOrders.isEmpty) {
      return OrderFulfillmentCategory.retail;
    }

    // 1. Check if bulk / event catering
    if (activeOrders.any((o) => o.isBulkOrder)) {
      final allItems = activeOrders.expand((o) => o.items).toList();
      final hasFoodItems = allItems.any((i) =>
          AppCategories.isFoodCategory(i.productName) ||
          (i.specialInstructions?.toLowerCase().contains('food') ?? false));
      final hasGstFood = activeOrders.any((o) => o.s9_5GstAmount > 0);

      if (hasFoodItems || hasGstFood) {
        return OrderFulfillmentCategory.cateringFood;
      }
      return OrderFulfillmentCategory.cateringSupplies;
    }

    // 2. Multi-shop cross-category evaluation
    final Set<OrderFulfillmentCategory> detectedCategories = {};

    for (final o in activeOrders) {
      detectedCategories.add(_resolveSingleOrderCategory(o));
    }

    if (detectedCategories.length > 1) {
      return OrderFulfillmentCategory.mixed;
    }

    return detectedCategories.isNotEmpty
        ? detectedCategories.first
        : OrderFulfillmentCategory.retail;
  }

  static OrderFulfillmentCategory _resolveSingleOrderCategory(OrderModel order) {
    // Check prescription flag
    if (order.items.any((i) => i.requiresPrescription)) {
      return OrderFulfillmentCategory.pharmacy;
    }

    // Check item names for pharmacy keywords
    for (final item in order.items) {
      final name = item.productName.toLowerCase();
      if (name.contains('tablet') ||
          name.contains('capsule') ||
          name.contains('syrup') ||
          name.contains('ointment') ||
          name.contains('paracetamol') ||
          name.contains('crocin') ||
          name.contains('pharma') ||
          name.contains('medicine') ||
          name.contains('bandage') ||
          name.contains('injection')) {
        return OrderFulfillmentCategory.pharmacy;
      }
    }

    // Check GST snapshot categories
    for (final cat in order.gstRateSnapshot.keys) {
      if (AppCategories.isPharmacyCategory(cat)) {
        return OrderFulfillmentCategory.pharmacy;
      }
    }

    // Check food vs non-food GST amounts
    final hasFoodGst = order.s9_5GstAmount > 0;
    final hasNonFoodGst = order.nonFoodGstAmount > 0;

    if (hasFoodGst && hasNonFoodGst) {
      return OrderFulfillmentCategory.mixed;
    }

    if (hasFoodGst) {
      // Further distinguish prepared food vs grocery
      for (final cat in order.gstRateSnapshot.keys) {
        final group = AppCategories.groupFor(cat);
        if (group == CategoryGroup.perishable) {
          return OrderFulfillmentCategory.grocery;
        }
      }
      return OrderFulfillmentCategory.food;
    }

    // Check category group in snapshot
    for (final cat in order.gstRateSnapshot.keys) {
      if (AppCategories.isFoodCategory(cat)) {
        final group = AppCategories.groupFor(cat);
        if (group == CategoryGroup.perishable) {
          return OrderFulfillmentCategory.grocery;
        }
        return OrderFulfillmentCategory.food;
      }
    }

    return OrderFulfillmentCategory.retail;
  }

  /// Returns the category-adaptive notification title & body for delivered status.
  static OrderNotificationContent getDeliveredNotification(
    OrderModel? order,
    List<OrderModel> groupOrders,
  ) {
    final category = resolveCategory(order, groupOrders);

    switch (category) {
      case OrderFulfillmentCategory.food:
        return const OrderNotificationContent(
          title: 'Order Delivered! 🍽️',
          body: 'Your food was successfully delivered. Enjoy your meal!',
        );
      case OrderFulfillmentCategory.pharmacy:
        return const OrderNotificationContent(
          title: 'Medicines Delivered! 💊',
          body:
              'Your medical supplies have arrived safely. Take care and get well soon!',
        );
      case OrderFulfillmentCategory.grocery:
        return const OrderNotificationContent(
          title: 'Groceries Delivered! 🛒',
          body:
              'Your grocery essentials have been delivered fresh and safe. Thank you!',
        );
      case OrderFulfillmentCategory.retail:
        return const OrderNotificationContent(
          title: 'Order Delivered! 🛍️',
          body: 'Your package has been successfully delivered. Hope you love it!',
        );
      case OrderFulfillmentCategory.mixed:
        return const OrderNotificationContent(
          title: 'Order Delivered! 🎉',
          body:
              'All items from your order have been delivered safely. Thank you for shopping with Enything!',
        );
      case OrderFulfillmentCategory.cateringFood:
        return const OrderNotificationContent(
          title: '🎉 Catering Feast Delivered!',
          body:
              'Your catering feast has been delivered and verified with OTP. Enjoy your celebration!',
        );
      case OrderFulfillmentCategory.cateringSupplies:
        return const OrderNotificationContent(
          title: '🎉 Event Supplies Delivered!',
          body:
              'Your event supplies have been delivered and verified with OTP. Have a wonderful event celebration!',
        );
    }
  }

  /// Returns the category-adaptive tracking stepper / header subtitle for delivered status.
  static String getDeliveredSubtitle(
    OrderModel? order,
    List<OrderModel> groupOrders,
  ) {
    final category = resolveCategory(order, groupOrders);

    switch (category) {
      case OrderFulfillmentCategory.food:
        return 'Enjoy your meal! Thank you 🍽️';
      case OrderFulfillmentCategory.pharmacy:
        return 'Medicines delivered safely. Take care! 💊';
      case OrderFulfillmentCategory.grocery:
        return 'Groceries delivered! Thank you 🛒';
      case OrderFulfillmentCategory.retail:
        return 'Enjoy your order! Thank you 🛍️';
      case OrderFulfillmentCategory.mixed:
        return 'Enjoy your order! Thank you 🎉';
      case OrderFulfillmentCategory.cateringFood:
        return 'Feast delivered & verified! 🎉';
      case OrderFulfillmentCategory.cateringSupplies:
        return 'Event supplies delivered & verified! 🎉';
    }
  }

  /// Returns adaptive banner label and emoji for catering orders.
  static CateringBannerInfo getCateringBannerInfo({
    required String status,
    required String deliveryOtp,
    Map<String, dynamic>? activeOrder,
  }) {
    // Check if the event or items indicate non-food supplies
    final eventName = activeOrder?['event_name']?.toString().toLowerCase() ?? '';
    final isSupplies = eventName.contains('rental') ||
        eventName.contains('equipment') ||
        eventName.contains('decor') ||
        eventName.contains('supplies') ||
        eventName.contains('chair') ||
        eventName.contains('tent');

    switch (status) {
      case 'bulk_confirmed':
      case 'bulk_preparing':
        return CateringBannerInfo(
          label: isSupplies ? 'Preparing Event Supplies' : 'Kitchen Cooking Feast',
          emoji: isSupplies ? '📦' : '👨‍🍳',
        );
      case 'bulk_ready':
        return CateringBannerInfo(
          label: isSupplies
              ? 'Supplies Prepared & Packed'
              : 'Feast Prepared & Packed',
          emoji: isSupplies ? '✨' : '🍱',
        );
      case 'bulk_dispatched':
        final otpSuffix =
            deliveryOtp.isNotEmpty ? ' (OTP: $deliveryOtp)' : '';
        return CateringBannerInfo(
          label: isSupplies
              ? 'Supplies Out for Delivery$otpSuffix'
              : 'Out for Delivery$otpSuffix',
          emoji: '🚗',
        );
      case 'bulk_pending':
      default:
        return CateringBannerInfo(
          label: isSupplies
              ? 'Event Booked · Scheduling Dispatch'
              : 'Feast Booked · Scheduling Kitchen',
          emoji: '🎉',
        );
    }
  }
}
