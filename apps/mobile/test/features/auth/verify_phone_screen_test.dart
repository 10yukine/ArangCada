import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/data/repositories/auth_repository.dart';
import 'package:arangcada/domain/models/demo_user.dart';
import 'package:arangcada/features/auth/verify_phone_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    child: const MaterialApp(home: VerifyPhoneScreen()),
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

  testWidgets('paste pulls a 6-digit code out of a full SMS body', (
    tester,
  ) async {
    // What a real SMS looks like -- the code is embedded in prose, and the
    // user copies the whole message.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          return <String, dynamic>{
            'text': '482913 is your ArangCada verification code. '
                'It expires in 10 minutes.',
          };
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(harness());
    await tester.pump();

    await tester.tap(find.text('Paste code'));
    await tester.pump();
    await tester.pump();

    expect(auth.verifiedTokens, ['482913']);
  });

  testWidgets('offers a way out so a mistyped number cannot strand the account', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    expect(find.text('Sign out'), findsOneWidget);
    await tester.tap(find.text('Sign out'));
    await tester.pump();

    expect(state.currentUser, isNull);
  });
}
