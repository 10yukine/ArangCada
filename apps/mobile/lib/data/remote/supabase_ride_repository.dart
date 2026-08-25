import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/geo/haversine.dart';
import '../../demo/demo_data.dart';
import '../../domain/fare/fare_calculator.dart';
import '../../domain/fare/fare_matrix.dart';
import '../../domain/models/booking.dart';
import '../../domain/models/demo_user.dart';
import '../../domain/models/driver_app_feedback.dart';
import '../../domain/state/driver_trip_state_machine.dart';
import '../mock/demo_state.dart';
import '../repositories/fare_repository.dart';
import '../repositories/location_repository.dart';

/// Mirrors server-authoritative ride rows into the existing mobile screens.
///
/// Critical writes always call a guarded SQL RPC; the client never patches a
/// trip, an approval, a fare, or a feedback obligation directly.
class SupabaseRideRepository extends ChangeNotifier {
  SupabaseRideRepository(
    this._client,
    this._state,
    this._location,
    this._fares,
  ) {
    _subscribeToTrips();
    if (_isDriver) {
      unawaited(refreshFeedbackState());
      _subscribeToAvailability(_userId);
    }
  }

  static const completionWindow = Duration(seconds: 60);
  static const _uuid = Uuid();

  final SupabaseClient _client;
  final DemoState _state;
  final LocationRepository _location;
  final FareRepository _fares;
  final Map<DemoBooking, String> _bookingKeys = {};

  StreamSubscription<List<Map<String, dynamic>>>? _tripSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _locationSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _feedbackSubscription;
  Timer? _locationTicker;
  bool _publishingLocation = false;
  bool _disposed = false;
  List<Map<String, dynamic>> _trips = const [];
  Map<String, dynamic>? _activeTrip;
  String? _connectionError;

  bool get _isDriver => _state.currentUser?.role == DemoRole.driver;
  String get _userId => _client.auth.currentUser!.id;
  String? get connectionError => _connectionError;
  Map<String, dynamic>? get activeTrip => _activeTrip;
  List<Map<String, dynamic>> get trips => List.unmodifiable(_trips);

  static BookingStatus commuterStatusFor(
    String status, {
    BookingStatus? previous,
  }) => switch (status) {
    'requested' ||
    'searching_driver' ||
    'driver_assigned' => BookingStatus.searching,
    'accepted' || 'driver_en_route' =>
      previous == BookingStatus.approaching
          ? BookingStatus.approaching
          : BookingStatus.matched,
    'arrived' => BookingStatus.approaching,
    'in_progress' || 'emergency_reported' => BookingStatus.inProgress,
    'completed' => BookingStatus.completed,
    'cancelled_by_rider' ||
    'cancelled_by_driver' ||
    'no_driver_available' => BookingStatus.cancelled,
    _ => throw ArgumentError.value(status, 'status', 'Unknown trip status'),
  };

  static DriverTripStatus? driverStatusFor(String status) => switch (status) {
    'driver_assigned' => DriverTripStatus.incoming,
    'accepted' || 'driver_en_route' => DriverTripStatus.accepted,
    'arrived' => DriverTripStatus.arrivedAtPickup,
    'in_progress' || 'emergency_reported' => DriverTripStatus.inProgress,
    'completed' => DriverTripStatus.completed,
    'cancelled_by_driver' => DriverTripStatus.declined,
    'cancelled_by_rider' || 'no_driver_available' => DriverTripStatus.available,
    'requested' || 'searching_driver' => null,
    _ => throw ArgumentError.value(status, 'status', 'Unknown trip status'),
  };

  static int completionSecondsRemaining(DateTime deadline, {DateTime? now}) {
    final remaining = deadline.difference(now ?? DateTime.now().toUtc());
    return remaining.inSeconds.clamp(0, completionWindow.inSeconds);
  }

  void _subscribeToTrips() {
    final ownerColumn = _isDriver ? 'driver_id' : 'rider_id';
    _tripSubscription = _client
        .from('trips')
        .stream(primaryKey: ['id'])
        .eq(ownerColumn, _userId)
        .order('requested_at', ascending: false)
        .listen(_receiveTrips, onError: _recordError);

    if (_isDriver) {
      _feedbackSubscription = _client
          .from('driver_feedback_obligations')
          .stream(primaryKey: ['trip_id'])
          .eq('driver_id', _userId)
          .listen(
            (_) => unawaited(refreshFeedbackState()),
            onError: _recordError,
          );
    }
  }

  void _receiveTrips(List<Map<String, dynamic>> rows) {
    if (_disposed) return;
    _trips = List.unmodifiable(rows);
    Map<String, dynamic>? selected;
    for (final trip in rows) {
      final status = trip['status'] as String?;
      if (status != null &&
          status != 'completed' &&
          status != 'cancelled_by_rider' &&
          status != 'cancelled_by_driver' &&
          status != 'no_driver_available') {
        selected = trip;
        break;
      }
    }
    if (selected == null && rows.isNotEmpty) {
      final latest = rows.first;
      if (latest['id'] == _state.liveTripId ||
          latest['id'] == _state.pendingFeedbackTripId) {
        selected = latest;
      }
    }
    if (selected != null) {
      _applyTrip(selected);
      return;
    }
    notifyListeners();
  }

  void _applyTrip(Map<String, dynamic> trip) {
    if (_disposed) return;
    final tripId = trip['id'] as String;
    final existingIndex = _trips.indexWhere((row) => row['id'] == tripId);
    if (existingIndex < 0) {
      _trips = [Map.unmodifiable(trip), ..._trips];
    } else {
      _trips = [..._trips]..[existingIndex] = Map.unmodifiable(trip);
    }
    final oldDriverId = _activeTrip?['driver_id'] as String?;
    _activeTrip = Map.unmodifiable(trip);
    _state.liveTripId = trip['id'] as String;
    _state.liveDriverName = trip['driver_display_name'] as String?;
    _state.liveCommuterName = trip['rider_display_name'] as String?;
    _state.liveTodaName = trip['toda_name'] as String?;
    final completion = trip['completion_available_at'] as String?;
    _state.completionAvailableAt = completion == null
        ? null
        : DateTime.tryParse(completion)?.toUtc();

    final pickup = _coordinate(trip, 'pickup');
    final destination = _coordinate(trip, 'destination');
    if (pickup != null) {
      _state.pickup = DemoPlace(
        id: 'live-pickup-${trip['id']}',
        name: trip['pickup_label'] as String? ?? 'Pickup',
        address: 'Live trip pickup',
        coordinate: pickup,
      );
    }
    if (destination != null) {
      _state.destination = DemoPlace(
        id: 'live-destination-${trip['id']}',
        name: trip['destination_label'] as String? ?? 'Destination',
        address: 'Live trip destination',
        coordinate: destination,
      );
    }

    final status = trip['status'] as String;
    if (_isDriver) {
      final next = driverStatusFor(status);
      if (next != null) _state.driverTrip.status = next;
      if (status == 'completed') unawaited(refreshFeedbackState());
    } else {
      final booking = _state.activeBooking ?? _restoreBooking(trip);
      booking.status = commuterStatusFor(status, previous: booking.status);
      if (status == 'completed') {
        booking.receiptReference = 'TRIP-${trip['id']}';
      }
      final driverId = trip['driver_id'] as String?;
      if (driverId != null && driverId != oldDriverId) {
        _subscribeToAvailability(driverId);
      }
    }
    _state.bookingChanged();
    notifyListeners();
  }

  DemoBooking _restoreBooking(Map<String, dynamic> trip) {
    final destination = _state.destination;
    if (destination == null) {
      throw StateError('The live trip has no valid destination.');
    }
    final localQuote = _fares.quote(
      distanceMeters: haversineDistanceMeters(
        _state.pickup.coordinate,
        destination.coordinate,
      ),
      rideType: RideType.special,
      passengerCount: 1,
      discountClass: DiscountClass.full,
    );
    final serverPesos = trip['final_fare'] ?? trip['fare_estimate'];
    final serverCentavos = serverPesos == null
        ? localQuote.partyTotalCentavos
        : ((serverPesos as num).toDouble() * 100).round();
    final quote = FareQuote(
      unitFareCentavos: serverCentavos,
      partyTotalCentavos: serverCentavos,
      farePerPassengerCentavos: null,
      baseFareCentavos: localQuote.baseFareCentavos,
      additionalDistanceCentavos: serverCentavos - localQuote.baseFareCentavos,
      distanceMeters: localQuote.distanceMeters,
      chargeableKm: localQuote.chargeableKm,
      rideType: RideType.special,
      passengerCount: 1,
      discountClass: DiscountClass.full,
      fareMatrixVersion: localQuote.fareMatrixVersion,
      createdAt: DateTime.now().toUtc(),
    );
    final booking = DemoBooking.draft(
      pickupName: _state.pickup.name,
      destinationName: destination.name,
      rideType: RideType.special,
      passengerCount: 1,
      userFareClass: UserFareClass.regular,
      paymentMethod: PaymentMethod.cash,
      fareQuote: quote,
    );
    _state.activeBooking = booking;
    return booking;
  }

  GeoCoordinate? _coordinate(Map<String, dynamic> row, String prefix) {
    final lat = row['${prefix}_lat'] as num?;
    final lng = row['${prefix}_lng'] as num?;
    if (lat == null || lng == null) return null;
    return GeoCoordinate(latitude: lat.toDouble(), longitude: lng.toDouble());
  }

  void _subscribeToAvailability(String driverId) {
    unawaited(_locationSubscription?.cancel());
    _locationSubscription = _client
        .from('driver_availability')
        .stream(primaryKey: ['driver_id'])
        .eq('driver_id', driverId)
        .listen((rows) {
          if (_disposed || rows.isEmpty) return;
          final row = rows.first;
          final latitude = row['latitude'] as num?;
          final longitude = row['longitude'] as num?;
          if (latitude != null && longitude != null) {
            _state.liveDriverLocation = GeoCoordinate(
              latitude: latitude.toDouble(),
              longitude: longitude.toDouble(),
            );
          }
          if (_isDriver &&
              _activeTrip == null &&
              _state.driverTrip.status != DriverTripStatus.incoming) {
            _state.driverTrip.status = row['is_online'] == true
                ? DriverTripStatus.available
                : DriverTripStatus.offline;
          }
          _state.driverChanged();
          notifyListeners();
        }, onError: _recordError);
  }

  Future<void> requestRide(DemoBooking booking) async {
    if (booking.rideType != RideType.special ||
        booking.paymentMethod != PaymentMethod.cash) {
      throw StateError(
        'Connected testing currently supports Special + Cash only.',
      );
    }
    final destination = _state.destination;
    if (destination == null) throw StateError('Choose a destination first.');
    final idempotencyKey = _bookingKeys.putIfAbsent(booking, _uuid.v4);
    final result = await _client.rpc(
      'request_ride',
      params: {
        'p_pickup_lat': _state.pickup.coordinate.latitude,
        'p_pickup_lng': _state.pickup.coordinate.longitude,
        'p_destination_lat': destination.coordinate.latitude,
        'p_destination_lng': destination.coordinate.longitude,
        'p_pickup_label': _state.pickup.name,
        'p_destination_label': destination.name,
        'p_idempotency_key': idempotencyKey,
      },
    );
    _applyTrip(_row(result));
  }

  Future<void> setDriverOnline(bool online) async {
    if (online && _state.driverFeedbackPending) {
      throw StateError(
        'Complete your required app feedback before going online.',
      );
    }
    LocationFix? fix;
    if (online) fix = await _location.currentLocation();
    final coordinate =
        fix?.coordinate ??
        _state.liveDriverLocation ??
        _state.pickup.coordinate;
    final result = await _client.rpc(
      'set_driver_availability',
      params: {
        'p_online': online,
        'p_lat': coordinate.latitude,
        'p_lng': coordinate.longitude,
      },
    );
    final row = _row(result);
    _state.liveDriverLocation = GeoCoordinate(
      latitude: (row['latitude'] as num).toDouble(),
      longitude: (row['longitude'] as num).toDouble(),
    );
    _state.driverTrip.status = online
        ? DriverTripStatus.available
        : DriverTripStatus.offline;
    _state.driverChanged();
    if (online) {
      _startLocationUpdates();
    } else {
      _locationTicker?.cancel();
    }
    notifyListeners();
  }

  Future<void> acceptRide() => _tripAction('accept_ride');
  Future<void> declineRide() => _tripAction('decline_ride');
  Future<void> expireRide() => _tripAction('expire_ride');
  Future<void> cancelRide() => _tripAction('cancel_ride');
  Future<void> markArrived() => _tripAction('mark_arrived');
  Future<void> startTrip() => _tripAction('start_trip');
  Future<void> completeTrip() => _tripAction('complete_trip');

  Future<void> _tripAction(String name) async {
    final tripId = _state.liveTripId;
    if (tripId == null) throw StateError('There is no active server trip.');
    final result = await _client.rpc(name, params: {'p_trip_id': tripId});
    _applyTrip(_row(result));
    if (name == 'accept_ride' || name == 'start_trip') _startLocationUpdates();
    if (name == 'complete_trip' || name == 'cancel_ride') {
      _locationTicker?.cancel();
    }
  }

  void _startLocationUpdates() {
    if (!_isDriver) return;
    unawaited(_publishLocation());
    _scheduleNextLocationUpdate();
  }

  /// Adaptive publish cadence instead of one fixed interval: a driver just
  /// waiting online costs battery and database writes for no dispatch
  /// benefit, while an approaching or in-progress trip needs a tighter fix
  /// so the rider sees a responsive marker. Self-reschedules each cycle so
  /// the interval always reflects the current trip status.
  Duration _locationInterval() {
    switch (_state.driverTrip.status) {
      case DriverTripStatus.accepted:
      case DriverTripStatus.arrivedAtPickup:
        return const Duration(seconds: 5);
      case DriverTripStatus.inProgress:
        return const Duration(seconds: 4);
      case DriverTripStatus.available:
      default:
        return const Duration(seconds: 15);
    }
  }

  void _scheduleNextLocationUpdate() {
    _locationTicker?.cancel();
    if (_disposed || !_state.driverTrip.isOnline) return;
    _locationTicker = Timer(_locationInterval(), () async {
      await _publishLocation();
      _scheduleNextLocationUpdate();
    });
  }

  Future<void> _publishLocation() async {
    if (_publishingLocation || _disposed) return;
    _publishingLocation = true;
    try {
      final fix = await _location.currentLocation();
      if (_disposed || !_state.driverTrip.isOnline) return;
      final tripId = _state.liveTripId;
      if (tripId == null ||
          _state.driverTrip.status == DriverTripStatus.available) {
        await _client.rpc(
          'set_driver_availability',
          params: {
            'p_online': true,
            'p_lat': fix.coordinate.latitude,
            'p_lng': fix.coordinate.longitude,
          },
        );
      } else {
        await _client.rpc(
          'publish_driver_location',
          params: {
            'p_trip_id': tripId,
            'p_lat': fix.coordinate.latitude,
            'p_lng': fix.coordinate.longitude,
            'p_accuracy_meters': fix.accuracyMeters,
          },
        );
      }
    } on Exception {
      // A missed foreground GPS fix must not end or rewrite the server trip.
    } finally {
      _publishingLocation = false;
    }
  }

  Future<void> refreshFeedbackState() async {
    if (!_isDriver || _disposed) return;
    try {
      final result = await _client.rpc('get_driver_feedback_state');
      final row = _row(result);
      _state.driverFeedbackPending = row['pending'] == true;
      _state.pendingFeedbackTripId = row['pending_trip_id'] as String?;
      if (_state.driverFeedbackPending && _trips.isNotEmpty) {
        final index = _trips.indexWhere(
          (trip) => trip['id'] == _state.pendingFeedbackTripId,
        );
        if (index >= 0 && _activeTrip?['id'] != _state.pendingFeedbackTripId) {
          _applyTrip(_trips[index]);
          return;
        }
      }
      _state.driverChanged();
      notifyListeners();
    } on Exception catch (error) {
      _recordError(error);
    }
  }

  Future<void> submitDriverFeedback({
    required Map<String, int> answers,
    required bool anonymous,
    String? comment,
  }) async {
    if (!DriverAppFeedback.hasValidAnswers(answers)) {
      throw StateError('Answer every app-feedback question from 1 to 5.');
    }
    final tripId = _state.pendingFeedbackTripId ?? _state.liveTripId;
    if (tripId == null) throw StateError('No completed trip needs feedback.');
    final trimmed = comment?.trim();
    if (trimmed != null && trimmed.length > 500) {
      throw StateError('Feedback comments cannot exceed 500 characters.');
    }
    await _client.rpc(
      'submit_driver_feedback',
      params: {
        'p_trip_id': tripId,
        'p_answers': answers,
        'p_comment': trimmed == null || trimmed.isEmpty ? null : trimmed,
        'p_anonymous': anonymous,
      },
    );
    _state.driverFeedbackPending = false;
    _state.pendingFeedbackTripId = null;
    _activeTrip = null;
    if (_state.driverTrip.status == DriverTripStatus.completed) {
      _state.finishDriverTrip();
    } else {
      _state.driverTrip.status = DriverTripStatus.available;
      _state.driverChanged();
    }
    _startLocationUpdates();
    notifyListeners();
  }

  Future<void> createSafetyReport(String reason) async {
    final tripId = _state.liveTripId;
    if (tripId == null) {
      throw StateError('Safety reports require an active trip.');
    }
    LocationFix? fix;
    try {
      fix = await _location.currentLocation();
    } on LocationFailure {
      // A safety report must still be delivered if GPS is temporarily denied.
    }
    await _client.rpc(
      'create_sos_report',
      params: {
        'p_trip_id': tripId,
        'p_reason': reason,
        'p_lat': fix?.coordinate.latitude,
        'p_lng': fix?.coordinate.longitude,
        'p_accuracy_meters': fix?.accuracyMeters,
        'p_idempotency_key': _uuid.v4(),
      },
    );
  }

  Future<void> reportTripChat({
    required String tripId,
    required String reason,
  }) async {
    if (reason.trim().isEmpty) {
      throw StateError('Describe why this conversation is being reported.');
    }
    await _client.rpc(
      'report_trip_chat',
      params: {
        'p_trip_id': tripId,
        'p_reason': reason.trim(),
        'p_consent': true,
      },
    );
  }

  Map<String, dynamic> _row(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is List && value.isNotEmpty && value.first is Map) {
      return Map<String, dynamic>.from(value.first as Map);
    }
    throw const FormatException('The server returned an invalid response.');
  }

  void _recordError(Object error) {
    if (_disposed) return;
    _connectionError = 'Live trip updates are temporarily unavailable.';
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _locationTicker?.cancel();
    unawaited(_tripSubscription?.cancel());
    unawaited(_locationSubscription?.cancel());
    unawaited(_feedbackSubscription?.cancel());
    super.dispose();
  }
}
