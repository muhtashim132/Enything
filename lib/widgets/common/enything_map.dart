import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:latlong2/latlong.dart';
import '../../theme/app_colors.dart';

class EnythingMap extends StatelessWidget {
  final LatLng center;
  final double zoom;
  final List<Marker> markers;
  final bool interactive;

  const EnythingMap({
    super.key,
    required this.center,
    this.zoom = 15.0,
    this.markers = const [],
    this.interactive = true,
  });

  /// Returns the Mapbox tile URL if a valid token is configured, otherwise
  /// falls back to OpenStreetMap so the app never shows a blank map.
  String get _tileUrl {
    final token = dotenv.maybeGet('MAPBOX_TOKEN') ?? '';
    final isValid = token.isNotEmpty && token.startsWith('pk.');
    if (isValid) {
      // Mapbox Streets v12 — beautiful, commercial-grade map tiles
      return 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/{z}/{x}/{y}?access_token=$token';
    }
    // Fallback until the user sets their Mapbox token
    return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  }

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      options: MapOptions(
        initialCenter: center,
        initialZoom: zoom,
        interactionOptions: InteractionOptions(
          flags: interactive ? InteractiveFlag.all : InteractiveFlag.none,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: _tileUrl,
          userAgentPackageName: 'com.enything.app',
          tileDimension: 256,
          // Mapbox requires attribution
          additionalOptions: const {
            'attribution': '© Mapbox © OpenStreetMap',
          },
        ),
        MarkerLayer(
          markers: [
            // Default center marker if no markers provided
            if (markers.isEmpty)
              Marker(
                point: center,
                width: 40,
                height: 40,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.location_on,
                    color: AppColors.primary,
                    size: 30,
                  ),
                ),
              ),
            ...markers,
          ],
        ),
      ],
    );
  }
}

