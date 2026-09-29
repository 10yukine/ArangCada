import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/data/repositories/auth_repository.dart';
import 'package:arangcada/domain/models/demo_user.dart';
import 'package:arangcada/core/widgets/arang_ui.dart';
import 'package:arangcada/domain/models/fare_class_claim.dart';
import 'package:arangcada/features/profile/discount_eligibility_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Returns whatever [claim] (or [loadError]) is set to. Submission is not
/// exercised here -- that needs image_picker's platform channel, which is
/// covered by manual/device testing per the testing policy, not this suite.
class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository(this._state);

  final DemoState _state;
  FareClassClaim? claim;
  String? loadError;

  @override
  DemoUser? get currentUser => _state.currentUser;

  @override
  Future<FareClassClaim?> latestFareClassClaim() async {
    final error = loadError;
    if (error != null) throw DemoAuthException(error);
    return claim;
  }

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
  Future<String> uploadProfilePhoto({
    required List<int> bytes,
    required String fileExtension,
  }) => throw UnimplementedError();

  @override
  Future<DemoUser> updateAvatarPath(String path) => throw UnimplementedError();
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

  Widget harness() => ProviderScope(
    overrides: [
      demoStateProvider.overrideWithValue(state),
      authRepositoryProvider.overrideWithValue(auth),
    ],
    child: const MaterialApp(home: DiscountEligibilityScreen()),
  );

  testWidgets('no claim on file shows the standard-fare status and all '
      'three claimable classes', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    expect(find.text('Standard fare applied'), findsOneWidget);
    expect(find.text('Student'), findsOneWidget);
    expect(find.text('Senior Citizen'), findsOneWidget);
    expect(find.text('PWD'), findsOneWidget);
    expect(find.text('Pending'), findsNothing);
    expect(find.text('Verified'), findsNothing);
  });

  testWidgets('a pending claim replaces the claimable list with a review '
      'banner', (tester) async {
    auth.claim = FareClassClaim(
      id: 'c1',
      requestedClass: FareClassRequestedClass.student,
      status: FareClassClaimStatus.pendingReview,
      createdAt: DateTime(2026, 9, 5),
    );
    await tester.pumpWidget(harness());
    await tester.pump();

    expect(find.text('Student claim pending review'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(
      find.textContaining('being reviewed by an administrator'),
      findsOneWidget,
    );
    // No tappable claim options while one is already pending.
    expect(find.text('Claim a discounted fare'), findsNothing);
  });

  testWidgets('an approved claim shows Verified and hides claim options', (
    tester,
  ) async {
    auth.claim = FareClassClaim(
      id: 'c1',
      requestedClass: FareClassRequestedClass.seniorCitizen,
      status: FareClassClaimStatus.approved,
      createdAt: DateTime(2026, 9, 5),
    );
    await tester.pumpWidget(harness());
    await tester.pump();

    expect(find.text('Senior Citizen fare applied'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);
    expect(find.text('Claim a discounted fare'), findsNothing);
  });

  testWidgets('a rejected claim shows the reason and still offers a fresh '
      'submission', (tester) async {
    auth.claim = FareClassClaim(
      id: 'c1',
      requestedClass: FareClassRequestedClass.pwd,
      status: FareClassClaimStatus.rejected,
      createdAt: DateTime(2026, 9, 5),
      rejectionReason: 'Photo was too blurry to read.',
    );
    await tester.pumpWidget(harness());
    await tester.pump();

    expect(find.text('PWD claim rejected'), findsOneWidget);
    expect(find.text('Photo was too blurry to read.'), findsOneWidget);
    // Rejected does not lock the commuter out -- the options remain tappable.
    expect(find.text('Claim a discounted fare'), findsOneWidget);
    expect(find.text('PWD'), findsOneWidget);
  });

  testWidgets('a failed load surfaces the error instead of pretending '
      'nothing is claimed', (tester) async {
    auth.loadError = 'Network unavailable.';
    await tester.pumpWidget(harness());
    await tester.pump();

    expect(find.text('Network unavailable.'), findsOneWidget);
  });

  testWidgets('tapping a claimable class opens the photo-capture sheet with '
      'submission disabled until a photo is picked', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    await tester.tap(find.text('Student'));
    await tester.pumpAndSettle();

    expect(find.text('Student discount'), findsOneWidget);
    expect(find.text('Tap to take a photo'), findsOneWidget);

    final submitButton = tester.widget<ArangButton>(
      find.widgetWithText(ArangButton, 'Submit claim'),
    );
    expect(submitButton.onPressed, isNull);
  });
}
