import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/booking.dart';
import '../../domain/models/demo_user.dart';
import '../../domain/models/fare_class_claim.dart';
import '../mock/demo_state.dart';
import '../repositories/auth_repository.dart';
import 'push/push_notification_service.dart';

/// Supabase Auth transport with role and test access resolved from profiles.
/// User-editable metadata never determines application authorization.
class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(
    this._client,
    this._state, {
    this._captcha = _noCaptcha,
  });

  final SupabaseClient _client;
  final DemoState _state;

  /// Asked for a fresh token before each request Auth's CAPTCHA would gate.
  /// Supplied by the app, which owns the screen the check appears on.
  final Future<String?> Function() _captcha;

  static Future<String?> _noCaptcha() async => null;

  /// The failures that have words of their own, whichever request met them.
  static void _checkKnownFailure(Object error) {
    if (error is AuthException && error.code == 'captcha_failed') {
      throw const DemoAuthException(
        'The security check did not finish. Please try again.',
      );
    }
    // How the Auth client reports a request that got no answer at all. With a
    // status it is the server that is in trouble, and that keeps the general
    // message. Without this a phone with no signal is told to check its
    // password.
    if (error is AuthRetryableFetchException && error.statusCode == null) {
      throw const DemoAuthException(
        'No connection. Check your internet and try again.',
      );
    }
  }

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
    bool emailConfirmed = true,
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
      isAdminAccount: profileRole == 'admin',
      mobileNumber: mobileNumber,
      phoneVerified: phoneVerified,
      emailConfirmed: emailConfirmed,
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
          'role, display_name, is_internal_tester, phone_verified_at, '
          'email_confirmed_at, avatar_path, fare_class',
        )
        .eq('id', user.id)
        .single();
    final role = profile['role'] as String?;
    // Website admins keep their server role and use commuter features here.
    // Those without a mobile number complete phone setup before SMS verification.
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
      emailConfirmed: profile['email_confirmed_at'] != null,
      avatarUrl: await _signedAvatarUrl(profile['avatar_path'] as String?),
    );
    _state.driverTodaName = role == 'driver'
        ? await _driverTodaName(user.id)
        : null;
    _state.setCurrentUser(mapped);
    _state.setUserFareClass(
      await _approvedFareClass(profile['fare_class'] as String?),
    );
    return mapped;
  }

  /// What the booking screens quote with. The server bills an approved rider
  /// the discounted fare; without this the app quoted, and showed as locked,
  /// the regular one. Student, Senior Citizen and PWD price the same, so the
  /// claim is only read for the label.
  Future<UserFareClass> _approvedFareClass(String? fareClass) async {
    if (fareClass != 'discounted') return UserFareClass.regular;
    final claim = await latestFareClassClaim();
    if (claim?.status != FareClassClaimStatus.approved) {
      return UserFareClass.student;
    }
    return switch (claim!.requestedClass) {
      FareClassRequestedClass.student => UserFareClass.student,
      FareClassRequestedClass.seniorCitizen => UserFareClass.seniorCitizen,
      FareClassRequestedClass.pwd => UserFareClass.pwd,
    };
  }

  /// A fresh signed URL for [avatarPath], or null when there is no photo or
  /// the mint fails. Deliberately swallowed rather than thrown -- a stale or
  /// unreadable avatar must never block the rest of profile restoration
  /// (sign-in, name, phone-verification state); it should just fall back to
  /// the initials `ArangAvatar` already renders for a null imageUrl.
  ///
  /// The URL is made once per profile load and shown for as long as the app
  /// stays open. At five minutes the photo turned into initials the next time
  /// Flutter reloaded it (after the image cache was cleared, or on a screen
  /// built later). It is the account's own photo, held only in memory.
  // ponytail: outlives any normal app run; an app left open for a week loses
  // the photo until restart. Re-mint when the image fails to load if that
  // ever matters.
  Future<String?> _signedAvatarUrl(String? avatarPath) async {
    if (avatarPath == null || avatarPath.isEmpty) return null;
    try {
      return await _client.storage
          .from('profile-photos')
          .createSignedUrl(avatarPath, const Duration(days: 7).inSeconds);
    } on StorageException {
      return null;
    }
  }

  /// The driver's TODA for the home header, or null when it cannot be read.
  /// Cosmetic, so a failure must not block sign-in.
  Future<String?> _driverTodaName(String id) async {
    try {
      final row = await _client
          .from('driver_profiles')
          .select('toda_zones(name)')
          .eq('id', id)
          .maybeSingle();
      return (row?['toda_zones'] as Map?)?['name'] as String?;
    } on Exception {
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
        captchaToken: await _captcha(),
      );
      final user = response.user;
      if (user == null) {
        throw const DemoAuthException(
          'Unable to sign in. Check your credentials and try again.',
        );
      }
      return await restoreProfile(user);
    } catch (error) {
      _checkKnownFailure(error);
      throw const DemoAuthException(
        'Unable to sign in. Check your credentials and try again.',
      );
    }
  }

  @override
  Future<DemoUser> signInWithPhone({
    required String phone,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signInWithPassword(
        phone: phone,
        password: password,
        captchaToken: await _captcha(),
      );
      final user = response.user;
      if (user == null) throw const AuthException('No user');
      return await restoreProfile(user);
    } catch (error) {
      _checkKnownFailure(error);
      // Same message whether the number is unknown, unverified or the
      // password is wrong, so the form never confirms who has an account.
      throw const DemoAuthException(
        'Unable to sign in with that number. Check your password, or log in '
        'with your email if you have not verified this number yet.',
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
        captchaToken: await _captcha(),
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
    } on AuthException catch (error) {
      _checkKnownFailure(error);
      if (error.code == 'user_already_exists' || error.code == 'email_exists') {
        throw const ExistingAccountException();
      }
      throw const DemoAuthException(
        'Account creation is unavailable. Check the details or sign in if you already have an account.',
      );
    }
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      // The link must come back into the app: the client uses PKCE, so the
      // code in it can only be exchanged by the app that asked for it (a
      // browser page would show the link as expired). The URL is on the
      // Supabase Auth redirect allow-list and in AndroidManifest.xml.
      await _client.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: 'ph.calamba.arangcada://reset-password',
        captchaToken: await _captcha(),
      );
    } on AuthException catch (error) {
      _checkKnownFailure(error);
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
      // must fail here, not at updateUser
      await _client.auth.signInWithPassword(
        email: email,
        password: currentPassword,
        captchaToken: await _captcha(),
      );
    } on AuthException catch (error) {
      _checkKnownFailure(error);
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
    final restored = await restoreProfile(_client.auth.currentUser ?? user);
    // A new address is unconfirmed again (the server clears it).
    if (!restored.emailConfirmed) _mailEmailConfirmation();
    return restored;
  }

  /// Mails the confirmation link without holding anything up. The Profile
  /// screen offers to send it again if this one never arrives.
  void _mailEmailConfirmation() {
    try {
      unawaited(
        _client.functions
            .invoke('send-email-confirmation')
            .then<void>((_) {}, onError: (_) {}),
      );
    } catch (_) {
      // Never let a missing email stop sign-up or an email change.
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
      // flow, which is why verifyPhoneOtp uses OtpType.phoneChange. Changing an
      // already-verified number goes through the exact same call -- the caller
      // is expected to have re-authenticated first.
      final current = _state.currentUser;
      final unverified = current != null && !current.phoneVerified;
      await _client.auth.updateUser(
        UserAttributes(
          phone: e164Phone,
          // Pending contact only; verification still comes from Supabase Auth.
          // Persist it so interrupted onboarding can resume after an app restart.
          data: unverified ? {'mobile_number': e164Phone} : null,
        ),
      );
      if (unverified && _state.currentUser?.email == current.email) {
        _state.setCurrentUser(current.withPendingPhone(e164Phone));
      }
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
      final restored = await restoreProfile(user);
      // Sign-up ends here: the number is proved, now ask for the email.
      if (!restored.emailConfirmed) _mailEmailConfirmation();
      return restored;
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
      // unregister_push_token is granted to signed-in callers only, so it has
      // to go out while the session is still attached. Left to the signedOut
      // listener in main.dart it is sent as anon and refused, and this device
      // keeps receiving the signed-out account's ride notifications. Bounded so
      // a phone with no signal can still sign out.
      await PushNotificationService.unregisterForSession(
        _client,
      ).timeout(const Duration(seconds: 5), onTimeout: () {});
      await _client.auth.signOut();
    } finally {
      await PushNotificationService.clearHistory();
      // Not setCurrentUser(null): that keeps the last destination, booking
      // and trip, which the next account to sign in on this phone would see.
      _state.reset();
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
