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

  /// Deletes the caller's own account, but only while it has never confirmed a
  /// mobile number.
  ///
  /// Exists because a mistyped number is otherwise unrecoverable: the code goes
  /// to a number the user does not hold, the account already exists, and going
  /// back to registration fails with "already registered" against their own
  /// email address. Supabase Auth has no verify-then-create flow, so the
  /// account is created as normal and removed the moment it is abandoned.
  ///
  /// The server refuses for verified accounts, internal testers and
  /// administrators, so this cannot become a back-door "delete my account".
  Future<void> abandonUnverifiedRegistration();

  /// Renames the signed-in account.
  ///
  /// Safe to call from the client: `profiles` grants UPDATE on
  /// (display_name, phone) to `authenticated` only, and
  /// guard_profiles_privileged_columns() rejects any attempt to change role or
  /// status in the same statement. So a tampered client can rename itself and
  /// nothing else.
  Future<DemoUser> updateDisplayName(String displayName);

  /// Proves the signed-in user actually holds [currentPassword] by replaying
  /// `signInWithPassword` against their own account.
  ///
  /// Exists because Supabase's `updateUser(password:)` does not check the
  /// existing password at all -- it changes it on the strength of the session
  /// alone. Without this step first, anyone holding an unlocked phone could
  /// take the account. Implementations must fail with a message naming
  /// "incorrect password" -- the one case the user can actually fix -- never a
  /// generic error. See .pipeline/specs.md Spec 11 §1.
  Future<void> reauthenticate(String currentPassword);

  /// Sets a new password. Callers must call [reauthenticate] first -- this
  /// method alone proves nothing about ownership, matching what the platform
  /// call underneath it does.
  Future<void> updatePassword(String newPassword);

  /// Changes the signed-in account's email address, applied immediately.
  ///
  /// Deliberately no confirmation step: the project's `mailer_autoconfirm`
  /// setting applies the change on the strength of the session alone (no
  /// custom SMTP exists to send a confirmation link either way), and the
  /// owner's explicit decision (Spec 11 §3 revision, 5 Sep 2026) is that this
  /// is the right trade for a capstone account where a mistyped sign-up email
  /// is otherwise unrecoverable. [reauthenticate] is still required first --
  /// it is what stops an unlocked-phone attacker who does not know the
  /// password from redirecting account recovery to an address they control.
  Future<DemoUser> updateEmail(String newEmail);

  /// Sends a 6-digit SMS code to [e164Phone] and attaches that number to the
  /// signed-in account. Safe to call again to resend; the server throttles.
  ///
  /// Also the mechanism for changing an already-verified account's number:
  /// attaching a new number is what triggers the OTP either way. Callers
  /// changing an existing number must call [reauthenticate] first.
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
