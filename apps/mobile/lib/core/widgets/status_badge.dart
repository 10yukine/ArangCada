import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';

enum StatusBadgeVariant { green, amber, red, clay }

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.label, {required this.variant, super.key});

  final String label;
  final StatusBadgeVariant variant;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (variant) {
      StatusBadgeVariant.green => (AppColors.greenFill, AppColors.greenDark),
      StatusBadgeVariant.amber => (AppColors.amberFill, AppColors.amberText),
      StatusBadgeVariant.red => (AppColors.dangerFill, AppColors.dangerDeep),
      StatusBadgeVariant.clay => (AppColors.clayFill, AppColors.clayText),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadii.badge),
      ),
      child: Text(
        label,
        style: AppTypography.badge.copyWith(color: foreground),
      ),
    );
  }
}
