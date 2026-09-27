import 'package:flutter/material.dart';

/// Colors mirror apps/web's tokens (apps/web/src/app/globals.css :root) so
/// the mobile app reads as the same product, without pulling in the
/// branded Google Fonts (Unbounded / Golos Text) the web app uses — that
/// is a reasonable follow-up once brand font assets are bundled locally.
/// This is the orange/forest-green palette web switched to; it supersedes
/// the ink-navy/gold tokens AGENTS.md itself documents.
class AppColors {
  const AppColors._();

  static const ink = Color(0xFF19231F);
  static const inkDeep = Color(0xFF183D30);
  static const ground = Color(0xFFF6F8F5);
  static const surface = Color(0xFFFFFFFF);
  static const accent = Color(0xFFE84616);
  static const accentHover = Color(0xFFCC3B10);
  static const accentSoft = Color(0xFFFFF7F2);
  static const line = Color(0xFFDFE4DF);
  static const lineStrong = Color(0xFFDFE4DF);
  static const muted = Color(0xFF626B65);
  static const mint = Color(0xFFB1D6C3);
  static const error = Color(0xFFB42318);
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.ink,
      primary: AppColors.ink,
      secondary: AppColors.accent,
      error: AppColors.error,
      surface: AppColors.surface,
    ),
    scaffoldBackgroundColor: AppColors.ground,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.muted,
      displayColor: AppColors.ink,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.ground,
      foregroundColor: AppColors.ink,
      elevation: 0,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.lineStrong),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.lineStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.ink, width: 2),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.line,
        disabledForegroundColor: AppColors.muted,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: AppColors.line, width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.ink),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
  );
}

/// The accent button used for the primary call-to-action (order button,
/// "Баталгаажуулах", etc.). Web's `.btn-accent`/`.btn-primary` both render
/// identically now (orange background, white text) — AGENTS.md's "text on
/// accent is always ink" rule was for the old gold accent and no longer
/// applies to this orange one; kept as a separate style from the theme
/// default only because call sites already distinguish accent/non-accent.
final ButtonStyle accentButtonStyle = ElevatedButton.styleFrom(
  backgroundColor: AppColors.accent,
  foregroundColor: Colors.white,
  disabledBackgroundColor: AppColors.line,
  disabledForegroundColor: AppColors.muted,
  minimumSize: const Size.fromHeight(52),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
);
