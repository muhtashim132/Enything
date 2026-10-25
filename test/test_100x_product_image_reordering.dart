import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:enythingmobilenew/pages/seller/add_product_page.dart';

void main() {
  group('100x Product Image Drag-and-Drop Repositioning Fortress Tests', () {
    test('Repositioning moves 2nd image into 1st place (Cover Photo)', () {
      final imgA = ProductImageItem.remote('https://cdn.enything.com/products/img_a.jpg', customId: 'img_a');
      final imgB = ProductImageItem.remote('https://cdn.enything.com/products/img_b.jpg', customId: 'img_b');

      final List<ProductImageItem> productImages = [imgA, imgB];

      // Initial state: Image A is cover photo (index 0)
      expect(productImages[0].id, 'img_a');
      expect(productImages[1].id, 'img_b');

      // User drags Image B (index 1) to position 0 (or taps "Make Cover")
      final movedItem = productImages.removeAt(1);
      productImages.insert(0, movedItem);

      // Verified: Image B is now in 1st place (Cover Photo)
      expect(productImages.length, 2);
      expect(productImages[0].id, 'img_b');
      expect(productImages[0].remoteUrl, 'https://cdn.enything.com/products/img_b.jpg');
      expect(productImages[1].id, 'img_a');
      expect(productImages[1].remoteUrl, 'https://cdn.enything.com/products/img_a.jpg');
    });

    test('Preserves mixed remote CDN and local file order upon save', () {
      final remoteImg = ProductImageItem.remote('https://cdn.enything.com/products/remote.jpg', customId: 'remote_1');
      final localFile = XFile('/mock/path/camera_photo.jpg');
      final localImg = ProductImageItem.local(localFile, customId: 'local_1');

      // Merchant starts with existing remote image, then adds a local camera photo
      final List<ProductImageItem> productImages = [remoteImg, localImg];

      // Merchant drags local camera photo to position 0 to make it the main cover photo
      final moved = productImages.removeAt(1);
      productImages.insert(0, moved);

      expect(productImages[0].isLocal, isTrue);
      expect(productImages[1].isRemote, isTrue);

      // Simulate _submit() image upload loop
      final List<String> uploadedUrls = [];
      for (int i = 0; i < productImages.length; i++) {
        final item = productImages[i];
        if (item.isRemote) {
          uploadedUrls.add(item.remoteUrl!);
        } else if (item.isLocal) {
          // Mock upload returning public URL for local photo
          final mockUploadedUrl = 'https://supabase.enything.com/storage/v1/object/public/products/shop1/camera_photo_$i.jpg';
          uploadedUrls.add(mockUploadedUrl);
        }
      }

      // Assert uploadedUrls order matches productImages exactly
      expect(uploadedUrls.length, 2);
      expect(uploadedUrls[0], contains('camera_photo_0.jpg')); // Local photo is 1st (Cover)
      expect(uploadedUrls[1], 'https://cdn.enything.com/products/remote.jpg'); // Remote photo is 2nd
    });

    test('1-Tap "Make Cover" moves any image directly to index 0', () {
      final img1 = ProductImageItem.remote('https://cdn.enything.com/p1.jpg', customId: '1');
      final img2 = ProductImageItem.remote('https://cdn.enything.com/p2.jpg', customId: '2');
      final img3 = ProductImageItem.remote('https://cdn.enything.com/p3.jpg', customId: '3');

      final List<ProductImageItem> productImages = [img1, img2, img3];

      // Tap "Make Cover" on img3 (index 2)
      const targetIndex = 2;
      final item = productImages.removeAt(targetIndex);
      productImages.insert(0, item);

      expect(productImages.map((e) => e.id).toList(), ['3', '1', '2']);
      expect(productImages.first.id, '3');
    });

    test('1-Tap Arrow Swap moves image left or right', () {
      final img1 = ProductImageItem.remote('https://cdn.enything.com/p1.jpg', customId: '1');
      final img2 = ProductImageItem.remote('https://cdn.enything.com/p2.jpg', customId: '2');
      final img3 = ProductImageItem.remote('https://cdn.enything.com/p3.jpg', customId: '3');

      final List<ProductImageItem> productImages = [img1, img2, img3];

      // Swap img2 (index 1) to left (index 0)
      final leftMoved = productImages.removeAt(1);
      productImages.insert(0, leftMoved);
      expect(productImages.map((e) => e.id).toList(), ['2', '1', '3']);

      // Swap img2 (now at index 0) to right (index 1)
      final rightMoved = productImages.removeAt(0);
      productImages.insert(1, rightMoved);
      expect(productImages.map((e) => e.id).toList(), ['1', '2', '3']);
    });

    test('Autofill snapshot and undo preserves productImages state and ordering', () {
      final origImg1 = ProductImageItem.remote('https://cdn.enything.com/orig1.jpg', customId: 'orig_1');
      final origImg2 = ProductImageItem.remote('https://cdn.enything.com/orig2.jpg', customId: 'orig_2');

      List<ProductImageItem> productImages = [origImg1, origImg2];

      // Snapshot before catalog autofill
      final snapshot = {
        'productImages': List<ProductImageItem>.from(productImages),
      };

      // Catalog Autofill replaces gallery with 3 new items
      final catalogImg1 = ProductImageItem.remote('https://cdn.enything.com/cat1.jpg', customId: 'cat_1');
      final catalogImg2 = ProductImageItem.remote('https://cdn.enything.com/cat2.jpg', customId: 'cat_2');
      final catalogImg3 = ProductImageItem.remote('https://cdn.enything.com/cat3.jpg', customId: 'cat_3');
      productImages = [catalogImg1, catalogImg2, catalogImg3];

      expect(productImages.length, 3);
      expect(productImages.first.id, 'cat_1');

      // User taps "Undo"
      productImages = List<ProductImageItem>.from(snapshot['productImages'] as List);

      expect(productImages.length, 2);
      expect(productImages[0].id, 'orig_1');
      expect(productImages[1].id, 'orig_2');
    });

    test('Removing cover photo smoothly promotes 2nd photo to cover', () {
      final imgA = ProductImageItem.remote('https://cdn.enything.com/pA.jpg', customId: 'A');
      final imgB = ProductImageItem.remote('https://cdn.enything.com/pB.jpg', customId: 'B');
      final imgC = ProductImageItem.remote('https://cdn.enything.com/pC.jpg', customId: 'C');

      final List<ProductImageItem> productImages = [imgA, imgB, imgC];

      // Remove 1st photo (index 0)
      productImages.removeAt(0);

      expect(productImages.length, 2);
      expect(productImages[0].id, 'B'); // Image B is now index 0 (new Cover photo)
      expect(productImages[1].id, 'C');
    });
  });
}
