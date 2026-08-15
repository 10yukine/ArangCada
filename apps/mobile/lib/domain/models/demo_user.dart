enum DemoRole { commuter, driver }

class DemoUser {
  const DemoUser({
    required this.email,
    required this.displayName,
    required this.role,
  });

  final String email;
  final String displayName;
  final DemoRole role;

  /// Only the seeded demo accounts may set a pickup by hand.
  ///
  /// For a real commuter the pickup is the device's location. Allowing a
  /// free choice of origin would let a rider understate the distance the
  /// fare is billed on, so this stays a walkthrough affordance.
  bool get canChoosePickup => email.endsWith('@arangcada.demo');
}
