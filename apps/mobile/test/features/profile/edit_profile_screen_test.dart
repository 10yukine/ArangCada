import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/data/repositories/auth_repository.dart';
import 'package:arangcada/domain/models/fare_class_claim.dart';
import 'package:arangcada/domain/models/demo_user.dart';
import 'package:arangcada/features/profile/edit_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records calls and never touches the network.
class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository(this._state);

  final DemoState _state;

  String? failReauthWith;
  String? failSendOtpWith;
  final List<String> reauthCalls = <String>[];
  final List<String> updateEmailCalls = <String>[];
  final List<String> sendOtpCalls = <String>[];
  String? failVerifyWith;
  final List<String> verifiedTokens = <String>[];

  @override
  DemoUser? get currentUser => _state.currentUser;

  @override
  Future<void> reauthenticate(String currentPassword) async {
    reauthCalls.add(currentPassword);
    final failure = failReauthWith;
    if (failure != null) throw DemoAuthException(failure);
  }

  @override
  Future<DemoUser> updateEmail(String newEmail) async {
    updateEmailCalls.add(newEmail);
    final updated = DemoUser(
      email: newEmail,
      displayName: _state.currentUser!.displayName,
      role: _state.currentUser!.role,
      mobileNumber: _state.currentUser!.mobileNumber,
      phoneVerified: _state.currentUser!.phoneVerified,
    );
    _state.setCurrentUser(updated);
    return updated;
  }

  @override
  Future<void> sendPhoneOtp(String e164Phone) async {
    sendOtpCalls.add(e164Phone);
    final failure = failSendOtpWith;
    if (failure != null) throw DemoAuthException(failure);
  }

  @override
  Future<DemoUser> verifyPhoneOtp({
    required String e164Phone,
    required String token,
  }) async {
    verifiedTokens.add(token);
    final failure = failVerifyWith;
    if (failure != null) throw DemoAuthException(failure);
    final updated = DemoUser(
      email: _state.currentUser!.email,
      displayName: _state.currentUser!.displayName,
      role: _state.currentUser!.role,
      mobileNumber: e164Phone,
      phoneVerified: true,
    );
    _state.setCurrentUser(updated);
    return updated;
  }

  final List<String> renamedTo = <String>[];

  @override
  Future<DemoUser> updateDisplayName(String displayName) async {
    renamedTo.add(displayName);
    final updated = _state.currentUser!.copyWithDisplayName(displayName);
    _state.setCurrentUser(updated);
    return updated;
  }

  @override
  Future<void> updatePassword(String newPassword) => throw UnimplementedError();

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
    child: const MaterialApp(home: EditProfileScreen()),
  );

  Future<void> pumpProfile(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(harness());
  }

  testWidgets('starts pre-filled with the current name, number, and email', (
    tester,
  ) async {
    await pumpProfile(tester);
    await tester.pump();

    String textOf(int index) => tester
        .widget<EditableText>(find.byType(EditableText).at(index))
        .controller
        .text;

    expect(textOf(0), 'Juan');
    expect(textOf(1), 'Dela Cruz');
    expect(textOf(2), '0917 123 4567');
    expect(textOf(3), 'juan@example.test');
  });

  testWidgets('saving the name needs no password', (tester) async {
    await pumpProfile(tester);
    await tester.pump();

    await tester.enterText(find.byType(EditableText).first, 'New');
    await tester.enterText(find.byType(EditableText).at(1), 'Name');
    await tester.tap(find.text('Save name'));
    await tester.pump();
    await tester.pump();

    expect(auth.renamedTo, ['New Name']);
    expect(find.text('Name updated.'), findsOneWidget);
  });

  testWidgets('an unchanged contact section saves nothing', (tester) async {
    await pumpProfile(tester);
    await tester.pump();

    await tester.tap(find.text('Save contact info'));
    await tester.pump();
    await tester.pump();

    expect(auth.reauthCalls, isEmpty);
    expect(auth.updateEmailCalls, isEmpty);
    expect(auth.sendOtpCalls, isEmpty);
  });

  testWidgets('changing the email without a password is refused', (
    tester,
  ) async {
    await pumpProfile(tester);
    await tester.pump();

    final fields = find.byType(EditableText);
    await tester.enterText(fields.at(3), 'new@example.test');
    await tester.tap(find.text('Save contact info'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Enter your current password.'), findsOneWidget);
    expect(auth.reauthCalls, isEmpty);
  });

  testWidgets(
    'a wrong current password fails at re-auth, never reaching updateEmail',
    (tester) async {
      auth.failReauthWith = 'That password is incorrect.';

      await pumpProfile(tester);
      await tester.pump();

      final fields = find.byType(EditableText);
      await tester.enterText(fields.at(3), 'new@example.test');
      await tester.enterText(fields.at(4), 'wrongpass');
      await tester.tap(find.text('Save contact info'));
      await tester.pump();
      await tester.pump();

      expect(find.text('That password is incorrect.'), findsOneWidget);
      expect(auth.updateEmailCalls, isEmpty);
    },
  );

  testWidgets(
    'a correct password updates the email immediately -- no OTP, by design '
    '(Spec 11 §3 revision)',
    (tester) async {
      await pumpProfile(tester);
      await tester.pump();

      final fields = find.byType(EditableText);
      await tester.enterText(fields.at(3), 'new@example.test');
      await tester.enterText(fields.at(4), 'correctpass');
      await tester.tap(find.text('Save contact info'));
      await tester.pump();
      await tester.pump();

      expect(auth.reauthCalls, ['correctpass']);
      expect(auth.updateEmailCalls, ['new@example.test']);
      expect(find.text('Email updated.'), findsOneWidget);
      // No inline OTP card for an email-only change.
      expect(find.text('Verify'), findsNothing);
    },
  );

  testWidgets(
    'changing email and mobile together: a phone-step failure still reports '
    'the email change that already succeeded on the server',
    (tester) async {
      auth.failSendOtpWith =
          'please wait a minute before requesting another code';

      await pumpProfile(tester);
      await tester.pump();

      final fields = find.byType(EditableText);
      await tester.enterText(fields.at(2), '0917 000 1111');
      await tester.enterText(fields.at(3), 'new@example.test');
      await tester.enterText(fields.at(4), 'correctpass');
      await tester.tap(find.text('Save contact info'));
      await tester.pump();
      await tester.pump();

      // The email step ran and committed before the phone step threw.
      expect(auth.updateEmailCalls, ['new@example.test']);
      // The user must be told the email change went through, not just shown
      // the throttle error as if nothing happened.
      expect(find.textContaining('Email updated.'), findsOneWidget);
      expect(find.textContaining('please wait a minute'), findsOneWidget);
      // No OTP card: the phone step never got far enough to send a code.
      expect(find.text('Verify'), findsNothing);
    },
  );

  testWidgets('clearing the mobile field is refused, not silently ignored', (
    tester,
  ) async {
    await pumpProfile(tester);
    await tester.pump();

    final fields = find.byType(EditableText);
    await tester.enterText(fields.at(2), '');
    await tester.tap(find.text('Save contact info'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Mobile number cannot be removed here.'), findsOneWidget);
    expect(auth.reauthCalls, isEmpty);
  });

  group('mobile number change', () {
    Future<void> changeNumber(WidgetTester tester) async {
      final fields = find.byType(EditableText);
      await tester.enterText(fields.at(2), '0917 000 1111');
      await tester.enterText(fields.at(4), 'correctpass');
      await tester.tap(find.text('Save contact info'));
      await tester.pump();
      await tester.pump();
    }

    testWidgets(
      'sends the code and reveals an inline verify card -- no separate page',
      (tester) async {
        await pumpProfile(tester);
        await tester.pump();

        await changeNumber(tester);

        expect(auth.reauthCalls, ['correctpass']);
        expect(auth.sendOtpCalls, ['+639170001111']);
        expect(find.text('Verify'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
      },
    );

    testWidgets('Cancel dismisses the card without verifying anything', (
      tester,
    ) async {
      await pumpProfile(tester);
      await tester.pump();

      await changeNumber(tester);
      await tester.ensureVisible(find.text('Cancel'));
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pump();

      expect(find.text('Verify'), findsNothing);
      expect(auth.verifiedTokens, isEmpty);
    });

    testWidgets('entering the code verifies it and clears the card', (
      tester,
    ) async {
      await pumpProfile(tester);
      await tester.pump();

      await changeNumber(tester);

      // The OTP field is the last EditableText once the inline card appears.
      final codeField = find.byType(EditableText).last;
      await tester.ensureVisible(codeField);
      await tester.pump();
      await tester.enterText(codeField, '123456');
      await tester.ensureVisible(find.text('Verify'));
      await tester.pump();
      await tester.tap(find.text('Verify'));
      await tester.pump();
      await tester.pump();

      expect(auth.verifiedTokens, ['123456']);
      expect(find.text('Mobile number updated.'), findsOneWidget);
      expect(find.text('Verify'), findsNothing);
    });
  });
}
