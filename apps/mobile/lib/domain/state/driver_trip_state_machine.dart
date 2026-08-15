enum DriverTripStatus {
  offline,
  available,
  incoming,
  accepted,
  arrivedAtPickup,
  inProgress,
  completed,
  declined,
}

class DriverTripStateMachine {
  DriverTripStatus status = DriverTripStatus.offline;

  bool get isOnline => status != DriverTripStatus.offline;

  void goOnline() => _transition(
    allowed: const {DriverTripStatus.offline},
    next: DriverTripStatus.available,
  );

  void goOffline() => _transition(
    allowed: const {DriverTripStatus.available, DriverTripStatus.declined},
    next: DriverTripStatus.offline,
  );

  void receiveRequest() => _transition(
    allowed: const {DriverTripStatus.available},
    next: DriverTripStatus.incoming,
  );

  void acceptRequest() => _transition(
    allowed: const {DriverTripStatus.incoming},
    next: DriverTripStatus.accepted,
  );

  void declineRequest() => _transition(
    allowed: const {DriverTripStatus.incoming},
    next: DriverTripStatus.declined,
  );

  void markArrivedAtPickup() => _transition(
    allowed: const {DriverTripStatus.accepted},
    next: DriverTripStatus.arrivedAtPickup,
  );

  void startTrip() => _transition(
    allowed: const {DriverTripStatus.arrivedAtPickup},
    next: DriverTripStatus.inProgress,
  );

  void completeTrip() => _transition(
    allowed: const {DriverTripStatus.inProgress},
    next: DriverTripStatus.completed,
  );

  void reset() => status = DriverTripStatus.offline;

  void _transition({
    required Set<DriverTripStatus> allowed,
    required DriverTripStatus next,
  }) {
    if (!allowed.contains(status)) {
      throw StateError(
        'Cannot move driver trip from ${status.name} to ${next.name}.',
      );
    }
    status = next;
  }
}
