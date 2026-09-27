import '../../domain/models/demo_user.dart';
import '../../domain/models/fare_class_claim.dart';
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

  /// Local test accounts are email-only, so phone sign-in is always live.
  @override
  Future<DemoUser> signInWithPhone({
    required String phone,
    required String password,
  }) => _requiredLive.signInWithPhone(phone: phone, password: password);

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

  // Live only, for the same reason as updateDisplayName's demo-account branch
  // is NOT mirrored here: a local test account has a fixed compiled-in
  // password and no server-side row, so there is nothing real to
  // re-authenticate against. Routing this to the mock would silently do
  // nothing useful for a real user whose email happened to look local.
  @override
  Future<void> reauthenticate(String currentPassword) =>
      _requiredLive.reauthenticate(currentPassword);

  @override
  Future<void> updatePassword(String newPassword) =>
      _requiredLive.updatePassword(newPassword);

  @override
  Future<DemoUser> updateEmail(String newEmail) =>
      _requiredLive.updateEmail(newEmail);

  // OTP always goes to the live repository. The local test accounts never
  // reach the verify screen -- they are internal testers, so
  // needsPhoneVerification is false -- and routing a code request to the mock
  // would silently do nothing for a real user whose email happened to look
  // local.
  @override
  Future<void> sendPhoneOtp(String e164Phone) =>
      _requiredLive.sendPhoneOtp(e164Phone);

  @override
  Future<DemoUser> verifyPhoneOtp({
    required String e164Phone,
    required String token,
  }) => _requiredLive.verifyPhoneOtp(e164Phone: e164Phone, token: token);

  // Routed, unlike the methods below. A demo account has no server-side row,
  // so its rename has to happen in memory; a real account must reach Postgres.
  @override
  Future<DemoUser> updateDisplayName(String displayName) {
    final current = _state.currentUser;
    if (current != null && current.isDemoAccount) {
      return _local.updateDisplayName(displayName);
    }
    return _requiredLive.updateDisplayName(displayName);
  }

  // Live only, for the same reason as the OTP methods above: a local test
  // account has no server-side row to delete, and routing this to the mock
  // would silently do nothing for a real user whose email happened to look
  // local. `_requiredLive` throws a message the user can act on instead.
  @override
  Future<void> abandonUnverifiedRegistration() =>
      _requiredLive.abandonUnverifiedRegistration();

  @override
  Future<void> signOut() async {
    // Sign out of both, always. Routing on `_live != null` signed the user out
    // of the wrong repository whenever Supabase was configured but the session
    // came from a hidden local test account: `_live.signOut()` ran, the local
    // branch never did, and `DemoState.currentUser` stayed set, so the app went
    // on believing someone was signed in.
    //
    // Signing out of both is deliberate rather than recording which repository
    // authenticated. Sign-out has to be total and idempotent; an "active
    // repository" flag is one more piece of state that can drift out of step
    // with reality across restarts and token refreshes. Signing out of a
    // repository that holds no session costs nothing -- MockAuthRepository's
    // signOut is just `setCurrentUser(null)`.
    //
    // The local clear sits in `finally` so a failed remote sign-out (offline,
    // expired token) cannot strand the user in a locally signed-in state. The
    // remote error still propagates, exactly as it did before.
    try {
      await _live?.signOut();
    } finally {
      await _local.signOut();
    }
  }

  // Live only, for the same reason as the OTP methods above: a local test
  // account has no server-side profiles row for an admin to review, so
  // routing this to the mock would silently do nothing useful for a real
  // user whose email happened to look local.
  @override
  Future<String> uploadFareClassIdPhoto({
    required List<int> bytes,
    required String fileExtension,
  }) => _requiredLive.uploadFareClassIdPhoto(
    bytes: bytes,
    fileExtension: fileExtension,
  );

  @override
  Future<FareClassClaim> submitFareClassClaim({
    required FareClassRequestedClass requestedClass,
    required String idPhotoPath,
  }) => _requiredLive.submitFareClassClaim(
    requestedClass: requestedClass,
    idPhotoPath: idPhotoPath,
  );

  @override
  Future<FareClassClaim?> latestFareClassClaim() {
    final current = _state.currentUser;
    if (current != null && current.isDemoAccount) {
      return _local.latestFareClassClaim();
    }
    return _requiredLive.latestFareClassClaim();
  }

  // Live only, same reasoning as uploadFareClassIdPhoto/submitFareClassClaim
  // above: a local test account has no server-side profiles row for
  // avatar_path to live on.
  @override
  Future<String> uploadProfilePhoto({
    required List<int> bytes,
    required String fileExtension,
  }) => _requiredLive.uploadProfilePhoto(
    bytes: bytes,
    fileExtension: fileExtension,
  );

  @override
  Future<DemoUser> updateAvatarPath(String path) =>
      _requiredLive.updateAvatarPath(path);
}
