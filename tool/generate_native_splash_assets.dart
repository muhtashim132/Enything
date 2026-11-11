// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Generate 100x Industrial Grade Native Splash Assets', () async {
    TestWidgetsFlutterBinding.ensureInitialized();

    // 1. Load Outfit Font
    final fontBytes = File('assets/google_fonts/Outfit-ExtraBold.ttf').readAsBytesSync();
    final fontLoader = FontLoader('Outfit');
    fontLoader.addFont(Future.value(ByteData.sublistView(Uint8List.fromList(fontBytes))));
    await fontLoader.load();

    // -------------------------------------------------------------------------
    // Helper: Draw Frosted Squircle Brand Logo
    // -------------------------------------------------------------------------
    void drawSquircleLogo({
      required Canvas canvas,
      required Offset center,
      required double size,
    }) {
      final r = size * 0.28;
      final logoRect = Rect.fromCenter(center: center, width: size, height: size);
      final rrect = RRect.fromRectAndRadius(logoRect, Radius.circular(r));

      // A. Outer Glows
      final outerGlowPaint = Paint()
        ..color = const Color(0xFF5B8BFF).withValues(alpha: 0.35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size * 0.35);
      canvas.drawCircle(center, (size + size * 0.25) / 2, outerGlowPaint);

      final innerGlowPaint = Paint()
        ..color = const Color(0xFF4C6EF5).withValues(alpha: 0.25)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size * 0.18);
      canvas.drawCircle(center, (size + size * 0.10) / 2, innerGlowPaint);

      // B. Frosted Squircle Background Gradient
      final bgGradient = ui.Gradient.linear(
        logoRect.topLeft,
        logoRect.bottomRight,
        const [Color(0xFF1A2A6C), Color(0xFF0D1B4A), Color(0xFF07103A)],
        const [0.0, 0.5, 1.0],
      );
      final bgPaint = Paint()..shader = bgGradient;
      canvas.drawRRect(rrect, bgPaint);

      // C. Frosted Border (2px)
      final borderPaint = Paint()
        ..color = const Color(0xFF5B8BFF).withValues(alpha: 0.40)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.0, size * 0.02);
      canvas.drawRRect(rrect, borderPaint);

      // D. Vector "E" Logo Inside Squircle
      canvas.save();
      canvas.clipRRect(RRect.fromRectAndRadius(logoRect, Radius.circular(r - 1.0)));

      final innerInset = size * 0.11;
      final innerSize = size - (innerInset * 2);
      final innerOrigin = Offset(logoRect.left + innerInset, logoRect.top + innerInset);

      final w = innerSize;
      final h = innerSize;
      final thickness = h * 0.24;
      final partRadius = Radius.circular(thickness / 2);

      final topBox = RRect.fromRectAndRadius(
        Rect.fromLTWH(innerOrigin.dx, innerOrigin.dy, w, thickness),
        partRadius,
      );
      final botBox = RRect.fromRectAndRadius(
        Rect.fromLTWH(innerOrigin.dx, innerOrigin.dy + h - thickness, w, thickness),
        partRadius,
      );
      final stemBox = RRect.fromRectAndRadius(
        Rect.fromLTWH(innerOrigin.dx, innerOrigin.dy, thickness, h),
        partRadius,
      );
      final midBox = RRect.fromRectAndRadius(
        Rect.fromLTWH(innerOrigin.dx, innerOrigin.dy + (h - thickness) / 2, w * 0.80, thickness),
        partRadius,
      );

      const colorTop = Color(0xCC00DCFF);  // Cyan
      const colorBot = Color(0xCC6432FF);  // Purple
      const colorStem = Color(0xCC4664FF); // Blue
      const colorMid = Color(0xCC00FFC8);  // Mint

      final botPaint = Paint()..color = colorBot;
      final topPaint = Paint()..color = colorTop;
      final stemPaint = Paint()..color = colorStem;
      final midPaint = Paint()..color = colorMid;

      canvas.drawRRect(botBox, botPaint);
      canvas.drawRRect(topBox, topPaint);
      canvas.drawRRect(stemBox, stemPaint);
      canvas.drawRRect(midBox, midPaint);

      canvas.restore();
    }

    // -------------------------------------------------------------------------
    // Asset 1: Enything_android12_icon.png (1024 x 1024)
    // Pure squircle for Android 12+ 160dp circular system mask
    // -------------------------------------------------------------------------
    {
      const canvasDim = 1024.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Squircle size = 640px (fits securely inside the 1024px circle mask)
      const logoSize = 640.0;
      drawSquircleLogo(
        canvas: canvas,
        center: const Offset(canvasDim / 2, canvasDim / 2),
        size: logoSize,
      );

      final picture = recorder.endRecording();
      final image = await picture.toImage(canvasDim.toInt(), canvasDim.toInt());
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();

      File('logo/Enything_android12_icon.png').writeAsBytesSync(bytes);
      print('✓ Generated logo/Enything_android12_icon.png (${bytes.length} bytes)');
    }

    // -------------------------------------------------------------------------
    // Asset 2: Enything_modern_splash.png (1382 x 1382)
    // Full Lockup (Squircle Logo + "ENYTHING" Wordmark) calibrated for 1:1 parity
    // -------------------------------------------------------------------------
    {
      const canvasDim = 1382.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Scale factor relative to 345.5pt 1x base canvas: 1382 / 345.5 = 4.0x
      const scale = 4.0;
      const logoSize = 97.5 * scale; // 390px
      const gap = 22.0 * scale;      // 88px
      const fontSize = 38.0 * scale; // 152px
      const tracking = 8.0 * scale;  // 32px

      // Measure text layout
      final textSpan = TextSpan(
        text: 'ENYTHING',
        style: TextStyle(
          fontFamily: 'Outfit',
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          letterSpacing: tracking,
          foreground: Paint()
            ..shader = ui.Gradient.linear(
              const Offset(0, 0),
              const Offset(canvasDim, fontSize),
              const [
                Color(0xFF99B8FF),
                Color(0xFF5B8BFF),
                Color(0xFF4C6EF5),
              ],
              const [0.0, 0.5, 1.0],
            ),
        ),
      );

      final textPainter = TextPainter(
        text: textSpan,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();

      final textWidth = textPainter.width;
      final textHeight = textPainter.height;

      // Lockup vertical geometry
      final totalLockupHeight = logoSize + gap + textHeight;
      // Center the entire lockup on the canvas
      final lockupTop = (canvasDim - totalLockupHeight) / 2.0;

      final logoCenter = Offset(canvasDim / 2.0, lockupTop + (logoSize / 2.0));

      // Draw Logo
      drawSquircleLogo(
        canvas: canvas,
        center: logoCenter,
        size: logoSize,
      );

      // Draw Wordmark with subpixel optical compensation
      // Exactly calibrated to align visible glyphs at canvas center (691.0)
      final textLeft = (canvasDim - textWidth) / 2.0 + (tracking / 2.0) - 19.0;
      final textTop = lockupTop + logoSize + gap;

      textPainter.paint(canvas, Offset(textLeft, textTop));

      final picture = recorder.endRecording();
      final image = await picture.toImage(canvasDim.toInt(), canvasDim.toInt());
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();

      File('logo/Enything_modern_splash.png').writeAsBytesSync(bytes);
      print('✓ Generated logo/Enything_modern_splash.png (${bytes.length} bytes)');
    }
  });
}
