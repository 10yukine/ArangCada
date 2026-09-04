import 'package:flutter/material.dart';

abstract final class AdminColors {
  // Shares the mobile client's Brand Blue identity (AppColors in
  // apps/mobile). The two apps are deliberately not code-coupled, so the
  // values are restated here rather than imported; keep them in step by hand
  // when the palette moves.
  static const background = Color(0xFFF6F9FD);
  static const surface = Color(0xFFE9F0F8);
  static const card = Colors.white;
  static const ink = Color(0xFF0F1A28);
  static const body = Color(0xFF2B3B4D);
  static const secondary = Color(0xFF48586B);
  static const muted = Color(0xFF5A6A7D);
  static const border = Color(0xFFDBE5F1);

  static const primary = Color(0xFF1262D0);
  static const primaryPress = Color(0xFF0E4EA6);
  static const primaryTint = Color(0xFFE4F0FE);

  /// Light brand accent. Decoration only -- 2.20:1 on white, so it never
  /// carries text on a light surface. On the navy [rail] it is legible and
  /// is the correct colour for the active nav indicator.
  static const sky = Color(0xFF53B8F6);

  /// Sidebar. Deep navy rather than near-black so the rail reads as the
  /// darkest step of the brand ramp instead of an unrelated neutral.
  static const rail = Color(0xFF0C2340);
  static const railText = Color(0xFFA8BED8);
  static const railTextMuted = Color(0xFF7E97B5);

  static const success = Color(0xFF16795C);
  static const successTint = Color(0xFFDFF3EB);
  static const warning = Color(0xFF8A6011);
  static const warningTint = Color(0xFFFCEFD6);
  static const danger = Color(0xFFB3403A);
  static const dangerTint = Color(0xFFFBE7E5);
}

ThemeData adminTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AdminColors.primary,
    brightness: Brightness.light,
    surface: AdminColors.card,
    primary: AdminColors.primary,
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
        borderSide: BorderSide(color: AdminColors.primary, width: 2),
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
