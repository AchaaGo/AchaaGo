import 'package:flutter/material.dart';

/// The customer web tokens in apps/web/src/app/globals.css, light and dark.
/// Screens read them with `context.palette` so they follow the active theme
/// (the device setting, or the choice saved by the theme toggle).
///
/// Names match the CSS custom properties: `ink` is the text colour (it turns
/// light in the dark theme), while `solidInk` and `inkDeep` stay dark in both
/// themes for panels and icon tiles. `accent` is the orange brand colour and
/// `onBrand` the text on it.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.ink,
    required this.inkDeep,
    required this.solidInk,
    required this.ground,
    required this.surface,
    required this.accent,
    required this.accentHover,
    required this.accentSoft,
    required this.onBrand,
    required this.line,
    required this.lineStrong,
    required this.muted,
    required this.mint,
    required this.mintSoft,
    required this.error,
    required this.errorBg,
    required this.entryEnd,
    required this.termsLine,
  });

  final Color ink;
  final Color inkDeep;
  final Color solidInk;
  final Color ground;
  final Color surface;
  final Color accent;
  final Color accentHover;
  final Color accentSoft;
  final Color onBrand;
  final Color line;
  final Color lineStrong;
  final Color muted;
  final Color mint;
  final Color mintSoft;
  final Color error;
  final Color errorBg;

  /// End colour of the login screen's background gradient.
  final Color entryEnd;

  /// Border of the terms-consent box on the login screen.
  final Color termsLine;

  static const light = AppPalette(
    ink: Color(0xFF19231F),
    inkDeep: Color(0xFF183D30),
    solidInk: Color(0xFF19231F),
    ground: Color(0xFFF6F8F5),
    surface: Color(0xFFFFFFFF),
    accent: Color(0xFFE84616),
    accentHover: Color(0xFFCC3B10),
    accentSoft: Color(0xFFFFF7F2),
    onBrand: Color(0xFFFFFFFF),
    line: Color(0xFFDFE4DF),
    lineStrong: Color(0xFFDFE4DF),
    muted: Color(0xFF626B65),
    mint: Color(0xFFB1D6C3),
    mintSoft: Color(0xFFE4F1E8),
    error: Color(0xFFB42318),
    errorBg: Color(0xFFFFF4F1),
    entryEnd: Color(0xFFEEF5EF),
    termsLine: Color(0xFFF1D7C8),
  );

  static const dark = AppPalette(
    ink: Color(0xFFEDF3EF),
    inkDeep: Color(0xFF183D30),
    solidInk: Color(0xFF10271F),
    ground: Color(0xFF101814),
    surface: Color(0xFF1C2922),
    accent: Color(0xFFE84616),
    accentHover: Color(0xFFFF9B78),
    accentSoft: Color(0xFF35251E),
    onBrand: Color(0xFFFFFFFF),
    line: Color(0xFF394A40),
    lineStrong: Color(0xFF607568),
    muted: Color(0xFFB7C5BD),
    mint: Color(0xFFB1D6C3),
    mintSoft: Color(0xFF253F32),
    error: Color(0xFFFFB4A8),
    errorBg: Color(0xFF3B2220),
    entryEnd: Color(0xFF14241B),
    termsLine: Color(0xFF765341),
  );

  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      ink: mix(ink, other.ink),
      inkDeep: mix(inkDeep, other.inkDeep),
      solidInk: mix(solidInk, other.solidInk),
      ground: mix(ground, other.ground),
      surface: mix(surface, other.surface),
      accent: mix(accent, other.accent),
      accentHover: mix(accentHover, other.accentHover),
      accentSoft: mix(accentSoft, other.accentSoft),
      onBrand: mix(onBrand, other.onBrand),
      line: mix(line, other.line),
      lineStrong: mix(lineStrong, other.lineStrong),
      muted: mix(muted, other.muted),
      mint: mix(mint, other.mint),
      mintSoft: mix(mintSoft, other.mintSoft),
      error: mix(error, other.error),
      errorBg: mix(errorBg, other.errorBg),
      entryEnd: mix(entryEnd, other.entryEnd),
      termsLine: mix(termsLine, other.termsLine),
    );
  }
}

extension AppPaletteContext on BuildContext {
  /// The active palette. Falls back to the matching built-in one when the
  /// surrounding theme did not come from [buildAppTheme] (for example a
  /// widget test that wraps a screen in a plain `MaterialApp`).
  AppPalette get palette {
    final theme = Theme.of(this);
    return theme.extension<AppPalette>() ??
        (theme.brightness == Brightness.dark ? AppPalette.dark : AppPalette.light);
  }
}

/// Shadow under bottom sheets: `0 -8px 28px #183d3024` on the web.
const sheetShadowColor = Color(0x24183D30);

ThemeData buildAppTheme(Brightness brightness) {
  final p = brightness == Brightness.dark ? AppPalette.dark : AppPalette.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: p.accent,
    onPrimary: p.onBrand,
    secondary: p.inkDeep,
    onSecondary: p.onBrand,
    error: p.error,
    onError: brightness == Brightness.dark ? p.solidInk : p.onBrand,
    surface: p.surface,
    onSurface: p.ink,
    onSurfaceVariant: p.muted,
    outline: p.lineStrong,
    outlineVariant: p.line,
    inverseSurface: p.ink,
    onInverseSurface: p.ground,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.ground,
    extensions: <ThemeExtension<dynamic>>[p],
  );
  final shape14 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  const buttonText = TextStyle(fontWeight: FontWeight.w700, fontSize: 18);
  return base.copyWith(
    // Body text is the main ink colour, as on the web; secondary text sets
    // `palette.muted` explicitly.
    textTheme: base.textTheme.apply(
      bodyColor: p.ink,
      displayColor: p.ink,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: p.ground,
      foregroundColor: p.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: TextStyle(color: p.muted),
      labelStyle: TextStyle(color: p.muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: p.lineStrong),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: p.lineStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: p.ink, width: 2),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: p.accent,
        foregroundColor: p.onBrand,
        disabledBackgroundColor: p.line,
        disabledForegroundColor: p.muted,
        elevation: 0,
        shadowColor: Colors.transparent,
        minimumSize: const Size.fromHeight(52),
        shape: shape14,
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.ink,
        backgroundColor: p.surface,
        minimumSize: const Size.fromHeight(52),
        side: BorderSide(color: p.ink, width: 2),
        shape: shape14,
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: p.ink),
    ),
    cardTheme: CardThemeData(
      color: p.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: p.line),
      ),
    ),
    listTileTheme: ListTileThemeData(iconColor: p.ink, textColor: p.ink),
    dividerTheme: DividerThemeData(color: p.line, thickness: 1),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: p.accent,
      linearTrackColor: p.line,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: p.lineStrong,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: TextStyle(color: p.ink, fontSize: 20, fontWeight: FontWeight.w700),
      contentTextStyle: TextStyle(color: p.muted, fontSize: 15),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      textStyle: TextStyle(color: p.ink, fontSize: 15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}

/// Same look as the default elevated button; kept so the "accent" call sites
/// (`PrimaryButton(accent: true)`, the call button) stay explicit. Colours
/// come from the theme, so it follows light and dark.
final ButtonStyle accentButtonStyle = ElevatedButton.styleFrom(
  minimumSize: const Size.fromHeight(52),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
);
