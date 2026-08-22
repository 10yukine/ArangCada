import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';

/// Keeps every screen readable at desktop-browser widths without touching
/// each screen individually.
///
/// Below [AppBreakpoints.compact] (phones -- the primary Android target),
/// [child] renders untouched at full width: zero behavior change from
/// before this widget existed. At [AppBreakpoints.compact] and above (the
/// Flutter Web build opened in a wide browser window), [child] sits in a
/// centered column capped at [AppSizes.maxContentWidth] so cards, fields,
/// and map surfaces don't stretch edge to edge, per the adaptive-UI
/// guidance to never let large screens gobble up all horizontal space.
///
/// This wraps every route's screen (`router.dart`'s `_screenPage`), which is
/// the single point every route -- shell tab or pushed screen alike --
/// passes through, so the constraint applies consistently instead of being
/// re-implemented per screen.
class AdaptiveScreenFrame extends StatelessWidget {
  const AdaptiveScreenFrame({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (AppBreakpoints.isCompact(context)) return child;

    return ColoredBox(
      color: AppColors.neutralFill,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.maxContentWidth),
          child: Material(color: AppColors.screenBackground, child: child),
        ),
      ),
    );
  }
}
