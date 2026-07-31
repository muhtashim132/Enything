import 'dart:core';

void main() {
  String openTime = '09:00';
  String closeTime = '05:00';
  
  // Test different times of day
  List<int> testMinutes = [178 /* 2:58 AM */, 300 /* 5:00 AM */, 540 /* 9:00 AM */, 896 /* 2:56 PM */, 1080 /* 6:00 PM */];
  
  final openParts = openTime.split(':');
  final closeParts = closeTime.split(':');
  
  final openH = int.parse(openParts[0]);
  final openM = int.parse(openParts[1]);
  final closeH = int.parse(closeParts[0]);
  final closeM = int.parse(closeParts[1]);
  
  final openMinutes = openH * 60 + openM;
  final closeMinutes = closeH * 60 + closeM;
  
  print("openMinutes: $openMinutes");
  print("closeMinutes: $closeMinutes");
  
  for (final nowMinutes in testMinutes) {
    bool isOpen = false;
    if (closeMinutes < openMinutes) {
      isOpen = (nowMinutes >= openMinutes || nowMinutes <= closeMinutes);
    } else {
      isOpen = (nowMinutes >= openMinutes && nowMinutes <= closeMinutes);
    }
    print("nowMinutes: $nowMinutes -> isOpen: $isOpen");
  }
}
