extension DateTimeIST on DateTime {
  /// Converts the DateTime to Indian Standard Time (IST) strictly.
  /// If the DateTime is already in UTC, it adds 5 hours and 30 minutes.
  /// This ensures that all UI formatting shows IST regardless of the device's local timezone.
  DateTime toIST() {
    final utc = isUtc ? this : toUtc();
    return utc.add(const Duration(hours: 5, minutes: 30));
  }
}
