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
}
