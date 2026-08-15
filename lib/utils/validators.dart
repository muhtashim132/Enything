class AppValidators {
  static String? email(String? value) {
    if (value == null || value.isEmpty) return 'Email is required';
    final regex = RegExp(r'^[\w-\.\+]+@([\w-]+\.)+[\w-]{2,}$');
    if (!regex.hasMatch(value)) return 'Enter a valid email address';
    return null;
  }

  static String? password(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < 6) return 'Minimum 6 characters required';
    return null;
  }

  static String? phone(String? value) {
    if (value == null || value.isEmpty) return 'Phone number is required';

    // Sanitize input: remove spaces, dashes, and +91/91 prefix
    String sanitized = value.replaceAll(RegExp(r'[\s\-]'), '');
    if (sanitized.startsWith('+91')) {
      sanitized = sanitized.substring(3);
    } else if (sanitized.startsWith('91') && sanitized.length == 12) {
      sanitized = sanitized.substring(2);
    }

    if (sanitized.length != 10) return 'Enter valid 10-digit number';
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(sanitized)) {
      return 'Enter valid Indian mobile number';
    }
    return null;
  }

  static String? required(String? value, {String field = 'Field'}) {
    if (value == null || value.trim().isEmpty) return '$field is required';
    return null;
  }

  static String? pinCode(String? value) {
    if (value == null || value.isEmpty) return 'Pin code is required';
    if (!RegExp(r'^\d{6}$').hasMatch(value.trim())) {
      return 'Enter valid 6-digit pin code';
    }
    return null;
  }

  static String? price(String? value) {
    if (value == null || value.isEmpty) return 'Price is required';
    final p = double.tryParse(value);
    if (p == null || p <= 0) return 'Enter a valid price';
    return null;
  }

  // ---------------------------------------------------------------------------
  // 100x Indian Compliance & Banking Validators
  // ---------------------------------------------------------------------------

  /// Validates 15-character Indian Goods and Services Tax Identification Number (GSTIN).
  /// Format: 2 digits (State code) + 5 letters (PAN) + 4 digits (PAN) + 1 letter (PAN) + 1 alphanumeric + 'Z' + 1 checksum
  static String? gstin(String? value, {bool isOptional = false}) {
    if (value == null || value.trim().isEmpty) {
      return isOptional ? null : 'GSTIN is required';
    }
    final sanitized = value.trim().toUpperCase();
    final gstRegex = RegExp(r'^\d{2}[A-Z]{5}\d{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$');
    if (!gstRegex.hasMatch(sanitized)) {
      return 'Enter valid 15-character GSTIN (e.g. 07AAAAA0000A1Z5)';
    }
    return null;
  }

  /// Validates 14-digit Indian Food Safety and Standards Authority of India (FSSAI) license.
  static String? fssai(String? value, {bool isOptional = false}) {
    if (value == null || value.trim().isEmpty) {
      return isOptional ? null : 'FSSAI License number is required';
    }
    final sanitized = value.trim();
    if (!RegExp(r'^[12]\d{13}$').hasMatch(sanitized)) {
      return 'Enter valid 14-digit FSSAI number (starts with 1 or 2)';
    }
    return null;
  }

  /// Validates 10-character Indian Permanent Account Number (PAN).
  /// Format: 5 letters + 4 digits + 1 letter (e.g. ABCDE1234F)
  static String? pan(String? value, {bool isOptional = false}) {
    if (value == null || value.trim().isEmpty) {
      return isOptional ? null : 'PAN is required';
    }
    final sanitized = value.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{5}\d{4}[A-Z]{1}$').hasMatch(sanitized)) {
      return 'Enter valid 10-character PAN (e.g. ABCDE1234F)';
    }
    return null;
  }

  /// Validates 11-character Indian Financial System Code (IFSC) for bank payouts.
  /// Format: 4 letters + 0 + 6 alphanumeric (e.g. SBIN0001234, HDFC0000001)
  static String? ifsc(String? value) {
    if (value == null || value.trim().isEmpty) return 'IFSC Code is required';
    final sanitized = value.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$').hasMatch(sanitized)) {
      return 'Enter valid 11-character IFSC (e.g. HDFC0000001)';
    }
    return null;
  }

  /// Validates standard Indian Bank Account Number (9 to 18 digits).
  static String? bankAccount(String? value) {
    if (value == null || value.trim().isEmpty) return 'Account number is required';
    final sanitized = value.trim();
    if (!RegExp(r'^\d{9,18}$').hasMatch(sanitized)) {
      return 'Enter valid bank account number (9-18 digits)';
    }
    return null;
  }

  /// Validates Indian Driving Licence number for rider KYC.
  static String? drivingLicence(String? value) {
    if (value == null || value.trim().isEmpty) return 'Driving Licence is required';
    final sanitized = value.replaceAll(RegExp(r'[\s\-]'), '').toUpperCase();
    if (sanitized.length < 10 || sanitized.length > 16) {
      return 'Enter valid Driving Licence number';
    }
    return null;
  }
}
