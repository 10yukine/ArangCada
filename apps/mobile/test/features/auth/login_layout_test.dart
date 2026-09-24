import 'package:arangcada/app/theme/app_theme.dart';
import 'package:arangcada/features/auth/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('login remains usable with large text and a tall keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: const MediaQuery(
            data: MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(1.5),
              viewInsets: EdgeInsets.only(bottom: 300),
            ),
            child: LoginScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final password = find.byType(TextField).last;
    await tester.ensureVisible(password);
    await tester.enterText(password, 'example-password');
    await tester.ensureVisible(find.byTooltip('Show password'));
    await tester.tap(find.byTooltip('Show password'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(password).obscureText, isFalse);
    await tester.ensureVisible(find.text('Log In'));
    await tester.pumpAndSettle();
    expect(find.text('Log In').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
