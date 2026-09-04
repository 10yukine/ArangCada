import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/data/repositories/auth_repository.dart';
import 'package:arangcada/domain/models/demo_user.dart';
import 'package:arangcada/features/auth/verify_phone_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records calls and never touches the network.
class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository(this._state);

  final DemoState _state;

  int sendCalls = 0;
  final List<String> verifiedTokens = <String>[];
  String? failVerifyWith;

  @override
  DemoUser? get currentUser => _state.currentUser;

  @override
  Future<void> sendPhoneOtp(String e164Phone) async {
    sendCalls++;
  }

  @override
  Future<DemoUser> verifyPhoneOtp({
    required String e164Phone,
    required String token,
  }) async {
    verifiedTokens.add(token);
    final failure = failVerifyWith;
    if (failure != null) throw DemoAuthException(failure);
    final verified = DemoUser(
      email: _state.currentUser!.email,
      displayName: _state.currentUser!.displayName,
      role: _state.currentUser!.role,
      mobileNumber: e164Phone,
      phoneVerified: true,
    );
    _state.setCurrentUser(verified);
    return verified;
  }

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

  int abandonCalls = 0;

  @override
  Future<void> abandonUnverifiedRegistration() async => abandonCalls++;
}

// NOTE ON pumpAndSettle: this screen runs a Timer.periodic for the resend
// cooldown, so there is always a pending timer and pumpAndSettle never
// settles -- it just times out. Every test below therefore pumps explicit
// durations instead. The timer is correct behaviour for the screen; it is the
// test helper that does not fit.
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
      ),
    );
    auth = _FakeAuthRepository(state);
  });

  tearDown(() => state.dispose());

  Widget harness() => ProviderScope(
    overrides: [
      demoStateProvider.overrideWithValue(state),
      authRepositoryProvider.overrideWithValue(auth),
    ],
    // A real router, not MaterialApp(home:). "Go Back" navigates, and a bare
    // home widget has no GoRouter in context for it to navigate with -- the
    // screen would throw in the test while working perfectly in the app.
    child: MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/verify-phone',
        routes: [
          GoRoute(
            path: '/verify-phone',
            builder: (_, _) => const VerifyPhoneScreen(),
          ),
          // Go Back's destination. A stand-in: the registration form itself is
          // not under test here, only that leaving lands on it.
          GoRoute(
            path: '/signup',
            builder: (_, _) => const Scaffold(body: Text('signup form')),
          ),
        ],
      ),
    ),
  );

  testWidgets('shows the number masked, not in full', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    // Enough for the user to recognise their own number; not enough for
    // someone glancing over their shoulder to read it.
    expect(find.textContaining('+63 917 *** 4567'), findsOneWidget);
    expect(
      find.textContaining('9171234567'),
      findsNothing,
      reason: 'the full number must not be printed on screen',
    );
  });

  testWidgets('submits automatically once six digits are entered', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    await tester.enterText(find.byType(EditableText).first, '123456');
    await tester.pump();
    await tester.pump();

    expect(auth.verifiedTokens, ['123456']);
  });

  testWidgets('a wrong code shows the reason and clears the field', (
    tester,
  ) async {
    auth.failVerifyWith = 'That code is incorrect or has expired.';

    await tester.pumpWidget(harness());
    await tester.pump();

    await tester.enterText(find.byType(EditableText).first, '000000');
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('incorrect'), findsOneWidget);

    // The field is cleared so the user retypes rather than trying to edit six
    // wrong digits one at a time on a phone keyboard.
    final field = tester.widget<EditableText>(find.byType(EditableText).first);
    expect(field.controller.text, isEmpty);
  });

  testWidgets('resend is blocked during the cooldown', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    // The code was already sent by sign-up, so the cooldown is running on
    // arrival. Offering an enabled Resend button the server would refuse is
    // worse than showing the wait.
    expect(find.textContaining('Resend code in'), findsOneWidget);

    // And the wait is shown as text, not as a disabled button. A countdown is
    // not a control: rendering it as one invites a tap that can never be
    // honoured. This assertion is the point of the test -- a later restyle
    // that turns it back into a greyed-out button would silently reinstate
    // exactly the affordance that was removed.
    expect(
      find.ancestor(
        of: find.textContaining('Resend code in'),
        matching: find.byType(TextButton),
      ),
      findsNothing,
    );
    expect(auth.sendCalls, 0);
  });

  testWidgets('resend works once the cooldown expires', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    // Tick the cooldown down one second at a time, the way it actually runs.
    for (var i = 0; i < 61; i++) {
      await tester.pump(const Duration(seconds: 1));
    }

    expect(find.text('Resend code'), findsOneWidget);
    await tester.tap(find.text('Resend code'));
    await tester.pump();
    await tester.pump();

    expect(auth.sendCalls, 1);
  });

  // Asserted as an absence. The button read the clipboard on the user's
  // behalf, which long-pressing the field already offers through the
  // platform's own paste affordance -- and Android logs a denial every time an
  // unfocused app touches the clipboard. Removing it is easy to undo by
  // accident, since "add a paste button to the OTP screen" reads like an
  // improvement.
  testWidgets('never reads the clipboard on behalf of the user', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    expect(find.text('Paste code'), findsNothing);
    expect(find.byIcon(Icons.content_paste_outlined), findsNothing);
  });

  testWidgets('offers a way back so a mistyped number cannot strand the account', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    // "Sign out" was the old label. It described the mechanism rather than the
    // intent, and pointed at a login screen the user has no account for yet.
    expect(find.text('Sign out'), findsNothing);
    expect(find.text('Go Back'), findsOneWidget);

    await tester.tap(find.text('Go Back'));
    await tester.pump();
    await tester.pump();

    // The session must end, or the router's verification gate redirects
    // straight back to this screen.
    expect(state.currentUser, isNull);
    expect(find.text('signup form'), findsOneWidget);

    // And the half-made account must be deleted, not merely signed out of.
    // Leaving it behind is what locked a user out of their own email address
    // after mistyping their number.
    expect(auth.abandonCalls, 1);
  });
}
