import 'dart:async';

void main() async {
  int count = 0;
  var timer = Timer.periodic(Duration(milliseconds: 100), (timer) {
    count++;
    print("Timer ran $count");
    if (count == 1) {
      throw Exception("Oops");
    }
    if (count == 3) {
      timer.cancel();
      print("Done");
    }
  });
  await Future.delayed(Duration(milliseconds: 500));
}
