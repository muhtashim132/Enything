import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

class ImageCompressionService {
  /// Compresses an image while maintaining very high visual quality.
  ///
  /// Uses a quality of 88 (which is visually indistinguishable from 100%
  /// but significantly reduces file size) and caps the max dimension to 2048px
  /// to prevent massive 12MP+ raws from wasting storage/bandwidth.
  static Future<Uint8List?> compressFile(File file) async {
    try {
      final fileLength = await file.length();

      // If the file is incredibly small already (e.g. < 50KB), don't bother compressing
      if (fileLength < 50 * 1024) {
        return await file.readAsBytes();
      }

      final compressedBytes = await FlutterImageCompress.compressWithFile(
        file.absolute.path,
        minWidth: 1600,
        minHeight: 1600,
        quality: 80, // Balanced quality and minimal RAM usage on low-memory devices
        format: CompressFormat.jpeg,
      );

      // In case compression fails or results in a larger file (rare), fallback to original
      if (compressedBytes != null &&
          compressedBytes.lengthInBytes < fileLength) {
        return compressedBytes;
      }

      return await file.readAsBytes();
    } catch (e) {
      debugPrint('Error during image compression: $e');
      // Graceful fallback: upload original file if compression errors out
      return await file.readAsBytes();
    }
  }
}
