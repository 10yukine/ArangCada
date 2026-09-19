import 'dart:convert';
import 'dart:typed_data';

import 'package:arangcada/data/remote/supabase_voice_notes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late SupabaseClient client;
  late SupabaseVoiceNotes notes;
  late List<http.Request> requests;
  var uploadStatus = 200;
  var rpcFails = false;
  var signedOutDuringUpload = false;
  setUp(() async {
    requests = [];
    uploadStatus = 200;
    rpcFails = signedOutDuringUpload = false;
    client = SupabaseClient(
      'https://example.test',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        dynamic data = {};
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
        } else if (request.url.path.contains('/object/sign/')) {
          data = {
            'signedURL':
                '/object/sign/trip-voice-notes/trip/rider/note.m4a?token=synthetic',
          };
        } else if (request.url.path.contains('/object/trip-voice-notes/')) {
          if (signedOutDuringUpload) {
            await client.auth.signOut(scope: SignOutScope.local);
          }
          status = uploadStatus;
          data = status == 200
              ? {'Key': 'trip-voice-notes/trip/rider/note.m4a'}
              : {
                  'statusCode': '$status',
                  'error': status == 409 ? 'Duplicate' : 'Unauthorized',
                  'message': 'upload rejected',
                };
        } else if (request.url.path.endsWith('/rpc/send_trip_voice_message')) {
          status = rpcFails ? 400 : 200;
          data = rpcFails
              ? {'code': '22023', 'message': 'trip closed'}
              : {'id': 'note', 'voice_path': 'trip/rider/note.m4a'};
        } else if (request.url.path.endsWith('/trip_messages')) {
          data = {'voice_path': 'trip/rider/note.m4a'};
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
    notes = SupabaseVoiceNotes(client);
    requests.clear();
  });
  tearDown(() => client.dispose());
  Future<void> send() async {
    await notes.send(
      tripId: 'trip',
      messageId: 'note',
      bytes: Uint8List.fromList([1, 2, 3]),
      durationMs: 1200,
    );
  }

  test(
    'uploads privately before send; lost acknowledgement retry uses same ID',
    () async {
      rpcFails = true;
      await expectLater(send(), throwsA(isA<PostgrestException>()));
      rpcFails = false;
      uploadStatus = 409;
      await send();
      final uploads = requests
          .where((r) => r.url.path.contains('/object/trip-voice-notes/'))
          .toList();
      expect(uploads.length, 2);
      expect(uploads.first.url, uploads.last.url);
      expect(uploads.first.headers['x-upsert'], 'false');
      final calls = requests
          .where((r) => r.url.path.contains('/rpc/'))
          .toList();
      expect(jsonDecode(calls.last.body), {
        'p_trip_id': 'trip',
        'p_message_id': 'note',
        'p_duration_ms': 1200,
      });
    },
  );
  test('failed upload never sends a message', () async {
    uploadStatus = 403;
    await expectLater(send(), throwsA(isA<StorageException>()));
    expect(requests.where((r) => r.url.path.contains('/rpc/')), isEmpty);
  });
  test('account change during upload prevents finalization', () async {
    signedOutDuringUpload = true;
    await expectLater(send(), throwsStateError);
    expect(requests.where((r) => r.url.path.contains('/rpc/')), isEmpty);
  });
  test('invalid size/duration rejected before network', () async {
    for (final duration in [0, 60001]) {
      await expectLater(
        notes.send(
          tripId: 'trip',
          messageId: 'note',
          bytes: Uint8List(1),
          durationMs: duration,
        ),
        throwsStateError,
      );
    }
    await expectLater(
      notes.send(
        tripId: 'trip',
        messageId: 'note',
        bytes: Uint8List(1048577),
        durationMs: 1000,
      ),
      throwsStateError,
    );
    expect(requests, isEmpty);
  });
  test(
    'play rechecks row and signs for only 60 seconds, never caches URL',
    () async {
      await notes.playbackUrl('note');
      await notes.playbackUrl('note');
      expect(
        requests.where((r) => r.url.path.endsWith('/trip_messages')).length,
        2,
      );
      final signs = requests.where((r) => r.url.path.contains('/object/sign/'));
      expect(signs.length, 2);
      expect(jsonDecode(signs.first.body)['expiresIn'], 60);
    },
  );
}
