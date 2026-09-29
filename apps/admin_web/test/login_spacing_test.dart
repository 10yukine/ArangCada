import 'package:arangcada_admin/main.dart';
import 'package:arangcada_admin/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('login branding has balanced margins and fits short windows', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final size in [
      const Size(1920, 944),
      const Size(900, 600),
      const Size(390, 844),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: LoginScreen())),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (size.width == 1920) {
        final title = tester.getRect(
          find.text('Local dispatch.\nClearer oversight.'),
        );
        final logo = tester.getRect(find.byType(BrandTile));
        expect(title.left, greaterThanOrEqualTo(130));
        expect(logo.left, closeTo(title.left, 1));
      }
      expect(find.text('Welcome back'), findsOneWidget);
    }
  });

  testWidgets('each empty login field shows its own error under it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LoginScreen())),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Open console'));
    await tester.tap(find.text('Open console'));
    await tester.pumpAndSettle();

    final email = tester.getRect(find.widgetWithText(TextFormField, 'Email'));
    final password = tester.getRect(
      find.widgetWithText(TextFormField, 'Password'),
    );
    final emailError = tester.getRect(find.text('Enter your email'));
    final passwordError = tester.getRect(find.text('Enter your password'));
    // Inside each field's own box, below its input, not in a summary.
    expect(emailError.top, greaterThan(email.top));
    expect(emailError.bottom, lessThanOrEqualTo(password.top));
    expect(passwordError.top, greaterThan(password.top));
    expect(find.byIcon(Icons.error), findsNWidgets(2));
  });
}
