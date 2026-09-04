import 'dart:convert';

import 'package:arangcada_admin/supabase_admin_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('password update confirms identity and forwards credentials', () async {
    final httpClient = _AuthClient(signInUserId: 'admin-1');
    final client = _client(httpClient);
    addTearDown(client.dispose);

    await SupabaseAdminRepository(client).updateOwnPassword(
      expectedUserId: 'admin-1',
      email: 'admin@example.com',
      currentPassword: 'current-password',
      newPassword: 'new-password',
    );

    expect(httpClient.requests.map((request) => request.method), [
      'POST',
      'PUT',
    ]);
    expect(jsonDecode(httpClient.requests.first.body), {
      'email': 'admin@example.com',
      'password': 'current-password',
      'gotrue_meta_security': {'captcha_token': null},
    });
    expect(jsonDecode(httpClient.requests.last.body), {
      'password': 'new-password',
    });
  });

  test(
    'password update rejects a mismatched reauthentication identity',
    () async {
      final httpClient = _AuthClient(signInUserId: 'other-admin');
      final client = _client(httpClient);
      addTearDown(client.dispose);

      await expectLater(
        SupabaseAdminRepository(client).updateOwnPassword(
          expectedUserId: 'admin-1',
          email: 'admin@example.com',
          currentPassword: 'current-password',
          newPassword: 'new-password',
        ),
        throwsStateError,
      );

      expect(
        httpClient.requests.where((request) => request.method == 'PUT'),
        isEmpty,
      );
    },
  );
}

SupabaseClient _client(http.Client httpClient) => SupabaseClient(
  'https://example.supabase.co',
  'test-anon-key',
  httpClient: httpClient,
  authOptions: const AuthClientOptions(autoRefreshToken: false),
);

class _AuthClient extends http.BaseClient {
  _AuthClient({required this.signInUserId});

  final String signInUserId;
  final List<_Request> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = await request.finalize().bytesToString();
    requests.add(_Request(request.method, request.url, body));
    final response = request.url.path.endsWith('/token')
        ? {
            'access_token': 'test-access-token',
            'refresh_token': 'test-refresh-token',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': _user(signInUserId),
          }
        : request.url.path.endsWith('/user')
        ? _user(signInUserId)
        : <String, dynamic>{};
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(response))),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

Map<String, dynamic> _user(String id) => {
  'id': id,
  'email': 'admin@example.com',
  'aud': 'authenticated',
  'role': 'authenticated',
  'app_metadata': <String, dynamic>{},
  'user_metadata': <String, dynamic>{},
  'created_at': '2026-08-26T00:00:00Z',
};

class _Request {
  const _Request(this.method, this.url, this.body);

  final String method;
  final Uri url;
  final String body;
}
