import 'dart:async';
import 'dart:convert';

import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/mock/mock_fare_repository.dart';
import 'package:arangcada/data/remote/supabase_ride_repository.dart';
import 'package:arangcada/data/repositories/location_repository.dart';
import 'package:arangcada/demo/demo_data.dart';
import 'package:arangcada/domain/models/demo_user.dart';
import 'package:arangcada/domain/state/driver_trip_state_machine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Gps implements LocationRepository {
  Completer<void>? hold;

  @override
  Future<bool> hasPermission() async => true;
  @override
  Future<LocationFix> currentLocation() async {
    await hold?.future;
    return LocationFix(
      coordinate: DemoData.places.first.coordinate,
      accuracyMeters: 8,
      timestamp: DateTime.now(),
    );
  }
}

void main() {
  late SupabaseClient client;
  late DemoState state;
  late SupabaseRideRepository rides;
  late List<String> calls;
  late _Gps gps;

  Future<void> start(DemoRole role) async {
    calls = [];
    client = SupabaseClient(
      'https://example.test',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      realtimeClientOptions: RealtimeClientOptions(
        transport: (_, _) => throw StateError('no realtime in tests'),
      ),
      httpClient: MockClient((request) async {
        Object? data = [];
        final path = request.url.path;
        if (path.endsWith('/token')) {
          data = {
            'access_token': 'test-token',
            'refresh_token': 'test-refresh',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': 'user-1',
              'email': 'user@example.test',
              'aud': 'authenticated',
              'role': 'authenticated',
              'app_metadata': {},
              'user_metadata': {},
              'created_at': '2026-09-01T00:00:00Z',
            },
          };
        } else if (path.contains('/rpc/')) {
          final name = path.split('/rpc/').last;
          calls.add(name);
          final decoded = request.body.isEmpty
              ? null
              : jsonDecode(request.body);
          final body = decoded is Map<String, dynamic>
              ? decoded
              : const <String, dynamic>{};
          final tripStep = const {
            'mark_arrived',
            'rider_confirm_pickup',
            'rider_request_stop',
          }.contains(name);
          data = !tripStep
              ? <String, dynamic>{}
              : {
                  'id': body['p_trip_id'],
                  'status': switch (name) {
                    'mark_arrived' => 'arrived',
                    'rider_request_stop' => 'in_progress',
                    _ => 'accepted',
                  },
                  'rider_confirmed_pickup_at': name == 'rider_confirm_pickup'
                      ? '2026-10-14T10:00:00Z'
                      : null,
                  'rider_requested_stop_at': name == 'rider_request_stop'
                      ? '2026-10-14T10:05:00Z'
                      : null,
                  'pickup_lat': 14.2,
                  'pickup_lng': 121.16,
                  'destination_lat': 14.21,
                  'destination_lng': 121.17,
                  'fare_estimate': 50,
                };
        }
        return http.Response(
          jsonEncode(data),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    await client.auth.signInWithPassword(
      email: 'user@example.test',
      password: 'test',
    );
    state = DemoState(
      initialUser: DemoUser(
        email: 'user@example.test',
        displayName: 'User',
        role: role,
      ),
    );
    state.liveTripId = 'trip-1';
    if (role == DemoRole.driver) {
      state.driverTrip.status = DriverTripStatus.accepted;
    }
    gps = _Gps();
    rides = SupabaseRideRepository(
      client,
      state,
      gps,
      const MockFareRepository(),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    calls.clear();
  }

  tearDown(() async {
    rides.dispose();
    state.dispose();
    await client.dispose();
  });

  test(
    '"My driver is here" calls rider_confirm_pickup and is recorded',
    () async {
      await start(DemoRole.commuter);
      await rides.confirmDriverHere();
      expect(calls, ['rider_confirm_pickup']);
      expect(state.riderConfirmedPickup, isTrue);
      expect(state.riderRequestedStop, isFalse);
    },
  );

  test('"Stop here" calls rider_request_stop and is recorded', () async {
    await start(DemoRole.commuter);
    await rides.requestStopHere();
    expect(calls, ['rider_request_stop']);
    expect(state.riderRequestedStop, isTrue);
  });

  test('a driver sends a current fix before asking to mark arrival', () async {
    await start(DemoRole.driver);
    await rides.markArrived();
    expect(calls, ['publish_driver_location', 'mark_arrived']);
  });

  test(
    'arrival waits for a location publish that is already under way',
    () async {
      await start(DemoRole.driver);
      gps.hold = Completer<void>();
      final routine = rides.publishLocationNow();
      final arrival = rides.markArrived();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        calls,
        isEmpty,
        reason: 'nothing may reach the server before the fix',
      );
      gps.hold!.complete();
      await Future.wait([routine, arrival]);
      expect(calls, ['publish_driver_location', 'mark_arrived']);
    },
  );
}
