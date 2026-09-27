import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/data/repositories/auth_repository.dart';
import 'package:arangcada/domain/models/fare_class_claim.dart';
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
  Future<DemoUser> signInWithPhone({
    required String phone,
    required String password,
  }) => throw UnimplementedError();

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
  Future<DemoUser> updateDisplayName(String displayName) async =>
      throw UnimplementedError();

  @override
  Future<void> abandonUnverifiedRegistration() async => abandonCalls++;

  @override
  Future<void> reauthenticate(String currentPassword) =>
      throw UnimplementedError();

  @override
  Future<void> updatePassword(String newPassword) =>
      throw UnimplementedError();

  @override
  Future<DemoUser> updateEmail(String newEmail) => throw UnimplementedError();

  @override
  Future<String> uploadFareClassIdPhoto({
    required List<int> bytes,
    required String fileExtension,
  }) => throw UnimplementedError();

  @override
  Future<FareClassClaim> submitFareClassClaim({
    required FareClassRequestedClass requestedClass,
    required String idPhotoPath,
  }) => throw UnimplementedError();

  @override
  Future<FareClassClaim?> latestFareClassClaim() => throw UnimplementedError();

  @override
  Future<String> uploadProfilePhoto({
    required List<int> bytes,
    required String fileExtension,
  }) => throw UnimplementedError();

  @override
  Future<DemoUser> updateAvatarPath(String path) => throw UnimplementedError();
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
          GoRoute(
            path: '/complete-mobile-profile',
            builder: (_, _) => const Scaffold(body: Text('change number')),
          ),
        ],
      ),
    ),
  );

  testWidgets('shows the number in full so a typo can be spotted', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    // Masking hid exactly the digits a user needs to check right after
    // typing them; it is their own number on their own screen.
    expect(find.textContaining('0917\u00A0123\u00A04567'), findsOneWidget);
    expect(find.text('Step 4 of 4'), findsOneWidget);
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
    expect(find.text('Cancel sign-up'), findsOneWidget);

    await tester.tap(find.text('Cancel sign-up'));
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

  testWidgets('wrong number opens phone setup and keeps the account', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    await tester.tap(find.text('Wrong number? Change number'));
    await tester.pump();
    await tester.pump();

    expect(find.text('change number'), findsOneWidget);
    expect(state.currentUser, isNotNull);
    expect(auth.abandonCalls, 0);
  });
}
