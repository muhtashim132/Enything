import 'package:flutter/material.dart';
void test(BuildContext context) {
  final controller = ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Hello')),
  );
  Future.delayed(const Duration(seconds: 3), () {
    controller.close();
  });
}
