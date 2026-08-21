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
}

class RegistrationResult {
  const RegistrationResult({
    required this.requiresEmailConfirmation,
    this.user,
  });

  final bool requiresEmailConfirmation;
  final DemoUser? user;
}

class DemoAuthException implements Exception {
  const DemoAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}
