import 'dart:convert';
import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/remote/supabase_auth_repository.dart';
import 'package:arangcada/data/repositories/auth_repository.dart';
import 'package:arangcada/domain/models/demo_user.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'admin identity and pending phone survive restoration without granting verification',
    () async {
      final state = DemoState();
      addTearDown(state.dispose);
      final requests = <http.Request>[];
      var metadata = <String, dynamic>{
        'display_name': 'Wrong metadata name',
        'role': 'driver',
      };
      Map<String, dynamic> user() => {
        'id': 'admin-test',
        'email': 'admin@example.test',
        'aud': 'authenticated',
        'created_at': '2026-09-01T00:00:00Z',
        'user_metadata': metadata,
        'app_metadata': <String, dynamic>{},
        'phone': '',
      };
      final client = SupabaseClient(
        'https://example.test',
        'synthetic',
        authOptions: const AuthClientOptions(
          autoRefreshToken: false,
          authFlowType: AuthFlowType.implicit,
        ),
        httpClient: MockClient((request) async {
          requests.add(request);
          dynamic body;
          if (request.url.path.endsWith('/token')) {
            body = {
              'access_token': 'test-token',
              'refresh_token': 'test-refresh',
              'expires_in': 3600,
              'token_type': 'bearer',
              'user': user(),
            };
          } else if (request.url.path.endsWith('/profiles')) {
            body = {
              'role': 'admin',
              'display_name': 'Verified Admin Name',
              'is_internal_tester': false,
              'phone_verified_at': null,
              'avatar_path': null,
            };
          } else if (request.url.path.endsWith('/record_otp_send')) {
            body = null;
          } else if (request.method == 'PUT' &&
              request.url.path.endsWith('/user')) {
            final attributes = jsonDecode(request.body) as Map<String, dynamic>;
            metadata = {
              ...metadata,
              ...attributes['data'] as Map<String, dynamic>,
            };
            body = user();
          } else {
            throw StateError('Unexpected request ${request.url}');
          }
          return http.Response(
            jsonEncode(body),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      final repository = SupabaseAuthRepository(client, state);
      final admin = await repository.signIn(
        email: 'admin@example.test',
        password: 'existing-password',
      );
      expect(admin.role, DemoRole.commuter);
      expect(admin.isAdminAccount, isTrue);
      expect(admin.displayName, 'Verified Admin Name');
      expect(admin.needsPhoneSetup, isTrue);
      await repository.sendPhoneOtp('+639171234567');
      expect(state.currentUser!.phoneVerified, isFalse);
      expect(state.currentUser!.mobileNumber, '+639171234567');
      final write = jsonDecode(
        requests.singleWhere((r) => r.method == 'PUT').body,
      );
      expect(write['phone'], '+639171234567');
      expect(write.containsKey('password'), isFalse);
      expect(write['data'], {'mobile_number': '+639171234567'});
      final restored = await repository.restoreProfile(
        client.auth.currentUser!,
      );
      expect(restored.isAdminAccount, isTrue);
      expect(restored.mobileNumber, '+639171234567');
      expect(restored.needsPhoneSetup, isFalse);
      expect(restored.needsPhoneVerification, isTrue);
      expect(restored.copyWithDisplayName('Updated').isAdminAccount, isTrue);
      expect(restored.copyWithAvatarUrl(null).isAdminAccount, isTrue);
    },
  );

  test(
    'duplicate signup directs to existing-password login without reading identity',
    () async {
      final requests = <http.Request>[];
      final state = DemoState();
      addTearDown(state.dispose);
      final client = SupabaseClient(
        'https://example.test',
        'synthetic',
        authOptions: const AuthClientOptions(
          autoRefreshToken: false,
          authFlowType: AuthFlowType.implicit,
        ),
        httpClient: MockClient((r) async {
          requests.add(r);
          return http.Response(
            jsonEncode({
              'error_code': 'user_already_exists',
              'msg': 'User already registered',
            }),
            422,
          );
        }),
      );
      addTearDown(client.dispose);
      await expectLater(
        SupabaseAuthRepository(client, state).signUp(
          displayName: 'Untrusted name',
          mobileNumber: '+639171234567',
          email: 'admin@example.test',
          password: 'not-a-new-password',
        ),
        throwsA(isA<ExistingAccountException>()),
      );
      expect(requests.length, 1);
      expect(requests.single.url.path, '/auth/v1/signup');
      expect(state.currentUser, isNull);
    },
  );
}
