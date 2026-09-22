import 'dart:convert';
import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/remote/supabase_auth_repository.dart';
import 'package:arangcada/data/repositories/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  for (final code in [
    'invalid_credentials',
    'email_not_confirmed',
    'user_banned',
  ]) {
    test('login conceals $code', () async {
      final client = SupabaseClient(
        'https://example.test',
        'synthetic',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient(
          (_) async =>
              http.Response(jsonEncode({'code': code, 'msg': code}), 400),
        ),
      );
      addTearDown(client.dispose);
      final state = DemoState();
      addTearDown(state.dispose);
      await expectLater(
        SupabaseAuthRepository(
          client,
          state,
        ).signIn(email: 'test@example.test', password: 'synthetic'),
        throwsA(
          isA<DemoAuthException>().having(
            (e) => e.message,
            'message',
            'Unable to sign in. Check your credentials and try again.',
          ),
        ),
      );
    });
  }
}
