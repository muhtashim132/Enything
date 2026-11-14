import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/saved_address_model.dart';
import '../utils/permission_utils.dart';

class LocationProvider extends ChangeNotifier with WidgetsBindingObserver {
  bool _isDisposed = false;

  void safeNotifyListeners() {
    if (!_isDisposed) notifyListeners();
  }

  LocationProvider() {
    WidgetsBinding.instance.addObserver(this);
    initFromCache();
  }

  /// 100x Strict Validation: Rejects Null Island (0,0), NaN, out-of-range coordinates
  static bool isValidCoordinates(LatLng? loc) {
    if (loc == null) return false;
    return loc.latitude != 0.0 &&
        loc.longitude != 0.0 &&
        !loc.latitude.isNaN &&
        !loc.longitude.isNaN &&
        loc.latitude.abs() <= 90.0 &&
        loc.longitude.abs() <= 180.0;
  }

  /// Fast-path cold start initialization from persistent SharedPreferences cache
  Future<void> initFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedAddr = prefs.getString('cached_delivery_address');
      final cachedLat = prefs.getDouble('cached_delivery_lat');
      final cachedLng = prefs.getDouble('cached_delivery_lng');
      final cachedHouse = prefs.getString('cached_delivery_house');
      final cachedMark = prefs.getString('cached_delivery_landmark');
      final cachedPin = prefs.getString('cached_delivery_pincode');

      if (_currentLocation == null &&
          cachedLat != null &&
          cachedLng != null &&
          cachedLat != 0.0 &&
          cachedLng != 0.0) {
        final loc = LatLng(cachedLat, cachedLng);
        if (isValidCoordinates(loc)) {
          _currentLocation = loc;
          if (cachedAddr != null && cachedAddr.isNotEmpty) {
            _currentAddress = cachedAddr;
          }
          if (cachedHouse != null) _houseNumber = cachedHouse;
          if (cachedMark != null) _landmark = cachedMark;
          if (cachedPin != null) _pincode = cachedPin;
          safeNotifyListeners();
        }
      }
    } catch (e) {
      debugPrint('initFromCache error: $e');
    }
  }

  /// Persists current location details to SharedPreferences for 0ms cold-start restoration
  Future<void> _cacheCurrentState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_currentAddress.isNotEmpty &&
          _currentAddress != 'Locating...' &&
          _currentAddress != 'Fetching address...') {
        await prefs.setString('cached_delivery_address', _currentAddress);
      }
      if (isValidCoordinates(_currentLocation)) {
        await prefs.setDouble(
            'cached_delivery_lat', _currentLocation!.latitude);
        await prefs.setDouble(
            'cached_delivery_lng', _currentLocation!.longitude);
      }
      if (_houseNumber.isNotEmpty) {
        await prefs.setString('cached_delivery_house', _houseNumber);
      }
      if (_landmark.isNotEmpty) {
        await prefs.setString('cached_delivery_landmark', _landmark);
      }
      if (_pincode.isNotEmpty) {
        await prefs.setString('cached_delivery_pincode', _pincode);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkLocationOnResume();
    }
  }

  Future<void> _checkLocationOnResume() async {
    if (_isLoading) return;
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        // Automatically refresh live GPS location on app resume if user has not explicitly locked a manual address
        if (_selectedAddress == null) {
          requestLocation(isUserAction: false);
        }
      }
    } catch (e) {
      debugPrint('Error checking location on resume: $e');
    }
  }

  /// Public entry point to trigger lifecycle location check on resume or role switch
  Future<void> checkLocationOnResume() => _checkLocationOnResume();

  SupabaseClient get _supabase => Supabase.instance.client;

  LatLng? _currentLocation;
  String _currentAddress = '';
  String _houseNumber = '';
  String _landmark = '';
  String _pincode = '';
  bool _isLoading = false;
  bool _permissionGranted = false;

  // ─── Saved Addresses (Swiggy/Zomato style) ──────────────────────────────
  List<SavedAddress> _savedAddresses = [];
  SavedAddress? _matchedAddress; // Auto-detected saved address near GPS
  SavedAddress? _selectedAddress; // Manually selected by user
  static const double _matchRadiusMeters = 200; // 200m proximity threshold

  LatLng? get currentLocation => _currentLocation;
  String get currentAddress {
    // If a saved address is actively selected, use its full address
    if (_selectedAddress != null) return _selectedAddress!.fullAddress;
    if (_matchedAddress != null) return _matchedAddress!.fullAddress;
    if (_houseNumber.isEmpty && _landmark.isEmpty && _pincode.isEmpty) {
      return _currentAddress;
    }
    final parts = <String>[];
    if (_houseNumber.isNotEmpty) parts.add(_houseNumber);
    if (_currentAddress.isNotEmpty &&
        _currentAddress != 'Fetching address...') {
      parts.add(_currentAddress);
    }
    if (_landmark.isNotEmpty) parts.add(_landmark);
    if (_pincode.isNotEmpty) parts.add(_pincode);
    return parts.isNotEmpty ? parts.join(', ') : _currentAddress;
  }

  String get rawAddress => _currentAddress;
  String get houseNumber => _houseNumber;
  String get landmark => _landmark;
  String get pincode => _pincode;

  // Saved address getters
  List<SavedAddress> get savedAddresses => _savedAddresses;
  SavedAddress? get matchedAddress => _matchedAddress;
  SavedAddress? get selectedAddress => _selectedAddress;

  /// Returns the active label ("Home", "Office", etc.) or empty string if no match
  String get activeLabel {
    if (_selectedAddress != null) return _selectedAddress!.displayLabel;
    if (_matchedAddress != null) return _matchedAddress!.displayLabel;
    return '';
  }

  /// Returns the emoji icon for the active address label
  String get activeLabelIcon {
    if (_selectedAddress != null) return _selectedAddress!.icon;
    if (_matchedAddress != null) return _matchedAddress!.icon;
    return '';
  }

  bool get isLoading => _isLoading;
  bool get permissionGranted => _permissionGranted;
  bool get hasLocation => isValidCoordinates(_currentLocation);

  void clear() {
    _currentLocation = null;
    _currentAddress = '';
    _houseNumber = '';
    _landmark = '';
    _pincode = '';
    _savedAddresses.clear();
    _matchedAddress = null;
    _selectedAddress = null;
    _permissionGranted = false;
    safeNotifyListeners();
  }

  /// Request location permission and fetch the current GPS position.
  ///
  /// [isUserAction] distinguishes automatic startup calls from explicit user
  /// interactions (e.g. tapping "Enable Location" or "Use Current Location").
  ///
  /// When `false` (startup / resume):
  ///   • Location Services off → silently returns `false`, no redirect.
  ///   • Permission denied → prompts once on first launch via native dialog,
  ///     then silently returns `false` on subsequent launches.
  ///   • Permission permanently denied → silently returns `false`.
  ///
  /// When `true` (user tapped a location button):
  ///   • Location Services off → shows a confirmation dialog offering to
  ///     open device Settings. Only opens Settings if the user confirms.
  ///   • Permission denied → triggers the native permission prompt.
  ///   • Permission permanently denied → shows a confirmation dialog
  ///     offering to open App Settings. Only opens if the user confirms.
  Future<bool> requestLocation({bool isUserAction = false}) async {
    _isLoading = true;
    safeNotifyListeners();

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _isLoading = false;
        safeNotifyListeners();
        if (isUserAction) {
          // User explicitly asked — offer to open Settings with confirmation
          final shouldOpen = await PermissionUtils.showOpenSettingsDialog(
            title: 'Location Services Off',
            message: Platform.isIOS
                ? 'Location Services are turned off. To enable them, go to '
                    'Settings > Privacy & Security > Location Services and '
                    'toggle it on.'
                : 'Location Services are turned off. Please enable them in '
                    'your device settings so we can find nearby shops for you.',
          );
          if (shouldOpen) {
            await Geolocator.openLocationSettings();
          }
        }
        // Startup (isUserAction == false): silently return, no redirect
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        if (!isUserAction) {
          // Automatic startup: only trigger the native prompt on the very
          // first app launch. After that, let the user explicitly tap
          // "Enable Location" — never nag on every open.
          final prefs = await SharedPreferences.getInstance();
          final hasPromptedOnce =
              prefs.getBool('has_prompted_location') ?? false;
          if (hasPromptedOnce) {
            _isLoading = false;
            safeNotifyListeners();
            return false;
          }
          await prefs.setBool('has_prompted_location', true);
        }
        permission =
            await PermissionUtils.requestLocationPermissionWithDisclosure(
          customReason:
              'Enything uses your location to discover nearby products, '
              'calculate accurate delivery times, and guide delivery '
              'partners to your exact address.',
        );
      }

      if (permission == LocationPermission.deniedForever) {
        _isLoading = false;
        _permissionGranted = false;
        safeNotifyListeners();
        if (isUserAction) {
          // User explicitly asked — offer to open App Settings
          final shouldOpen = await PermissionUtils.showOpenSettingsDialog(
            title: 'Location Permission Required',
            message: Platform.isIOS
                ? 'Location access is turned off for Enything. To enable it, '
                    'go to Settings > Enything > Location and select '
                    '"While Using the App".'
                : 'Location permission is permanently denied. Please enable '
                    'it in App Settings > Permissions > Location.',
          );
          if (shouldOpen) {
            await Geolocator.openAppSettings();
          }
        }
        // Startup (isUserAction == false): silently return, no redirect
        return false;
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        // ── Fast-path Tier 1: Instant Last-Known Position (< 50ms) ───────────
        // Immediately place the user in their neighborhood / city while
        // high-accuracy satellite lock warms up in the background.
        try {
          final lastKnown = await Geolocator.getLastKnownPosition();
          if (lastKnown != null && _currentLocation == null) {
            _currentLocation = LatLng(lastKnown.latitude, lastKnown.longitude);
            _permissionGranted = true;
            _currentAddress = 'Locating...';
            _autoMatchSavedAddress();
            safeNotifyListeners();
            // Start early background reverse-geocode
            updateAddress();
          }
        } catch (e) {
          debugPrint('Fast-path lastKnown error: $e');
        }

        // ── Tier 2: Refined High-Accuracy Live Fix ────────────────────────────
        Position? position;
        try {
          position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 10),
            ),
          );
        } catch (_) {
          if (_currentLocation == null) {
            position = await Geolocator.getLastKnownPosition();
          }
        }

        if (position != null) {
          _currentLocation = LatLng(position.latitude, position.longitude);
          _permissionGranted = true;
          _autoMatchSavedAddress();
          _isLoading = false;
          safeNotifyListeners();
          await updateAddress();
          return true;
        } else if (_currentLocation != null) {
          _isLoading = false;
          safeNotifyListeners();
          return true;
        }

        _isLoading = false;
        safeNotifyListeners();
        return false;
      }
    } catch (e) {
      debugPrint('Location error: $e');
    }

    _isLoading = false;
    safeNotifyListeners();
    return false;
  }

  /// 100x Reviewer Security Guard: Restricts the far-away default address bypass
  /// strictly to verified Apple App Store Reviewer demo phone credentials.
  /// Never hijacks the location of real production customers, sellers, or admins.
  bool _isAppleReviewerAccount() {
    try {
      final phone = _supabase.auth.currentUser?.phone ?? '';
      final digits = phone.replaceAll(RegExp(r'\D'), '');
      if (digits.isEmpty) return false;
      return digits.endsWith('9999999991') ||
          digits.endsWith('9999999992') ||
          digits.endsWith('9999999993') ||
          digits.endsWith('9999999996') ||
          digits.endsWith('9999999997') ||
          digits.endsWith('9999999998') ||
          digits.endsWith('9999999999') ||
          digits.endsWith('9876500000');
    } catch (_) {
      return false;
    }
  }

  /// Manually select a saved address as the delivery address
  void selectSavedAddress(SavedAddress addr) {
    _selectedAddress = addr;
    _matchedAddress = null; // Clear auto-match when manual selection
    if (addr.hasValidCoordinates) {
      _currentLocation = addr.location;
    } else {
      // 100x Self-Healing Geocoder: Resolve genuine coordinates if missing (0,0)
      _resolveAndSyncAddressCoordinates(addr);
    }
    _currentAddress = addr.address;
    _houseNumber = addr.flatNumber ?? '';
    _landmark = addr.landmark ?? '';
    _pincode = addr.pincode ?? '';
    _permissionGranted = true;
    _cacheCurrentState();
    safeNotifyListeners();

    // 100x Automatic Sync: Keep database profile synchronized with active selection
    final userId = _supabase.auth.currentUser?.id;
    if (userId != null) {
      syncLocationToDatabase('customer', userId);
    }
  }

  /// Asynchronously resolves coordinates for addresses lacking GPS coordinates
  Future<void> _resolveAndSyncAddressCoordinates(SavedAddress addr) async {
    try {
      final loc = await geocodeAddress(addr.fullAddress);
      if (loc != null && isValidCoordinates(loc)) {
        if (_selectedAddress?.id == addr.id) {
          _currentLocation = loc;
          _cacheCurrentState();
          safeNotifyListeners();
          final userId = _supabase.auth.currentUser?.id;
          if (userId != null) {
            syncLocationToDatabase('customer', userId);
            await _supabase.from('saved_addresses').update({
              'latitude': loc.latitude,
              'longitude': loc.longitude,
            }).eq('id', addr.id);
          }
        }
      }
    } catch (e) {
      debugPrint('_resolveAndSyncAddressCoordinates error: $e');
    }
  }

  /// Clear any manual selection (revert to GPS-based auto-match)
  void clearSelectedAddress() {
    _selectedAddress = null;
    safeNotifyListeners();
  }

  /// Auto-match current GPS against saved addresses
  void _autoMatchSavedAddress() {
    if (_currentLocation == null || _savedAddresses.isEmpty) {
      _matchedAddress = null;
      return;
    }
    const distCalc = Distance();
    SavedAddress? closest;
    double closestDist = double.infinity;

    for (final addr in _savedAddresses) {
      if (!addr.hasValidCoordinates) continue;
      final d = distCalc(_currentLocation!, addr.location);
      if (d < _matchRadiusMeters && d < closestDist) {
        closest = addr;
        closestDist = d;
      }
    }
    _matchedAddress = closest;
    // If we auto-matched and no manual selection, update address details
    if (_matchedAddress != null && _selectedAddress == null) {
      _houseNumber = _matchedAddress!.flatNumber ?? '';
      _landmark = _matchedAddress!.landmark ?? '';
      _pincode = _matchedAddress!.pincode ?? '';
    }
  }

  // ─── Saved Address CRUD ──────────────────────────────────────────────────

  /// Load all saved addresses for a user from the database
  Future<void> loadSavedAddresses(String userId) async {
    try {
      final db = _supabase;
      final response = await db
          .from('saved_addresses')
          .select()
          .eq('user_id', userId)
          .order('is_default', ascending: false)
          .order('created_at', ascending: true);
      _savedAddresses =
          (response as List).map((m) => SavedAddress.fromMap(m)).toList();
      _autoMatchSavedAddress();

      // If user has saved addresses and either no GPS locked or GPS is far outside
      // serviceable region (e.g. Apple Reviewer testing in California), auto-select
      // the default saved address so nearby stores and menus display properly.
      // 100x Guard: Strictly restricted to Apple Reviewer demo credentials; never hijacks real users.
      if (_savedAddresses.isNotEmpty && _selectedAddress == null) {
        final defaultAddr = _savedAddresses.firstWhere(
          (a) => a.isDefault && a.hasValidCoordinates,
          orElse: () => _savedAddresses.firstWhere(
            (a) => a.hasValidCoordinates,
            orElse: () => _savedAddresses.first,
          ),
        );
        if (defaultAddr.hasValidCoordinates) {
          const distCalc = Distance();
          final isFarAway = _currentLocation == null ||
              distCalc(_currentLocation!, defaultAddr.location) > 50000;
          if (isFarAway && _isAppleReviewerAccount()) {
            selectSavedAddress(defaultAddr);
          }
        }
      }

      safeNotifyListeners();
    } catch (e) {
      debugPrint('loadSavedAddresses error: $e');
    }
  }

  /// Add a new saved address
  Future<String?> addSavedAddress(SavedAddress addr) async {
    try {
      var resolvedAddr = addr;
      if (!resolvedAddr.hasValidCoordinates) {
        final coords = await geocodeAddress(resolvedAddr.fullAddress);
        if (coords != null) {
          resolvedAddr = resolvedAddr.copyWith(
            latitude: coords.latitude,
            longitude: coords.longitude,
          );
        }
      }
      final db = _supabase;
      // If this is the first address or marked default, clear others' default
      if (resolvedAddr.isDefault || _savedAddresses.isEmpty) {
        await db
            .from('saved_addresses')
            .update({'is_default': false}).eq('user_id', resolvedAddr.userId);
      }
      await db.from('saved_addresses').insert(resolvedAddr.toInsertMap());
      await loadSavedAddresses(resolvedAddr.userId);
      return null; // success
    } catch (e) {
      debugPrint('addSavedAddress error: $e');
      if (e.toString().contains('Maximum of 4')) {
        return 'You can save up to 4 addresses. Please delete one first.';
      }
      return 'Failed to save address: $e';
    }
  }

  /// Update an existing saved address
  Future<String?> updateSavedAddress(SavedAddress addr) async {
    try {
      var resolvedAddr = addr;
      if (!resolvedAddr.hasValidCoordinates) {
        final coords = await geocodeAddress(resolvedAddr.fullAddress);
        if (coords != null) {
          resolvedAddr = resolvedAddr.copyWith(
            latitude: coords.latitude,
            longitude: coords.longitude,
          );
        }
      }
      final db = _supabase;
      if (resolvedAddr.isDefault) {
        await db
            .from('saved_addresses')
            .update({'is_default': false}).eq('user_id', resolvedAddr.userId);
      }
      await db
          .from('saved_addresses')
          .update(resolvedAddr.toUpdateMap())
          .eq('id', resolvedAddr.id);
      await loadSavedAddresses(resolvedAddr.userId);
      return null; // success
    } catch (e) {
      debugPrint('updateSavedAddress error: $e');
      return 'Failed to update address: $e';
    }
  }

  /// Delete a saved address
  Future<String?> deleteSavedAddress(String addressId, String userId) async {
    try {
      final db = _supabase;
      await db.from('saved_addresses').delete().eq('id', addressId);
      // Clear selection if the deleted address was selected
      if (_selectedAddress?.id == addressId) _selectedAddress = null;
      if (_matchedAddress?.id == addressId) _matchedAddress = null;
      await loadSavedAddresses(userId);
      return null;
    } catch (e) {
      debugPrint('deleteSavedAddress error: $e');
      return 'Failed to delete address: $e';
    }
  }

  /// Set a specific address as the default
  Future<void> setDefaultAddress(String addressId, String userId) async {
    try {
      final db = _supabase;
      await db
          .from('saved_addresses')
          .update({'is_default': false}).eq('user_id', userId);
      await db
          .from('saved_addresses')
          .update({'is_default': true}).eq('id', addressId);
      await loadSavedAddresses(userId);
    } catch (e) {
      debugPrint('setDefaultAddress error: $e');
    }
  }

  void setManualLocation(LatLng location, String address,
      {String? house, String? mark}) {
    if (!isValidCoordinates(location)) return;
    _currentLocation = location;
    _currentAddress = address;
    if (house != null && house.isNotEmpty) _houseNumber = house;
    if (mark != null && mark.isNotEmpty) _landmark = mark;
    _permissionGranted = true;
    _selectedAddress = null; // Clear manual selection on GPS update
    _autoMatchSavedAddress();
    _cacheCurrentState();
    safeNotifyListeners();

    final userId = _supabase.auth.currentUser?.id;
    if (userId != null) {
      syncLocationToDatabase('customer', userId);
    }
  }

  void setLocalAddressDetails(
      {String? house,
      String? mark,
      String? pin,
      String? addressText,
      LatLng? location}) {
    if (house != null) _houseNumber = house;
    if (mark != null) _landmark = mark;
    if (pin != null) _pincode = pin;
    if (addressText != null && addressText.isNotEmpty) {
      _currentAddress = addressText;
    }
    if (location != null && isValidCoordinates(location)) {
      _currentLocation = location;
    }
    _cacheCurrentState();
    safeNotifyListeners();
  }

  Future<void> updateAddressDetails(String userId,
      {String? house, String? mark, String? pin}) async {
    if (house != null) _houseNumber = house;
    if (mark != null) _landmark = mark;
    if (pin != null) _pincode = pin;
    safeNotifyListeners();
    try {
      final db = _supabase;
      // H5 FIX: Fetch existing address_home to merge rather than overwrite
      final existing = await db
          .from('customers')
          .select('address_home')
          .eq('id', userId)
          .maybeSingle();
      Map<String, dynamic> currentAddressHome = {};
      if (existing != null && existing['address_home'] is Map) {
        currentAddressHome =
            Map<String, dynamic>.from(existing['address_home']);
      }
      if (house != null) {
        currentAddressHome['house'] = house;
      }

      await db.from('customers').upsert({
        'id': userId,
        if (currentAddressHome.isNotEmpty) 'address_home': currentAddressHome,
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
      await loadSavedAddresses(userId);
      final db = _supabase;
      final response = await db
          .from('customers')
          .select('address_home, landmark, pincode')
          .eq('id', userId)
          .maybeSingle();
      if (response != null) {
        if (response['address_home'] != null &&
            response['address_home'] is Map) {
          _houseNumber = response['address_home']['house'] ?? '';
        }
        _landmark = response['landmark'] ?? '';
        _pincode = response['pincode'] ?? '';
        safeNotifyListeners();
      }
    } catch (e) {
      debugPrint('loadAddressFromDb error: $e');
    }
  }

  double distanceTo(LatLng target) {
    if (!isValidCoordinates(_currentLocation) || !isValidCoordinates(target)) {
      return -1.0;
    }
    const distance = Distance();
    return distance(_currentLocation!, target) / 1000;
  }

  Future<void> updateAddress() async {
    if (!isValidCoordinates(_currentLocation)) return;

    try {
      final response = await http.get(
        Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?format=json&lat=${_currentLocation!.latitude}&lon=${_currentLocation!.longitude}',
        ),
        headers: {
          'User-Agent':
              'Enything-Food-Delivery-App/1.0 (contact: support@enything.in)',
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
        _cacheCurrentState();
        safeNotifyListeners();

        final userId = _supabase.auth.currentUser?.id;
        if (userId != null) {
          syncLocationToDatabase('customer', userId);
        }
      }
    } catch (e) {
      debugPrint('Reverse geocoding error: $e');
      _currentAddress = 'Current Location';
      _cacheCurrentState();
      safeNotifyListeners();
    }
    // After reverse geocode completes, check for proximity matches
    _autoMatchSavedAddress();
  }

  /// Returns a formatted address string for the current coordinates
  Future<String> getAddressForLocation(LatLng location) async {
    if (!isValidCoordinates(location)) return '';
    try {
      final response = await http.get(
        Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?format=json&lat=${location.latitude}&lon=${location.longitude}',
        ),
        headers: {
          'User-Agent':
              'Enything-Food-Delivery-App/1.0 (contact: support@enything.in)',
        },
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

  /// Forward-geocodes an address string via Nominatim to resolve genuine GPS coordinates.
  Future<LatLng?> geocodeAddress(String addressText) async {
    if (addressText.trim().isEmpty) return null;
    try {
      final query = Uri.encodeComponent(addressText.trim());
      final response = await http.get(
        Uri.parse(
          'https://nominatim.openstreetmap.org/search?format=json&q=$query&limit=1',
        ),
        headers: {
          'User-Agent':
              'Enything-Food-Delivery-App/1.0 (contact: support@enything.in)',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List && data.isNotEmpty) {
          final first = data.first as Map<String, dynamic>;
          final lat = double.tryParse(first['lat']?.toString() ?? '') ?? 0.0;
          final lon = double.tryParse(first['lon']?.toString() ?? '') ?? 0.0;
          final loc = LatLng(lat, lon);
          if (isValidCoordinates(loc)) return loc;
        }
      }
    } catch (e) {
      debugPrint('geocodeAddress error: $e');
    }
    return null;
  }

  /// Writes the current in-memory GPS coordinates back to the correct Supabase
  /// table so that the stored location is always fresh.
  ///
  /// [role] must be one of: 'customer', 'seller', 'delivery_partner'
  /// [userId] is the authenticated user's UUID.
  Future<void> syncLocationToDatabase(String role, String userId) async {
    if (_currentLocation == null) return;
    final db = _supabase;
    final point =
        'POINT(${_currentLocation!.longitude} ${_currentLocation!.latitude})';
    try {
      switch (role) {
        case 'customer':
          await db.from('customers').update({
            'location': point,
            if (currentAddress.isNotEmpty &&
                currentAddress != 'Fetching address...')
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
