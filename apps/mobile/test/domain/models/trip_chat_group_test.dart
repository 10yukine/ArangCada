import 'package:arangcada/domain/models/trip_chat_group.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 9, 19);
  Map<String, dynamic> trip(
    String id,
    String driver,
    String status, {
    int age = 1,
    String rider = 'rider',
  }) => {
    'id': id,
    'rider_id': rider,
    'driver_id': driver,
    'status': status,
    'requested_at': now.subtract(Duration(days: age)).toIso8601String(),
    'completed_at': status == 'completed'
        ? now.subtract(Duration(days: age)).toIso8601String()
        : null,
  };
  test(
    'repeat rides share a stable identity, active ride owns new messages',
    () {
      final old = trip('old', 'driver', 'completed', age: 10);
      final first = TripChatGroup.retained([old], now: now).single;
      final groups = TripChatGroup.retained([
        old,
        trip('new', 'driver', 'accepted'),
        trip('different-driver', 'driver-2', 'completed'),
        trip('different-rider', 'driver', 'completed', rider: 'rider-2'),
      ], now: now);
      expect(groups.length, 3);
      expect(groups.first.id, first.id);
      expect(groups.first.tripIds, ['new', 'old']);
      expect(groups.first.active, isTrue);
      expect(first.active, isFalse);
    },
  );
  test(
    'new rides never extend expired history and unaccepted trips are hidden',
    () {
      final groups = TripChatGroup.retained([
        trip('expired', 'driver', 'completed', age: 31),
        trip('retained', 'driver', 'completed', age: 29),
        trip('active', 'driver', 'in_progress'),
        trip('unaccepted', 'other', 'driver_assigned'),
        trip('cancelled', 'other', 'cancelled_by_driver'),
        {...trip('no-driver', 'other', 'accepted'), 'driver_id': null},
      ], now: now);
      expect(groups.single.tripIds, ['active', 'retained']);
      expect(
        TripChatGroup.retained([
          trip('expired-only', 'driver', 'completed', age: 31),
        ], now: now),
        isEmpty,
      );
    },
  );
}
