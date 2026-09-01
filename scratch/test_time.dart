import 'dart:core';

void main() {
  String openTime = '09:00';
  String closeTime = '05:00';

  final now = DateTime.now();
  print("Current time: $now");
  final openParts = openTime.split(':');
  final closeParts = closeTime.split(':');

  final openH = int.parse(openParts[0]);
  final openM = int.parse(openParts[1]);
  final closeH = int.parse(closeParts[0]);
  final closeM = int.parse(closeParts[1]);

  final nowMinutes = now.hour * 60 + now.minute;
  final openMinutes = openH * 60 + openM;
  final closeMinutes = closeH * 60 + closeM;

  print("nowMinutes: $nowMinutes");
  print("openMinutes: $openMinutes");
  print("closeMinutes: $closeMinutes");

  if (closeMinutes < openMinutes) {
    print("Night shift");
    print(nowMinutes >= openMinutes || nowMinutes <= closeMinutes);
  } else {
    print("Normal shift");
    print(nowMinutes >= openMinutes && nowMinutes <= closeMinutes);
  }
}
