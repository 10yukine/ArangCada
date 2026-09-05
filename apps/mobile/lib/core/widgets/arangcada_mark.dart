import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';

class ArangCadaMark extends StatelessWidget {
  const ArangCadaMark({super.key, this.compact = false, this.badge = false});

  final bool compact;

  /// Presents the mark on a rounded-square backdrop with a small drop
  /// shadow. Off by default so About and Splash -- which already reference
  /// this widget -- render exactly as before; only the login screen opts in.
  ///
  /// Two deliberate choices here, both from user review:
  ///
  /// 1. The backdrop fill matches `AppColors.screenBackground`, the same
  ///    colour as the page behind it. A contrasting circle was tried first
  ///    and read as a mismatched container. The app icon already
  ///    establishes a rounded square as this brand's separating shape, so
  ///    the square is legible from its edge and shadow alone rather than
  ///    from a colour change.
  /// 2. Badge mode swaps in `arangcada_mark_square.svg`, the designer's
  ///    square-framed composition of the same artwork. The default
  ///    `arangcada_icon.svg` is framed tall: its content sits 128px below
  ///    the canvas centre with ~18% dead space above, which looks
  ///    noticeably low and left once placed inside a square. The square
  ///    framing centres to within 2px on both axes.
  final bool badge;

  /// 84, down from 116 (5 Sep 2026). The badge is the first thing on the login
  /// screen and at 116 it took a third of the width, pushing the form the user
  /// actually came for toward the fold. A brand mark should identify the app,
  /// not dominate the only screen where nobody has signed in yet.
  static const double _badgeSize = 84;

  /// ~22% of the badge, matching the app icon's own corner ratio
  /// (225/1024) so the two read as the same family. Scaled with the badge --
  /// keeping 25 on an 84px tile would have read as a different shape.
  static const double _badgeRadius = 18;

  /// The square asset carries its own internal padding, so it is inset
  /// less than the raw mark would need. Same ~90% ratio as before.
  static const double _badgeMarkSize = 76;

  @override
  Widget build(BuildContext context) {
    if (badge) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: _badgeSize,
            height: _badgeSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.screenBackground,
              borderRadius: BorderRadius.circular(_badgeRadius),
              // Deliberately soft: this is the only thing separating the
              // badge from the page now that the fill colour matches.
              boxShadow: const [
                BoxShadow(
                  color: AppColors.shadowMedium,
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: SizedBox.square(
              dimension: _badgeMarkSize,
              child: SvgPicture.asset(
                'assets/branding/arangcada_mark_square.svg',
                fit: BoxFit.contain,
                semanticsLabel: 'ArangCada tricycle mark',
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('ArangCada', style: AppTypography.displaySm),
        ],
      );
    }

    final markHeight = compact ? 48.0 : 82.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: markHeight,
          child: SvgPicture.asset(
            'assets/branding/arangcada_icon.svg',
            fit: BoxFit.contain,
            semanticsLabel: 'ArangCada tricycle mark',
          ),
        ),
        SizedBox(height: compact ? AppSpacing.xxs : AppSpacing.md),
        Text(
          'ArangCada',
          style: compact ? AppTypography.displaySm : AppTypography.display,
        ),
      ],
    );
  }
}
