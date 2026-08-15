import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/mock/mock_auth_repository.dart';
import 'package:arangcada/domain/models/demo_user.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('both demo accounts sign in by role and can sign out', () async {
    final state = DemoState();
    final repository = MockAuthRepository(state);

    final commuter = await repository.signIn(
      email: 'commuter@arangcada.demo',
      password: 'demo1234',
    );
    expect(commuter.role, DemoRole.commuter);

    await repository.signOut();
    expect(repository.currentUser, isNull);

    final driver = await repository.signIn(
      email: 'driver@arangcada.demo',
      password: 'demo1234',
    );
    expect(driver.role, DemoRole.driver);
    state.dispose();
  });
}
