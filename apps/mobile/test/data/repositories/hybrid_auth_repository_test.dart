import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/mock/mock_auth_repository.dart';
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
}
