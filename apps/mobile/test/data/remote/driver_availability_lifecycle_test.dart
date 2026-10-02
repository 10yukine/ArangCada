import 'dart:convert';

import 'package:arangcada/core/geo/haversine.dart';
import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/mock/mock_fare_repository.dart';
import 'package:arangcada/data/remote/supabase_ride_repository.dart';
import 'package:arangcada/data/repositories/location_repository.dart';
import 'package:arangcada/domain/models/demo_user.dart';
import 'package:arangcada/domain/state/driver_trip_state_machine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Gps implements LocationRepository {
  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<LocationFix> currentLocation() async => LocationFix(
    coordinate: const GeoCoordinate(latitude: 14.2160, longitude: 121.1660),
    accuracyMeters: 12,
    timestamp: DateTime.now(),
  );
}

// complete_trip sets the driver offline on the server. The app used to keep
// showing Online and never told the server otherwise, so a driver who finished
// a trip silently stopped receiving offers.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  late SupabaseClient client;
  late DemoState state;
  late SupabaseRideRepository rides;
  late List<Map<String, dynamic>> heartbeats;
  // SQLSTATE the server answers set_driver_availability with, from the n-th
  // call on; null accepts every call.
  String? refuseWith;
  var refuseFrom = 0;

  setUp(() async {
    heartbeats = [];
    refuseWith = null;
    refuseFrom = 0;
    client = SupabaseClient(
      'https://example.test',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        dynamic data = [];
        var status = 200;
        final path = request.url.path;
        if (path.endsWith('/token')) {
          data = {
            'access_token': 'test-token',
            'refresh_token': 'test-refresh',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': 'driver',
              'email': 'driver@example.test',
              'aud': 'authenticated',
              'role': 'authenticated',
              'app_metadata': {},
              'user_metadata': {},
              'created_at': '2026-09-01T00:00:00Z',
            },
          };
        } else if (path.endsWith('/rpc/get_driver_feedback_state')) {
          data = {'pending': false, 'pending_trip_id': null};
        } else if (path.endsWith('/rpc/set_driver_availability')) {
          heartbeats.add(jsonDecode(request.body) as Map<String, dynamic>);
          if (refuseWith != null && heartbeats.length >= refuseFrom) {
            status = 403;
            data = {'code': refuseWith, 'message': 'refused'};
          } else {
            data = {
              'is_online': true,
              'latitude': 14.2160,
              'longitude': 121.1660,
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
      email: 'driver@example.test',
      password: 'test',
    );
    state = DemoState(
      initialUser: const DemoUser(
        email: 'driver@example.test',
        displayName: 'Test Driver',
        role: DemoRole.driver,
      ),
    );
    rides = SupabaseRideRepository(
      client,
      state,
      _Gps(),
      const MockFareRepository(),
    );
    // Let the constructor's initial stream fetches finish.
    await settle();
  });

  tearDown(() async {
    rides.dispose();
    state.dispose();
    await client.dispose();
  });

  test(
    'closing a completed trip puts the driver back online on the server',
    () async {
      state.driverTrip.status = DriverTripStatus.completed;
      state.liveTripId = 'trip-1';

      await rides.finishDriverTrip();

      expect(heartbeats, isNotEmpty);
      expect(heartbeats.first['p_online'], true);
      expect(state.driverTrip.status, DriverTripStatus.available);
      expect(state.liveTripId, isNull);
    },
  );

  test('a cancelled pickup is closed the same way', () async {
    state.driverTrip.status = DriverTripStatus.declined;
    state.liveTripId = 'trip-1';

    await rides.finishDriverTrip();

    expect(heartbeats.first['p_online'], true);
    expect(state.driverTrip.status, DriverTripStatus.available);
    expect(state.liveTripId, isNull);
  });

  test('Online is not shown when the server refuses', () async {
    refuseWith = '42501';
    refuseFrom = 1;
    state.driverTrip.status = DriverTripStatus.completed;
    state.liveTripId = 'trip-1';

    await expectLater(
      rides.finishDriverTrip(),
      throwsA(isA<PostgrestException>()),
    );

    expect(state.driverTrip.status, DriverTripStatus.offline);
  });

  test('a heartbeat refused with 42501 flips the driver to Offline', () async {
    refuseWith = '42501';
    refuseFrom = 2; // going online succeeds, the first heartbeat is refused
    await rides.setDriverOnline(true);
    await settle();

    expect(heartbeats, hasLength(2));
    expect(state.driverTrip.status, DriverTripStatus.offline);
  });

  test(
    'a heartbeat that loses a race with dispatch (22023) keeps ticking',
    () async {
      refuseWith = '22023';
      refuseFrom = 2;
      await rides.setDriverOnline(true);
      await settle();

      expect(heartbeats, hasLength(2));
      expect(state.driverTrip.status, DriverTripStatus.available);
    },
  );

  test(
    'a completed trip sends no heartbeat until the driver closes it',
    () async {
      await rides.setDriverOnline(true);
      await settle();
      heartbeats.clear();
      state.driverTrip.status = DriverTripStatus.completed;

      await rides.publishLocationNow();

      expect(heartbeats, isEmpty);
    },
  );
}
