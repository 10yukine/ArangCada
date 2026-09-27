import 'dart:async';

import 'package:arangcada/app/app.dart';
import 'package:arangcada/app/router.dart';
import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/domain/models/demo_user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final role in DemoRole.values) {
    testWidgets(
      'holds splash while restoring ${role.name}, never flashes login',
      (tester) async {
        final pending = Completer<void>();
        final state = DemoState();
        final container = ProviderContainer(
          overrides: [
            demoStateProvider.overrideWithValue(state),
            sessionRestorationProvider.overrideWith((ref) => pending.future),
          ],
        );
        addTearDown(container.dispose);
        addTearDown(state.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const ArangCadaApp(),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(find.text('Log In'), findsNothing);
        final router = container.read(appRouterProvider);
        router.go('/login');
        await tester.pump();
        expect(router.routeInformationProvider.value.uri.path, '/splash');
        // An unverified account must still pass the existing verification gate.
        // With a number on file; a missing number goes to phone setup first.
        state.setCurrentUser(
          DemoUser(
            email: 'test@example.com',
            displayName: 'Test',
            role: role,
            mobileNumber: '+639171234567',
          ),
        );
        await tester.pump();
        expect(find.text('Log In'), findsNothing);
        pending.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(router.routeInformationProvider.value.uri.path, '/verify-phone');
        expect(find.text('Log In'), findsNothing);
        state.setCurrentUser(
          DemoUser(
            email: 'test@example.com',
            displayName: 'Test',
            role: role,
            phoneVerified: true,
          ),
        );
        router.go('/splash');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          router.routeInformationProvider.value.uri.path,
          role == DemoRole.commuter ? '/home' : '/driver',
        );
        expect(find.text('Log In'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('failed restoration offers retry without showing login', (
    tester,
  ) async {
    var attempts = 0;
    final container = ProviderContainer(
      overrides: [
        sessionRestorationProvider.overrideWith((ref) async {
          if (attempts++ == 0) throw Exception('offline');
        }),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ArangCadaApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Log In'), findsNothing);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Log In'), findsOneWidget);
    expect(attempts, 2);
  });
}
