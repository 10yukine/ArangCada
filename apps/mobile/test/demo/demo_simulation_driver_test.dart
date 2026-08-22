import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/demo/demo_simulation.dart';
import 'package:arangcada/domain/state/driver_trip_state_machine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DemoState state;
  late DemoSimulationService service;

  setUp(() {
    state = DemoState();
    service = DemoSimulationService();
  });

  tearDown(() => service.dispose());

  group('forceDriverIncomingRequest', () {
    test('delivers a request immediately when the driver is available', () {
      state.driverTrip.goOnline();
      expect(state.driverTrip.status, DriverTripStatus.available);

      final advanced = service.forceDriverIncomingRequest(state);

      expect(advanced, isTrue);
      expect(state.driverTrip.status, DriverTripStatus.incoming);
    });

    test('does nothing when the driver is not available', () {
      expect(state.driverTrip.status, DriverTripStatus.offline);

      final advanced = service.forceDriverIncomingRequest(state);

      expect(advanced, isFalse);
      expect(state.driverTrip.status, DriverTripStatus.offline);
    });
  });

  group('forceResetDriverSession', () {
    test('resets a mid-trip driver back to offline', () {
      state.driverTrip
        ..goOnline()
        ..receiveRequest()
        ..acceptRequest();

      final advanced = service.forceResetDriverSession(state);

      expect(advanced, isTrue);
      expect(state.driverTrip.status, DriverTripStatus.offline);
    });

    test('reports no change when already offline', () {
      final advanced = service.forceResetDriverSession(state);
      expect(advanced, isFalse);
    });
  });

  group('DemoState driver rating', () {
    void completeATrip() => state.driverTrip
      ..goOnline()
      ..receiveRequest()
      ..acceptRequest()
      ..markArrivedAtPickup()
      ..startTrip()
      ..completeTrip();

    test('submitDriverTripRating requires a completed trip', () {
      expect(
        () => state.submitDriverTripRating(5, null),
        throwsStateError,
      );
    });

    test('submitDriverTripRating records stars and an optional comment', () {
      completeATrip();

      state.submitDriverTripRating(4, 'Polite passenger');

      expect(state.driverTripRating, 4);
      expect(state.driverTripRatingComment, 'Polite passenger');
    });

    test('finishDriverTrip clears the rating and returns to available', () {
      completeATrip();
      state.submitDriverTripRating(5, null);

      state.finishDriverTrip();

      expect(state.driverTrip.status, DriverTripStatus.available);
      expect(state.driverTripRating, isNull);
      expect(state.driverTripRatingComment, isNull);
    });
  });
}
