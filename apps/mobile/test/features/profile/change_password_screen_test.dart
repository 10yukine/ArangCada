import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/data/repositories/auth_repository.dart';
import 'package:arangcada/domain/models/demo_user.dart';
import 'package:arangcada/features/profile/change_password_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records calls and never touches the network.
class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository(this._state);

  final DemoState _state;

  String? failReauthWith;
  final List<String> reauthCalls = <String>[];
  final List<String> updatePasswordCalls = <String>[];

  @override
  DemoUser? get currentUser => _state.currentUser;

  @override
  Future<void> reauthenticate(String currentPassword) async {
    reauthCalls.add(currentPassword);
    final failure = failReauthWith;
    if (failure != null) throw DemoAuthException(failure);
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    updatePasswordCalls.add(newPassword);
  }

  @override
  Future<DemoUser> updateEmail(String newEmail) => throw UnimplementedError();

  @override
  Future<DemoUser> signIn({required String email, required String password}) =>
      throw UnimplementedError();

  @override
  Future<RegistrationResult> signUp({
    required String displayName,
    required String mobileNumber,
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<void> sendPasswordReset(String email) => throw UnimplementedError();

  @override
  Future<void> signOut() async => _state.setCurrentUser(null);

  @override
  Future<DemoUser> updateDisplayName(String displayName) async =>
      throw UnimplementedError();

  @override
  Future<void> abandonUnverifiedRegistration() async {}

  @override
  Future<void> sendPhoneOtp(String e164Phone) => throw UnimplementedError();

  @override
  Future<DemoUser> verifyPhoneOtp({
    required String e164Phone,
    required String token,
  }) => throw UnimplementedError();
}

void main() {
  late DemoState state;
  late _FakeAuthRepository auth;

  setUp(() {
    state = DemoState();
    state.setCurrentUser(
      const DemoUser(
        email: 'juan@example.test',
        displayName: 'Juan Dela Cruz',
        role: DemoRole.commuter,
        mobileNumber: '+639171234567',
        phoneVerified: true,
      ),
    );
    auth = _FakeAuthRepository(state);
  });

  tearDown(() => state.dispose());

  // ChangePasswordScreen calls context.pop() on success, which needs an
  // actual pushed route to return to. initialLocation being the screen
  // itself would leave nothing on the stack to pop -- so this harness starts
  // on a plain screen and pushes the real one from a button, the way the
  // Account & Security screen really does.
  Widget harness() => ProviderScope(
    overrides: [
      demoStateProvider.overrideWithValue(state),
      authRepositoryProvider.overrideWithValue(auth),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/start',
        routes: [
          GoRoute(
            path: '/start',
            builder: (context, state) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => context.push('/profile/change-password'),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/profile/change-password',
            builder: (_, _) => const ChangePasswordScreen(),
          ),
        ],
      ),
    ),
  );

  Future<void> openScreen(WidgetTester tester) async {
    await tester.pumpWidget(harness());
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> fillAndSave(
    WidgetTester tester, {
    required String current,
    required String next,
    required String repeat,
  }) async {
    final fields = find.byType(EditableText);
    await tester.enterText(fields.at(0), current);
    await tester.enterText(fields.at(1), next);
    await tester.enterText(fields.at(2), repeat);
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
    'a wrong current password fails at re-auth, never reaching updatePassword',
    (tester) async {
      auth.failReauthWith = 'That password is incorrect.';

      await openScreen(tester);

      await fillAndSave(
        tester,
        current: 'wrongpass',
        next: 'newpassword1',
        repeat: 'newpassword1',
      );

      expect(find.text('That password is incorrect.'), findsOneWidget);
      expect(auth.reauthCalls, ['wrongpass']);
      expect(
        auth.updatePasswordCalls,
        isEmpty,
        reason: 'step 2 must never run once step 1 has failed',
      );
    },
  );

  testWidgets('mismatched repeat password is rejected before any network call', (
    tester,
  ) async {
    await openScreen(tester);

    await fillAndSave(
      tester,
      current: 'oldpassword',
      next: 'newpassword1',
      repeat: 'somethingelse',
    );

    expect(find.text('Passwords do not match.'), findsOneWidget);
    expect(auth.reauthCalls, isEmpty);
  });

  testWidgets(
    'a correct current password re-authenticates, updates the password, and '
    'pops',
    (tester) async {
      await openScreen(tester);

      await fillAndSave(
        tester,
        current: 'oldpassword',
        next: 'newpassword1',
        repeat: 'newpassword1',
      );

      expect(auth.reauthCalls, ['oldpassword']);
      expect(auth.updatePasswordCalls, ['newpassword1']);
      expect(find.text('Password updated.'), findsOneWidget);
      // Popped back to the screen that pushed it.
      expect(find.text('open'), findsOneWidget);
    },
  );
}
