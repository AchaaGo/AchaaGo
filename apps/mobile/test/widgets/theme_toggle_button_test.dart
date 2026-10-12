import 'package:achaago_mobile/l10n/strings.dart';
import 'package:achaago_mobile/state/app_scope.dart';
import 'package:achaago_mobile/state/app_state.dart';
import 'package:achaago_mobile/theme/app_theme.dart';
import 'package:achaago_mobile/widgets/theme_toggle_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  // The same wiring as AchaaGoApp: the app rebuilds when AppState changes.
  Widget app(AppState state) => AppScope(
        state: state,
        child: ListenableBuilder(
          listenable: state,
          builder: (context, _) => MaterialApp(
            theme: buildAppTheme(Brightness.light),
            darkTheme: buildAppTheme(Brightness.dark),
            themeMode: state.themeMode,
            themeAnimationDuration: Duration.zero,
            home: const Scaffold(body: Center(child: ThemeToggleButton())),
          ),
        ),
      );

  testWidgets('offers dark mode on a light screen and switches both ways', (tester) async {
    final state = AppState();
    addTearDown(state.dispose);
    await tester.pumpWidget(app(state));

    expect(find.byTooltip(Strings.themeSwitchToDark), findsOneWidget);
    expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget);

    await tester.tap(find.byType(ThemeToggleButton));
    await tester.pumpAndSettle();
    expect(state.themeMode, ThemeMode.dark);
    expect(find.byTooltip(Strings.themeSwitchToLight), findsOneWidget);
    expect(find.byIcon(Icons.light_mode_outlined), findsOneWidget);

    await tester.tap(find.byType(ThemeToggleButton));
    await tester.pumpAndSettle();
    expect(state.themeMode, ThemeMode.light);
    expect(find.byTooltip(Strings.themeSwitchToDark), findsOneWidget);
  });

  testWidgets('starts dark when the device is dark, and then switches to light', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final state = AppState();
    addTearDown(state.dispose);
    await tester.pumpWidget(app(state));

    expect(state.themeMode, ThemeMode.system);
    expect(find.byIcon(Icons.light_mode_outlined), findsOneWidget);

    await tester.tap(find.byType(ThemeToggleButton));
    await tester.pumpAndSettle();
    expect(state.themeMode, ThemeMode.light);
    expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget);
  });
}
