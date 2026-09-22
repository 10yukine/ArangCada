import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract final class AdminColors {
  // Shares the mobile client's Brand Blue identity (AppColors in
  // apps/mobile). The two apps are deliberately not code-coupled, so the
  // values are restated here rather than imported; keep them in step by hand
  // when the palette moves.
  static const background = Color(0xFFFBFCFE);
  static const surface = Color(0xFFE9F0F8);
  static const card = Colors.white;
  static const ink = Color(0xFF0F1A28);
  static const body = Color(0xFF2B3B4D);
  static const secondary = Color(0xFF48586B);
  static const muted = Color(0xFF5A6A7D);
  static const border = Color(0xFFDBE5F1);

  static const primary = Color(0xFF1457C5);
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


final adminThemeMode = ValueNotifier<ThemeMode>(ThemeMode.system);

/// Maps existing semantic tokens to the active theme at the point of use.
extension AdminColorContext on BuildContext {
  Color adminColor(Color light) {
    if (Theme.of(this).brightness == Brightness.light) return light;
    return switch (light) {
      AdminColors.background => const Color(0xFF0D1725),
      AdminColors.card => const Color(0xFF152235),
      AdminColors.surface => const Color(0xFF203047),
      AdminColors.ink => const Color(0xFFEDF3FC),
      AdminColors.body => const Color(0xFFD4DFEE),
      AdminColors.secondary || AdminColors.muted => const Color(0xFFADBDD2),
      AdminColors.border => const Color(0xFF304159),
      AdminColors.primary || AdminColors.primaryPress => const Color(0xFF8AB9FF),
      AdminColors.primaryTint => const Color(0xFF203655),
      AdminColors.success => const Color(0xFF83D9B6),
      AdminColors.successTint => const Color(0xFF163D32),
      AdminColors.warning => const Color(0xFFF6D68D),
      AdminColors.warningTint => const Color(0xFF3C3017),
      AdminColors.danger => const Color(0xFFFFABA6),
      AdminColors.dangerTint => const Color(0xFF492623),
      _ => light,
    };
  }
}

ThemeData adminTheme({Brightness brightness = Brightness.light}) {
  final dark = brightness == Brightness.dark;
  final background = dark ? const Color(0xFF0D1725) : const Color(0xFFFBFCFE);
  final surface = dark ? const Color(0xFF152235) : Colors.white;
  final ink = dark ? const Color(0xFFEDF3FC) : AdminColors.ink;
  final muted = dark ? const Color(0xFFADBDD2) : AdminColors.muted;
  final border = dark ? const Color(0xFF304159) : AdminColors.border;
  final primary = dark ? const Color(0xFF8AB9FF) : AdminColors.primary;
  final scheme = ColorScheme.fromSeed(
    seedColor: AdminColors.primary, brightness: brightness,
    surface: surface, primary: primary,
    onPrimary: dark ? const Color(0xFF102B50) : Colors.white,
    error: dark ? const Color(0xFFFFABA6) : AdminColors.danger,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
  final outline = OutlineInputBorder(
    borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    fontFamily: 'Roboto',
    textTheme: TextTheme(
      displaySmall: TextStyle(fontSize: 40, height: 1.1, fontWeight: FontWeight.w600, letterSpacing: -1.5, color: ink),
      headlineLarge: TextStyle(fontSize: 30, height: 1.2, fontWeight: FontWeight.w600, letterSpacing: -.8, color: ink),
      headlineMedium: TextStyle(fontSize: 24, height: 1.25, fontWeight: FontWeight.w600, letterSpacing: -.5, color: ink),
      titleLarge: TextStyle(fontSize: 18, height: 1.35, fontWeight: FontWeight.w600, color: ink),
      titleMedium: TextStyle(fontSize: 15, height: 1.4, fontWeight: FontWeight.w600, color: ink),
      bodyLarge: TextStyle(fontSize: 16, height: 1.5, color: ink),
      bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: ink),
      bodySmall: TextStyle(fontSize: 12, height: 1.45, color: muted),
      labelLarge: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    dividerColor: border,
    dividerTheme: DividerThemeData(color: border, thickness: 1),
    cardTheme: CardThemeData(color: surface, elevation: 0, margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: outline, enabledBorder: outline,
      focusedBorder: outline.copyWith(borderSide: BorderSide(color: primary, width: 2)),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
      minimumSize: const Size(48,48), padding: const EdgeInsets.symmetric(horizontal: 20), shape: shape)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
      minimumSize: const Size(48,48), padding: const EdgeInsets.symmetric(horizontal: 20),
      side: BorderSide(color: border), shape: shape)),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(
      minimumSize: const Size(48,48), shape: shape)),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(minimumSize: const Size(48,48))),
    segmentedButtonTheme: SegmentedButtonThemeData(style: ButtonStyle(shape: WidgetStatePropertyAll(shape))),
    chipTheme: ChipThemeData(shape: shape, side: BorderSide(color: border)),
    dialogTheme: DialogThemeData(backgroundColor: surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
    dataTableTheme: DataTableThemeData(
      headingRowColor: WidgetStatePropertyAll(dark ? const Color(0xFF1B2C43) : const Color(0xFFF1F5FA)),
      headingTextStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: muted),
      dataTextStyle: TextStyle(fontSize: 14, color: ink),
      dividerThickness: .5, horizontalMargin: 16, columnSpacing: 24,
      dataRowMinHeight: 52, dataRowMaxHeight: 80,
    ),
    tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 450)),
  );
}

class AdminAppearanceButton extends StatelessWidget {
  const AdminAppearanceButton({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
    valueListenable: adminThemeMode,
    builder: (context, mode, _) => PopupMenuButton<ThemeMode>(
      tooltip: 'Appearance',
      icon: Icon(switch(mode) {
        ThemeMode.system => Icons.brightness_auto_outlined,
        ThemeMode.light => Icons.light_mode_outlined,
        ThemeMode.dark => Icons.dark_mode_outlined,
      }),
      onSelected: (value) async {
        adminThemeMode.value = value;
        final preferences = await SharedPreferences.getInstance();
        await preferences.setString('admin-appearance', value.name);
      },
      itemBuilder: (_) => [
        for (final value in ThemeMode.values)
          CheckedPopupMenuItem(value: value, checked: value == mode,
            child: Text(switch(value) {ThemeMode.system => 'System', ThemeMode.light => 'Light', ThemeMode.dark => 'Dark'})),
      ],
    ),
  );
}
