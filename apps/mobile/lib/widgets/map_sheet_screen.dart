import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shared layout for the screens that pair the decorative map area with a
/// scrollable content sheet below it (route selection, finding a driver,
/// tracking, public tracking) — the mobile equivalent of the web app's
/// map-plus-bottom-sheet screens, built as a plain scrollable column
/// instead of absolute positioning so it can never overflow on a small
/// device.
class MapSheetScreen extends StatelessWidget {
  const MapSheetScreen({
    super.key,
    required this.background,
    required this.children,
    this.backgroundHeight = 200,
  });

  final Widget background;
  final List<Widget> children;
  final double backgroundHeight;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: backgroundHeight, child: background),
        Expanded(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ),
        ),
      ],
    );
  }
}
