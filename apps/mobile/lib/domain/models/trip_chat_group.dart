/// Groups only already-authorized, retained trip rows. Names are never identity.
class TripChatGroup {
  TripChatGroup(this.trips);

  final List<Map<String, dynamic>> trips;
  static const activeStatuses = {
    'accepted',
    'driver_en_route',
    'arrived',
    'in_progress',
    'emergency_reported',
  };

  String get id =>
      'pair:${trips.first['rider_id']}:${trips.first['driver_id']}';
  Map<String, dynamic> get current => trips.first;
  bool get active => activeStatuses.contains(current['status']);
  Iterable<String> get tripIds => trips.map((trip) => trip['id'] as String);

  static List<TripChatGroup> retained(
    List<Map<String, dynamic>> rows, {
    DateTime? now,
  }) {
    final cutoff = (now ?? DateTime.now()).toUtc().subtract(
      const Duration(days: 30),
    );
    final pairs = <String, TripChatGroup>{};
    for (final trip in rows) {
      if (trip['rider_id'] == null || trip['driver_id'] == null) continue;
      if (!activeStatuses.contains(trip['status'])) {
        final completed = DateTime.tryParse(
          trip['completed_at'] as String? ?? '',
        );
        if (trip['status'] != 'completed' ||
            completed == null ||
            completed.toUtc().isBefore(cutoff)) {
          continue;
        }
      }
      final key = '${trip['rider_id']}:${trip['driver_id']}';
      (pairs.putIfAbsent(key, () => TripChatGroup([]))).trips.add(trip);
    }
    for (final group in pairs.values) {
      group.trips.sort((a, b) {
        final activeA = activeStatuses.contains(a['status']);
        final activeB = activeStatuses.contains(b['status']);
        if (activeA != activeB) return activeA ? -1 : 1;
        return (b['requested_at'] as String? ?? '').compareTo(
          a['requested_at'] as String? ?? '',
        );
      });
    }
    return pairs.values.toList();
  }
}
