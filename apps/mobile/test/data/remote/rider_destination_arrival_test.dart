import 'dart:async';
import 'dart:convert';

import 'package:arangcada/core/geo/haversine.dart';
import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/mock/mock_fare_repository.dart';
import 'package:arangcada/data/remote/supabase_ride_repository.dart';
import 'package:arangcada/data/repositories/location_repository.dart';
import 'package:arangcada/demo/demo_data.dart';
import 'package:arangcada/domain/fare/fare_matrix.dart';
import 'package:arangcada/domain/models/booking.dart';
import 'package:arangcada/domain/models/demo_user.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Gps implements LocationRepository {
  bool permitted = true;
  double accuracy = 12;
  GeoCoordinate coordinate = DemoData.places.first.coordinate;
  Future<LocationFix>? pending;
  int calls = 0;

  LocationFix get fix => LocationFix(
    coordinate: coordinate,
    accuracyMeters: accuracy,
    timestamp: DateTime.now(),
  );
  @override
  Future<bool> hasPermission() async => permitted;
  @override
  Future<LocationFix> currentLocation() async {
    calls++;
    return pending ?? fix;
  }
}

void main() {
  late SupabaseClient client;
  late DemoState state;
  late SupabaseRideRepository rides;
  late _Gps gps;
  late DateTime now;
  late List<Map<String, dynamic>> reports;
  bool unsupported = false;

  setUp(() async {
    now = DateTime.utc(2026, 10, 14, 6);
    reports = [];
    unsupported = false;
    gps = _Gps();
    client = SupabaseClient(
      'https://example.test',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      realtimeClientOptions: RealtimeClientOptions(
        transport: (_, _) => throw StateError('no realtime in tests'),
      ),
      httpClient: MockClient((request) async {
        Object? data = [];
        var status = 200;
        if (request.url.path.endsWith('/token')) {
          data = {
            'access_token': 'test-token',
            'refresh_token': 'test-refresh',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': 'rider',
              'email': 'rider@example.test',
              'aud': 'authenticated',
              'role': 'authenticated',
              'app_metadata': {},
              'user_metadata': {},
              'created_at': '2026-09-01T00:00:00Z',
            },
          };
        } else if (request.url.path.endsWith(
          '/rpc/rider_reached_destination',
        )) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          reports.add(body);
          if (unsupported) {
            status = 404;
            data = {'code': 'PGRST202', 'message': 'RPC not deployed'};
          } else {
            data = {
              'id': body['p_trip_id'],
              'status': 'in_progress',
              'completion_available_at': now
                  .add(const Duration(seconds: 60))
                  .toIso8601String(),
            };
          }
        }
        return http.Response(
          jsonEncode(data),
          status,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    await client.auth.signInWithPassword(
      email: 'rider@example.test',
      password: 'test',
    );
    state = DemoState(
      now: () => now,
      initialUser: const DemoUser(
        email: 'rider@example.test',
        displayName: 'Commuter',
        role: DemoRole.commuter,
      ),
    );
    state.setDestination(DemoData.places.first);
    final booking = DemoBooking.draft(
      pickupName: 'Pickup',
      destinationName: state.destination!.name,
      rideType: RideType.special,
      passengerCount: 1,
      userFareClass: UserFareClass.regular,
      paymentMethod: PaymentMethod.cash,
      fareQuote: const MockFareRepository().quote(
        distanceMeters: 3000,
        rideType: RideType.special,
        passengerCount: 1,
        discountClass: DiscountClass.full,
      ),
    )..status = BookingStatus.inProgress;
    state.setActiveBooking(booking);
    state.liveTripId = 'trip-1';
    state.recordLiveDriverLocation(
      gps.coordinate,
      driverId: 'driver-1',
      updatedAt: 'v1',
    );
    rides = SupabaseRideRepository(
      client,
      state,
      gps,
      const MockFareRepository(),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  tearDown(() async {
    rides.dispose();
    state.dispose();
    await client.dispose();
  });

  test(
    'fresh GPS does nothing; stale GPS reports once per trip and applies arrival',
    () async {
      await rides.checkRiderDestinationArrival();
      now = now.add(const Duration(seconds: 30));
      await rides.checkRiderDestinationArrival();
      expect(gps.calls, 0);
      now = now.add(const Duration(seconds: 1));
      await rides.checkRiderDestinationArrival();
      expect(reports, hasLength(1));
      expect(reports.single, {
        'p_trip_id': 'trip-1',
        'p_lat': gps.coordinate.latitude,
        'p_lng': gps.coordinate.longitude,
        'p_accuracy_meters': 12,
      });
      expect(state.completionAvailableAt, now.add(const Duration(seconds: 60)));
      await rides.checkRiderDestinationArrival();
      expect(reports, hasLength(1));
      state.completionAvailableAt = null;
      await rides.checkRiderDestinationArrival();
      expect(reports, hasLength(1));
      state.liveTripId = 'trip-2';
      await rides.checkRiderDestinationArrival();
      expect(reports, hasLength(2));
    },
  );

  test('an unavailable RPC is quiet and retried on the next check', () async {
    now = now.add(const Duration(seconds: 31));
    unsupported = true;
    final error = rides.connectionError;
    await rides.checkRiderDestinationArrival();
    expect(state.completionAvailableAt, isNull);
    expect(rides.connectionError, error);
    unsupported = false;
    await rides.checkRiderDestinationArrival();
    expect(reports, hasLength(2));
    expect(state.completionAvailableAt, isNotNull);
  });

  test('coarse or distant GPS never reports arrival', () async {
    now = now.add(const Duration(seconds: 31));
    gps.accuracy = 51;
    await rides.checkRiderDestinationArrival();
    gps.accuracy = 12;
    gps.coordinate = const GeoCoordinate(latitude: 0, longitude: 0);
    await rides.checkRiderDestinationArrival();
    expect(reports, isEmpty);
  });

  test('no permission does not request GPS or report arrival', () async {
    now = now.add(const Duration(seconds: 31));
    gps.permitted = false;
    await rides.checkRiderDestinationArrival();
    expect(gps.calls, 0);
    expect(reports, isEmpty);
  });

  test('completed trips and drivers never use the fallback', () async {
    now = now.add(const Duration(seconds: 31));
    state.activeBooking!.status = BookingStatus.completed;
    await rides.checkRiderDestinationArrival();
    state.activeBooking!.status = BookingStatus.inProgress;
    state.setCurrentUser(
      const DemoUser(
        email: 'driver@example.test',
        displayName: 'Driver',
        role: DemoRole.driver,
      ),
    );
    await rides.checkRiderDestinationArrival();
    expect(gps.calls, 0);
    expect(reports, isEmpty);
  });

  test(
    'overlapping checks and a fresh driver update during GPS do not report',
    () async {
      now = now.add(const Duration(seconds: 31));
      final fix = Completer<LocationFix>();
      gps.pending = fix.future;
      final pending = rides.checkRiderDestinationArrival();
      await Future<void>.delayed(Duration.zero);
      await rides.checkRiderDestinationArrival();
      expect(gps.calls, 1);
      state.recordLiveDriverLocation(
        gps.coordinate,
        driverId: 'driver-1',
        updatedAt: 'v2',
      );
      fix.complete(gps.fix);
      await pending;
      expect(reports, isEmpty);
    },
  );
}
