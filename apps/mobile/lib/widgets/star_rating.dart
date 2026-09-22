import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class StarRating extends StatelessWidget {
  const StarRating({super.key, required this.value, this.onChanged, this.size = 34});

  final int value;
  final ValueChanged<int>? onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final starValue = index + 1;
        final filled = starValue <= value;
        return IconButton(
          onPressed: onChanged == null ? null : () => onChanged!(starValue),
          icon: Icon(
            filled ? Icons.star : Icons.star_border,
            color: AppColors.accent,
            size: size,
          ),
          tooltip: '$starValue од',
        );
      }),
    );
  }
}
