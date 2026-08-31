import '../../domain/models/demo_user.dart';

abstract interface class AuthRepository {
  DemoUser? get currentUser;

  Future<DemoUser> signIn({required String email, required String password});

  Future<RegistrationResult> signUp({
    required String displayName,
    required String mobileNumber,
    required String email,
    required String password,
  });

  Future<void> sendPasswordReset(String email);

  Future<void> signOut();

  /// Sends a 6-digit SMS code to [e164Phone] and attaches that number to the
  /// signed-in account. Safe to call again to resend; the server throttles.
  Future<void> sendPhoneOtp(String e164Phone);

  /// Confirms the code. Returns the refreshed user, now phone-verified.
  Future<DemoUser> verifyPhoneOtp({
    required String e164Phone,
    required String token,
  });
}

class RegistrationResult {
  const RegistrationResult({
    required this.requiresEmailConfirmation,
    this.user,
  });

  /// Retained for the mock/local path. The live flow no longer confirms by
  /// emailed link -- since 31 Aug 2026 verification is a 6-digit SMS code, and
  /// the account is signed in but held on the verify screen. Email
  /// confirmation may return later as an optional profile action.
  final bool requiresEmailConfirmation;
  final DemoUser? user;
}

class DemoAuthException implements Exception {
  const DemoAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}
