import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';

class ArangCadaMark extends StatelessWidget {
  const ArangCadaMark({super.key, this.compact = false, this.badge = false});

  final bool compact;

  /// Presents the mark on a soft rounded backdrop with a small drop shadow,
  /// matching the prototype's login screen. Off by default so About and
  /// Splash -- which already reference this widget -- render exactly as
  /// before; only the login screen opts in.
  final bool badge;

  @override
  Widget build(BuildContext context) {
    final markHeight = compact ? 48.0 : 82.0;
    final mark = SizedBox(
      height: markHeight,
      child: SvgPicture.asset(
        'assets/branding/arangcada_icon.svg',
        fit: BoxFit.contain,
        semanticsLabel: 'ArangCada tricycle mark',
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (badge)
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: const BoxDecoration(
              color: AppColors.clayFill,
              shape: BoxShape.circle,
              // Deliberately small: a launcher icon never bakes in a
              // shadow (the OS supplies its own), but this is in-app UI on
              // a flat background, where a soft lift reads as intentional
              // rather than decorative excess.
              boxShadow: [
                BoxShadow(
                  color: Color(0x1F1F1E1D),
                  blurRadius: 16,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: mark,
          )
        else
          mark,
        SizedBox(height: compact ? AppSpacing.xxs : AppSpacing.md),
        Text(
          'ArangCada',
          style: compact ? AppTypography.displaySm : AppTypography.display,
        ),
      ],
    );
  }
}
