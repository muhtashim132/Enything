import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:enythingmobilenew/services/kyc_draft_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('100x Low-RAM KYC Memory Fortress Tests', () {
    test('Seller Pending Slot Lifecycle (LMK Recovery Guard)', () async {
      // 1. Initially no pending slot
      final initialSlot = await KycDraftService.getPendingSlot('seller');
      expect(initialSlot, isNull);

      // 2. Set pending slot before opening camera
      await KycDraftService.setPendingSlot('seller', 'aadhar_front');
      final recordedSlot = await KycDraftService.getPendingSlot('seller');
      expect(recordedSlot, 'aadhar_front');

      // 3. Clear pending slot after recovery or dismiss
      await KycDraftService.clearPendingSlot('seller');
      final clearedSlot = await KycDraftService.getPendingSlot('seller');
      expect(clearedSlot, isNull);
    });

    test('Delivery Partner Pending Slot Lifecycle (LMK Recovery Guard)', () async {
      // 1. Initially no pending slot
      final initialSlot = await KycDraftService.getPendingSlot('delivery');
      expect(initialSlot, isNull);

      // 2. Set pending slot for driving license back
      await KycDraftService.setPendingSlot('delivery', 'dl_back');
      final recordedSlot = await KycDraftService.getPendingSlot('delivery');
      expect(recordedSlot, 'dl_back');

      // 3. Clear pending slot
      await KycDraftService.clearPendingSlot('delivery');
      final clearedSlot = await KycDraftService.getPendingSlot('delivery');
      expect(clearedSlot, isNull);
    });

    test('Seller KYC Draft Persistence & Restoration on Process Death', () async {
      const testUserId = 'test_seller_user_uuid_100x';

      // 1. Verify no initial draft
      final initialDraft = await KycDraftService.getSellerDraft(testUserId);
      expect(initialDraft, isNull);

      // 2. Save full seller draft
      await KycDraftService.saveSellerDraft(
        userId: testUserId,
        textFields: {
          'aadhar': '251396937779',
          'pan': 'CKAPM2492L',
          'gst': '22AAAAA0000A1Z5',
          'enrolmentId': 'ENR12345678',
          'tradeLicense': 'TL-998877',
          'accountHolder': 'Muhtashim Nazki',
          'bankAccount': '123456789012',
          'ifsc': 'SBIN0001234',
        },
        filePaths: {
          'aadharFront': '/mock/path/aadhar_front.jpg',
          'aadharBack': '/mock/path/aadhar_back.jpg',
          'panFront': '/mock/path/pan_front.jpg',
          'panBack': null,
          'shopProof1': '/mock/path/shop_1.jpg',
          'shopProof2': null,
          'bankProof': '/mock/path/bank.jpg',
        },
        isGstRegistered: false,
        exemptionDeclared: true,
      );

      // 3. Retrieve and verify all fields preserved
      final restoredDraft = await KycDraftService.getSellerDraft(testUserId);
      expect(restoredDraft, isNotNull);
      final textFields = restoredDraft!['textFields'] as Map<String, dynamic>;
      expect(textFields['aadhar'], '251396937779');
      expect(textFields['pan'], 'CKAPM2492L');
      expect(textFields['accountHolder'], 'Muhtashim Nazki');
      expect(restoredDraft['isGstRegistered'], isFalse);
      expect(restoredDraft['exemptionDeclared'], isTrue);

      final filePaths = restoredDraft['filePaths'] as Map<String, dynamic>;
      expect(filePaths['aadharFront'], '/mock/path/aadhar_front.jpg');
      expect(filePaths['panBack'], isNull);

      // 4. Purge draft on successful KYC submission
      await KycDraftService.clearSellerDraft(testUserId);
      final finalDraft = await KycDraftService.getSellerDraft(testUserId);
      expect(finalDraft, isNull);
    });

    test('Delivery KYC Draft Persistence & Restoration', () async {
      const testRiderId = 'test_rider_user_uuid_100x';

      await KycDraftService.saveDeliveryDraft(
        userId: testRiderId,
        textFields: {
          'aadhar': '999988887777',
          'pan': 'ABCDE1234F',
          'dl': 'DL-0420110012345',
          'accountHolder': 'Fast Rider',
          'bankAccount': '9876543210',
          'ifsc': 'HDFC0001234',
        },
        filePaths: {
          'aadharFront': '/mock/rider/aadhar_front.jpg',
          'aadharBack': '/mock/rider/aadhar_back.jpg',
          'panFront': '/mock/rider/pan_front.jpg',
          'panBack': '/mock/rider/pan_back.jpg',
          'dlFront': '/mock/rider/dl_front.jpg',
          'dlBack': '/mock/rider/dl_back.jpg',
          'rcFront': '/mock/rider/rc_front.jpg',
          'rcBack': null,
        },
      );

      final restored = await KycDraftService.getDeliveryDraft(testRiderId);
      expect(restored, isNotNull);
      final textFields = restored!['textFields'] as Map<String, dynamic>;
      expect(textFields['dl'], 'DL-0420110012345');
      expect(textFields['pan'], 'ABCDE1234F');

      await KycDraftService.clearDeliveryDraft(testRiderId);
      expect(await KycDraftService.getDeliveryDraft(testRiderId), isNull);
    });

    test('fileFromPath gracefully handles null, empty, and non-existent paths', () {
      expect(KycDraftService.fileFromPath(null), isNull);
      expect(KycDraftService.fileFromPath(''), isNull);
      expect(KycDraftService.fileFromPath('/non/existent/path/image.jpg'), isNull);
    });
  });
}
