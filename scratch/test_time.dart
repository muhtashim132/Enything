void main() {
  var now = DateTime.now();
  var utcNow = now.toUtc();
  var localNow = utcNow.toLocal();
  print(utcNow.difference(localNow).inSeconds);
}
