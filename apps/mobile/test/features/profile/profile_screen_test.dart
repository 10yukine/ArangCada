import 'package:arangcada/core/widgets/arang_ui.dart';
import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/data/repositories/auth_repository.dart';
import 'package:arangcada/domain/models/demo_user.dart';
import 'package:arangcada/domain/models/fare_class_claim.dart';
import 'package:arangcada/features/profile/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records calls and never touches the network. Upload/update are not
/// exercised end to end here -- picking an actual photo needs
/// image_picker's platform channel, which is manual/device testing per
/// CLAUDE.md rule 11, same as discount_eligibility_screen_test.dart.
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

void main() {
  late DemoState state;
  late _FakeAuthRepository auth;

  setUp(() {
    state = DemoState();
    auth = _FakeAuthRepository(state);
  });

  tearDown(() => state.dispose());

  Widget harness() => ProviderScope(
    overrides: [
      demoStateProvider.overrideWithValue(state),
      authRepositoryProvider.overrideWithValue(auth),
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
}
