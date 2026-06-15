import 'package:latlong2/latlong.dart';

class SavedAddress {
  final String id;
  final String userId;
  final String label;         // Home, Office, Hotel, Hospital, Other
  final String? customLabel;  // User-defined name when label == 'Other'
  final String? flatNumber;
  final String address;
  final String? landmark;
  final String? pincode;
  final double latitude;
  final double longitude;
  final bool isDefault;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  SavedAddress({
    required this.id,
    required this.userId,
    required this.label,
    this.customLabel,
    this.flatNumber,
    required this.address,
    this.landmark,
    this.pincode,
    required this.latitude,
    required this.longitude,
    this.isDefault = false,
    this.createdAt,
    this.updatedAt,
  });

  LatLng get location => LatLng(latitude, longitude);

  /// Human-readable display name for the label
  String get displayLabel {
    if (label == 'Other' && customLabel != null && customLabel!.isNotEmpty) {
      return customLabel!;
    }
    return label;
  }

  /// Emoji icon for each label type
  String get icon {
    switch (label) {
      case 'Home':     return '🏠';
      case 'Office':   return '💼';
      case 'Hotel':    return '🏨';
      case 'Hospital': return '🏥';
      default:         return '📍';
    }
  }

  /// Full formatted address string
  String get fullAddress {
    final parts = <String>[];
    if (flatNumber != null && flatNumber!.isNotEmpty) parts.add(flatNumber!);
    if (address.isNotEmpty) parts.add(address);
    if (landmark != null && landmark!.isNotEmpty) parts.add(landmark!);
    if (pincode != null && pincode!.isNotEmpty) parts.add(pincode!);
    return parts.join(', ');
  }

  /// Whether the GPS coordinates are valid (not 0,0 placeholder)
  bool get hasValidCoordinates => latitude != 0 || longitude != 0;

  factory SavedAddress.fromMap(Map<String, dynamic> map) {
    return SavedAddress(
      id: map['id'] ?? '',
      userId: map['user_id'] ?? '',
      label: map['label'] ?? 'Home',
      customLabel: map['custom_label'],
      flatNumber: map['flat_number'],
      address: map['address'] ?? '',
      landmark: map['landmark'],
      pincode: map['pincode'],
      latitude: (map['latitude'] ?? 0).toDouble(),
      longitude: (map['longitude'] ?? 0).toDouble(),
      isDefault: map['is_default'] ?? false,
      createdAt: DateTime.tryParse(map['created_at'] ?? ''),
      updatedAt: DateTime.tryParse(map['updated_at'] ?? ''),
    );
  }

  Map<String, dynamic> toInsertMap() => {
    'user_id': userId,
    'label': label,
    'custom_label': customLabel,
    'flat_number': flatNumber,
    'address': address,
    'landmark': landmark,
    'pincode': pincode,
    'latitude': latitude,
    'longitude': longitude,
    'is_default': isDefault,
  };

  Map<String, dynamic> toUpdateMap() => {
    'label': label,
    'custom_label': customLabel,
    'flat_number': flatNumber,
    'address': address,
    'landmark': landmark,
    'pincode': pincode,
    'latitude': latitude,
    'longitude': longitude,
    'is_default': isDefault,
    'updated_at': DateTime.now().toIso8601String(),
  };

  SavedAddress copyWith({
    String? label,
    String? customLabel,
    String? flatNumber,
    String? address,
    String? landmark,
    String? pincode,
    double? latitude,
    double? longitude,
    bool? isDefault,
  }) {
    return SavedAddress(
      id: id,
      userId: userId,
      label: label ?? this.label,
      customLabel: customLabel ?? this.customLabel,
      flatNumber: flatNumber ?? this.flatNumber,
      address: address ?? this.address,
      landmark: landmark ?? this.landmark,
      pincode: pincode ?? this.pincode,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
