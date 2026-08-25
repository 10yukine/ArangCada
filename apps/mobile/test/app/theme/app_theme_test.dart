import 'package:arangcada/app/theme/app_colors.dart';
import 'package:arangcada/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app-bar typography and divider match the approved prototype', () {
    final appBar = AppTheme.light.appBarTheme;

    expect(appBar.titleTextStyle?.fontSize, 17);
    expect(appBar.titleTextStyle?.fontWeight, FontWeight.w500);
    expect(
      appBar.shape,
      const Border(bottom: BorderSide(color: AppColors.dividerLight)),
    );
  });
}
