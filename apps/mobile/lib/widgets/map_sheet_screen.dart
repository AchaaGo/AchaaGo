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
    this.header,
  });

  final Widget background;
  final List<Widget> children;
  final double backgroundHeight;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    if (header != null) {
      return SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header!,
            SizedBox(height: backgroundHeight, child: background),
            DecoratedBox(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                      color: Color(0x2414213D),
                      blurRadius: 28,
                      offset: Offset(0, -8))
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children),
              ),
            ),
          ],
        ),
      );
    }
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
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children),
            ),
          ),
        ),
      ],
    );
  }
}
