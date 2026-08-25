import 'package:arangcada_admin/main.dart';
import 'package:arangcada_admin/models.dart';
import 'package:arangcada_admin/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('demo login opens the seven-section console', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    auth.value = null;
    addTearDown(() async {
      auth.value = null;
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(const ProviderScope(child: AdminApp()));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    await tester.ensureVisible(find.text('Open console'));
    await tester.tap(find.text('Open console'));
    await tester.pumpAndSettle();

    expect(find.text('Good morning, evaluator'), findsOneWidget);
    expect(find.text('Live map'), findsAtLeastNWidgets(1));
    expect(find.text('Driver survey'), findsAtLeastNWidgets(1));
    expect(find.text('Settings'), findsAtLeastNWidgets(1));
  });

  testWidgets('compact rail remains usable at a narrow desktop size', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    auth.value = const AdminSession(
      name: 'Coordinator',
      role: AdminRole.toda,
      toda: 'Brgy. Real',
    );
    addTearDown(() async {
      auth.value = null;
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(const ProviderScope(child: AdminApp()));
    await tester.pumpAndSettle();

    expect(find.text('Good morning, evaluator'), findsOneWidget);
    expect(find.byIcon(Icons.map_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'dashboard restores operations panels and actionable review cards',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      auth.value = const AdminSession(
        name: 'LGU evaluator',
        role: AdminRole.lgu,
      );
      addTearDown(() async {
        auth.value = null;
        await tester.binding.setSurfaceSize(null);
      });

      await tester.pumpWidget(const ProviderScope(child: AdminApp()));
      await tester.pumpAndSettle();

      expect(find.text('Live dispatch map'), findsOneWidget);
      expect(find.text('Rides per hour · today'), findsOneWidget);
      expect(find.text('Terminal activity'), findsOneWidget);

      final semantics = tester.ensureSemantics();
      await tester.tap(find.text('PENDING REVIEWS'));
      await tester.pumpAndSettle();

      expect(find.text('Driver verification'), findsOneWidget);
      expect(find.text('Joel Mendoza'), findsOneWidget);
      expect(find.text('Mario Santos'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Settings')), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('Sign out')), findsWidgets);
      semantics.dispose();

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Compact table density'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Drivers'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<DataTable>(find.byType(DataTable)).dataRowMinHeight,
        48,
      );
    },
  );

  testWidgets('TODA survey hides and cannot record other terminals', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    auth.value = const AdminSession(
      name: 'Coordinator',
      role: AdminRole.toda,
      toda: 'Brgy. Real',
    );
    addTearDown(() async {
      auth.value = null;
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(const ProviderScope(child: AdminApp()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Driver survey'));
    await tester.pumpAndSettle();

    expect(find.text('Parian'), findsNothing);
    expect(find.text('Canlubang'), findsNothing);
    expect(find.text('10'), findsOneWidget);

    await tester.tap(find.text('Record response'));
    await tester.pumpAndSettle();

    expect(find.text('Record survey response'), findsOneWidget);
    expect(find.text('Parian'), findsNothing);
    expect(find.text('Canlubang'), findsNothing);

    await tester.tap(find.text('Submit response'));
    await tester.pumpAndSettle();
    expect(find.text('9'), findsOneWidget);

    await tester.tap(find.text('Dashboard'));
    await tester.pumpAndSettle();
    expect(find.text('9 of 10 target responses'), findsOneWidget);

    await tester.tap(find.text('Driver survey'));
    await tester.pumpAndSettle();
    expect(find.text('9'), findsOneWidget);
  });
}
