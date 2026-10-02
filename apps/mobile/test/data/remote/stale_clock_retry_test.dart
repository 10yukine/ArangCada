import 'package:arangcada/data/remote/stale_clock_retry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  // PostgREST 14.5 refuses the first request after it has been idle with
  // 401 "JWT issued at future", then accepts the same token a moment later.
  test('a 401 from the data API is sent once more', () async {
    var calls = 0;
    final client = staleClockRetryClient(
      MockClient((request) async {
        calls++;
        return http.Response(
          calls == 1 ? '{"code":"PGRST303"}' : '[]',
          calls == 1 ? 401 : 200,
          request: request,
        );
      }),
    );

    final response = await client.post(
      Uri.parse('https://example.test/rest/v1/rpc/request_ride'),
      body: '{"p":1}',
    );

    expect(response.statusCode, 200);
    expect(calls, 2);
  });

  test(
    'a second 401 is returned, and sign-in failures are not retried',
    () async {
      var calls = 0;
      final client = staleClockRetryClient(
        MockClient((request) async {
          calls++;
          return http.Response('{}', 401, request: request);
        }),
      );

      expect(
        (await client.get(
          Uri.parse('https://example.test/rest/v1/profiles'),
        )).statusCode,
        401,
      );
      expect(calls, 2);

      calls = 0;
      await client.post(
        Uri.parse('https://example.test/auth/v1/token?grant_type=password'),
      );
      expect(calls, 1);
    },
  );
}
