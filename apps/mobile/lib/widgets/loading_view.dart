import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.dark = false});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: dark ? AppColors.ink : Colors.transparent,
      child: Center(
        child: CircularProgressIndicator(color: dark ? AppColors.accent : AppColors.ink),
      ),
    );
  }
}
