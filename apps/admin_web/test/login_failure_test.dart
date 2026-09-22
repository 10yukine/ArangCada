import 'package:arangcada_admin/admin_controller.dart';
import 'package:arangcada_admin/app_config.dart';
import 'package:arangcada_admin/main.dart';
import 'package:arangcada_admin/models.dart';
import 'package:arangcada_admin/supabase_admin_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FailingRepository extends Fake implements SupabaseAdminRepository {
  _FailingRepository(this.failure);
  @override
  bool get hasSession => false;
  final Object failure;
  @override
  Future<AdminSession> signIn({
    required String email,
    required String password,
  }) async => throw failure;
}

void main() {
  for (final error in [
    const AuthException('Email not confirmed'),
    StateError('Not an administrator'),
  ]) {
    testWidgets(
      'login conceals ${error.runtimeType}',
      (tester) async {
        final repository = _FailingRepository(error);
        await tester.binding.setSurfaceSize(const Size(1440, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          ProviderScope(
            overrides: [adminRepositoryProvider.overrideWithValue(repository)],
            child: const MaterialApp(home: LoginScreen()),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextFormField).at(0),
          'test@example.test',
        );
        await tester.enterText(
          find.byType(TextFormField).at(1),
          'synthetic-password',
        );
        await tester.tap(find.text('Open console'));
        await tester.pumpAndSettle();
        expect(
          find.text('Unable to sign in. Check your credentials and try again.'),
          findsOneWidget,
        );
        expect(find.text('Email not confirmed'), findsNothing);
        expect(find.text('Not an administrator'), findsNothing);
      },
      skip: !AdminAppConfig.isSupabaseConfigured,
    );
  }
}
