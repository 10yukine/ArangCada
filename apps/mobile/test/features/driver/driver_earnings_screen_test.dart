import 'package:arangcada/app/theme/app_theme.dart';
import 'package:arangcada/features/driver/driver_earnings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('earnings follows the approved summary and recent-trips layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const DriverEarningsScreen()),
    );

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('₱478.00'), findsOneWidget);
    expect(find.text('9 trips · 6.5 hrs online'), findsOneWidget);
    expect(find.text('This week'), findsOneWidget);
    expect(find.text('Avg per trip'), findsOneWidget);
    expect(find.text('Recent trips'), findsOneWidget);
    expect(find.text('Trip history'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Settlement status'), 200);
    expect(find.text('Cash rides'), findsOneWidget);
    expect(find.text('Digital rides'), findsOneWidget);
    expect(find.text('Settlement status'), findsOneWidget);
    expect(find.textContaining('Sandbox only'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
