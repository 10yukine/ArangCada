import 'dart:convert';
import 'dart:io';

import 'package:arangcada_admin/supabase_admin_repository.dart';
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
        return http.Response(
          jsonEncode(
            _session(
              request.url.queryParameters['grant_type'] == 'pkce'
                  ? 'resetting'
                  : 'admin',
            ),
          ),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    await client.auth.signInWithPassword(
      email: 'admin@example.test',
      password: 'test',
    );
    requests.clear();
  });
  tearDown(() => client.dispose());

  // The SDK's own handling would sign the browser into these tokens.
  test(
    'a URL carrying session tokens does not change who is signed in',
    () async {
      for (final url in [
        'https://admin.example/reset-password#access_token=a&refresh_token=r'
            '&expires_in=3600&token_type=bearer&type=recovery',
        'https://admin.example/dashboard?access_token=a&refresh_token=r'
            '&expires_in=3600&token_type=bearer',
        'https://admin.example/login?code=abc',
      ]) {
        expect(await redeemResetLink(Uri.parse(url), client.auth), isFalse);
      }

      expect(requests, isEmpty);
      expect(client.auth.currentUser?.id, 'admin');
    },
  );

  test(
    'the reset link is exchanged with the verifier this browser stored',
    () async {
      storage.items['supabase.auth.token-code-verifier'] =
          'verifier-123/passwordRecovery';

      final redeemed = await redeemResetLink(
        Uri.parse('https://admin.example/reset-password?code=abc'),
        client.auth,
      );

      expect(redeemed, isTrue);
      expect(requests.single.url.queryParameters['grant_type'], 'pkce');
      expect(jsonDecode(requests.single.body), {
        'auth_code': 'abc',
        'code_verifier': 'verifier-123',
      });
      expect(client.auth.currentUser?.id, 'resetting');
    },
  );

  test('a code this browser never asked for is not sent anywhere', () async {
    final redeemed = await redeemResetLink(
      Uri.parse('https://admin.example/reset-password?code=abc'),
      client.auth,
    );

    expect(redeemed, isFalse);
    expect(requests, isEmpty);
    expect(client.auth.currentUser?.id, 'admin');
  });

  // redeemResetLink only matters while the SDK's own handling is off.
  test('main.dart switches off the SDK URL session handling', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(source, contains('detectSessionInUri: false'));
  });
}
