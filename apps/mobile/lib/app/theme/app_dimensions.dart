import 'package:flutter/widgets.dart';

abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
}

abstract final class AppRadii {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double badge = 10;
  static const double input = 12;
  static const double card = 16;
  static const double sheet = 20;
  static const double chip = 20;
  static const double pill = 999;
}

abstract final class AppSizes {
  static const double buttonHeight = 48;
  static const double iconButton = 42;
  static const double avatar = 42;
  static const double rowIcon = 38;
  static const double minTapTarget = 48;

  /// Widest a single screen's content column is allowed to grow. Past
  /// [AppBreakpoints.medium], screens sit inside [AdaptiveScreenFrame]
  /// rather than stretching cards, fields, and reading content across a
  /// desktop-width browser window.
  static const double maxContentWidth = 480;

  /// Width of the side navigation rail shown at [AppBreakpoints.medium] and
  /// above, replacing the bottom [FloatingTabBar] used on compact widths.
  static const double navigationRailWidth = 88;
}

abstract final class AppMotion {
  static const screen = Duration(milliseconds: 180);
  static const button = Duration(milliseconds: 150);
  static const sheet = Duration(milliseconds: 220);
}

/// Window-width breakpoints, per Material's adaptive layout guidance:
/// bottom navigation below [medium], a navigation rail at [medium] and
/// above. Decisions branch on available width via `MediaQuery.sizeOf` or
/// `LayoutBuilder`, never on device type or platform.
abstract final class AppBreakpoints {
  static const double compact = 600;
  static const double medium = 840;

  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < compact;

  static bool isExpanded(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= medium;
}
