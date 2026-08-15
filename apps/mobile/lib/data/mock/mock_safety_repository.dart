import '../repositories/safety_repository.dart';
import 'demo_state.dart';

class MockSafetyRepository implements SafetyRepository {
  MockSafetyRepository(this._state);

  final DemoState _state;

  @override
  Future<void> recordDemoAlert() async {
    _state.recordSafetyAlert();
  }
}
