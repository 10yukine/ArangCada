import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';

class ArangCadaMark extends StatelessWidget {
  const ArangCadaMark({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final markSize = compact ? 52.0 : 72.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: markSize,
          height: markSize,
          decoration: BoxDecoration(
            color: AppColors.coral,
            borderRadius: BorderRadius.circular(compact ? 14 : 20),
          ),
          alignment: Alignment.center,
          child: Text(
            'A',
            style: AppTypography.display.copyWith(
              color: Colors.white,
              fontSize: compact ? 28 : 38,
            ),
          ),
        ),
        SizedBox(height: compact ? AppSpacing.xs : AppSpacing.md),
        Text('ArangCada', style: AppTypography.display),
      ],
    );
  }
}
