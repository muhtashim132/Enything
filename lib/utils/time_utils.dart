extension DateTimeIST on DateTime {
  /// Converts the DateTime to Indian Standard Time (IST) strictly.
  /// If the DateTime is already in UTC, it adds 5 hours and 30 minutes.
  /// This ensures that all UI formatting shows IST regardless of the device's local timezone.
  DateTime toIST() {
    final utc = isUtc ? this : toUtc();
    return utc.add(const Duration(hours: 5, minutes: 30));
  }
}

/// 100x Standardized Indian Standard Time (IST) & Date Utilities
class DateTimeUtils {
  /// Converts any DateTime to IST representation.
  static DateTime toIST(DateTime dateTime) => dateTime.toIST();

  /// Formats a DateTime into a friendly relative string in IST.
  /// Examples: "Just now", "5m ago", "2h ago", "Yesterday, 3:30 PM", "15 Aug, 11:30 AM"
  static String formatRelative(DateTime? dateTime) {
    if (dateTime == null) return '';
    final nowIst = DateTime.now().toIST();
    final targetIst = dateTime.toIST();
    final difference = nowIst.difference(targetIst);

    if (difference.isNegative) {
      return formatTimeOnly(targetIst);
    }

    if (difference.inSeconds < 45) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24 && nowIst.day == targetIst.day) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays == 1 || (difference.inHours < 48 && nowIst.day - targetIst.day == 1)) {
      return 'Yesterday, ${formatTimeOnly(targetIst)}';
    } else if (targetIst.year == nowIst.year) {
      return '${_monthName(targetIst.month)} ${targetIst.day}, ${formatTimeOnly(targetIst)}';
    } else {
      return '${_monthName(targetIst.month)} ${targetIst.day}, ${targetIst.year}';
    }
  }

  /// Formats DateTime into 12-hour time string in IST (e.g. "9:30 AM", "11:05 PM").
  static String formatTimeOnly(DateTime dateTime) {
    final ist = dateTime.toIST();
    final hour = ist.hour == 0 ? 12 : (ist.hour > 12 ? ist.hour - 12 : ist.hour);
    final minute = ist.minute.toString().padLeft(2, '0');
    final period = ist.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  /// Formats operating hours nicely (e.g. "09:00", "22:30" -> "9:00 AM - 10:30 PM").
  static String formatOperatingHours(String? openTime, String? closeTime) {
    if (openTime == null || openTime.isEmpty) return 'Open 24 Hours';
    final formattedOpen = _formatTimeString(openTime);
    if (closeTime == null || closeTime.isEmpty) return 'Opens at $formattedOpen';
    final formattedClose = _formatTimeString(closeTime);
    return '$formattedOpen - $formattedClose';
  }

  /// Evaluates whether a shop is open right now in IST, accounting for midnight crossovers
  /// (e.g. opens at 19:00 (7 PM) and closes at 02:00 (2 AM)).
  static bool isWithinOperatingHours(String? openTime, String? closeTime) {
    if (openTime == null || closeTime == null || openTime.isEmpty || closeTime.isEmpty) {
      return true; // Default open if unconfigured
    }

    try {
      final nowIst = DateTime.now().toIST();
      final nowMinutes = nowIst.hour * 60 + nowIst.minute;

      final openParts = openTime.split(':');
      final closeParts = closeTime.split(':');
      if (openParts.length < 2 || closeParts.length < 2) return true;

      final openMin = int.parse(openParts[0]) * 60 + int.parse(openParts[1]);
      final closeMin = int.parse(closeParts[0]) * 60 + int.parse(closeParts[1]);

      if (openMin <= closeMin) {
        // Normal daytime schedule (e.g. 09:00 to 22:00)
        return nowMinutes >= openMin && nowMinutes < closeMin;
      } else {
        // Midnight crossover schedule (e.g. 19:00 to 02:00)
        return nowMinutes >= openMin || nowMinutes < closeMin;
      }
    } catch (_) {
      return true;
    }
  }

  /// Returns remaining minutes if store is closing within 30 minutes in IST.
  static int? closingUrgencyMinutes(String? closeTime, {bool isOpenNow = true}) {
    if (!isOpenNow || closeTime == null || closeTime.isEmpty) return null;
    try {
      final nowIst = DateTime.now().toIST();
      final nowMinutes = nowIst.hour * 60 + nowIst.minute;

      final closeParts = closeTime.split(':');
      if (closeParts.length < 2) return null;

      final closeH = int.parse(closeParts[0]);
      final closeM = int.parse(closeParts[1]);
      var closeMin = closeH * 60 + closeM;

      if (closeMin < nowMinutes) {
        closeMin += 24 * 60; // Midnight rollover
      }

      final diff = closeMin - nowMinutes;
      if (diff > 0 && diff <= 30) return diff;
    } catch (_) {}
    return null;
  }

  static String _formatTimeString(String time24) {
    try {
      final parts = time24.split(':');
      if (parts.length < 2) return time24;
      final h = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      final hour = h == 0 ? 12 : (h > 12 ? h - 12 : h);
      final minStr = m.toString().padLeft(2, '0');
      final period = h >= 12 ? 'PM' : 'AM';
      return '$hour:$minStr $period';
    } catch (_) {
      return time24;
    }
  }

  static String _monthName(int month) {
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return (month >= 1 && month <= 12) ? months[month] : '';
  }
}
