import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../state/app_scope.dart';

/// Switches between the light and dark theme, like the toggle on the web
/// (apps/web ThemeToggle.tsx). The first tap picks the opposite of what is
/// showing now; the choice is remembered on this device.
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key, this.color});

  /// Icon colour, for use on a panel whose colour does not follow the theme.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, color: color),
      tooltip: dark ? Strings.themeSwitchToLight : Strings.themeSwitchToDark,
      onPressed: () => AppScope.read(context).setThemeMode(dark ? ThemeMode.light : ThemeMode.dark),
    );
  }
}
