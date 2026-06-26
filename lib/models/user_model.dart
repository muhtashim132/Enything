class UserModel {
  final String id;
  final String role;          // primary role stored in profiles table
  final String fullName;
  final String email;
  final String phone;
  final String? avatarUrl;
  final DateTime createdAt;
  /// All roles this user has signed up for (checked across role tables)
  final List<String> activeRoles;
  /// The role currently chosen for this session (may differ from primary role)
  final String activeSessionRole;
  final double averageRating;
  final int totalReviews;
  /// KYC verification status for the active role (pending, verified, rejected)
  final String verificationStatus;
  
  /// Specific verification status for seller role (if applicable)
  final String sellerVerificationStatus;
  
  /// Specific verification status for rider role (if applicable)
  final String riderVerificationStatus;

  UserModel({
    required this.id,
    required this.role,
    required this.fullName,
    required this.email,
    required this.phone,
    this.avatarUrl,
    required this.createdAt,
    List<String>? activeRoles,
    String? activeSessionRole,
    this.averageRating = 0.0,
    this.totalReviews = 0,
    this.verificationStatus = 'verified', // Default for customers usually
    this.sellerVerificationStatus = 'unverified',
    this.riderVerificationStatus = 'unverified',
  })  : activeRoles = activeRoles ?? [role],
        activeSessionRole = activeSessionRole ?? role;

  factory UserModel.fromMap(Map<String, dynamic> map) {
    final role = map['role'] ?? 'customer';
    return UserModel(
      id: map['id'] ?? '',
      role: role,
      fullName: map['full_name'] ?? map['name'] ?? '',
      email: map['email'] ?? '',
      phone: map['phone'] ?? '',
      avatarUrl: map['avatar_url'],
      createdAt: DateTime.tryParse(map['created_at'] ?? '') ?? DateTime.now(),
      activeRoles: (map['activeRoles'] as List<dynamic>?)?.cast<String>() ?? [role],
      activeSessionRole: map['activeSessionRole'] as String? ?? role,
      averageRating: (map['average_rating'] ?? 0.0).toDouble(),
      totalReviews: map['total_reviews'] ?? 0,
      verificationStatus: map['verification_status'] as String? ?? 'verified',
      sellerVerificationStatus: map['seller_verification_status'] as String? ?? 'unverified',
      riderVerificationStatus: map['rider_verification_status'] as String? ?? 'unverified',
    );
  }

  UserModel copyWith({
    String? activeSessionRole,
    List<String>? activeRoles,
    double? averageRating,
    int? totalReviews,
    String? verificationStatus,
    String? sellerVerificationStatus,
    String? riderVerificationStatus,
  }) {
    return UserModel(
      id: id,
      role: role,
      fullName: fullName,
      email: email,
      phone: phone,
      avatarUrl: avatarUrl,
      createdAt: createdAt,
      activeRoles: activeRoles ?? this.activeRoles,
      activeSessionRole: activeSessionRole ?? this.activeSessionRole,
      averageRating: averageRating ?? this.averageRating,
      totalReviews: totalReviews ?? this.totalReviews,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      sellerVerificationStatus: sellerVerificationStatus ?? this.sellerVerificationStatus,
      riderVerificationStatus: riderVerificationStatus ?? this.riderVerificationStatus,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'role': role,
    'full_name': fullName,
    'email': email,
    'phone': phone,
    'avatar_url': avatarUrl,
    'average_rating': averageRating,
    'total_reviews': totalReviews,
  };

  String get initials {
    final parts = fullName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (fullName.isNotEmpty) {
      return fullName[0].toUpperCase();
    }
    return 'U';
  }

  /// Human-readable label for a given role string
  static String roleLabel(String r) {
    switch (r) {
      case 'admin':            return 'Admin';       // APP3 FIX: was falling through to default
      case 'seller':           return 'Seller';
      case 'delivery_partner': return 'Delivery Partner';
      case 'customer':         return 'Customer';
      default:                 return r;
    }
  }

  /// Human-readable label for the current primary role
  String get roleDisplay => roleLabel(role);

  /// Human-readable label for the active session role
  String get sessionRoleDisplay => roleLabel(activeSessionRole);
}
