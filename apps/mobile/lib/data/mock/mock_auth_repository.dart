import '../../domain/models/demo_user.dart';
import '../repositories/auth_repository.dart';
import 'demo_state.dart';

class DemoAccount {
  const DemoAccount({required this.user, required this.password});

  final DemoUser user;
  final String password;
}

class MockAuthRepository implements AuthRepository {
  MockAuthRepository(this._state);

  final DemoState _state;

  static const accounts = <DemoAccount>[
    DemoAccount(
      user: DemoUser(
        email: 'commuter@arangcada.demo',
        displayName: 'Joshua Adia',
        role: DemoRole.commuter,
        // isInternalTester must be true or these accounts are trapped.
        //
        // Phone verification (31 Aug 2026) routes any account with
        // needsPhoneVerification to /verify-phone. These demo logins have no
        // SIM behind them and this repository throws for sendPhoneOtp, so
        // without the flag a QA session would reach the verify screen and have
        // no way off it except signing out -- every device QA run would be
        // dead on arrival. The flag mirrors profiles.is_internal_tester, which
        // is what the server-side gate checks.
        isInternalTester: true,
      ),
      password: 'demo1234',
    ),
    DemoAccount(
      user: DemoUser(
        email: 'driver@arangcada.demo',
        displayName: 'Marco Dela Cruz',
        role: DemoRole.driver,
        isInternalTester: true,
      ),
      password: 'demo1234',
    ),
  ];

  @override
  DemoUser? get currentUser => _state.currentUser;

  @override
  Future<DemoUser> signIn({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    for (final account in accounts) {
      if (account.user.email == normalizedEmail &&
          account.password == password) {
        _state.setCurrentUser(account.user);
        return account.user;
      }
    }
    throw const DemoAuthException('Use one of the demo accounts shown below.');
  }

  @override
  Future<DemoUser> updateDisplayName(String displayName) async {
    final current = _state.currentUser;
    if (current == null) {
      throw const DemoAuthException('Sign in again to change your name.');
    }
    // In-memory only. The seeded accounts are compiled in, so the rename lasts
    // for the session and is gone on the next launch -- correct for a fixture.
    final renamed = current.copyWithDisplayName(displayName.trim());
    _state.setCurrentUser(renamed);
    return renamed;
  }

  // The seeded demo accounts have a fixed, compiled-in password and no
  // server-side row, so there is nothing real to re-authenticate against or
  // change. Reaching either method below means something routed a demo
  // account to the password-change screen, which is a bug -- hence the
  // explicit throw rather than a silent no-op, matching sendPhoneOtp below.
  @override
  Future<void> reauthenticate(String currentPassword) {
    throw const DemoAuthException(
      'Demo accounts have a fixed password and cannot be changed.',
    );
  }

  @override
  Future<DemoUser> updateEmail(String newEmail) {
    throw const DemoAuthException(
      'Demo accounts have a fixed email and cannot be changed.',
    );
  }

  @override
  Future<void> updatePassword(String newPassword) {
    throw const DemoAuthException(
      'Demo accounts have a fixed password and cannot be changed.',
    );
  }

  @override
  Future<void> abandonUnverifiedRegistration() async {
    // Nothing to abandon. The seeded accounts are internal testers, so they
    // never reach the verify screen, and they are compiled in rather than
    // stored -- there is no row for this to delete.
  }

  @override
  Future<void> signOut() async {
    _state.setCurrentUser(null);
  }

  @override
  Future<RegistrationResult> signUp({
    required String displayName,
    required String mobileNumber,
    required String email,
    required String password,
  }) {
    throw const DemoAuthException(
      'Account creation requires configured Supabase Auth.',
    );
  }

  @override
  Future<void> sendPasswordReset(String email) {
    throw const DemoAuthException(
      'Password recovery requires configured Supabase Auth.',
    );
  }

  // The seeded demo accounts have no SIM behind them, so there is nothing to
  // send a code to. They are exempt instead: the accounts above set
  // isInternalTester, which makes needsPhoneVerification false, and the server
  // grants the same exemption through is_verified_account(). Reaching either
  // method below therefore means something routed a demo account to the verify
  // screen, which is a bug -- hence the explicit throw rather than a no-op.
  @override
  Future<void> sendPhoneOtp(String e164Phone) {
    throw const DemoAuthException(
      'Demo accounts are already verified and cannot receive an SMS code.',
    );
  }

  @override
  Future<DemoUser> verifyPhoneOtp({
    required String e164Phone,
    required String token,
  }) {
    throw const DemoAuthException(
      'Demo accounts are already verified and cannot receive an SMS code.',
    );
  }
}
