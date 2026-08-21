import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';

class ArangCadaMark extends StatelessWidget {
  const ArangCadaMark({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final markHeight = compact ? 58.0 : 82.0;
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
        SizedBox(height: compact ? AppSpacing.xs : AppSpacing.md),
        Text('ArangCada', style: AppTypography.display),
      ],
    );
  }
}
