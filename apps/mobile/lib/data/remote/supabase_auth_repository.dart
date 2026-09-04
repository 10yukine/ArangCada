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
    String? mobileNumber,
    bool phoneVerified = false,
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
      mobileNumber: mobileNumber,
      phoneVerified: phoneVerified,
    );
  }

  static String _titleCase(String value) => value
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');

  /// The account's mobile number, preferring the verified `auth.users.phone`
  /// over the unverified copy the sign-up form put in user metadata.
  ///
  /// Extracted rather than inlined because `cond ? x as String? : y` hits a
  /// Dart parse ambiguity -- the `?` of the nullable type is read as the start
  /// of another conditional -- and the workaround parenthesising is less
  /// readable than a named helper.
  static String? _mobileOf(User user) {
    final phone = user.phone;
    if (phone != null && phone.isNotEmpty) return phone;
    return user.userMetadata?['mobile_number'] as String?;
  }

  static DemoUser fromSupabaseUser(User user) => mapIdentity(
    email: user.email ?? 'commuter@arangcada.local',
    displayName: user.userMetadata?['display_name'] as String?,
    appRole: user.appMetadata['role'] as String?,
    mobileNumber: _mobileOf(user),
    phoneVerified: user.phoneConfirmedAt != null,
  );

  Future<DemoUser> restoreProfile(User user) async {
    final profile = await _client
        .from('profiles')
        .select('role, display_name, is_internal_tester, phone_verified_at')
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
      mobileNumber: _mobileOf(user),
      // profiles.phone_verified_at is the mirrored copy the rest of the app
      // reads. auth.users.phone_confirmed_at is the authority, but the trigger
      // that mirrors it can lag a hair behind the session, so accept either.
      phoneVerified:
          profile['phone_verified_at'] != null || user.phoneConfirmedAt != null,
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
  Future<void> sendPhoneOtp(String e164Phone) async {
    try {
      // Server-side throttle first, so a client loop cannot drain the prepaid
      // SMS balance. record_otp_send raises rather than returning false, so a
      // caller cannot ignore the result by accident.
      await _client.rpc('record_otp_send', params: {'p_phone': e164Phone});

      // Attaching the phone to the existing account is what triggers the OTP.
      // The account was created with email+password; this is the phone-change
      // flow, which is why verifyPhoneOtp uses OtpType.phoneChange.
      await _client.auth.updateUser(UserAttributes(phone: e164Phone));
    } on PostgrestException catch (error) {
      // The throttle speaks in sentences meant for the user, so pass it
      // through rather than replacing it with something vaguer.
      throw DemoAuthException(
        error.message.isEmpty
            ? 'Could not send the code. Try again in a moment.'
            : error.message,
      );
    } on AuthException catch (error) {
      throw DemoAuthException(
        error.message.isEmpty
            ? 'Could not send the code to that number.'
            : error.message,
      );
    }
  }

  @override
  Future<DemoUser> verifyPhoneOtp({
    required String e164Phone,
    required String token,
  }) async {
    try {
      await _client.auth.verifyOTP(
        phone: e164Phone,
        token: token.trim(),
        type: OtpType.phoneChange,
      );
      final user = _client.auth.currentUser;
      if (user == null) {
        throw const DemoAuthException('Your session expired. Sign in again.');
      }
      return await restoreProfile(user);
    } on AuthException {
      throw const DemoAuthException(
        'That code is incorrect or has expired. Request a new one.',
      );
    }
  }

  @override
  Future<void> abandonUnverifiedRegistration() async {
    // The session's JWT is dead the moment this returns -- the user it names no
    // longer exists -- so the caller must sign out immediately afterwards.
    await _client.rpc('abandon_unverified_registration');
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
