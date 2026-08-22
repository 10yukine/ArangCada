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

  test('finishTrip returns a completed driver to available', () {
    // Before finishTrip existed, `completed` had no way out at all:
    // goOffline()'s allowed set does not include it, so a driver who
    // returned to Home after a trip was stuck there with a
    // non-functional online toggle. This pins the fix.
    final machine = DriverTripStateMachine()
      ..goOnline()
      ..receiveRequest()
      ..acceptRequest()
      ..markArrivedAtPickup()
      ..startTrip()
      ..completeTrip()
      ..finishTrip();

    expect(machine.status, DriverTripStatus.available);
    expect(machine.isOnline, isTrue);
  });

  test('finishTrip rejects being called from any status but completed', () {
    final machine = DriverTripStateMachine()..goOnline();
    expect(machine.finishTrip, throwsStateError);
  });

  test('a driver can go offline immediately after finishing a trip', () {
    // The whole point of finishTrip: the online toggle must work again.
    final machine = DriverTripStateMachine()
      ..goOnline()
      ..receiveRequest()
      ..acceptRequest()
      ..markArrivedAtPickup()
      ..startTrip()
      ..completeTrip()
      ..finishTrip()
      ..goOffline();

    expect(machine.status, DriverTripStatus.offline);
  });
}
