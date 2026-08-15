import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppTypography {
  static const display = TextStyle(
    fontFamily: 'serif',
    fontSize: 28,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.28,
    color: AppColors.ink,
  );

  static const displaySm = TextStyle(
    fontFamily: 'serif',
    fontSize: 24,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.24,
    color: AppColors.ink,
  );

  static const h2 = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
  );

  static const body = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: AppColors.ink,
  );

  static const bodySm = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.ink,
  );

  static const label = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: AppColors.label,
  );

  static const caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textMuted,
  );

  static const badge = TextStyle(fontSize: 11);
  static const tab = TextStyle(fontSize: 11);

  static const bodyTag = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w700,
    color: Colors.white,
  );
}
