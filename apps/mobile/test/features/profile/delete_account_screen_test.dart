import 'package:arangcada/app/router.dart';
import 'package:arangcada/app/theme/app_theme.dart';
import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/data/repositories/auth_repository.dart';
import 'package:arangcada/domain/models/demo_user.dart';
import 'package:arangcada/features/profile/delete_account_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _Auth extends Fake implements AuthRepository {
  _Auth(this.state);
  final DemoState state;
  @override
  DemoUser? get currentUser => state.currentUser;
  @override
  Future<void> signOut() async {
    state.setCurrentUser(null);
    // The deleted account's server sign-out fails; the screen must not care.
    throw const DemoAuthException('user not found');
  }
}

void main() {
  late DemoState state;
  late List<String> attempts;
  late ProviderContainer container;

  Future<void> open(WidgetTester tester, {DemoAuthException? failure}) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    state = DemoState(
      initialUser: const DemoUser(
        email: 'juan@example.test',
        displayName: 'Juan Dela Cruz',
        role: DemoRole.commuter,
        mobileNumber: '+639171234567',
        phoneVerified: true,
      ),
    );
    attempts = [];
    container = ProviderContainer(
      overrides: [
        demoStateProvider.overrideWithValue(state),
        authRepositoryProvider.overrideWithValue(_Auth(state)),
        sessionRestorationProvider.overrideWith((ref) async {}),
        accountDeleterProvider.overrideWithValue((password) async {
          attempts.add(password);
          if (failure != null) throw failure;
        }),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) => MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: ref.watch(appRouterProvider),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    container.read(appRouterProvider).go('/profile/delete-account');
    await tester.pumpAndSettle();
  }

  testWidgets('deletes after the password, signs out and returns to login', (
    tester,
  ) async {
    await open(tester);
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete my account'));
    await tester.pump();
    expect(find.text('Enter your password to confirm.'), findsOneWidget);
    expect(attempts, isEmpty);

    await tester.enterText(find.byType(TextField), 'secret-pass');
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete my account'));
    await tester.pumpAndSettle();
    expect(attempts, ['secret-pass']);
    expect(state.currentUser, isNull);
    expect(
      container.read(appRouterProvider).routeInformationProvider.value.uri.path,
      '/login',
    );
    expect(find.text('Your account was deleted.'), findsOneWidget);
  });

  testWidgets('a refused deletion keeps the account and explains why', (
    tester,
  ) async {
    await open(
      tester,
      failure: const DemoAuthException(
        'Finish or cancel your current ride before deleting your account.',
      ),
    );
    await tester.enterText(find.byType(TextField), 'secret-pass');
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete my account'));
    await tester.pumpAndSettle();
    expect(state.currentUser, isNotNull);
    expect(find.textContaining('Finish or cancel'), findsOneWidget);
    expect(find.byType(DeleteAccountScreen), findsOneWidget);
    expect(
      GoRouter.of(tester.element(find.byType(DeleteAccountScreen))),
      isNotNull,
    );
  });
}
