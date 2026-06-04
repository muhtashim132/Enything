import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';

class LocationProvider extends ChangeNotifier {
  LatLng? _currentLocation;
  String _currentAddress = '';
  String _houseNumber = '';
  String _landmark = '';
  String _pincode = '';
  bool _isLoading = false;
  bool _permissionGranted = false;

  LatLng? get currentLocation => _currentLocation;
  String get currentAddress {
    if (_houseNumber.isEmpty && _landmark.isEmpty && _pincode.isEmpty) return _currentAddress;
    final parts = <String>[];
    if (_houseNumber.isNotEmpty) parts.add(_houseNumber);
    if (_currentAddress.isNotEmpty && _currentAddress != 'Fetching address...') parts.add(_currentAddress);
    if (_landmark.isNotEmpty) parts.add(_landmark);
    if (_pincode.isNotEmpty) parts.add(_pincode);
    return parts.isNotEmpty ? parts.join(', ') : _currentAddress;
  }
  
  String get rawAddress => _currentAddress;
  String get houseNumber => _houseNumber;
  String get landmark => _landmark;
  String get pincode => _pincode;

  bool get isLoading => _isLoading;
  bool get permissionGranted => _permissionGranted;
  bool get hasLocation => _currentLocation != null;

  Future<bool> requestLocation() async {
    _isLoading = true;
    notifyListeners();

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _isLoading = false;
        notifyListeners();
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        _isLoading = false;
        _permissionGranted = false;
        notifyListeners();
        return false;
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        Position? position;

        // Try high accuracy first, fall back to last known position
        try {
          position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 15),
            ),
          );
        } catch (_) {
          // Fallback: last known position (works on emulators)
          position = await Geolocator.getLastKnownPosition();
        }

        if (position == null) {
          _isLoading = false;
          notifyListeners();
          return false;
        }

        _currentLocation = LatLng(position.latitude, position.longitude);
        _permissionGranted = true;
        _currentAddress = 'Fetching address...';
        _isLoading = false;
        notifyListeners();

        // Reverse geocode in background
        await updateAddress();
        return true;
      }
    } catch (e) {
      debugPrint('Location error: $e');
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  void setManualLocation(LatLng location, String address) {
    _currentLocation = location;
    _currentAddress = address;
    _permissionGranted = true;
    notifyListeners();
  }

  void setLocalAddressDetails({String? house, String? mark, String? pin, String? addressText}) {
    if (house != null) _houseNumber = house;
    if (mark != null) _landmark = mark;
    if (pin != null) _pincode = pin;
    if (addressText != null && addressText.isNotEmpty) _currentAddress = addressText;
    notifyListeners();
  }

  Future<void> updateAddressDetails(String userId, {String? house, String? mark, String? pin}) async {
    if (house != null) _houseNumber = house;
    if (mark != null) _landmark = mark;
    if (pin != null) _pincode = pin;
    notifyListeners();
    
    try {
      final db = Supabase.instance.client;
      await db.from('customers').upsert({
        'id': userId,
        if (house != null) 'address_home': {'house': house},
        if (mark != null) 'landmark': mark,
        if (pin != null) 'pincode': pin,
        'address': currentAddress,
      });
    } catch (e) {
      debugPrint('updateAddressDetails error: $e');
    }
  }

  Future<void> loadAddressFromDb(String userId) async {
    try {
      final db = Supabase.instance.client;
      final response = await db.from('customers').select('address_home, landmark, pincode').eq('id', userId).maybeSingle();
      if (response != null) {
        if (response['address_home'] != null && response['address_home'] is Map) {
          _houseNumber = response['address_home']['house'] ?? '';
        } else if (response['address_home'] is String) {
          _houseNumber = response['address_home'];
        }
        _landmark = response['landmark'] ?? '';
        _pincode = response['pincode'] ?? '';
        notifyListeners();
      }
    } catch (e) {
      debugPrint('loadAddressFromDb error: $e');
    }
  }

  double distanceTo(LatLng target) {

    if (_currentLocation == null) return 0;
    const distance = Distance();
    return distance(_currentLocation!, target) / 1000;
  }

  Future<void> updateAddress() async {
    if (_currentLocation == null) return;

    try {
      final response = await http.get(
        Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?format=json&lat=${_currentLocation!.latitude}&lon=${_currentLocation!.longitude}',
        ),
        headers: {
          'User-Agent': 'EnythingMobileApp/1.0',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final address = data['address'] as Map<String, dynamic>?;
        if (address != null) {
          // Build a readable short address
          final parts = <String>[];
          if (address['road'] != null) parts.add(address['road']);
          if (address['suburb'] != null) parts.add(address['suburb']);
          if (address['city'] != null) {
            parts.add(address['city']);
          } else if (address['town'] != null) {
            parts.add(address['town']);
          } else if (address['village'] != null) {
            parts.add(address['village']);
          }
          _currentAddress = parts.isNotEmpty
              ? parts.join(', ')
              : (data['display_name'] ?? 'Your current location');
        } else {
          _currentAddress = data['display_name'] ?? 'Your current location';
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Reverse geocoding error: $e');
      _currentAddress = 'Current Location';
      notifyListeners();
    }
  }

  /// Returns a formatted address string for the current coordinates
  Future<String> getAddressForLocation(LatLng location) async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?format=json&lat=${location.latitude}&lon=${location.longitude}',
        ),
        headers: {'User-Agent': 'EnythingMobileApp/1.0'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['display_name'] ?? 'Location found';
      }
    } catch (e) {
      debugPrint('getAddressForLocation error: $e');
    }
    return '${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)}';
  }

  /// Writes the current in-memory GPS coordinates back to the correct Supabase
  /// table so that the stored location is always fresh.
  ///
  /// [role] must be one of: 'customer', 'seller', 'delivery_partner'
  /// [userId] is the authenticated user's UUID.
  Future<void> syncLocationToDatabase(String role, String userId) async {
    if (_currentLocation == null) return;
    final db = Supabase.instance.client;
    final point =
        'POINT(${_currentLocation!.longitude} ${_currentLocation!.latitude})';
    try {
      switch (role) {
        case 'customer':
          await db.from('customers').update({
            'location': point,
            if (currentAddress.isNotEmpty && currentAddress != 'Fetching address...')
              'address': currentAddress,
          }).eq('id', userId);
          break;
        case 'seller':
          // For sellers we update the shop location via seller_id
          await db.from('shops').update({
            'location': point,
          }).eq('seller_id', userId);
          break;
        case 'delivery_partner':
          await db.from('delivery_partners').update({
            'location': point,
          }).eq('id', userId);
          break;
      }
      debugPrint('✅ Location synced to DB for role=$role');
    } catch (e) {
      debugPrint('syncLocationToDatabase error: $e');
    }
  }
}
