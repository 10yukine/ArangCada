enum DemoRole { commuter, driver }

class DemoUser {
  const DemoUser({
    required this.email,
    required this.displayName,
    required this.role,
    this.isInternalTester = false,
    this.isAdminAccount = false,
    this.mobileNumber,
    this.phoneVerified = false,
    this.avatarUrl,
  });

  final String email;
  final String displayName;
  final DemoRole role;
  final bool isInternalTester;

  /// Server-resolved account type, used for mobile onboarding only.
  /// Admin capabilities remain on the website.
  final bool isAdminAccount;

  /// E.164, as stored on the account. Null when the account predates phone
  /// collection or the number was never set.
  final String? mobileNumber;

  /// Whether SMS OTP has proved control of [mobileNumber].
  ///
  /// This mirrors `profiles.phone_verified_at` and is used only to decide which
  /// screen to show. It is **not** the access control: `request_ride`,
  /// `can_driver_go_online` and `create_ride_share_link` each enforce
  /// verification server-side, so a tampered client that forces this to true
  /// still cannot book, drive, or share a link.
  final bool phoneVerified;

  /// A freshly minted signed URL into the `profile-photos` bucket, valid
  /// for longer than the app stays open, or null when the account has no
  /// photo yet. Never persisted --
  /// `profiles.avatar_path` (the Storage path) is what is stored; this is
  /// re-minted every time the profile is (re)loaded,.
  final String? avatarUrl;

  /// [displayName] and [avatarUrl]/[avatarPath] are the only fields a user
  /// may change themselves: `profiles` grants UPDATE on
  /// (display_name, phone, avatar_path) to authenticated, and a trigger
  /// blocks role and status outright. Widen these when the server permits
  /// more, not before -- a copyWith that can express changes the database
  /// will reject is a trap.
  DemoUser copyWithDisplayName(String value) => DemoUser(
    email: email,
    displayName: value,
    role: role,
    isInternalTester: isInternalTester,
    isAdminAccount: isAdminAccount,
    mobileNumber: mobileNumber,
    phoneVerified: phoneVerified,
    avatarUrl: avatarUrl,
  );

  DemoUser copyWithAvatarUrl(String? value) => DemoUser(
    email: email,
    displayName: displayName,
    role: role,
    isInternalTester: isInternalTester,
    isAdminAccount: isAdminAccount,
    mobileNumber: mobileNumber,
    phoneVerified: phoneVerified,
    avatarUrl: value,
  );

  DemoUser withPendingPhone(String number) => DemoUser(
    email: email,
    displayName: displayName,
    role: role,
    isInternalTester: isInternalTester,
    isAdminAccount: isAdminAccount,
    mobileNumber: number,
    phoneVerified: false,
    avatarUrl: avatarUrl,
  );

  bool get needsPhoneSetup =>
      needsPhoneVerification &&
      (mobileNumber == null || mobileNumber!.trim().isEmpty);

  /// True when the app should hold this account on the verify screen.
  ///
  /// Internal testers are exempt because the hidden `@arangcada.demo` accounts
  /// have no real SIM behind them. The same exemption exists server-side, and
  /// `is_internal_tester` is not self-service -- the profiles privilege guard
  /// stops an ordinary account granting itself the flag.
  bool get needsPhoneVerification =>
      !phoneVerified && (isAdminAccount || !isInternalTester);

  /// The seeded `@arangcada.demo` accounts, and only those accounts. Used to
  /// gate walkthrough-only affordances in App Settings.
  bool get isDemoAccount => email.endsWith('@arangcada.demo');

  /// GPS starts the pickup, but commuters may correct an inaccurate fix.
  /// The server still validates the final point and computes the locked fare.
  bool get canChoosePickup => role == DemoRole.commuter;
}
