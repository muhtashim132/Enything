import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:enythingmobilenew/models/saved_address_model.dart';
import 'package:enythingmobilenew/providers/location_provider.dart';

void main() {
  group('100x SavedAddress Model & Forensic Validation', () {
    test('Correctly identifies valid coordinates and rejects Null Island and NaN', () {
      final valid = SavedAddress(
        id: 'addr-1',
        userId: 'user-1',
        label: 'Home',
        address: '123 Main Street',
        latitude: 34.0837,
        longitude: 74.7973,
      );
      expect(valid.hasValidCoordinates, isTrue);
      expect(valid.location, equals(const LatLng(34.0837, 74.7973)));

      final nullIsland = SavedAddress(
        id: 'addr-2',
        userId: 'user-1',
        label: 'Work',
        address: 'Null Island',
        latitude: 0.0,
        longitude: 0.0,
      );
      expect(nullIsland.hasValidCoordinates, isFalse);

      final nanCoords = SavedAddress(
        id: 'addr-3',
        userId: 'user-1',
        label: 'Office',
        address: 'Corrupt GPS',
        latitude: double.nan,
        longitude: 74.7973,
      );
      expect(nanCoords.hasValidCoordinates, isFalse);

      final outOfBounds = SavedAddress(
        id: 'addr-4',
        userId: 'user-1',
        label: 'Shop',
        address: 'Off Planet',
        latitude: 195.0,
        longitude: 250.0,
      );
      expect(outOfBounds.hasValidCoordinates, isFalse);
    });

    test('Validates Work and Shop emoji icons and labels', () {
      final work = SavedAddress(
        id: 'w1',
        userId: 'u1',
        label: 'Work',
        address: 'Tech Park',
        latitude: 34.08,
        longitude: 74.79,
      );
      expect(work.icon, equals('💼'));
      expect(work.displayLabel, equals('Work'));

      final shop = SavedAddress(
        id: 's1',
        userId: 'u1',
        label: 'Shop',
        address: 'Bazaar Road',
        latitude: 34.08,
        longitude: 74.79,
      );
      expect(shop.icon, equals('🏪'));
      expect(shop.displayLabel, equals('Shop'));

      final customOther = SavedAddress(
        id: 'o1',
        userId: 'u1',
        label: 'Other',
        customLabel: 'Gym',
        address: 'Fitness Center',
        latitude: 34.08,
        longitude: 74.79,
      );
      expect(customOther.icon, equals('📍'));
      expect(customOther.displayLabel, equals('Gym'));
    });

    test('Serializes and deserializes accurately', () {
      final map = {
        'id': 'a99',
        'user_id': 'u99',
        'label': 'Office',
        'flat_number': 'Suite 404',
        'address': 'Silicon Tower',
        'landmark': 'Next to Metro',
        'pincode': '190001',
        'latitude': 34.0837,
        'longitude': 74.7973,
        'is_default': true,
      };

      final parsed = SavedAddress.fromMap(map);
      expect(parsed.flatNumber, equals('Suite 404'));
      expect(parsed.isDefault, isTrue);
      expect(parsed.fullAddress, contains('Suite 404'));
      expect(parsed.fullAddress, contains('Silicon Tower'));
      expect(parsed.fullAddress, contains('Next to Metro'));

      final updateMap = parsed.toUpdateMap();
      expect(updateMap['flat_number'], equals('Suite 404'));
      expect(updateMap['is_default'], isTrue);
    });
  });

  group('100x LocationProvider Static Coordinate Validators & Distance Guards', () {
    test('LocationProvider.isValidCoordinates rejects (0,0), NaN, null, and out of bounds', () {
      expect(LocationProvider.isValidCoordinates(null), isFalse);
      expect(LocationProvider.isValidCoordinates(const LatLng(0.0, 0.0)), isFalse);
      expect(LocationProvider.isValidCoordinates(LatLng(double.nan, 74.0)), isFalse);
      expect(LocationProvider.isValidCoordinates(LatLng(34.0, double.nan)), isFalse);
      expect(LocationProvider.isValidCoordinates(const LatLng(91.0, 50.0)), isFalse);
      expect(LocationProvider.isValidCoordinates(const LatLng(34.0, 185.0)), isFalse);
      expect(LocationProvider.isValidCoordinates(const LatLng(34.0837, 74.7973)), isTrue);
    });
  });
}
