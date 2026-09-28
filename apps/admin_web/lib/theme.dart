import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract final class AdminColors {
  // Shares the mobile client's Brand Blue identity (AppColors in
  // apps/mobile) and the public site's tokens (apps/web/public/site.css).
  // The apps are deliberately not code-coupled, so the values are restated
  // here rather than imported; keep them in step by hand when the palette
  // moves.
  static const background = Color(0xFFE6EBF2);
  static const surface = Color(0xFFDCE3EC);
  // Soft off-white rather than pure white, so cards never glare.
  static const card = Color(0xFFFAFBFD);
  static const ink = Color(0xFF0F1A28);
  static const body = Color(0xFF2B3B4D);
  static const secondary = Color(0xFF3E4F63);
  static const muted = Color(0xFF4B5B6E);
  static const border = Color(0xFFCAD5E3);

  static const primary = Color(0xFF1262D0);
  static const primaryPress = Color(0xFF0E4EA6);
  static const primaryTint = Color(0xFFE6F1FD);

  /// Calamba City blues. Royal and azure frame brand moments (sidebar,
  /// login, headline metrics) -- never body text on a light surface.
  static const royal = Color(0xFF0B4DB8);
  static const azure = Color(0xFF1FA2E8);

  /// Light brand accent. Decoration only -- 2.20:1 on white, so it never
  /// carries text on a light surface.
  static const sky = Color(0xFF53B8F6);

  /// Sidebar base: the deep end of the royal ramp. White text on it is
  /// above 8:1, so it also works as a solid "brand ink" chip colour.
  static const rail = Color(0xFF08357F);
  static const railText = Color(0xFFDCEBFC);
  static const railTextMuted = Color(0xFFA9CBF2);

  static const success = Color(0xFF16795C);
  static const successTint = Color(0xFFDFF3EB);
  static const warning = Color(0xFF8A6011);
  static const warningTint = Color(0xFFFCEFD6);
  static const danger = Color(0xFFB3403A);
  static const dangerTint = Color(0xFFFBE7E5);
}

/// Royal -> action blue -> azure, the same sweep as arangcada.app.
const adminBrandGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF083C97), Color(0xFF0E52B4), Color(0xFF1683C9)],
  stops: [0, .5, 1],
);

LinearGradient adminRailGradient(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF0B2C66), Color(0xFF081F4A)],
      )
    : const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF0A43A3), Color(0xFF08357F)],
      );

final adminThemeMode = ValueNotifier<ThemeMode>(ThemeMode.system);

/// Maps existing semantic tokens to the active theme at the point of use.
extension AdminColorContext on BuildContext {
  Color adminColor(Color light) {
    if (Theme.of(this).brightness == Brightness.light) return light;
    return switch (light) {
      AdminColors.background => const Color(0xFF0A1321),
      AdminColors.card => const Color(0xFF111D2F),
      AdminColors.surface => const Color(0xFF1A2A40),
      AdminColors.ink => const Color(0xFFEAF2FC),
      AdminColors.body => const Color(0xFFC9D6E6),
      AdminColors.secondary || AdminColors.muted => const Color(0xFFA3B5CB),
      AdminColors.border => const Color(0xFF24354C),
      AdminColors.primary ||
      AdminColors.primaryPress => const Color(0xFF7DB4FF),
      AdminColors.primaryTint => const Color(0xFF15263D),
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
  final background = dark ? const Color(0xFF0A1321) : AdminColors.background;
  final surface = dark ? const Color(0xFF111D2F) : AdminColors.card;
  final fill = dark ? const Color(0xFF15233A) : const Color(0xFFEEF2F7);
  final ink = dark ? const Color(0xFFEAF2FC) : AdminColors.ink;
  final muted = dark ? const Color(0xFFA3B5CB) : AdminColors.muted;
  final border = dark ? const Color(0xFF24354C) : AdminColors.border;
  final primary = dark ? const Color(0xFF7DB4FF) : AdminColors.primary;
  final scheme = ColorScheme.fromSeed(
    seedColor: AdminColors.primary,
    brightness: brightness,
    surface: surface,
    primary: primary,
    onPrimary: dark ? const Color(0xFF0A1A33) : Colors.white,
    error: dark ? const Color(0xFFFFABA6) : AdminColors.danger,
  );
  // Mobile radii (AppRadii): 12 for controls, 14 for cards.
  final control = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(12),
  );
  final field = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: border),
  );
  return ThemeData(
    useMaterial3: true,
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        for (final platform in TargetPlatform.values)
          platform: const AdminPageTransitionsBuilder(),
      },
    ),
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    fontFamily: 'Fredoka',
    textTheme: TextTheme(
      // Large sizes track tighter, small sizes stay near zero.
      displaySmall: TextStyle(
        fontSize: 40,
        height: 1.05,
        fontWeight: FontWeight.w600,
        letterSpacing: -1.4,
        color: ink,
      ),
      headlineLarge: TextStyle(
        fontSize: 32,
        height: 1.12,
        fontWeight: FontWeight.w600,
        letterSpacing: -1,
        color: ink,
      ),
      headlineMedium: TextStyle(
        fontSize: 24,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: -.5,
        color: ink,
      ),
      headlineSmall: TextStyle(
        fontSize: 21,
        height: 1.25,
        fontWeight: FontWeight.w600,
        letterSpacing: -.3,
        color: ink,
      ),
      titleLarge: TextStyle(
        fontSize: 19,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: -.2,
        color: ink,
      ),
      titleMedium: TextStyle(
        fontSize: 15,
        height: 1.4,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        height: 1.4,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      bodyLarge: TextStyle(fontSize: 16, height: 1.5, color: ink),
      bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: ink),
      bodySmall: TextStyle(fontSize: 12.5, height: 1.45, color: muted),
      labelLarge: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: .9,
        color: muted,
      ),
    ),
    dividerColor: border,
    dividerTheme: DividerThemeData(color: border, thickness: 1),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: fill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      border: field,
      enabledBorder: field,
      focusedBorder: field.copyWith(
        borderSide: BorderSide(color: primary, width: 2),
      ),
      prefixIconColor: muted,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        shape: control,
        textStyle: const TextStyle(
          fontFamily: 'Fredoka',
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        side: BorderSide(color: border),
        shape: control,
        textStyle: const TextStyle(
          fontFamily: 'Fredoka',
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: control,
        textStyle: const TextStyle(
          fontFamily: 'Fredoka',
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(shape: WidgetStatePropertyAll(control)),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: BorderSide(color: border),
    ),
    dialogTheme: DialogThemeData(
      // Narrow inset: on a phone the default 40 px margins squeezed dialog
      // content (driver documents wrapped a letter per line). Desktop
      // dialogs are sized by their content and never reach the margin.
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      backgroundColor: surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: border),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: primary),
    dataTableTheme: DataTableThemeData(
      headingRowColor: WidgetStatePropertyAll(
        dark ? const Color(0xFF15233A) : const Color(0xFFEBF0F6),
      ),
      headingTextStyle: TextStyle(
        fontFamily: 'Fredoka',
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: .4,
        color: muted,
      ),
      dataTextStyle: TextStyle(fontFamily: 'Fredoka', fontSize: 14, color: ink),
      dividerThickness: .5,
      horizontalMargin: 18,
      columnSpacing: 24,
      dataRowMinHeight: 56,
      dataRowMaxHeight: 80,
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 450),
    ),
  );
}

class AdminAppearanceButton extends StatelessWidget {
  const AdminAppearanceButton({super.key, this.inRail = false});

  /// A labelled row in white for the navigation drawer (phones), instead of
  /// the bare toolbar icon.
  final bool inRail;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
    valueListenable: adminThemeMode,
    builder: (context, mode, _) => PopupMenuButton<ThemeMode>(
      tooltip: 'Appearance',
      icon: inRail ? null : Icon(_icon(mode)),
      child: inRail
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(_icon(mode), size: 22, color: AdminColors.railText),
                  const SizedBox(width: 14),
                  Flexible(
                    child: Text(
                      'Appearance · ${switch (mode) {
                        ThemeMode.system => 'System',
                        ThemeMode.light => 'Light',
                        ThemeMode.dark => 'Dark',
                      }}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AdminColors.railText,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : null,
      onSelected: (value) async {
        adminThemeMode.value = value;
        final preferences = await SharedPreferences.getInstance();
        await preferences.setString('admin-appearance', value.name);
      },
      itemBuilder: (_) => [
        for (final value in ThemeMode.values)
          PopupMenuItem(
            value: value,
            child: Semantics(
              selected: value == mode,
              child: Row(
                children: [
                  Icon(_icon(value)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(switch (value) {
                      ThemeMode.system => 'System',
                      ThemeMode.light => 'Light',
                      ThemeMode.dark => 'Dark',
                    }),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 24,
                    child: value == mode
                        ? const Icon(Icons.check, size: 20)
                        : null,
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );

  static IconData _icon(ThemeMode mode) => switch (mode) {
    ThemeMode.system => Icons.brightness_auto_outlined,
    ThemeMode.light => Icons.light_mode_outlined,
    ThemeMode.dark => Icons.dark_mode_outlined,
  };
}

/// Small vertical movement keeps navigation free of zoom effects.
class AdminPageTransitionsBuilder extends PageTransitionsBuilder {
  const AdminPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, .035),
        end: Offset.zero,
      ).animate(animation.drive(CurveTween(curve: Curves.easeOutCubic))),
      child: Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: child,
      ),
    );
  }
}
