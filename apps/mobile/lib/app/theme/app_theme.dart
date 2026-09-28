import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_dimensions.dart';
import 'app_typography.dart';

abstract final class AppTheme {
  static ThemeData get light {
    const colorScheme = ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      primaryContainer: AppColors.primaryFill,
      onPrimaryContainer: AppColors.primaryText,
      secondary: AppColors.sky,
      onSecondary: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      error: AppColors.danger,
      onError: Colors.white,
      outline: AppColors.borderStrong,
      outlineVariant: AppColors.border,
    );

    const textTheme = TextTheme(
      displaySmall: AppTypography.display,
      headlineSmall: AppTypography.displaySm,
      titleLarge: AppTypography.h2,
      titleMedium: AppTypography.h2,
      bodyLarge: AppTypography.body,
      bodyMedium: AppTypography.bodySm,
      labelLarge: AppTypography.label,
      bodySmall: AppTypography.caption,
      labelSmall: AppTypography.badge,
    );

    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.pill),
    );
    const buttonText = TextStyle(
      fontFamily: 'Fredoka',
      fontSize: 16,
      fontWeight: FontWeight.w500,
    );

    return ThemeData(
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
      fontFamily: 'Fredoka',
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.screenBackground,
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.screenBackground,
        foregroundColor: AppColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Fredoka',
          fontSize: 17,
          fontWeight: FontWeight.w500,
          color: AppColors.ink,
        ),
        shape: Border(bottom: BorderSide(color: AppColors.dividerLight)),
        // Flush leading: Flutter's auto back button is a bare IconButton, so
        // it inherits iconButtonTheme below. Tighten its box and the gap to
        // the title so the arrow sits close, the way every pushed screen in
        // the reference prototype does -- not a bordered circle with a wide
        // toolbar gutter around it.
        leadingWidth: 44,
        titleSpacing: 8,
      ),
      cardTheme: const CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadii.card)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.focused)
              ? AppColors.surface
              : AppColors.inputFill,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 13,
        ),
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 15),
        labelStyle: AppTypography.label,
        prefixIconColor: AppColors.textMuted,
        suffixIconColor: AppColors.textMuted,
        prefixIconConstraints: const BoxConstraints(
          minWidth: 46,
          minHeight: 46,
        ),
        suffixIconConstraints: const BoxConstraints(
          minWidth: 46,
          minHeight: 46,
        ),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadii.input)),
          borderSide: BorderSide(color: AppColors.borderStrong),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadii.input)),
          borderSide: BorderSide(color: AppColors.borderStrong),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadii.input)),
          borderSide: BorderSide(color: AppColors.primary),
        ),
        disabledBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadii.input)),
          borderSide: BorderSide(color: AppColors.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(
            Size(double.infinity, AppSizes.buttonHeight),
          ),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(14)),
          shape: WidgetStatePropertyAll(buttonShape),
          textStyle: const WidgetStatePropertyAll(buttonText),
          animationDuration: AppMotion.button,
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return AppColors.disabledFill;
            }
            if (states.contains(WidgetState.pressed)) {
              return AppColors.primaryPressed;
            }
            return AppColors.primary;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.disabled)
                ? AppColors.textDisabled
                : Colors.white;
          }),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(
            Size(double.infinity, AppSizes.buttonHeight),
          ),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(14)),
          shape: WidgetStatePropertyAll(buttonShape),
          textStyle: const WidgetStatePropertyAll(buttonText),
          animationDuration: AppMotion.button,
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.pressed)
                ? AppColors.pressedFill
                : AppColors.surface;
          }),
          foregroundColor: const WidgetStatePropertyAll(AppColors.textRow),
          side: const WidgetStatePropertyAll(
            BorderSide(color: AppColors.borderStrong),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? AppColors.textMuted
                : AppColors.primary,
          ),
          // Family must be restated: a theme textStyle replaces the inherited
          // one, and without it every TextButton fell back to the platform font.
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontFamily: 'Fredoka', fontWeight: FontWeight.w600),
          ),
          animationDuration: AppMotion.button,
        ),
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.primaryFill,
        disabledColor: AppColors.neutralFill,
        side: BorderSide(color: AppColors.borderStrong),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadii.chip)),
        ),
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        labelPadding: EdgeInsets.zero,
        labelStyle: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        secondaryLabelStyle: TextStyle(
          fontSize: 13,
          color: AppColors.primaryText,
          fontWeight: FontWeight.w600,
        ),
        checkmarkColor: AppColors.primaryText,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: AppColors.disabledFill,
        dragHandleSize: Size(36, 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadii.sheet),
          ),
        ),
      ),
      // Flat by default -- no fill, border, or forced circle. This is what
      // Flutter's auto-generated AppBar back button renders with (it is a
      // bare IconButton with no explicit style), so a bordered-circle
      // default here was showing up as a boxed back button on every pushed
      // screen. Buttons that do want a filled circle (map controls, the
      // profile edit pencil) already build their own via ArangIconButton
      // and are unaffected.
      iconButtonTheme: const IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(AppColors.ink),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        textColor: AppColors.textRow,
        iconColor: AppColors.textMuted,
        titleTextStyle: TextStyle(
          fontFamily: 'Fredoka',
          fontSize: 15,
          color: AppColors.textRow,
        ),
        subtitleTextStyle: AppTypography.caption,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.dividerLight,
        thickness: 1,
        space: 1,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: AppTypography.displaySm,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadii.card)),
          side: BorderSide(color: AppColors.border),
        ),
      ),
    );
  }
}
