import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';

class ArangCadaMark extends StatelessWidget {
  const ArangCadaMark({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final markSize = compact ? 48.0 : 72.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: markSize,
          height: markSize,
          decoration: const BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.all(Radius.circular(AppRadii.xl)),
          ),
          child: Icon(
            Icons.electric_rickshaw_rounded,
            color: Colors.white,
            size: compact ? 28 : 40,
          ),
        ),
        SizedBox(height: compact ? AppSpacing.xs : AppSpacing.md),
        Text(
          'ArangCada',
          style: compact
              ? Theme.of(context).textTheme.titleLarge
              : Theme.of(
                  context,
                ).textTheme.displaySmall?.copyWith(color: AppColors.primary),
        ),
      ],
    );
  }
}
