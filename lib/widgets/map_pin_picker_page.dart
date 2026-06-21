import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../theme/app_colors.dart';

// ─── Result model ─────────────────────────────────────────────────────────────

/// Returned by [MapPinPickerPage] when the user confirms a location.
class MapPickResult {
  final LatLng location;
  final String address;
  const MapPickResult({required this.location, required this.address});
}

// ─── Page ─────────────────────────────────────────────────────────────────────

/// Full-screen, Swiggy/Zomato-style map pin picker.
///
/// The map moves under a stationary center pin.
/// When the user lifts their finger, the pin drops and reverse-geocodes in real time.
///
/// Push this page and await the result:
/// ```dart
/// final result = await Navigator.push<MapPickResult?>(
///   context,
///   MaterialPageRoute(builder: (_) => const MapPinPickerPage()),
/// );
/// if (result != null) { /* use result.location and result.address */ }
/// ```
class MapPinPickerPage extends StatefulWidget {
  /// Pre-center the map here (existing address / GPS fix).
  final LatLng? initialLocation;

  /// Pre-fill the address text (e.g. for editing an existing address).
  final String? initialAddress;

  /// AppBar title text.
  final String title;

  /// Label for the bottom confirm button.
  final String confirmLabel;

  /// Tooltip shown above the pin.  Pass `null` to hide it entirely.
  final String? tooltip;

  const MapPinPickerPage({
    super.key,
    this.initialLocation,
    this.initialAddress,
    this.title = 'Select Your Location',
    this.confirmLabel = 'Confirm Location',
    this.tooltip = 'Place the pin to your exact location',
  });

  @override
  State<MapPinPickerPage> createState() => _MapPinPickerPageState();
}

class _MapPinPickerPageState extends State<MapPinPickerPage>
    with TickerProviderStateMixin {
  // Map
  late final MapController _mapController;

  // Pin animation (lifts when dragging, drops when still)
  late final AnimationController _pinAnim;
  late final Animation<double> _pinLift; // 0 → -18 px

  // Search
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  bool _isSearching = false;
  List<Map<String, dynamic>> _suggestions = [];
  bool _showSuggestions = false;

  // State
  LatLng _center = const LatLng(20.5937, 78.9629); // fallback: centre of India
  String _address = '';
  bool _isGeocoding = false;
  bool _isDragging = false;
  bool _isFetchingGps = false;
  Timer? _geocodeDebounce;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    _mapController = MapController();

    _pinAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _pinLift = Tween<double>(begin: 0, end: -18).animate(
      CurvedAnimation(parent: _pinAnim, curve: Curves.easeOut),
    );

    if (widget.initialLocation != null) {
      _center = widget.initialLocation!;
      _address = widget.initialAddress ?? '';
      if (_address.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback(
            (_) => _reverseGeocode(_center, force: true));
      }
    } else {
      // No seed location → try GPS
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _goToCurrentLocation());
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    _pinAnim.dispose();
    _searchCtrl.dispose();
    _geocodeDebounce?.cancel();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // ── Tile URL ────────────────────────────────────────────────────────────────

  String get _tileUrl {
    final token = dotenv.maybeGet('MAPBOX_TOKEN') ?? '';
    if (token.isNotEmpty && token.startsWith('pk.')) {
      return 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/{z}/{x}/{y}?access_token=$token';
    }
    return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  }

  // ── Map interaction ─────────────────────────────────────────────────────────

  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    _center = camera.center;
    if (hasGesture) {
      if (!_isDragging) {
        setState(() {
          _isDragging = true;
          _address = '';
        });
        _pinAnim.forward();
      }
      _geocodeDebounce?.cancel();
    }
  }

  /// Called by [Listener.onPointerUp] — flutter_map v8 has no built-in "drag end".
  void _onPointerUp(PointerUpEvent _) {
    if (!_isDragging) return;
    setState(() => _isDragging = false);
    _pinAnim.reverse();
    _geocodeDebounce?.cancel();
    _geocodeDebounce = Timer(
      const Duration(milliseconds: 650),
      () => _reverseGeocode(_center),
    );
  }

  // ── Geocoding ───────────────────────────────────────────────────────────────

  Future<void> _reverseGeocode(LatLng loc, {bool force = false}) async {
    if (!mounted) return;
    setState(() => _isGeocoding = true);
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?format=json'
        '&lat=${loc.latitude}'
        '&lon=${loc.longitude}'
        '&zoom=18'
        '&addressdetails=1',
      );
      final resp = await http
          .get(uri, headers: {'User-Agent': 'EnythingMobileApp/1.0'})
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        final addr = data['address'] as Map<String, dynamic>?;
        String built = '';
        if (addr != null) {
          final parts = <String>[];
          for (final key in [
            'road',
            'neighbourhood',
            'suburb',
            'village',
            'town',
            'city',
            'state_district',
            'state'
          ]) {
            if (addr.containsKey(key) && (addr[key] as String).isNotEmpty) {
              // Avoid duplicates
              if (!parts.contains(addr[key])) parts.add(addr[key] as String);
              // Stop after city-level
              if (key == 'city' || key == 'town' || key == 'village') break;
            }
          }
          if (addr['state'] != null &&
              (parts.isEmpty || parts.last != addr['state'])) {
            parts.add(addr['state'] as String);
          }
          built = parts.isNotEmpty
              ? parts.join(', ')
              : (data['display_name'] as String? ?? '');
        } else {
          built = data['display_name'] as String? ?? '';
        }
        if (mounted) {
          setState(() {
            _address = built;
            _isGeocoding = false;
          });
        }
      } else {
        _setFallbackAddress(loc);
      }
    } catch (_) {
      _setFallbackAddress(loc);
    }
  }

  void _setFallbackAddress(LatLng loc) {
    if (!mounted) return;
    setState(() {
      _address =
          '${loc.latitude.toStringAsFixed(5)}, ${loc.longitude.toStringAsFixed(5)}';
      _isGeocoding = false;
    });
  }

  // ── Location search ─────────────────────────────────────────────────────────

  Future<void> _doSearch(String query) async {
    if (query.trim().length < 3) {
      if (mounted) {
        setState(() {
          _suggestions = [];
          _showSuggestions = false;
          _isSearching = false;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _isSearching = true);
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?format=json'
        '&q=${Uri.encodeQueryComponent(query)}'
        '&limit=5'
        '&addressdetails=1',
      );
      final resp = await http
          .get(uri, headers: {'User-Agent': 'EnythingMobileApp/1.0'})
          .timeout(const Duration(seconds: 8));

      if (!mounted) return;
      if (resp.statusCode == 200) {
        final results = json.decode(resp.body) as List;
        setState(() {
          _suggestions = results.cast<Map<String, dynamic>>();
          _showSuggestions = _suggestions.isNotEmpty;
          _isSearching = false;
        });
      } else {
        setState(() => _isSearching = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _selectSuggestion(Map<String, dynamic> r) {
    final lat = double.tryParse(r['lat'] as String? ?? '') ?? 0;
    final lon = double.tryParse(r['lon'] as String? ?? '') ?? 0;
    if (lat == 0 && lon == 0) return;

    final loc = LatLng(lat, lon);
    _mapController.move(loc, 16);
    final addr = r['display_name'] as String? ?? '';

    setState(() {
      _center = loc;
      _address = addr;
      _showSuggestions = false;
      _isSearching = false;
    });
    _searchCtrl.clear();
    FocusScope.of(context).unfocus();
  }

  // ── My Location ──────────────────────────────────────────────────────────────

  Future<void> _goToCurrentLocation() async {
    if (!mounted) return;
    setState(() => _isFetchingGps = true);
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        if (mounted) setState(() => _isFetchingGps = false);
        return;
      }

      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 10),
          ),
        );
      } catch (_) {
        pos = await Geolocator.getLastKnownPosition();
      }

      if (!mounted) return;
      if (pos == null) {
        setState(() => _isFetchingGps = false);
        return;
      }
      final loc = LatLng(pos.latitude, pos.longitude);
      _mapController.move(loc, 16);
      setState(() {
        _center = loc;
        _isFetchingGps = false;
      });
      await _reverseGeocode(loc);
    } catch (_) {
      if (mounted) setState(() => _isFetchingGps = false);
    }
  }

  // ── Confirm ──────────────────────────────────────────────────────────────────

  void _confirm() {
    if (_isGeocoding) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Finding address, please wait…',
            style: GoogleFonts.outfit()),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      return;
    }
    if (_address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Move the map to set your location first',
            style: GoogleFonts.outfit()),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      return;
    }
    Navigator.pop(
      context,
      MapPickResult(location: _center, address: _address),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── 1. Full-screen interactive map ─────────────────────────────
          Listener(
            onPointerUp: _onPointerUp,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _center,
                initialZoom: 15,
                onPositionChanged: _onPositionChanged,
              ),
              children: [
                TileLayer(
                  urlTemplate: _tileUrl,
                  userAgentPackageName: 'com.enything.app',
                  tileDimension: 256,
                ),
              ],
            ),
          ),

          // ── 2. Stationary center pin (map moves under it) ─────────────
          IgnorePointer(
            child: Center(
              child: AnimatedBuilder(
                animation: _pinLift,
                builder: (_, child) => Transform.translate(
                  // -32 shifts the pin base to map center; lift raises it
                  offset: Offset(0, _pinLift.value - 32),
                  child: child,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Tooltip bubble (only shown when not dragging)
                    if (widget.tooltip != null)
                      AnimatedBuilder(
                        animation: _pinAnim,
                        builder: (_, child) => Opacity(
                          opacity: (1 - _pinAnim.value).clamp(0.0, 1.0),
                          child: child,
                        ),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.82),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            widget.tooltip!,
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    // Pin icon
                    Stack(
                      alignment: Alignment.topCenter,
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 52,
                          color: AppColors.primary,
                        ),
                        Positioned(
                          top: 8,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                    ),
                    // Shadow under pin (shrinks when lifted)
                    AnimatedBuilder(
                      animation: _pinAnim,
                      builder: (_, __) {
                        final t = _pinAnim.value;
                        return Container(
                          width: (16 - t * 6).clamp(8.0, 16.0),
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.black
                                .withValues(alpha: (0.25 - t * 0.2).clamp(0.0, 0.25)),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── 3. Top overlay: back + title + search ─────────────────────
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Back button + title row
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  child: Row(
                    children: [
                      _circleButton(
                        icon: Icons.arrow_back,
                        isDark: isDark,
                        onTap: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.title,
                          style: GoogleFonts.outfit(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Colors.black87,
                            shadows: const [
                              Shadow(color: Colors.black26, blurRadius: 6),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // Search bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (v) {
                        setState(() {}); // refresh suffix icon
                        _searchDebounce?.cancel();
                        _searchDebounce = Timer(
                          const Duration(milliseconds: 400),
                          () => _doSearch(v),
                        );
                      },
                      style: GoogleFonts.outfit(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search for area, street name...',
                        hintStyle: GoogleFonts.outfit(
                            color: Colors.grey.shade500, fontSize: 14),
                        prefixIcon: _isSearching
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                ),
                              )
                            : const Icon(Icons.search_rounded,
                                color: AppColors.primary),
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() {
                                    _suggestions = [];
                                    _showSuggestions = false;
                                  });
                                  FocusScope.of(context).unfocus();
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                      ),
                    ),
                  ),
                ),

                // Search suggestions dropdown
                if (_showSuggestions && _suggestions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                    child: Container(
                      decoration: BoxDecoration(
                        color:
                            isDark ? const Color(0xFF1E1E2E) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: _suggestions.map((r) {
                            final name = r['display_name'] as String? ?? '';
                            final trimmed = name.length > 65
                                ? '${name.substring(0, 65)}…'
                                : name;
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.location_on_outlined,
                                  color: AppColors.primary, size: 18),
                              title: Text(trimmed,
                                  style: GoogleFonts.outfit(fontSize: 13)),
                              onTap: () => _selectSuggestion(r),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── 4. My Location FAB ─────────────────────────────────────────
          Positioned(
            right: 16,
            bottom: safeBottom + 210,
            child: FloatingActionButton.small(
              heroTag: 'mapPickerMyLocation',
              backgroundColor:
                  isDark ? const Color(0xFF1E1E2E) : Colors.white,
              elevation: 6,
              onPressed: _isFetchingGps ? null : _goToCurrentLocation,
              child: _isFetchingGps
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location_rounded,
                      color: AppColors.primary, size: 22),
            ),
          ),

          // ── 5. Bottom card: address + Confirm ──────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(20, 20, 20, safeBottom + 20),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Address row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.location_on_rounded,
                          color: AppColors.primary, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _isGeocoding
                            ? Row(
                                children: [
                                  const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                  const SizedBox(width: 10),
                                  Text('Finding address…',
                                      style: GoogleFonts.outfit(
                                          fontSize: 13,
                                          color: Colors.grey.shade500)),
                                ],
                              )
                            : _address.isEmpty
                                ? Text(
                                    'Drag the map to place the pin',
                                    style: GoogleFonts.outfit(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? Colors.white70
                                          : Colors.black54,
                                    ),
                                  )
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _address,
                                        style: GoogleFonts.outfit(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black87,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Confirm button
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: (_isGeocoding || _address.isEmpty)
                          ? null
                          : _confirm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            AppColors.primary.withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        widget.confirmLabel,
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleButton({
    required IconData icon,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: isDark ? Colors.black87 : Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: 20,
            color: isDark ? Colors.white : Colors.black87),
      ),
    );
  }
}
