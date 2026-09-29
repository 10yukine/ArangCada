import 'package:arangcada/app/theme/app_theme.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/data/repositories/auth_repository.dart';
import 'package:arangcada/domain/models/demo_user.dart';
import 'package:arangcada/features/auth/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _Auth extends Fake implements AuthRepository {
  final calls = <String>[];

  DemoUser _user(String email) => DemoUser(
    email: email,
    displayName: 'Maria',
    role: DemoRole.commuter,
    phoneVerified: true,
  );

  @override
  Future<DemoUser> signIn({
    required String email,
    required String password,
  }) async {
    calls.add('email:$email');
    return _user(email);
  }

  @override
  Future<DemoUser> signInWithPhone({
    required String phone,
    required String password,
  }) async {
    calls.add('phone:$phone');
    return _user('maria@example.com');
  }
}

Future<_Auth> _logIn(
  WidgetTester tester,
  String identifier, {
  String password = 'example-password',
}) async {
  final auth = _Auth();
  final router = GoRouter(
    initialLocation: '/login',
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/home', builder: (_, _) => const Text('home')),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(auth)],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).first, identifier);
  await tester.enterText(find.byType(TextField).last, password);
  await tester.tap(find.text('Log In'));
  await tester.pumpAndSettle();
  return auth;
}

void main() {
  testWidgets('email logs in by email', (tester) async {
    final auth = await _logIn(tester, ' maria@example.com ');
    expect(auth.calls, ['email:maria@example.com']);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('local mobile number logs in by E.164 phone', (tester) async {
    final auth = await _logIn(tester, '0917 123 4567');
    expect(auth.calls, ['phone:+639171234567']);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('neither email nor mobile stays on login', (tester) async {
    final auth = await _logIn(tester, '12345');
    expect(auth.calls, isEmpty);
    expect(
      find.text(
        'Enter your email or a Philippine mobile number, like 0917 123 4567',
      ),
      findsOneWidget,
    );
  });

  testWidgets('empty fields each show their own error, and nothing is sent', (
    tester,
  ) async {
    final auth = await _logIn(tester, '', password: '');
    expect(auth.calls, isEmpty);
    final identifier = tester.getRect(find.byType(TextField).first);
    final password = tester.getRect(find.byType(TextField).last);
    final identifierError = tester.getRect(
      find.text('Enter your mobile number or email'),
    );
    expect(identifierError.top, greaterThan(identifier.top + 40));
    expect(identifierError.bottom, lessThanOrEqualTo(password.top));
    expect(find.text('Enter your password'), findsOneWidget);

    // Typing clears that field's error only.
    await tester.enterText(find.byType(TextField).first, 'maria@example.com');
    await tester.pump();
    expect(find.text('Enter your mobile number or email'), findsNothing);
    expect(find.text('Enter your password'), findsOneWidget);
  });
}
