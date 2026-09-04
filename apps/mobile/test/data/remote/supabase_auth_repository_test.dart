import 'package:arangcada/data/remote/supabase_auth_repository.dart';
import 'package:arangcada/domain/models/demo_user.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('trusted app role selects driver; missing role defaults commuter', () {
    final driver = SupabaseAuthRepository.mapIdentity(
      email: 'driver@example.test',
      displayName: 'Mang Ben',
      appRole: 'driver',
    );
    final commuter = SupabaseAuthRepository.mapIdentity(
      email: 'ana.santos@example.test',
    );

    expect(driver.role, DemoRole.driver);
    expect(driver.displayName, 'Mang Ben');
    expect(commuter.role, DemoRole.commuter);
    expect(commuter.displayName, 'Ana Santos');
  });

  test('authoritative profile role overrides stale auth metadata', () {
    final promotedDriver = SupabaseAuthRepository.mapIdentity(
      email: 'driver@example.test',
      appRole: 'commuter',
      profileRole: 'driver',
    );
    final demotedCommuter = SupabaseAuthRepository.mapIdentity(
      email: 'commuter@example.test',
      appRole: 'driver',
      profileRole: 'commuter',
    );

    expect(promotedDriver.role, DemoRole.driver);
    expect(demotedCommuter.role, DemoRole.commuter);
  });

  test('real commuters can adjust an inaccurate GPS pickup', () {
    final commuter = SupabaseAuthRepository.mapIdentity(
      email: 'commuter@example.test',
      profileRole: 'commuter',
    );

    expect(commuter.canChoosePickup, isTrue);
  });
}
