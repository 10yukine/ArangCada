import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';

class AppRowIcon extends StatelessWidget {
  const AppRowIcon(this.icon, {super.key, this.danger = false});

  final Widget icon;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSizes.rowIcon,
      height: AppSizes.rowIcon,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: danger ? AppColors.dangerFill : AppColors.neutralFill,
        borderRadius: BorderRadius.circular(AppRadii.badge),
      ),
      child: IconTheme(
        data: IconThemeData(
          size: 20,
          color: danger ? AppColors.danger : AppColors.textMuted,
        ),
        child: icon,
      ),
    );
  }
}
