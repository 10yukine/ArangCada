import 'package:arangcada/app/theme/app_theme.dart';
import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/providers/repository_providers.dart';
import 'package:arangcada/domain/models/demo_user.dart';
import 'package:arangcada/features/trips/trips_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> render(WidgetTester tester, DemoRole role, {bool samples = false}) async {
    final state = DemoState(
      initialUser: DemoUser(
        email: '${role.name}@arangcada.demo',
        displayName: role == DemoRole.driver ? 'Mang Ben D.' : 'Ana Santos',
        role: role,
      ),
    );
    if (samples) state.setSampleContent(true);
    addTearDown(state.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [demoStateProvider.overrideWithValue(state)],
        child: MaterialApp(theme: AppTheme.light, home: const TripsScreen()),
      ),
    );
  }

  testWidgets('first-run trip histories stay honestly empty for both roles', (
    tester,
  ) async {
    await render(tester, DemoRole.commuter);
    expect(find.text('No trips yet'), findsOneWidget);
    expect(find.text('Calamba Crossing → SM Calamba'), findsNothing);

    await render(tester, DemoRole.driver);
    expect(find.text('No driver trips yet'), findsOneWidget);
    expect(find.text('Crossing Market → City Hall'), findsNothing);
  });

  testWidgets('commuter sample trips match the approved history filters', (
    tester,
  ) async {
    await render(tester, DemoRole.commuter, samples: true);

    expect(find.text('Trip history'), findsOneWidget);
    expect(find.text('Latest completed trip: Jul 3'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Special'), findsWidgets);
    expect(find.text('Pooling'), findsWidgets);
    expect(find.text('Calamba Crossing → SM Calamba'), findsOneWidget);
    expect(find.text('₱60.00'), findsNWidgets(2));

    await tester.tap(find.text('Pooling').first);
    await tester.pumpAndSettle();
    expect(find.text('City Hall → Crossing Market'), findsOneWidget);
    expect(find.text('Calamba Crossing → SM Calamba'), findsNothing);
  });

  testWidgets('driver sample trips follow the approved three-record layout', (
    tester,
  ) async {
    await render(tester, DemoRole.driver, samples: true);

    expect(find.text('Trip records'), findsOneWidget);
    expect(find.text('Crossing Market → City Hall'), findsOneWidget);
    expect(find.text('Brgy. Real → Crossing Market'), findsOneWidget);
    expect(find.text('Calamba Crossing → SM Calamba'), findsOneWidget);
    expect(find.text('Commuter: Rico C. · Pooling'), findsOneWidget);
    expect(find.text('₱15.00'), findsOneWidget);
    expect(find.text('₱60.00'), findsNWidgets(2));
  });
}
