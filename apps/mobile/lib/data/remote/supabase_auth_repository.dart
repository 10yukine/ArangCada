import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/demo_user.dart';
import '../mock/demo_state.dart';
import '../repositories/auth_repository.dart';

/// Supabase Auth transport with role and test access resolved from profiles.
/// User-editable metadata never determines application authorization.
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
    String? profileRole,
    bool isInternalTester = false,
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
      role: (profileRole ?? appRole) == 'driver'
          ? DemoRole.driver
          : DemoRole.commuter,
      isInternalTester: isInternalTester,
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

  Future<DemoUser> restoreProfile(User user) async {
    final profile = await _client
        .from('profiles')
        .select('role, display_name, is_internal_tester')
        .eq('id', user.id)
        .single();
    final role = profile['role'] as String?;
    if (role != 'commuter' && role != 'driver') {
      throw const DemoAuthException(
        'This account belongs in the LGU/TODA admin console.',
      );
    }
    final mapped = mapIdentity(
      email: user.email ?? 'commuter@arangcada.local',
      displayName: profile['display_name'] as String?,
      profileRole: role,
      isInternalTester: profile['is_internal_tester'] == true,
    );
    _state.setCurrentUser(mapped);
    return mapped;
  }

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
      return await restoreProfile(user);
    } on AuthException {
      throw const DemoAuthException('Email or password is incorrect.');
    } on PostgrestException {
      throw const DemoAuthException(
        'Your account profile is unavailable. Contact an administrator.',
      );
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
      final mapped = user == null
          ? null
          : response.session == null
          ? fromSupabaseUser(user)
          : await restoreProfile(user);
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
