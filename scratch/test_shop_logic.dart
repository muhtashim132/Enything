class Shop {
  final bool isActive;
  final String? openTime;
  final String? closeTime;

  Shop({required this.isActive, this.openTime, this.closeTime});

  bool get isOpenRightNow {
    if (!isActive) return false;
    if (openTime == null || closeTime == null) return isActive;

    try {
      final now = DateTime.now();
      final openParts = openTime!.split(':');
      final closeParts = closeTime!.split(':');
      if (openParts.length < 2 || closeParts.length < 2) return isActive;

      final openH = int.parse(openParts[0]);
      final openM = int.parse(openParts[1]);
      final closeH = int.parse(closeParts[0]);
      final closeM = int.parse(closeParts[1]);

      final nowMinutes = now.hour * 60 + now.minute;
      final openMinutes = openH * 60 + openM;
      final closeMinutes = closeH * 60 + closeM;

      if (closeMinutes < openMinutes) {
        // Night shift
        return (nowMinutes >= openMinutes || nowMinutes <= closeMinutes);
      } else {
        // Normal shift
        return (nowMinutes >= openMinutes && nowMinutes <= closeMinutes);
      }
    } catch (_) {
      return isActive;
    }
  }
}

void main() {
  print('Current time: ${DateTime.now()}');
  final s1 = Shop(isActive: true, openTime: '09:00', closeTime: '21:00');
  print('09:00 - 21:00: ${s1.isOpenRightNow}');
  final s2 = Shop(isActive: true, openTime: '00:00:00', closeTime: '23:59:59');
  print('00:00 - 23:59: ${s2.isOpenRightNow}');
}
