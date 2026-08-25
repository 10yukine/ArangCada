enum DemoRole { commuter, driver }

class DemoUser {
  const DemoUser({
    required this.email,
    required this.displayName,
    required this.role,
    this.isInternalTester = false,
  });

  final String email;
  final String displayName;
  final DemoRole role;
  final bool isInternalTester;

  /// The seeded `@arangcada.demo` accounts, and only those accounts. Used to
  /// gate every walkthrough-only affordance: manual pickup choice, and the
  /// Demo section on App Settings.
  bool get isDemoAccount => email.endsWith('@arangcada.demo');

  /// GPS starts the pickup, but commuters may correct an inaccurate fix.
  /// The server still validates the final point and computes the locked fare.
  bool get canChoosePickup => role == DemoRole.commuter;
}
