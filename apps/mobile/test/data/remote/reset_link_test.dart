import 'dart:convert';
import 'dart:io';

import 'package:arangcada/data/remote/reset_link.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Storage extends GotrueAsyncStorage {
  final items = <String, String>{};

  @override
  Future<String?> getItem({required String key}) async => items[key];

  @override
  Future<void> removeItem({required String key}) async => items.remove(key);

  @override
  Future<void> setItem({required String key, required String value}) async =>
      items[key] = value;
}

Map<String, dynamic> _session(String userId) => {
  'access_token': 'token-of-$userId',
  'refresh_token': 'refresh',
  'token_type': 'bearer',
  'expires_in': 3600,
  'user': {
    'id': userId,
    'email': '$userId@example.test',
    'aud': 'authenticated',
    'role': 'authenticated',
    'app_metadata': {},
    'user_metadata': {},
    'created_at': '2026-09-01T00:00:00Z',
  },
};

void main() {
  late SupabaseClient client;
  late List<http.Request> requests;
  final storage = _Storage();

  setUp(() async {
    requests = [];
    storage.items.clear();
    client = SupabaseClient(
      'https://example.test',
      'test-key',
      authOptions: AuthClientOptions(
        autoRefreshToken: false,
        pkceAsyncStorage: storage,
      ),
      httpClient: MockClient((request) async {
        requests.add(request);
        final grant = request.url.queryParameters['grant_type'];
        return http.Response(
          jsonEncode(
            grant == 'pkce'
                ? _session('resetting')
                : request.url.path.endsWith('/user')
                ? _session('attacker')['user']
                : _session('victim'),
          ),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    await client.auth.signInWithPassword(
      email: 'victim@example.test',
      password: 'test',
    );
    requests.clear();
  });
  tearDown(() => client.dispose());

  // Any web page or app can open ph.calamba.arangcada://reset-password. The
  // SDK's own handler would take these tokens and replace the session.
  test(
    'a link carrying session tokens does not change who is signed in',
    () async {
      for (final link in [
        'ph.calamba.arangcada://reset-password#access_token=a&refresh_token=r'
            '&expires_in=3600&token_type=bearer&type=recovery',
        'ph.calamba.arangcada://reset-password?access_token=a&refresh_token=r'
            '&expires_in=3600&token_type=bearer',
        'ph.calamba.arangcada://elsewhere?code=abc',
        'https://evil.example/reset-password?code=abc',
      ]) {
        await redeemResetLink(Uri.parse(link), client.auth);
      }

      expect(requests, isEmpty);
      expect(client.auth.currentUser?.id, 'victim');
    },
  );

  test(
    'the reset link the app asked for is exchanged with its verifier',
    () async {
      storage.items['supabase.auth.token-code-verifier'] =
          'verifier-123/passwordRecovery';
      final events = <AuthChangeEvent>[];
      final subscription = client.auth.onAuthStateChange.listen(
        (data) => events.add(data.event),
      );
      addTearDown(subscription.cancel);

      await redeemResetLink(
        Uri.parse('ph.calamba.arangcada://reset-password?code=abc'),
        client.auth,
      );
      await Future<void>.delayed(Duration.zero);

      expect(requests.single.url.queryParameters['grant_type'], 'pkce');
      expect(jsonDecode(requests.single.body), {
        'auth_code': 'abc',
        'code_verifier': 'verifier-123',
      });
      expect(events, contains(AuthChangeEvent.passwordRecovery));
    },
  );

  test('a code this phone never asked for is not sent anywhere', () async {
    await redeemResetLink(
      Uri.parse('ph.calamba.arangcada://reset-password?code=abc'),
      client.auth,
    );

    expect(requests, isEmpty);
    expect(client.auth.currentUser?.id, 'victim');
  });

  // The function above only matters while the SDK's own observer is off.
  test('main.dart switches off the SDK link observer', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(source, contains('detectSessionInUri: false'));
  });
}
