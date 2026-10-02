import 'dart:convert';

import 'package:arangcada/core/network/api_exceptions.dart';
import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/mock/mock_fare_repository.dart';
import 'package:arangcada/data/remote/supabase_auth_repository.dart';
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

class _NoGps implements LocationRepository {
  @override
  Future<bool> hasPermission() async => false;

  @override
  Future<LocationFix> currentLocation() async => throw const LocationFailure(
    LocationFailureReason.permissionDenied,
    'not used',
  );
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  late SupabaseClient client;
  late DemoState state;
  // What request_ride answers with: a status code and a body.
  late (int, Object) requestRideAnswer;
  var profile = <String, dynamic>{};
  var claims = <Map<String, dynamic>>[];
  Object? photoLinkSeconds;

  setUp(() async {
    photoLinkSeconds = null;
    profile = {'role': 'commuter', 'display_name': 'Test Rider'};
    claims = [];
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
              'id': 'rider',
              'email': 'rider@example.test',
              'aud': 'authenticated',
              'role': 'authenticated',
              'app_metadata': {},
              'user_metadata': {},
              'created_at': '2026-09-01T00:00:00Z',
            },
          };
        } else if (path.endsWith('/rpc/request_ride')) {
          (status, data) = requestRideAnswer;
        } else if (path.endsWith('/profiles')) {
          data = profile;
        } else if (path.endsWith('/fare_class_claims')) {
          data = claims.isEmpty ? null : claims.first;
        } else if (path.endsWith('/driver_profiles')) {
          data = {
            'toda_zones': {'name': 'Test TODA'},
          };
        } else if (path.contains('/object/sign/')) {
          photoLinkSeconds = (jsonDecode(request.body) as Map)['expiresIn'];
          data = {'signedURL': '/object/sign/profile-photos/x?token=t'};
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
      initialUser: const DemoUser(
        email: 'rider@example.test',
        displayName: 'Test Rider',
        role: DemoRole.commuter,
      ),
    );
    state.setDestination(DemoData.places.first);
  });

  tearDown(() async {
    state.dispose();
    await client.dispose();
  });

  Future<(SupabaseRideRepository, DemoBooking)> book() async {
    final rides = SupabaseRideRepository(
      client,
      state,
      _NoGps(),
      const MockFareRepository(),
    );
    addTearDown(rides.dispose);
    await settle();
    final booking = DemoBooking.draft(
      pickupName: state.pickup.name,
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
    );
    state.setActiveBooking(booking);
    return (rides, booking);
  }

  // The server bills an approved rider the discounted fare and the driver's
  // offer card shows it. The rider's screens must show the same amount.
  test('the fare shown after booking is the one the server set', () async {
    requestRideAnswer = (
      200,
      {
        'id': 'trip-1',
        'status': 'searching_driver',
        'fare_estimate': 54.0,
        'pickup_lat': 14.2117,
        'pickup_lng': 121.1653,
        'destination_lat': 14.22,
        'destination_lng': 121.17,
      },
    );
    final (rides, booking) = await book();
    expect(booking.fareQuote.partyTotalCentavos, isNot(5400));

    await rides.requestRide(booking);

    expect(booking.fareQuote.partyTotalCentavos, 5400);
    expect(booking.fareQuote.unitFareCentavos, 5400);
  });

  // trips_one_active_per_rider. This used to read "Something went wrong".
  test('booking while another ride is still open says so', () async {
    requestRideAnswer = (
      409,
      {'code': '23505', 'message': 'duplicate key value'},
    );
    final (rides, booking) = await book();

    await expectLater(
      rides.requestRide(booking),
      throwsA(
        isA<ApiRejectedException>().having(
          (error) => error.message,
          'message',
          contains('already have a ride in progress'),
        ),
      ),
    );
  });

  test('an approved discount is what the booking screens quote with', () async {
    profile['fare_class'] = 'discounted';
    claims = [
      {
        'id': 'claim-1',
        'requested_class': 'senior_citizen',
        'status': 'approved',
        'created_at': '2026-09-20T00:00:00Z',
      },
    ];

    await SupabaseAuthRepository(
      client,
      state,
    ).restoreProfile(client.auth.currentUser!);

    expect(state.userFareClass, UserFareClass.seniorCitizen);
    expect(state.userFareClass.discountClass, DiscountClass.discounted);
  });

  test(
    'a rider with no approved discount is quoted the regular fare',
    () async {
      profile['fare_class'] = 'standard';

      await SupabaseAuthRepository(
        client,
        state,
      ).restoreProfile(client.auth.currentUser!);

      expect(state.userFareClass, UserFareClass.regular);
    },
  );

  // Both were found on a phone: the photo link lasted five minutes while the
  // app showed it for hours, and the header took the TODA from the last trip.
  test('a driver profile has its TODA and a photo link that lasts', () async {
    profile = {
      'role': 'driver',
      'display_name': 'Test Driver',
      'avatar_path': 'rider/1.jpg',
    };

    final user = await SupabaseAuthRepository(
      client,
      state,
    ).restoreProfile(client.auth.currentUser!);

    expect(state.driverTodaName, 'Test TODA');
    expect(user.avatarUrl, contains('token=t'));
    expect(photoLinkSeconds, greaterThan(24 * 3600));
  });

  test('a rider has no TODA', () async {
    state.driverTodaName = 'left over';

    await SupabaseAuthRepository(
      client,
      state,
    ).restoreProfile(client.auth.currentUser!);

    expect(state.driverTodaName, isNull);
  });
}
