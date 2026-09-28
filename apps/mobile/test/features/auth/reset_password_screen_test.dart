import 'package:arangcada/app/router.dart';
import 'package:arangcada/app/theme/app_theme.dart';
import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/data/repositories/auth_repository.dart';
import 'package:arangcada/domain/models/demo_user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Auth extends Fake implements AuthRepository {
  _Auth(this.state);
  final DemoState state;
  final updates = <String>[];
  @override
  DemoUser? get currentUser => state.currentUser;
  @override
  Future<void> updatePassword(String newPassword) async =>
      updates.add(newPassword);
  @override
  Future<void> signOut() async => state.setCurrentUser(null);
}

class _App extends ConsumerWidget {
  const _App();
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    theme: AppTheme.light,
    routerConfig: ref.watch(appRouterProvider),
  );
}

void main() {
  // A reset link can open the app while a session is restored, so the
  // recovery screen must win over the signed-in home screen.
  testWidgets('reset link shows only the new-password screen, then login', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final state = DemoState(
      initialUser: const DemoUser(
        email: 'juan@example.test',
        displayName: 'Juan Dela Cruz',
        role: DemoRole.commuter,
        mobileNumber: '+639171234567',
        phoneVerified: true,
      ),
    );
    final auth = _Auth(state);
    final container = ProviderContainer(
      overrides: [
        demoStateProvider.overrideWithValue(state),
        authRepositoryProvider.overrideWithValue(auth),
        sessionRestorationProvider.overrideWith((ref) async {}),
      ],
    );
    addTearDown(() {
      passwordRecoveryPending.value = false;
      container.dispose();
      state.dispose();
    });
    String path() => container
        .read(appRouterProvider)
        .routeInformationProvider
        .value
        .uri
        .path;
    Future<void> settle() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const _App()),
    );
    await settle();
    expect(path(), '/home');

    passwordRecoveryPending.value = true;
    await settle();
    expect(path(), '/reset-password');
    container.read(appRouterProvider).go('/home');
    await settle();
    expect(path(), '/reset-password');

    await tester.enterText(find.byType(TextField).at(0), 'newpass123');
    await tester.enterText(find.byType(TextField).at(1), 'different1');
    await tester.tap(find.text('Save new password'));
    await settle();
    expect(find.text('Passwords do not match.'), findsOneWidget);
    expect(auth.updates, isEmpty);

    await tester.enterText(find.byType(TextField).at(1), 'newpass123');
    await tester.tap(find.text('Save new password'));
    await settle();
    expect(auth.updates, ['newpass123']);
    expect(passwordRecoveryPending.value, isFalse);
    expect(state.currentUser, isNull);
    expect(path(), '/login');
  });

  // Demo tools fake trip outcomes; a real beta account must not reach them.
  testWidgets('a real account cannot open demo tools', (tester) async {
    final state = DemoState(
      initialUser: const DemoUser(
        email: 'juan@example.test',
        displayName: 'Juan Dela Cruz',
        role: DemoRole.commuter,
        mobileNumber: '+639171234567',
        phoneVerified: true,
      ),
    );
    final container = ProviderContainer(
      overrides: [
        demoStateProvider.overrideWithValue(state),
        authRepositoryProvider.overrideWithValue(_Auth(state)),
        sessionRestorationProvider.overrideWith((ref) async {}),
      ],
    );
    addTearDown(() {
      container.dispose();
      state.dispose();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const _App()),
    );
    await tester.pump();
    final router = container.read(appRouterProvider);
    router.go('/profile/demo-tools');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(router.routeInformationProvider.value.uri.path, '/home');
  });
}
