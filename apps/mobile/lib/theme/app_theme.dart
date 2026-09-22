import 'package:flutter/material.dart';

/// Colors mirror the design tokens documented in AGENTS.md so the mobile
/// app reads as the same product as apps/web, without pulling in the
/// branded Google Fonts (Unbounded / Golos Text) the web app uses — that
/// is a reasonable follow-up once brand font assets are bundled locally.
class AppColors {
  const AppColors._();

  static const ink = Color(0xFF14213D);
  static const inkDeep = Color(0xFF0E1830);
  static const ground = Color(0xFFF4F1EA);
  static const surface = Color(0xFFFFFFFF);
  static const accent = Color(0xFFF2A516);
  static const accentSoft = Color(0xFFFFF6E0);
  static const line = Color(0xFFE2DCCF);
  static const lineStrong = Color(0xFFCFC7B6);
  static const muted = Color(0xFF4A5263);
  static const muted2 = Color(0xFF3E4658);
  static const disabledBg = Color(0xFFD9D3C6);
  static const disabledFg = Color(0xFF5E6472);
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
      bodyColor: AppColors.muted2,
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
        backgroundColor: AppColors.ink,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.disabledBg,
        disabledForegroundColor: AppColors.disabledFg,
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
/// "Баталгаажуулах", etc.) — text on accent is always ink, matching the
/// design rule in AGENTS.md.
final ButtonStyle accentButtonStyle = ElevatedButton.styleFrom(
  backgroundColor: AppColors.accent,
  foregroundColor: AppColors.ink,
  disabledBackgroundColor: AppColors.disabledBg,
  disabledForegroundColor: AppColors.disabledFg,
  minimumSize: const Size.fromHeight(52),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
);
