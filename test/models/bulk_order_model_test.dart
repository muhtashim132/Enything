import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:enythingmobilenew/models/bulk_order_model.dart';
import 'package:enythingmobilenew/models/product_model.dart';
import 'package:enythingmobilenew/models/order_model.dart';
import 'package:enythingmobilenew/models/shop_model.dart';

void main() {
  group('Bulk Event Catering Model Unit Tests', () {
    test('ProductModel tiered pricing calculates correct unit price for quantity', () {
      final product = ProductModel(
        id: 'p1',
        shopId: 's1',
        name: 'Veg Biryani Handi',
        category: 'Food',
        price: 250.0,
        bulkEligible: true,
        minBulkQuantity: 10,
        bulkPriceTiers: [
          {'min_qty': 10, 'price': 230.0},
          {'min_qty': 25, 'price': 210.0},
          {'min_qty': 50, 'price': 190.0},
        ],
      );

      // Quantities below first tier or base
      expect(product.getPriceForQuantity(5), 250.0);
      // Tier 1 (10-24)
      expect(product.getPriceForQuantity(10), 230.0);
      expect(product.getPriceForQuantity(20), 230.0);
      expect(product.getPriceForQuantity(24), 230.0);
      // Tier 2 (25-49)
      expect(product.getPriceForQuantity(25), 210.0);
      expect(product.getPriceForQuantity(40), 210.0);
      expect(product.getPriceForQuantity(49), 210.0);
      // Tier 3 (50+)
      expect(product.getPriceForQuantity(50), 190.0);
      expect(product.getPriceForQuantity(150), 190.0);
    });

    test('BulkOrderModel calculates packaging progress correctly', () {
      final model = BulkOrderModel(
        id: 'b1',
        orderId: 'o1',
        eventName: 'Tech Meetup Catering',
        eventDate: DateTime(2026, 11, 15),
        deliveryTimeSlotStart: DateTime(2026, 11, 15, 12, 0),
        deliveryTimeSlotEnd: DateTime(2026, 11, 15, 14, 0),
        contactPersonName: 'Aamir',
        contactPersonPhone: '9876543210',
        totalPackagesEstimate: 4,
        totalBatches: 5,
        batchesPacked: 3,
        prepStartedAt: DateTime(2026, 11, 15, 9, 0),
        sellerResponseStatus: 'accepted',
        createdAt: DateTime.now(),
      );

      expect(model.packagingProgress, closeTo(0.6, 0.001));
      expect(model.isAllPacked, false);
      expect(model.eventDateDisplay, isNotEmpty);
      expect(model.slotDisplay, contains('–'));

      final fullyPacked = model.copyWith(batchesPacked: 5);
      expect(fullyPacked.packagingProgress, 1.0);
      expect(fullyPacked.isAllPacked, true);
    });

    test('OrderModel bulk getters and status displays adhere to 100x standards', () {
      final bulkOrder = OrderModel(
        id: 'ord-1234-5678-90ab',
        customerId: 'c1',
        shopId: 's1',
        deliveryCharges: 0.0,
        orderType: 'bulk',
        status: 'bulk_preparing',
        paymentStatus: 'captured',
        paymentMethod: 'upi',
        totalAmount: 5000.0,
        createdAt: DateTime.now(),
      );

      expect(bulkOrder.isBulkOrder, true);
      expect(bulkOrder.isInstantOrder, false);
      expect(bulkOrder.statusDisplay, 'Preparing');

      final readyOrder = bulkOrder.copyWith(status: 'bulk_ready');
      expect(readyOrder.statusDisplay, 'Ready for Pickup');

      final dispatchedOrder = bulkOrder.copyWith(status: 'bulk_dispatched');
      expect(dispatchedOrder.statusDisplay, 'Out for Delivery (Fleet)');

      final instantOrder = bulkOrder.copyWith(orderType: 'instant', status: 'preparing');
      expect(instantOrder.isBulkOrder, false);
      expect(instantOrder.isInstantOrder, true);
      expect(instantOrder.statusDisplay, 'Preparing');
    });

    test('ShopModel bulk catering attributes deserialize cleanly', () {
      final shop = ShopModel(
        id: 's1',
        sellerId: 'sel1',
        name: 'The Royal Banquet Kitchen',
        shopType: 'restaurant',
        address: '123 Residency Road, Srinagar',
        location: const LatLng(34.0837, 74.7973),
        category: 'Restaurant',
        categories: const ['Restaurant'],
        isActive: true,
        acceptsBulkOrders: true,
        maxBulkItemsPerSlot: 150,
        minBulkLeadTimeHours: 6,
        maxBulkLeadTimeHours: 72,
        bulkSlotDurationMinutes: 120,
      );

      expect(shop.acceptsBulkOrders, true);
      expect(shop.maxBulkItemsPerSlot, 150);
      expect(shop.minBulkLeadTimeHours, 6);
      expect(shop.maxBulkLeadTimeHours, 72);
      expect(shop.bulkSlotDurationMinutes, 120);
    });
  });
}
