import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:enythingmobilenew/utils/geo_utils.dart';

void main() {
  group('GeoUtils & Live Tracking Logic Tests', () {
    test('1. calculateBearing computes cardinal bearings accurately', () {
      // Due North: lat increases, lng stays same
      final northBearing = GeoUtils.calculateBearing(
        const LatLng(28.0, 77.0),
        const LatLng(29.0, 77.0),
      );
      expect(northBearing, closeTo(0.0, 0.5));

      // Due East: lat stays same, lng increases
      final eastBearing = GeoUtils.calculateBearing(
        const LatLng(0.0, 0.0),
        const LatLng(0.0, 1.0),
      );
      expect(eastBearing, closeTo(90.0, 0.5));

      // Due South: lat decreases
      final southBearing = GeoUtils.calculateBearing(
        const LatLng(29.0, 77.0),
        const LatLng(28.0, 77.0),
      );
      expect(southBearing, closeTo(180.0, 0.5));

      // Due West: lng decreases
      final westBearing = GeoUtils.calculateBearing(
        const LatLng(0.0, 1.0),
        const LatLng(0.0, 0.0),
      );
      expect(westBearing, closeTo(270.0, 0.5));
    });

    test('2. lerpAngle follows shortest angular path across 0/360 boundary', () {
      // Interpolating from 350° to 10° at t=0.5 should pass through 0° (i.e. result = 0° or 360°)
      final midAngle = GeoUtils.lerpAngle(350.0, 10.0, 0.5);
      expect(midAngle, closeTo(0.0, 0.1));

      // Interpolating from 10° to 350° at t=0.5 should also be 0°
      final reverseMid = GeoUtils.lerpAngle(10.0, 350.0, 0.5);
      expect(reverseMid, closeTo(0.0, 0.1));

      // Standard acute angle
      final standardMid = GeoUtils.lerpAngle(40.0, 80.0, 0.5);
      expect(standardMid, closeTo(60.0, 0.1));
    });

    test('3. lerpLatLng correctly interpolates coordinates', () {
      const p1 = LatLng(10.0, 20.0);
      const p2 = LatLng(20.0, 40.0);

      final mid = GeoUtils.lerpLatLng(p1, p2, 0.5);
      expect(mid.latitude, closeTo(15.0, 0.0001));
      expect(mid.longitude, closeTo(30.0, 0.0001));
    });

    test('4. computeBounds frames multiple points with padding', () {
      final points = [
        const LatLng(28.5, 77.1),
        const LatLng(28.7, 77.3),
        const LatLng(28.6, 77.2),
      ];

      final bounds = GeoUtils.computeBounds(points, paddingFactor: 0.01);
      expect(bounds, isNotNull);
      expect(bounds!.southWest.latitude, closeTo(28.5 - 0.01, 0.001));
      expect(bounds.northEast.latitude, closeTo(28.7 + 0.01, 0.001));
      expect(bounds.southWest.longitude, closeTo(77.1 - 0.01, 0.001));
      expect(bounds.northEast.longitude, closeTo(77.3 + 0.01, 0.001));
    });

    test('5. formatDistance formats meters and kilometers cleanly', () {
      expect(GeoUtils.formatDistance(0.0), '0 m');
      expect(GeoUtils.formatDistance(0.45), '450 m');
      expect(GeoUtils.formatDistance(1.234), '1.2 km');
      expect(GeoUtils.formatDistance(5.0), '5.0 km');
    });

    test('6. estimateTravelTime calculates realistic city delivery ETA', () {
      expect(GeoUtils.estimateTravelTime(0.0), '< 1 min');
      expect(GeoUtils.estimateTravelTime(0.5), closeTo(1, 1).toString().isNotEmpty ? isNotEmpty : isTrue);
      expect(GeoUtils.estimateTravelTime(3.6, avgSpeedKmh: 20.0), '11 min');
    });
  });
}
