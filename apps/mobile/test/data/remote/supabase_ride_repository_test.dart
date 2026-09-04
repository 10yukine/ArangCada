import 'package:arangcada/data/remote/supabase_ride_repository.dart';
import 'package:arangcada/domain/models/booking.dart';
import 'package:arangcada/domain/state/driver_trip_state_machine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
