import 'package:flutter/material.dart';

abstract final class AdminColors {
  static const background = Color(0xFFFAF9F5);
  static const surface = Color(0xFFF0EEE5);
  static const card = Colors.white;
  static const ink = Color(0xFF1F1E1D);
  static const body = Color(0xFF3D3A34);
  static const secondary = Color(0xFF5C574D);
  static const muted = Color(0xFF6B675E);
  static const border = Color(0xFFE3DFD5);
  static const clay = Color(0xFFB4552F);
  static const clayPress = Color(0xFF9C4826);
  static const clayTint = Color(0xFFF6E3D7);
  static const rail = Color(0xFF262421);
  static const success = Color(0xFF3D7558);
  static const successTint = Color(0xFFE5F1EA);
  static const warning = Color(0xFF98691D);
  static const warningTint = Color(0xFFFFF0D0);
  static const danger = Color(0xFFA74343);
  static const dangerTint = Color(0xFFF9E2E2);
}

ThemeData adminTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AdminColors.clay,
    brightness: Brightness.light,
    surface: AdminColors.card,
    primary: AdminColors.clay,
    error: AdminColors.danger,
  );
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'Fredoka',
    colorScheme: scheme,
    scaffoldBackgroundColor: AdminColors.background,
    textTheme: const TextTheme(
      displaySmall: TextStyle(
        fontSize: 44,
        height: 1.02,
        fontWeight: FontWeight.w600,
        color: AdminColors.ink,
      ),
      headlineLarge: TextStyle(
        fontSize: 30,
        height: 1.1,
        fontWeight: FontWeight.w600,
        color: AdminColors.ink,
      ),
      headlineMedium: TextStyle(
        fontSize: 24,
        height: 1.15,
        fontWeight: FontWeight.w600,
        color: AdminColors.ink,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        height: 1.25,
        fontWeight: FontWeight.w600,
        color: AdminColors.ink,
      ),
      titleMedium: TextStyle(
        fontSize: 15,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: AdminColors.ink,
      ),
      bodyLarge: TextStyle(fontSize: 15, height: 1.45, color: AdminColors.body),
      bodyMedium: TextStyle(fontSize: 14, height: 1.4, color: AdminColors.body),
      bodySmall: TextStyle(
        fontSize: 12,
        height: 1.35,
        color: AdminColors.muted,
      ),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    dividerColor: AdminColors.border,
    cardTheme: const CardThemeData(
      color: AdminColors.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AdminColors.border),
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: AdminColors.card,
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: AdminColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: AdminColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: AdminColors.clay, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: const StadiumBorder(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        side: const BorderSide(color: AdminColors.border),
        shape: const StadiumBorder(),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: AdminColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
      ),
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 450),
    ),
  );
}
