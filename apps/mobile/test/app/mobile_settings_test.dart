import 'dart:convert';
import 'dart:io';

import 'package:arangcada/app/app.dart';
import 'package:arangcada/app/mobile_settings.dart';
import 'package:arangcada/config/app_build.dart';
import 'package:arangcada/core/geo/haversine.dart';
import 'package:arangcada/data/remote/fallback_routing_repository.dart';
import 'package:arangcada/data/repositories/routing_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient _serverAnswering(int status, Object? body) => SupabaseClient(
  'https://example.test',
  'test-key',
  authOptions: const AuthClientOptions(autoRefreshToken: false),
  httpClient: MockClient(
    (request) async => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    ),
  ),
);

Map<String, Object> _settings({
  int minimum = 0,
  String routing = 'google',
  String search = 'google',
}) => {'min_mobile_build': minimum, 'routing': routing, 'search': search};

class _Router implements RoutingRepository {
  _Router(this.name, {this.hasRoute = true});

  final String name;
  final bool hasRoute;
  int calls = 0;

  @override
  String get attribution => name;

  @override
  Future<RouteResult> route({
    required GeoCoordinate from,
    required GeoCoordinate to,
  }) async {
    calls++;
    return RouteResult(
      geometry: hasRoute ? [from, to] : const [],
      distanceMeters: 0,
      durationSeconds: 0,
      isFallback: !hasRoute,
      retrievedAt: DateTime(2026),
    );
  }
}

void main() {
  void reset() {
    updateRequired.value = false;
    serviceChoices.value = (routing: 'google', search: 'google');
  }

  setUp(reset);
  tearDown(reset);

  // The server compares against this number, so it has to be the build's own.
  test('appBuild is the build number in pubspec.yaml', () {
    final version = RegExp(
      r'^version: .*\+(\d+)\s*$',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync());
    expect(int.parse(version!.group(1)!), appBuild);
  });

  test('a newer minimum asks for an update, and lowering it lets go', () async {
    final newer = _serverAnswering(200, _settings(minimum: appBuild + 1));
    addTearDown(newer.dispose);
    await loadMobileSettings(newer);
    expect(updateRequired.value, isTrue);

    final lowered = _serverAnswering(200, _settings(minimum: appBuild));
    addTearDown(lowered.dispose);
    await loadMobileSettings(lowered);
    expect(updateRequired.value, isFalse);
  });

  test('the owner’s service choices are taken up', () async {
    final client = _serverAnswering(
      200,
      _settings(routing: 'ors_only', search: 'maptiler'),
    );
    addTearDown(client.dispose);
    await loadMobileSettings(client);
    expect(serviceChoices.value, (routing: 'ors_only', search: 'maptiler'));
    expect(updateRequired.value, isFalse);
  });

  // Locking everyone out, or dropping a switch the owner set, because the
  // question could not be asked would be worse than waiting for the next ask.
  test('a server that cannot answer changes nothing', () async {
    serviceChoices.value = (routing: 'ors_only', search: 'maptiler');
    for (final (status, body) in <(int, Object?)>[
      (404, {'code': 'PGRST202', 'message': 'not found'}),
      (500, {'message': 'down'}),
      (200, null),
      (200, 4036),
    ]) {
      final client = _serverAnswering(status, body);
      addTearDown(client.dispose);
      await loadMobileSettings(client);
      expect(updateRequired.value, isFalse);
      expect(serviceChoices.value, (routing: 'ors_only', search: 'maptiler'));
    }
  });

  testWidgets('an outdated build shows only the update screen', (tester) async {
    updateRequired.value = true;
    await tester.pumpWidget(const ProviderScope(child: ArangCadaApp()));
    await tester.pumpAndSettle();
    expect(find.text('Update ArangCada'), findsOneWidget);
    expect(find.text('Get the update'), findsOneWidget);
    expect(find.text('Log In'), findsNothing);
  });

  group('routing follows the owner’s choice', () {
    const a = GeoCoordinate(latitude: 14.21, longitude: 121.16);
    const b = GeoCoordinate(latitude: 14.22, longitude: 121.17);

    test(
      'Google first by default, openrouteservice only when it has none',
      () async {
        final google = _Router('google');
        final ors = _Router('ors');
        final chosen = ChosenRoutingRepository(
          google: google,
          ors: ors,
          choice: () => 'google',
        );
        await chosen.route(from: a, to: b);
        expect((google.calls, ors.calls), (1, 0));
        expect(chosen.attribution, 'google');
      },
    );

    test('ors_only never calls Google, even when ORS has no route', () async {
      final google = _Router('google');
      final ors = _Router('ors', hasRoute: false);
      final chosen = ChosenRoutingRepository(
        google: google,
        ors: ors,
        choice: () => 'ors_only',
      );
      final result = await chosen.route(from: a, to: b);
      expect(result.isFallback, isTrue);
      expect((google.calls, ors.calls), (0, 1));
    });

    test(
      'ors puts openrouteservice first and a change applies at once',
      () async {
        final google = _Router('google');
        final ors = _Router('ors');
        var choice = 'ors';
        final chosen = ChosenRoutingRepository(
          google: google,
          ors: ors,
          choice: () => choice,
        );
        await chosen.route(from: a, to: b);
        expect((google.calls, ors.calls), (0, 1));
        expect(chosen.attribution, 'ors');

        choice = 'google';
        await chosen.route(from: a, to: b);
        expect((google.calls, ors.calls), (1, 1));
      },
    );
  });
}
