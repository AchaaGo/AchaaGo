import 'package:achaago_mobile/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG contrast ratio between two colours.
double contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  final lighter = first > second ? first : second;
  final darker = first > second ? second : first;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  final palettes = {'light': AppPalette.light, 'dark': AppPalette.dark};

  for (final entry in palettes.entries) {
    final p = entry.value;
    group('${entry.key} palette', () {
      test('body text is readable on every background it sits on', () {
        for (final background in [
          p.ground,
          p.surface,
          p.accentSoft,
          p.mintSoft
        ]) {
          expect(contrast(p.ink, background), greaterThanOrEqualTo(4.5));
        }
      });

      test('secondary text is readable', () {
        for (final background in [p.ground, p.surface, p.accentSoft]) {
          expect(contrast(p.muted, background), greaterThanOrEqualTo(4.5));
        }
      });

      test('error text is readable', () {
        for (final background in [p.ground, p.surface, p.errorBg]) {
          expect(contrast(p.error, background), greaterThanOrEqualTo(4.5));
        }
      });

      test(
          'white button text on the blue brand colour meets the large-text minimum',
          () {
        // Buttons use 18 px bold text, which WCAG treats as large text (3:1).
        expect(contrast(p.onBrand, p.accent), greaterThanOrEqualTo(3.0));
      });

      test('the navy login header and icon tiles are legible', () {
        expect(contrast(p.onBrand, p.inkDeep), greaterThanOrEqualTo(4.5));
        expect(contrast(p.mint, p.inkDeep), greaterThanOrEqualTo(4.5));
        expect(contrast(p.mint, p.inkDeep), greaterThanOrEqualTo(3.0));
      });
    });
  }

  test('dark text colours flip while the brand panels stay dark', () {
    expect(AppPalette.light.ink.computeLuminance(), lessThan(0.1));
    expect(AppPalette.dark.ink.computeLuminance(), greaterThan(0.8));
    expect(AppPalette.light.solidInk.computeLuminance(), lessThan(0.1));
    expect(AppPalette.dark.solidInk.computeLuminance(), lessThan(0.1));
    expect(AppPalette.light.accent, AppPalette.dark.accent);
  });

  test('lerp blends two palettes and ignores a foreign extension', () {
    final halfway = AppPalette.light.lerp(AppPalette.dark, 0.5);
    expect(halfway.ground,
        Color.lerp(AppPalette.light.ground, AppPalette.dark.ground, 0.5));
    expect(AppPalette.light.lerp(null, 0.5), same(AppPalette.light));
  });

  group('buildAppTheme', () {
    test('each brightness carries its own palette', () {
      expect(buildAppTheme(Brightness.light).brightness, Brightness.light);
      expect(buildAppTheme(Brightness.dark).brightness, Brightness.dark);
      expect(buildAppTheme(Brightness.light).extension<AppPalette>(),
          same(AppPalette.light));
      expect(buildAppTheme(Brightness.dark).extension<AppPalette>(),
          same(AppPalette.dark));
    });

    test('the page, text and buttons use the palette', () {
      for (final brightness in Brightness.values) {
        final p =
            brightness == Brightness.dark ? AppPalette.dark : AppPalette.light;
        final theme = buildAppTheme(brightness);
        expect(theme.scaffoldBackgroundColor, p.ground);
        expect(theme.colorScheme.primary, p.accent);
        expect(theme.colorScheme.onSurface, p.ink);
        expect(theme.textTheme.bodyMedium?.color, p.ink);
        final button = theme.elevatedButtonTheme.style!;
        expect(button.backgroundColor!.resolve({}), p.accent);
        expect(button.foregroundColor!.resolve({}), p.onBrand);
        expect(button.backgroundColor!.resolve({WidgetState.disabled}), p.line);
        expect(
            button.foregroundColor!.resolve({WidgetState.disabled}), p.muted);
      }
    });
  });

  testWidgets('context.palette follows the theme and falls back without one',
      (tester) async {
    late AppPalette seen;
    Future<void> show(ThemeData? theme) async {
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        themeAnimationDuration: Duration.zero,
        home: Builder(builder: (context) {
          seen = context.palette;
          return const SizedBox();
        }),
      ));
      await tester.pumpAndSettle();
    }

    // Compare colours, not instances: a theme change animates through lerp().
    void expectPalette(AppPalette expected) {
      expect(seen.ink, expected.ink);
      expect(seen.ground, expected.ground);
      expect(seen.surface, expected.surface);
    }

    await show(buildAppTheme(Brightness.dark));
    expectPalette(AppPalette.dark);
    await show(buildAppTheme(Brightness.light));
    expectPalette(AppPalette.light);
    // A theme that did not come from buildAppTheme (a plain widget test).
    await show(ThemeData.dark());
    expectPalette(AppPalette.dark);
    await show(null);
    expectPalette(AppPalette.light);
  });
}
