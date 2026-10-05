import 'package:arangcada/core/widgets/arang_ui.dart';
import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/data/repositories/auth_repository.dart';
import 'package:arangcada/data/repositories/email_confirmation_repository.dart';
import 'package:arangcada/domain/models/demo_user.dart';
import 'package:arangcada/domain/models/fare_class_claim.dart';
import 'package:arangcada/features/profile/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records calls and never touches the network. Upload/update are not
/// exercised end to end here -- picking an actual photo needs
/// image_picker's platform channel, which is manual/device testing per
/// the testing policy, same as discount_eligibility_screen_test.dart.
class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository(this._state);

  final DemoState _state;
  final List<String> uploadCalls = <String>[];
  final List<String> updateAvatarPathCalls = <String>[];

  @override
  DemoUser? get currentUser => _state.currentUser;

  @override
  Future<String> uploadProfilePhoto({
    required List<int> bytes,
    required String fileExtension,
  }) async {
    uploadCalls.add(fileExtension);
    return 'uid/photo.$fileExtension';
  }

  @override
  Future<DemoUser> updateAvatarPath(String path) async {
    updateAvatarPathCalls.add(path);
    final updated = _state.currentUser!.copyWithAvatarUrl(
      'https://example.test/signed/$path',
    );
    _state.setCurrentUser(updated);
    return updated;
  }

  @override
  Future<void> signOut() async => _state.setCurrentUser(null);

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
  Future<void> abandonUnverifiedRegistration() async {}

  @override
  Future<DemoUser> updateDisplayName(String displayName) =>
      throw UnimplementedError();

  @override
  Future<void> reauthenticate(String currentPassword) =>
      throw UnimplementedError();

  @override
  Future<void> updatePassword(String newPassword) => throw UnimplementedError();

  @override
  Future<DemoUser> updateEmail(String newEmail) => throw UnimplementedError();

  @override
  Future<void> sendPhoneOtp(String e164Phone) => throw UnimplementedError();

  @override
  Future<DemoUser> verifyPhoneOtp({
    required String e164Phone,
    required String token,
  }) => throw UnimplementedError();

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
}

/// Stands in for the server: counts sends, can refuse one, and can report the
/// email as confirmed the next time the app looks.
class _FakeEmailConfirmation implements EmailConfirmationRepository {
  _FakeEmailConfirmation(this._state);

  final DemoState _state;
  int sends = 0;
  int refreshes = 0;
  DemoAuthException? failure;
  bool confirmedOnServer = false;

  @override
  Future<void> send() async {
    sends++;
    if (failure != null) throw failure!;
  }

  @override
  Future<void> refresh() async {
    refreshes++;
    final user = _state.currentUser;
    if (confirmedOnServer && user != null) {
      _state.setCurrentUser(user.copyWithEmailConfirmed(true));
    }
  }
}

void main() {
  late DemoState state;
  late _FakeAuthRepository auth;

  setUp(() {
    state = DemoState();
    auth = _FakeAuthRepository(state);
  });

  tearDown(() => state.dispose());

  Widget harness({EmailConfirmationRepository? email}) => ProviderScope(
    overrides: [
      demoStateProvider.overrideWithValue(state),
      authRepositoryProvider.overrideWithValue(auth),
      emailConfirmationRepositoryProvider.overrideWithValue(email),
    ],
    child: const MaterialApp(home: ProfileScreen()),
  );

  testWidgets('shows initials when the account has no photo yet', (
    tester,
  ) async {
    state.setCurrentUser(
      const DemoUser(
        email: 'juan@example.test',
        displayName: 'Juan Dela Cruz',
        role: DemoRole.commuter,
      ),
    );
    await tester.pumpWidget(harness());
    await tester.pump();

    expect(find.text('JC'), findsOneWidget);
  });

  testWidgets('shows the uploaded photo once the account has one', (
    tester,
  ) async {
    state.setCurrentUser(
      const DemoUser(
        email: 'juan@example.test',
        displayName: 'Juan Dela Cruz',
        role: DemoRole.commuter,
        avatarUrl: 'https://example.test/signed/uid/photo.jpg',
      ),
    );
    await tester.pumpWidget(harness());
    await tester.pump();

    // ArangAvatar's own render-vs-fallback behaviour (including what
    // happens when the network request fails, as it always does in this
    // test environment) is covered by arang_avatar_test.dart -- this only
    // checks profile_screen.dart wires the signed-in user's avatarUrl
    // through, independent of that rendering timing.
    final avatar = tester.widget<ArangAvatar>(find.byType(ArangAvatar));
    expect(avatar.imageUrl, 'https://example.test/signed/uid/photo.jpg');
  });

  testWidgets(
    'tapping Change photo offers Take a photo / Choose from gallery, and '
    'dismissing without picking either calls nothing',
    (tester) async {
      state.setCurrentUser(
        const DemoUser(
          email: 'juan@example.test',
          displayName: 'Juan Dela Cruz',
          role: DemoRole.commuter,
        ),
      );
      await tester.pumpWidget(harness());
      await tester.pump();

      await tester.tap(find.byTooltip('Edit profile'));
      await tester.pumpAndSettle();

      expect(find.text('Change photo'), findsOneWidget);
      await tester.tap(find.text('Change photo'));
      await tester.pumpAndSettle();

      expect(find.text('Take a photo'), findsOneWidget);
      expect(find.text('Choose from gallery'), findsOneWidget);

      // Dismiss the source-choice sheet without selecting either option --
      // this must never reach image_picker's real platform channel.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(auth.uploadCalls, isEmpty);
      expect(auth.updateAvatarPathCalls, isEmpty);
    },
  );

  testWidgets(
    'driver profile displays Franchise & documents and not TODA membership',
    (tester) async {
      state.setCurrentUser(
        const DemoUser(
          email: 'driver@arangcada.demo',
          displayName: 'SJVTODA Test Driver',
          role: DemoRole.driver,
        ),
      );
      await tester.pumpWidget(harness());
      await tester.pump();

      expect(find.text('LGU & TODA records'), findsOneWidget);
      expect(find.text('Franchise & documents'), findsOneWidget);
      expect(find.text('TODA membership'), findsNothing);
    },
  );

  group('confirm your email', () {
    DemoUser rider({
      bool confirmed = false,
      DemoRole role = DemoRole.commuter,
    }) => DemoUser(
      email: 'juan@example.test',
      displayName: 'Juan Dela Cruz',
      role: role,
      emailConfirmed: confirmed,
    );

    testWidgets('a confirmed account is not asked', (tester) async {
      state.setCurrentUser(rider(confirmed: true));
      await tester.pumpWidget(harness(email: _FakeEmailConfirmation(state)));
      await tester.pump();
      expect(find.text('Confirm your email'), findsNothing);
    });

    testWidgets('demo mode, with no server, never asks', (tester) async {
      state.setCurrentUser(rider());
      await tester.pumpWidget(harness());
      await tester.pump();
      expect(find.text('Confirm your email'), findsNothing);
    });

    testWidgets('the prompt sits under the header and sends the link once', (
      tester,
    ) async {
      final email = _FakeEmailConfirmation(state);
      state.setCurrentUser(rider());
      await tester.pumpWidget(harness(email: email));
      await tester.pump();

      expect(find.text('Confirm your email'), findsOneWidget);
      expect(
        find.text(
          "We'll send a link to juan@example.test. Open it from your inbox "
          'to confirm.',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(find.text('Change email'), findsOneWidget);
      // Between the profile header and the first section.
      expect(
        tester.getTopLeft(find.text('Confirm your email')).dy,
        greaterThan(tester.getTopLeft(find.text('Juan Dela Cruz')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Confirm your email')).dy,
        lessThan(tester.getTopLeft(find.text('Account')).dy),
      );
      // Opening the screen looks once for a confirmation made elsewhere.
      expect(email.refreshes, 1);
      expect(email.sends, 0);

      await tester.tap(find.text('Send link'));
      await tester.pump();
      await tester.pump();
      expect(email.sends, 1);
      expect(
        find.text(
          'Link sent to juan@example.test. Open it from your inbox to confirm.',
          findRichText: true,
        ),
        findsOneWidget,
      );

      // The server sends one link a minute, so the button waits it out.
      expect(
        find.text('Wait 60s before requesting another link'),
        findsOneWidget,
      );
      await tester.tap(find.text('Send again'));
      await tester.pump();
      expect(email.sends, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.text('Wait 59s before requesting another link'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 59));
      expect(find.textContaining('before requesting'), findsNothing);
      await tester.tap(find.text('Send again'));
      await tester.pump();
      await tester.pump();
      expect(email.sends, 2);
    });

    testWidgets('being told to wait is shown calmly, in the server\'s words', (
      tester,
    ) async {
      final email = _FakeEmailConfirmation(state)
        ..failure = const EmailConfirmationWait(
          'Please wait a minute before asking for another link.',
        );
      state.setCurrentUser(rider());
      await tester.pumpWidget(harness(email: email));
      await tester.pump();
      await tester.tap(find.text('Send link'));
      await tester.pump();
      await tester.pump();
      expect(
        find.text('Please wait a minute before asking for another link.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.schedule), findsOneWidget);
      // Not reported as sent, and it looks again in case the reason was that
      // the email is already confirmed.
      expect(find.text('Send link'), findsOneWidget);
      expect(email.refreshes, 2);
    });

    testWidgets('a send that failed is shown as an error', (tester) async {
      final email = _FakeEmailConfirmation(state)
        ..failure = const DemoAuthException(
          'Could not send the confirmation email. Try again later.',
        );
      state.setCurrentUser(rider());
      await tester.pumpWidget(harness(email: email));
      await tester.pump();
      await tester.tap(find.text('Send link'));
      await tester.pump();
      await tester.pump();
      expect(
        find.text('Could not send the confirmation email. Try again later.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.schedule), findsNothing);
      expect(find.text('Send link'), findsOneWidget);
    });

    testWidgets('closing the prompt hides it for that address', (tester) async {
      state.setCurrentUser(rider());
      await tester.pumpWidget(harness(email: _FakeEmailConfirmation(state)));
      await tester.pump();
      await tester.tap(find.byTooltip('Hide for now'));
      await tester.pump();
      expect(find.text('Confirm your email'), findsNothing);

      // A different address has not been asked about yet.
      state.setCurrentUser(
        const DemoUser(
          email: 'other@example.test',
          displayName: 'Juan Dela Cruz',
          role: DemoRole.commuter,
          emailConfirmed: false,
        ),
      );
      await tester.pump();
      expect(find.text('Confirm your email'), findsOneWidget);
    });

    testWidgets('a driver is pointed to the office, not to an edit screen', (
      tester,
    ) async {
      state.setCurrentUser(rider(role: DemoRole.driver));
      await tester.pumpWidget(harness(email: _FakeEmailConfirmation(state)));
      await tester.pump();
      expect(find.text('Confirm your email'), findsOneWidget);
      expect(
        find.text('Not your email? Ask your LGU/TODA office to correct it.'),
        findsOneWidget,
      );
      expect(find.text('Change email'), findsNothing);
    });

    testWidgets('the prompt goes away once the link has been opened', (
      tester,
    ) async {
      final email = _FakeEmailConfirmation(state);
      state.setCurrentUser(rider());
      await tester.pumpWidget(harness(email: email));
      await tester.pump();
      expect(find.text('Confirm your email'), findsOneWidget);

      // The link is opened in a browser; the app comes back to the front.
      email.confirmedOnServer = true;
      for (final next in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(next);
      }
      await tester.pump();
      await tester.pump();
      expect(email.refreshes, 2);
      expect(find.text('Confirm your email'), findsNothing);
    });
  });
}
