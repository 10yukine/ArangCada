import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/demo_user.dart';
import '../mock/demo_state.dart';
import '../repositories/auth_repository.dart';

/// Supabase Auth transport only.
///
/// Application tables are not deployed remotely yet, so this repository does
/// not query `profiles`. Role may come only from trusted `app_metadata`; absent
/// metadata defaults to commuter. User metadata is display data, never an
/// authorization decision.
class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client, this._state);

  final SupabaseClient _client;
  final DemoState _state;

  @override
  DemoUser? get currentUser => _state.currentUser;

  static DemoUser mapIdentity({
    required String email,
    String? displayName,
    String? appRole,
  }) {
    final normalizedName = displayName?.trim();
    final fallbackName = email
        .split('@')
        .first
        .replaceAll(RegExp(r'[._-]+'), ' ');
    return DemoUser(
      email: email,
      displayName: normalizedName == null || normalizedName.isEmpty
          ? _titleCase(fallbackName)
          : normalizedName,
      role: appRole == 'driver' ? DemoRole.driver : DemoRole.commuter,
    );
  }

  static String _titleCase(String value) => value
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');

  static DemoUser fromSupabaseUser(User user) => mapIdentity(
    email: user.email ?? 'commuter@arangcada.local',
    displayName: user.userMetadata?['display_name'] as String?,
    appRole: user.appMetadata['role'] as String?,
  );

  @override
  Future<DemoUser> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      final user = response.user;
      if (user == null) {
        throw const DemoAuthException('Unable to sign in right now.');
      }
      final mapped = fromSupabaseUser(user);
      _state.setCurrentUser(mapped);
      return mapped;
    } on AuthException {
      throw const DemoAuthException('Email or password is incorrect.');
    }
  }

  @override
  Future<RegistrationResult> signUp({
    required String displayName,
    required String mobileNumber,
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {
          'display_name': displayName.trim(),
          'mobile_number': mobileNumber.trim(),
        },
      );
      final user = response.user;
      final mapped = user == null ? null : fromSupabaseUser(user);
      if (response.session != null && mapped != null) {
        _state.setCurrentUser(mapped);
      }
      return RegistrationResult(
        requiresEmailConfirmation: response.session == null,
        user: mapped,
      );
    } on AuthException {
      throw const DemoAuthException(
        'Account creation is unavailable. Check the details and try again.',
      );
    }
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email.trim());
    } on AuthException {
      throw const DemoAuthException(
        'Password recovery is unavailable right now.',
      );
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } finally {
      _state.setCurrentUser(null);
    }
  }
}
