import 'package:arangcada/core/geo/haversine.dart';
import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/remote/supabase_ride_repository.dart';
import 'package:arangcada/domain/models/booking.dart';
import 'package:arangcada/domain/state/driver_trip_state_machine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('location age uses receipt time and preserves it on a replay', () {
    var now = DateTime.utc(2030, 1, 1);
    final state = DemoState(now: () => now);
    addTearDown(state.dispose);
    const coordinate = GeoCoordinate(latitude: 14.2, longitude: 121.1);
    void receive(String version, {String driver = 'driver-1'}) {
      state.recordLiveDriverLocation(
        coordinate,
        driverId: driver,
        updatedAt: version,
      );
    }

    // Server time is deliberately years behind the phone; only identity matters.
    receive('2026-10-14T05:33:57Z');
    final receivedAt = state.liveDriverLocationReceivedAt;
    expect(state.liveDriverLocationAge, Duration.zero);
    now = now.add(const Duration(seconds: 40));
    receive('2026-10-14T05:33:57Z');
    expect(state.liveDriverLocationReceivedAt, receivedAt);
    expect(state.liveDriverLocationAge, const Duration(seconds: 40));

    // A new timestamp is fresh even if the driver's coordinates are unchanged.
    receive('2026-10-14T05:35:09Z');
    expect(state.liveDriverLocationAge, Duration.zero);
    now = now.add(const Duration(seconds: 20));
    receive('2026-10-14T05:35:09Z', driver: 'driver-2');
    expect(state.liveDriverLocationAge, Duration.zero);
  });

  for (final finishTrip in [false, true]) {
    test(
      'clearing location clears its freshness (finish trip: $finishTrip)',
      () {
        final state = DemoState();
        addTearDown(state.dispose);
        state.recordLiveDriverLocation(
          const GeoCoordinate(latitude: 14.2, longitude: 121.1),
          driverId: 'driver-1',
          updatedAt: '2026-10-14T05:33:57Z',
        );
        if (finishTrip) {
          state.driverTrip.status = DriverTripStatus.completed;
          state.finishDriverTrip();
        } else {
          state.reset();
        }
        expect(state.liveDriverLocation, isNull);
        expect(state.liveDriverLocationReceivedAt, isNull);
        expect(state.liveDriverLocationAge, isNull);
      },
    );
  }

  test('server-owned trip statuses map to the existing commuter flow', () {
    expect(
      SupabaseRideRepository.commuterStatusFor('driver_assigned'),
      BookingStatus.searching,
    );
    expect(
      SupabaseRideRepository.commuterStatusFor('accepted'),
      BookingStatus.matched,
    );
    expect(
      SupabaseRideRepository.commuterStatusFor('in_progress'),
      BookingStatus.inProgress,
    );
    expect(
      SupabaseRideRepository.commuterStatusFor('cancelled_by_rider'),
      BookingStatus.cancelled,
    );
  });

  test('server-owned trip statuses map to the existing driver flow', () {
    expect(
      SupabaseRideRepository.driverStatusFor('driver_assigned'),
      DriverTripStatus.incoming,
    );
    expect(
      SupabaseRideRepository.driverStatusFor('arrived'),
      DriverTripStatus.arrivedAtPickup,
    );
    expect(
      SupabaseRideRepository.driverStatusFor('completed'),
      DriverTripStatus.completed,
    );
  });

  test('destination completion countdown starts at 60 seconds', () {
    final reachedAt = DateTime.utc(2026, 8, 25, 10);
    final deadline = reachedAt.add(const Duration(seconds: 60));

    expect(
      SupabaseRideRepository.completionSecondsRemaining(
        deadline,
        now: reachedAt,
      ),
      60,
    );
    expect(
      SupabaseRideRepository.completionSecondsRemaining(
        deadline,
        now: reachedAt.add(const Duration(seconds: 17)),
      ),
      43,
    );
    expect(
      SupabaseRideRepository.completionSecondsRemaining(
        deadline,
        now: reachedAt.add(const Duration(minutes: 2)),
      ),
      0,
    );
  });
}
