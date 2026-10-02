import 'package:arangcada_admin/admin_controller.dart';
import 'package:arangcada_admin/main.dart';
import 'package:arangcada_admin/models.dart';
import 'package:arangcada_admin/session.dart';
import 'package:arangcada_admin/supabase_admin_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecoveryRepository extends Fake implements SupabaseAdminRepository {
  _RecoveryRepository({required this.hasSession});

  @override
  final bool hasSession;
  bool restoreCalled = false;
  String? newPassword;

  @override
  Future<AdminSession> restoreSession() async {
    restoreCalled = true;
    throw StateError('A reset link must never restore a console session.');
  }

  @override
  Future<void> completePasswordReset(String password) async {
    newPassword = password;
  }
}

void main() {
  tearDown(() {
    auth.value = null;
    authRestoring.value = false;
    authError.value = null;
    passwordRecovery.value = false;
  });

  Future<_RecoveryRepository> openResetLink(
    WidgetTester tester, {
    required bool hasSession,
    bool redeemed = true,
  }) async {
    // What main() records after exchanging the link's code.
    passwordRecovery.value = redeemed;
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _RecoveryRepository(hasSession: hasSession);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [adminRepositoryProvider.overrideWithValue(repository)],
        child: const AdminApp(initialLocation: '/reset-password'),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  testWidgets('weak passwords are explained, and errors clear on typing', (
    tester,
  ) async {
    final repository = await openResetLink(tester, hasSession: true);
    await tester.enterText(find.byType(TextFormField).at(0), 'lowercase1');
    await tester.pump();
    // Length and number are met; mixed case and the repeat are not.
    expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
    await tester.tap(find.text('Update password'));
    await tester.pumpAndSettle();
    expect(
      find.text('Use both uppercase and lowercase letters'),
      findsOneWidget,
    );
    expect(find.text('Enter the new password again'), findsOneWidget);
    expect(repository.newPassword, isNull);

    // Typing in a field clears only that field's error.
    await tester.enterText(find.byType(TextFormField).at(0), 'Lowercase1');
    await tester.pump();
    expect(find.text('Use both uppercase and lowercase letters'), findsNothing);
    expect(find.text('Enter the new password again'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNWidgets(3));
  });

  testWidgets('a reset link asks for a new password instead of signing in', (
    tester,
  ) async {
    final repository = await openResetLink(tester, hasSession: true);

    expect(repository.restoreCalled, isFalse);
    expect(auth.value, isNull);
    expect(find.text('Choose a new password'), findsOneWidget);
    expect(find.text('Operations overview'), findsNothing);

    await tester.enterText(find.byType(TextFormField).at(0), 'Correct-horse1');
    await tester.enterText(find.byType(TextFormField).at(1), 'Different-one1');
    await tester.tap(find.text('Update password'));
    await tester.pumpAndSettle();
    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(repository.newPassword, isNull);

    await tester.enterText(find.byType(TextFormField).at(1), 'Correct-horse1');
    await tester.tap(find.text('Update password'));
    await tester.pumpAndSettle();
    expect(repository.newPassword, 'Correct-horse1');
    expect(find.text('Password updated'), findsOneWidget);

    await tester.tap(find.text('Go to sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
  });

  // The page sets a password without asking for the current one. A signed-in
  // administrator has a session too; that alone must not open the form.
  testWidgets('being signed in does not unlock the reset form', (tester) async {
    final repository = await openResetLink(
      tester,
      hasSession: true,
      redeemed: false,
    );

    expect(find.text('This reset link has expired'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(repository.newPassword, isNull);
  });

  testWidgets('an expired or reused reset link explains what to do', (
    tester,
  ) async {
    await openResetLink(tester, hasSession: false, redeemed: false);

    expect(find.text('This reset link has expired'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Back to sign in'), findsOneWidget);
  });
}
