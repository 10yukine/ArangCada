import 'package:arangcada_admin/admin_controller.dart';
import 'package:arangcada_admin/main.dart';
import 'package:arangcada_admin/models.dart';
import 'package:arangcada_admin/supabase_admin_repository.dart';
import 'package:arangcada_admin/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _NotAnAdmin extends Fake implements SupabaseAdminRepository {
  @override
  bool get hasSession => false;

  @override
  Future<AdminSession> signIn({
    required String email,
    required String password,
  }) async => throw StateError('Administrator scope is not recognized.');
}

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

  testWidgets('after a failed sign-in the password is focused and selected', (
    tester,
  ) async {
    // Regression: in Firefox the field looked locked after a failed sign-in
    // (keyboard focus stuck on the browser's stale login form).
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [adminRepositoryProvider.overrideWithValue(_NotAnAdmin())],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'commuter@example.test',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'Test-pass1',
    );
    await tester.tap(find.text('Open console'));
    await tester.pumpAndSettle();

    expect(
      find.text('Unable to sign in. Check your credentials and try again.'),
      findsOneWidget,
    );
    final field = tester.widget<EditableText>(
      find.descendant(
        of: find.widgetWithText(TextFormField, 'Password'),
        matching: find.byType(EditableText),
      ),
    );
    expect(field.focusNode.hasFocus, isTrue);
    expect(field.controller.selection.extentOffset, 'Test-pass1'.length);
    expect(field.controller.selection.baseOffset, 0);
  });
}
