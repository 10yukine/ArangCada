import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/demo_user.dart';
import '../../domain/models/fare_class_claim.dart';
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
    String? avatarUrl,
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
      avatarUrl: avatarUrl,
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
        .select(
          'role, display_name, is_internal_tester, phone_verified_at, avatar_path',
        )
        .eq('id', user.id)
        .single();
    final role = profile['role'] as String?;
    // An LGU/TODA admin account is still a real person who commutes --
    // owner's explicit call. It maps to DemoRole.commuter below exactly
    // like a plain commuter account does (mapIdentity() already treats
    // anything that is not 'driver' as commuter); admin grants nothing
    // extra here, this app has no admin-specific UI or capability at all.
    // An invite-created admin has no phone on record (Spec 19 exemption),
    // so it still cannot book a ride until one is added and verified via
    // Account & Security, same requirement every commuter already has.
    if (role != 'commuter' && role != 'driver' && role != 'admin') {
      throw const DemoAuthException(
        'This account could not be loaded. Contact a developer.',
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
      avatarUrl: await _signedAvatarUrl(profile['avatar_path'] as String?),
    );
    _state.setCurrentUser(mapped);
    return mapped;
  }

  /// A fresh signed URL for [avatarPath], or null when there is no photo or
  /// the mint fails. Deliberately swallowed rather than thrown -- a stale or
  /// unreadable avatar must never block the rest of profile restoration
  /// (sign-in, name, phone-verification state); it should just fall back to
  /// the initials `ArangAvatar` already renders for a null imageUrl.
  Future<String?> _signedAvatarUrl(String? avatarPath) async {
    if (avatarPath == null || avatarPath.isEmpty) return null;
    try {
      return await _client.storage
          .from('profile-photos')
          .createSignedUrl(avatarPath, 300);
    } on StorageException {
      return null;
    }
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
  Future<void> reauthenticate(String currentPassword) async {
    final email = _client.auth.currentUser?.email;
    if (email == null) {
      throw const DemoAuthException('Sign in again to continue.');
    }
    try {
      // Deliberately signInWithPassword, not a lighter check: it is the only
      // Supabase Auth call that actually verifies a password against the
      // account, and it is what the spec names as step 1. A wrong password
      // must fail here, not at updateUser -- see .pipeline/specs.md Spec 11 §1.
      await _client.auth.signInWithPassword(email: email, password: currentPassword);
    } on AuthException {
      throw const DemoAuthException('That password is incorrect.');
    }
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    try {
      await _client.auth.updateUser(UserAttributes(password: newPassword));
    } on AuthException catch (error) {
      throw DemoAuthException(
        error.message.isEmpty
            ? 'Could not update your password. Try again.'
            : error.message,
      );
    }
  }

  @override
  Future<DemoUser> updateEmail(String newEmail) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const DemoAuthException('Sign in again to change your email.');
    }
    try {
      await _client.auth.updateUser(UserAttributes(email: newEmail.trim()));
    } on AuthException catch (error) {
      throw DemoAuthException(
        error.message.isEmpty
            ? 'Could not update your email. Try again.'
            : error.message,
      );
    }
    return restoreProfile(_client.auth.currentUser ?? user);
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
      // flow, which is why verifyPhoneOtp uses OtpType.phoneChange. Changing an
      // already-verified number goes through the exact same call -- the caller
      // is expected to have re-authenticated first.
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
  Future<DemoUser> updateDisplayName(String displayName) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const DemoAuthException('Sign in again to change your name.');
    }

    final trimmed = displayName.trim();
    try {
      await _client
          .from('profiles')
          .update({'display_name': trimmed})
          .eq('id', user.id);
    } on PostgrestException {
      throw const DemoAuthException('Could not save your name. Try again.');
    }

    // Re-read rather than patching local state, so what the app shows is what
    // the database actually stored. If a trigger or policy rewrote the value,
    // the user sees the truth instead of the value they typed.
    return restoreProfile(user);
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

  @override
  Future<String> uploadFareClassIdPhoto({
    required List<int> bytes,
    required String fileExtension,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const DemoAuthException('Sign in again to submit a claim.');
    }
    // auth.uid()-prefixed, per discount_id_insert_own's Storage policy --
    // anything else is rejected server-side regardless of what this writes.
    final path =
        '${user.id}/${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
    try {
      await _client.storage
          .from('discount-eligibility-ids')
          .uploadBinary(path, Uint8List.fromList(bytes));
    } on StorageException catch (error) {
      throw DemoAuthException(
        error.message.isEmpty
            ? 'Could not upload that photo. Try again.'
            : error.message,
      );
    }
    return path;
  }

  @override
  Future<FareClassClaim> submitFareClassClaim({
    required FareClassRequestedClass requestedClass,
    required String idPhotoPath,
  }) async {
    try {
      final result = await _client.rpc(
        'submit_fare_class_claim',
        params: {
          'p_class': requestedClass.wireValue,
          'p_id_photo_path': idPhotoPath,
        },
      );
      return FareClassClaim.fromRow(_row(result));
    } on PostgrestException catch (error) {
      throw DemoAuthException(
        error.message.isEmpty
            ? 'Could not file your claim. Try again.'
            : error.message,
      );
    }
  }

  @override
  Future<FareClassClaim?> latestFareClassClaim() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    try {
      final row = await _client
          .from('fare_class_claims')
          .select()
          .eq('profile_id', user.id)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return row == null ? null : FareClassClaim.fromRow(row);
    } on PostgrestException catch (error) {
      // Unlike the two methods above, this one is called from initState() on
      // every visit to the screen, not from a button press -- an uncaught
      // PostgrestException here doesn't just fail one action, it leaves
      // _refresh()'s try/catch (which only matches DemoAuthException) never
      // reaching its setState(loading = false), spinning forever instead of
      // showing an error. Found on a physical device, 6 Sep 2026.
      throw DemoAuthException(
        error.message.isEmpty
            ? 'Could not load your claim status. Try again.'
            : error.message,
      );
    }
  }

  @override
  Future<String> uploadProfilePhoto({
    required List<int> bytes,
    required String fileExtension,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const DemoAuthException('Sign in again to change your photo.');
    }
    // auth.uid()-prefixed, per profile_photos_insert_own's Storage policy --
    // anything else is rejected server-side regardless of what this writes.
    final path =
        '${user.id}/${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
    try {
      await _client.storage
          .from('profile-photos')
          .uploadBinary(path, Uint8List.fromList(bytes));
    } on StorageException catch (error) {
      throw DemoAuthException(
        error.message.isEmpty
            ? 'Could not upload that photo. Try again.'
            : error.message,
      );
    }
    return path;
  }

  @override
  Future<DemoUser> updateAvatarPath(String path) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const DemoAuthException('Sign in again to change your photo.');
    }
    try {
      await _client
          .from('profiles')
          .update({'avatar_path': path})
          .eq('id', user.id);
    } on PostgrestException {
      throw const DemoAuthException('Could not save your photo. Try again.');
    }
    // Re-read rather than patching local state, matching updateDisplayName --
    // this is also what mints the signed URL the UI actually displays.
    return restoreProfile(user);
  }

  /// `rpc()` returns a bare object for a rowtype-returning function on some
  /// PostgREST/postgrest-dart versions and a single-element list on others --
  /// mirrors `SupabaseRideRepository._row()`'s defensive cast.
  Map<String, dynamic> _row(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is List && value.isNotEmpty && value.first is Map) {
      return Map<String, dynamic>.from(value.first as Map);
    }
    throw const FormatException('The server returned an invalid response.');
  }
}
