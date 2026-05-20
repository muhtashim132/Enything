import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class LocationProvider extends ChangeNotifier {
  LatLng? _currentLocation;
  String _currentAddress = '';
  bool _isLoading = false;
  bool _permissionGranted = false;

  LatLng? get currentLocation => _currentLocation;
  String get currentAddress => _currentAddress;
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
}
