import '../../domain/models/demo_user.dart';

abstract interface class AuthRepository {
  DemoUser? get currentUser;

  Future<DemoUser> signIn({required String email, required String password});

  Future<void> signOut();
}

class DemoAuthException implements Exception {
  const DemoAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}
