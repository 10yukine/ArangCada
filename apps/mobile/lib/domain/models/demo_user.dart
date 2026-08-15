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
}
