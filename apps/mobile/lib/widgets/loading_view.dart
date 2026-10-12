import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.dark = false});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ColoredBox(
      color: dark ? p.solidInk : Colors.transparent,
      child: Center(
        child: CircularProgressIndicator(color: p.accent),
      ),
    );
  }
}
