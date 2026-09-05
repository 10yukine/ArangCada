import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/repositories/auth_repository.dart';
import 'package:arangcada/data/repositories/hybrid_auth_repository.dart';
import 'package:arangcada/domain/models/demo_user.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what it was asked to do and authenticates nobody. Stands in for
/// Supabase Auth so these tests need no network and no configured project.
class _SpyLiveAuthRepository implements AuthRepository {
  int signOutCalls = 0;
  bool throwOnSignOut = false;

  @override
  DemoUser? get currentUser => null;

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

  /// Records the number handed to the live repository, so the OTP-routing
  /// test can assert the hybrid did not divert a code request to the mock.
  String? sentOtpTo;

  @override
  Future<void> sendPhoneOtp(String e164Phone) async {
    sentOtpTo = e164Phone;
  }

  @override
  Future<DemoUser> verifyPhoneOtp({
    required String e164Phone,
    required String token,
  }) => throw UnimplementedError();

  /// Records the password handed to the live repository, so the
  /// re-authentication routing test can assert the hybrid did not divert it
  /// to the mock (which has no real account to check it against).
  String? reauthenticatedWith;

  @override
  Future<void> reauthenticate(String currentPassword) async {
    reauthenticatedWith = currentPassword;
  }

  String? updatedPasswordTo;

  @override
  Future<void> updatePassword(String newPassword) async {
    updatedPasswordTo = newPassword;
  }

  String? updatedEmailTo;

  @override
  Future<DemoUser> updateEmail(String newEmail) async {
    updatedEmailTo = newEmail;
    return DemoUser(
      email: newEmail,
      displayName: 'Live User',
      role: DemoRole.commuter,
    );
  }

  /// Records the name handed to the live repository, so the routing test can
  /// assert a real account's rename was not diverted to the mock.
  String? renamedTo;

  @override
  Future<DemoUser> updateDisplayName(String displayName) async {
    renamedTo = displayName;
    return DemoUser(
      email: 'live@example.test',
      displayName: displayName,
      role: DemoRole.commuter,
    );
  }

  @override
  Future<void> abandonUnverifiedRegistration() async {
    abandonCalls++;
  }

  int abandonCalls = 0;

  @override
  Future<void> signOut() async {
    signOutCalls++;
    if (throwOnSignOut) {
      throw const DemoAuthException('remote sign-out failed');
    }
  }
}

void main() {
  const localEmail = 'commuter@arangcada.demo';
  const localPassword = 'demo1234';

  group('HybridAuthRepository.signOut', () {
    // The regression this file exists for. signOut() used to branch on whether
    // a live repository existed rather than on which one held the session, so
    // with Supabase configured a local test account was signed out of Supabase
    // while DemoState kept the user -- leaving the app signed in after the user
    // had asked to leave.
    test(
      'clears the local session even when a live repository is configured',
      () async {
        final state = DemoState();
        final live = _SpyLiveAuthRepository();
        final repo = HybridAuthRepository(state: state, live: live);

        await repo.signIn(email: localEmail, password: localPassword);
        expect(repo.currentUser, isNotNull, reason: 'sign-in should populate');

        await repo.signOut();

        expect(
          repo.currentUser,
          isNull,
          reason: 'a signed-out user must not remain in DemoState',
        );
      },
    );

    test('still signs out of the live repository', () async {
      final state = DemoState();
      final live = _SpyLiveAuthRepository();
      final repo = HybridAuthRepository(state: state, live: live);

      await repo.signIn(email: localEmail, password: localPassword);
      await repo.signOut();

      expect(
        live.signOutCalls,
        1,
        reason: 'the remote session must be ended too, not skipped',
      );
    });

    test('clears local state even if the remote sign-out fails', () async {
      final state = DemoState();
      final live = _SpyLiveAuthRepository()..throwOnSignOut = true;
      final repo = HybridAuthRepository(state: state, live: live);

      await repo.signIn(email: localEmail, password: localPassword);

      // The remote failure still surfaces -- callers should know the server
      // session may survive -- but it must not strand the user locally.
      await expectLater(repo.signOut(), throwsA(isA<DemoAuthException>()));

      expect(
        repo.currentUser,
        isNull,
        reason: 'an offline sign-out must still log the user out on device',
      );
    });

    test('works with no live repository configured', () async {
      final state = DemoState();
      final repo = HybridAuthRepository(state: state, live: null);

      await repo.signIn(email: localEmail, password: localPassword);
      await repo.signOut();

      expect(repo.currentUser, isNull);
    });

    test('is idempotent when nobody is signed in', () async {
      final state = DemoState();
      final live = _SpyLiveAuthRepository();
      final repo = HybridAuthRepository(state: state, live: live);

      await repo.signOut();
      await repo.signOut();

      expect(repo.currentUser, isNull);
    });
  });

  group('HybridAuthRepository OTP routing', () {
    test('sends the code through the live repository, never the mock', () async {
      // The mock repository throws for sendPhoneOtp, so if the hybrid ever
      // routed a code request locally -- for instance by reusing the
      // _isLocalTestEmail check that signIn uses -- this would throw instead
      // of recording the number. A real user whose email merely looked local
      // would silently never receive a code.
      final state = DemoState();
      addTearDown(state.dispose);
      final live = _SpyLiveAuthRepository();
      final hybrid = HybridAuthRepository(state: state, live: live);

      await hybrid.sendPhoneOtp('+639171234567');

      expect(live.sentOtpTo, '+639171234567');
    });
  });

  group('HybridAuthRepository password-change routing', () {
    // The mock repository throws for both methods (Spec 11: a demo account has
    // a fixed, compiled-in password and no real account to re-authenticate
    // against), so if the hybrid ever routed either call locally this would
    // throw instead of recording what it was asked to do.
    test('reauthenticate always goes through the live repository', () async {
      final state = DemoState();
      addTearDown(state.dispose);
      final live = _SpyLiveAuthRepository();
      final hybrid = HybridAuthRepository(state: state, live: live);

      await hybrid.reauthenticate('correct-horse-battery-staple');

      expect(live.reauthenticatedWith, 'correct-horse-battery-staple');
    });

    test('updatePassword always goes through the live repository', () async {
      final state = DemoState();
      addTearDown(state.dispose);
      final live = _SpyLiveAuthRepository();
      final hybrid = HybridAuthRepository(state: state, live: live);

      await hybrid.updatePassword('a-brand-new-password');

      expect(live.updatedPasswordTo, 'a-brand-new-password');
    });

    test('updateEmail always goes through the live repository', () async {
      final state = DemoState();
      addTearDown(state.dispose);
      final live = _SpyLiveAuthRepository();
      final hybrid = HybridAuthRepository(state: state, live: live);

      await hybrid.updateEmail('new@example.test');

      expect(live.updatedEmailTo, 'new@example.test');
    });
  });

  test('a demo account renames in memory and never reaches the live repository', () async {
    final state = DemoState();
    final live = _SpyLiveAuthRepository();
    final hybrid = HybridAuthRepository(state: state, live: live);

    await hybrid.signIn(
      email: 'commuter@arangcada.demo',
      password: 'demo1234',
    );
    final renamed = await hybrid.updateDisplayName('Bagong Pangalan');

    // The seeded accounts are compiled in, not stored, so there is no row for
    // the live repository to update. Routing this remotely would fail for an
    // account that authenticated entirely offline.
    expect(live.renamedTo, isNull);
    expect(renamed.displayName, 'Bagong Pangalan');
    expect(state.currentUser?.displayName, 'Bagong Pangalan');

    state.dispose();
  });

  test('a real account renames through the live repository', () async {
    final state = DemoState();
    final live = _SpyLiveAuthRepository();
    final hybrid = HybridAuthRepository(state: state, live: live);

    state.setCurrentUser(
      const DemoUser(
        email: 'someone@example.test',
        displayName: 'Old Name',
        role: DemoRole.commuter,
      ),
    );
    await hybrid.updateDisplayName('New Name');

    expect(live.renamedTo, 'New Name');

    state.dispose();
  });
}
