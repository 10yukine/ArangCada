import 'dart:convert';

import 'package:arangcada/data/remote/supabase_driver_documents_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late SupabaseClient client;
  late SupabaseDriverDocumentsRepository repository;
  late List<http.Request> requests;
  var path = 'driver-a/license.jpg';
  var suspended = false;
  var missingProfile = false;
  var downloadStatus = 200;

  setUp(() async {
    requests = [];
    path = 'driver-a/license.jpg';
    suspended = false;
    missingProfile = false;
    downloadStatus = 200;
    final transport = MockClient((request) async {
      requests.add(request);
      dynamic body;
      final uri = request.url;
      if (uri.path.endsWith('/token')) {
        body = {
          'access_token': 'test-token',
          'refresh_token': 'test-refresh-token',
          'token_type': 'bearer',
          'expires_in': 3600,
          'user': {
            'id': 'driver-a',
            'email': 'driver@example.test',
            'aud': 'authenticated',
            'role': 'authenticated',
            'app_metadata': <String, dynamic>{},
            'user_metadata': <String, dynamic>{},
            'created_at': '2026-09-01T00:00:00Z',
          },
        };
      } else if (uri.path.endsWith('/driver_profiles')) {
        body = missingProfile
            ? null
            : {
                'body_number': '024',
                'plate_number': 'ABC123',
                'license_expires_on': '2027-09-01',
                'verification_status': 'pending_review',
                'toda_zones': {'name': 'Test TODA'},
              };
      } else if (uri.path.endsWith('/profiles')) {
        body = {'status': suspended ? 'suspended' : 'active'};
      } else if (uri.path.endsWith('/driver_documents')) {
        body = uri.queryParameters['select'] == 'storage_path'
            ? {'storage_path': path}
            : [
                {
                  'id': 'doc-a',
                  'document_type': 'drivers_license',
                  'status': 'rejected',
                  'rejection_reason': 'Image is blurred',
                },
              ];
      } else if (request.method == 'POST' &&
          uri.path.contains('/object/sign/')) {
        body = {
          'signedURL':
              '/object/sign/driver-documents/driver-a/license.jpg?token=synthetic',
        };
      } else if (request.method == 'GET' &&
          uri.path.contains('/object/sign/')) {
        return http.Response.bytes([1, 2, 3], downloadStatus);
      } else {
        throw StateError('Unexpected test request: ${uri.path}');
      }
      return http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    });
    client = SupabaseClient(
      'https://example.test',
      'test-anon-key',
      httpClient: transport,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    repository = SupabaseDriverDocumentsRepository(client, transport);
    await client.auth.signInWithPassword(
      email: 'driver@example.test',
      password: 'synthetic',
    );
    requests.clear();
  });

  tearDown(() => client.dispose());

  test('loads only own records and maps actual review results', () async {
    final records = (await repository.load())!;
    expect(records.toda, 'Test TODA');
    expect(records.plateNumber, 'ABC123');
    expect(records.status, 'pending_review');
    expect(records.documents.single.rejectionReason, 'Image is blurred');
    expect(requests, hasLength(3));
    for (final request in requests) {
      final key = request.url.path.endsWith('/driver_documents')
          ? 'driver_id'
          : 'id';
      expect(request.url.queryParameters[key], 'eq.driver-a');
      expect(request.method, 'GET');
      expect(
        request.url.queryParameters['select'],
        isNot(contains('storage_path')),
      );
    }
  });

  test('account suspension overrides registration approval state', () async {
    suspended = true;
    expect((await repository.load())!.status, 'suspended');
  });

  test('missing registration returns an empty result', () async {
    missingProfile = true;
    expect(await repository.load(), isNull);
  });

  test('signs own document for five minutes and returns bytes', () async {
    expect(await repository.loadDocument('doc-a'), [1, 2, 3]);
    expect(requests.first.url.queryParameters['driver_id'], 'eq.driver-a');
    expect(requests.first.url.queryParameters['id'], 'eq.doc-a');
    final signing = requests.singleWhere((r) => r.method == 'POST');
    expect(jsonDecode(signing.body)['expiresIn'], 300);
    expect(
      signing.url.path,
      contains('/driver-documents/driver-a/license.jpg'),
    );
    await repository.loadDocument('doc-a');
    expect(requests.where((r) => r.method == 'POST'), hasLength(2));
  });

  test(
    'refuses another owner or traversal before requesting a signed URL',
    () async {
      for (final invalid in [
        'driver-b/license.jpg',
        'driver-a/../driver-b/license.jpg',
      ]) {
        path = invalid;
        await expectLater(repository.loadDocument('doc-a'), throwsStateError);
      }
      expect(requests.where((r) => r.method == 'POST'), isEmpty);
    },
  );

  test(
    'failed download reports failure instead of returning error-page bytes',
    () async {
      downloadStatus = 403;
      await expectLater(repository.loadDocument('doc-a'), throwsStateError);
    },
  );

  test('signed-out users cannot request records or signed URLs', () async {
    final anonymous = SupabaseClient(
      'https://example.test',
      'test-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final transport = MockClient(
      (_) async => throw StateError('Must not send'),
    );
    addTearDown(anonymous.dispose);
    addTearDown(transport.close);
    final repo = SupabaseDriverDocumentsRepository(anonymous, transport);
    await expectLater(repo.load(), throwsStateError);
    await expectLater(repo.loadDocument('doc-a'), throwsStateError);
  });
}
