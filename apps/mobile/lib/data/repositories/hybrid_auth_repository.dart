import '../../domain/models/demo_user.dart';
import '../mock/demo_state.dart';
import '../mock/mock_auth_repository.dart';
import 'auth_repository.dart';

/// Routes hidden local test accounts to the offline repository and every other
/// account to Supabase Auth when configured.
class HybridAuthRepository implements AuthRepository {
  factory HybridAuthRepository({
    required DemoState state,
    required AuthRepository? live,
  }) => HybridAuthRepository._(state, live);

  HybridAuthRepository._(this._state, this._live)
    : _local = MockAuthRepository(_state);

  final DemoState _state;
  final AuthRepository? _live;
  final MockAuthRepository _local;

  @override
  DemoUser? get currentUser => _state.currentUser;

  bool _isLocalTestEmail(String email) => MockAuthRepository.accounts.any(
    (account) => account.user.email == email.trim().toLowerCase(),
  );

  AuthRepository get _requiredLive =>
      _live ??
      (throw const DemoAuthException(
        'Live authentication is unavailable. Check your connection or configuration.',
      ));

  @override
  Future<DemoUser> signIn({required String email, required String password}) {
    if (_isLocalTestEmail(email)) {
      return _local.signIn(email: email, password: password);
    }
    return _requiredLive.signIn(email: email, password: password);
  }

  @override
  Future<RegistrationResult> signUp({
    required String displayName,
    required String mobileNumber,
    required String email,
    required String password,
  }) => _requiredLive.signUp(
    displayName: displayName,
    mobileNumber: mobileNumber,
    email: email,
    password: password,
  );

  @override
  Future<void> sendPasswordReset(String email) =>
      _requiredLive.sendPasswordReset(email);

  @override
  Future<void> signOut() async {
    if (_live != null) {
      await _live.signOut();
    } else {
      await _local.signOut();
    }
  }
}
