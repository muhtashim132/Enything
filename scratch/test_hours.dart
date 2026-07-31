void main() {
  final now = DateTime(2026, 8, 1, 15, 30); // 3:30 PM
  final openTime = "09:00";
  final closeTime = "04:30";

  final openParts = openTime.split(':');
  final closeParts = closeTime.split(':');
  
  final openH = int.parse(openParts[0]);
  final openM = int.parse(openParts[1]);
  final closeH = int.parse(closeParts[0]);
  final closeM = int.parse(closeParts[1]);

  final nowMinutes = now.hour * 60 + now.minute;
  final openMinutes = openH * 60 + openM;
  final closeMinutes = closeH * 60 + closeM;
  
  print("Now: $nowMinutes");
  print("Open: $openMinutes");
  print("Close: $closeMinutes");
  
  if (closeMinutes < openMinutes) {
    // Night shift
    print(nowMinutes >= openMinutes || nowMinutes <= closeMinutes);
  } else {
    // Normal shift
    print(nowMinutes >= openMinutes && nowMinutes <= closeMinutes);
  }
}
