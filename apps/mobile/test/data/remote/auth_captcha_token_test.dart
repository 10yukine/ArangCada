import 'dart:convert';

import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/remote/supabase_auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Once CAPTCHA is on, Supabase Auth refuses a sign-in, sign-up or reset
/// request that carries no token. Each of the app's five such requests has to
/// ask for its own, because a token can be redeemed only once.
void main() {
  late List<http.Request> sent;
  late SupabaseClient client;
  late DemoState state;
  var asked = 0;
  var failCaptcha = false;

  setUp(() {
    sent = [];
    asked = 0;
    failCaptcha = false;
    client = SupabaseClient(
      'https://example.test',
      'synthetic',
      // The reset request needs no stored state this way.
      authOptions: const AuthClientOptions(
        autoRefreshToken: false,
        authFlowType: AuthFlowType.implicit,
      ),
      httpClient: MockClient((request) async {
        sent.add(request);
        if (failCaptcha) {
          return http.Response(
            jsonEncode({
              'error_code': 'captcha_failed',
              'msg': 'CAPTCHA failed',
            }),
            400,
            headers: {'content-type': 'application/json'},
          );
        }
        final signedIn = request.url.path.endsWith('/token');
        return http.Response(
          jsonEncode(
            signedIn
                ? {
                    'access_token': 'synthetic-access',
                    'refresh_token': 'synthetic-refresh',
                    'token_type': 'bearer',
                    'expires_in': 3600,
                    'user': {
                      'id': 'rider',
                      'email': 'rider@example.test',
                      'aud': 'authenticated',
                      'role': 'authenticated',
                      'app_metadata': <String, dynamic>{},
                      'user_metadata': <String, dynamic>{},
                      'created_at': '2026-09-01T00:00:00Z',
                    },
                  }
                : <String, dynamic>{},
          ),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    state = DemoState();
  });

  tearDown(() async {
    state.dispose();
    await client.dispose();
  });

  /// The token each request to [path] carried, read the way Auth reads it.
  List<Object?> tokensTo(String path) => [
    for (final request in sent)
      if (request.url.path.endsWith(path))
        (jsonDecode(request.body)['gotrue_meta_security']
            as Map?)?['captcha_token'],
  ];

  // What follows a sign-in (loading the profile) is not faked here and is
  // not what these tests are about.
  Future<void> attempt(Future<Object?> call) =>
      call.then<void>((_) {}, onError: (_) {});

  test('every gated request carries its own fresh token', () async {
    final auth = SupabaseAuthRepository(
      client,
      state,
      captcha: () async => 'token-${++asked}',
    );

    await attempt(auth.signIn(email: 'rider@example.test', password: 'pw'));
    await attempt(auth.signInWithPhone(phone: '+639171234567', password: 'pw'));
    await attempt(auth.reauthenticate('pw'));
    await attempt(
      auth.signUp(
        email: 'new@example.test',
        password: 'pw',
        displayName: 'New Rider',
        mobileNumber: '+639171234568',
      ),
    );
    await attempt(auth.sendPasswordReset('rider@example.test'));

    expect(tokensTo('/token'), ['token-1', 'token-2', 'token-3']);
    expect(tokensTo('/signup'), ['token-4']);
    expect(tokensTo('/recover'), ['token-5']);
    expect(asked, 5);
  });

  test('a build with no check page sends no token', () async {
    final auth = SupabaseAuthRepository(client, state);

    await attempt(auth.signIn(email: 'rider@example.test', password: 'pw'));
    await attempt(auth.sendPasswordReset('rider@example.test'));

    expect(tokensTo('/token'), [null]);
    expect(tokensTo('/recover'), [null]);
  });

  test('an unfinished check stops all five Auth requests', () async {
    await attempt(
      SupabaseAuthRepository(
        client,
        state,
      ).signIn(email: 'rider@example.test', password: 'pw'),
    );
    sent.clear();
    final auth = SupabaseAuthRepository(
      client,
      state,
      captcha: () async {
        throw const AuthException(
          'Security check incomplete',
          code: 'captcha_failed',
        );
      },
    );
    for (final request in <Future<Object?> Function()>[
      () => auth.signIn(email: 'rider@example.test', password: 'pw'),
      () => auth.signInWithPhone(phone: '+639171234567', password: 'pw'),
      () => auth.signUp(
        email: 'new@example.test',
        password: 'pw',
        displayName: 'Rider',
        mobileNumber: '+639171234567',
      ),
      () => auth.sendPasswordReset('rider@example.test'),
      () => auth.reauthenticate('pw'),
    ]) {
      await expectLater(
        request(),
        throwsA(
          predicate(
            (error) =>
                error.toString().contains('security check did not finish'),
          ),
        ),
      );
    }
    expect(sent, isEmpty);
  });

  test(
    'all five requests report a security check failure accurately',
    () async {
      final auth = SupabaseAuthRepository(client, state);
      await attempt(auth.signIn(email: 'rider@example.test', password: 'pw'));
      failCaptcha = true;
      for (final request in <Future<Object?> Function()>[
        () => auth.signIn(email: 'rider@example.test', password: 'pw'),
        () => auth.signInWithPhone(phone: '+639171234567', password: 'pw'),
        () => auth.signUp(
          email: 'new@example.test',
          password: 'pw',
          displayName: 'Rider',
          mobileNumber: '+639171234567',
        ),
        () => auth.sendPasswordReset('rider@example.test'),
        () => auth.reauthenticate('pw'),
      ]) {
        await expectLater(
          request(),
          throwsA(
            predicate(
              (error) =>
                  error.toString().contains('security check did not finish'),
            ),
          ),
        );
      }
    },
  );
}
