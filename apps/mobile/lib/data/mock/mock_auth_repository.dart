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
      ),
      password: 'demo1234',
    ),
    DemoAccount(
      user: DemoUser(
        email: 'driver@arangcada.demo',
        displayName: 'Marco Dela Cruz',
        role: DemoRole.driver,
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
}
