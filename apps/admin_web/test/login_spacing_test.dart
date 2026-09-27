import 'package:arangcada_admin/main.dart';
import 'package:arangcada_admin/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('login branding has balanced margins and fits short windows', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final size in [const Size(1920, 944), const Size(900, 600), const Size(390, 844)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: LoginScreen())));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (size.width == 1920) {
        final title = tester.getRect(find.text('Local dispatch.\nClearer oversight.'));
        final logo = tester.getRect(find.byType(BrandTile));
        expect(title.left, greaterThanOrEqualTo(130));
        expect(logo.left, closeTo(title.left, 1));
      }
      expect(find.text('Welcome back'), findsOneWidget);
    }
  });
}
