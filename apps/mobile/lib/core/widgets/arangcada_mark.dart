import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';

class ArangCadaMark extends StatelessWidget {
  const ArangCadaMark({
    super.key,
    this.compact = false,
    this.badge = false,
    this.showName = true,
  });

  final bool showName;

  final bool compact;

  /// White rounded-square brand tile shared by login and startup.
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
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(_badgeRadius),
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
          if (showName) ...[
            const SizedBox(height: AppSpacing.md),
            Text('ArangCada', style: AppTypography.display),
          ],
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
