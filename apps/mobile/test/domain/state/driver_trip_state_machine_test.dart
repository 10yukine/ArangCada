import 'package:arangcada/domain/state/driver_trip_state_machine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('driver state machine accepts its legal path', () {
    final machine = DriverTripStateMachine()
      ..goOnline()
      ..receiveRequest()
      ..acceptRequest()
      ..markArrivedAtPickup()
      ..startTrip()
      ..completeTrip();

    expect(machine.status, DriverTripStatus.completed);
  });

  test('driver state machine rejects Complete Trip before Start Trip', () {
    final machine = DriverTripStateMachine()
      ..goOnline()
      ..receiveRequest()
      ..acceptRequest();

    expect(machine.completeTrip, throwsStateError);
  });
}
