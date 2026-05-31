import 'package:flutter/material.dart';

class StarRatingDisplay extends StatelessWidget {
  final double rating;
  final double size;
  final Color color;

  const StarRatingDisplay({
    super.key,
    required this.rating,
    this.size = 14,
    this.color = Colors.amber,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        if (index < rating.floor()) {
          return Icon(Icons.star_rounded, color: color, size: size);
        } else if (index < rating && rating % 1 != 0) {
          return Icon(Icons.star_half_rounded, color: color, size: size);
        } else {
          return Icon(Icons.star_border_rounded, color: color, size: size);
        }
      }),
    );
  }
}
