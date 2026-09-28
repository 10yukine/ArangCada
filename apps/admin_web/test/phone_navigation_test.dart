import 'package:arangcada_admin/main.dart';
import 'package:arangcada_admin/models.dart';
import 'package:arangcada_admin/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/admin_fixture.dart';

void main() {
  // Phones use the menu button and drawer. A bottom tab bar was tried and
  // removed (owner, 28 Sep 2026: the drawer behaves better on phones).
  testWidgets('phones open every section from the menu button', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    auth.value = const AdminSession(name: 'LGU evaluator', role: AdminRole.lgu);
    addTearDown(() async {
      auth.value = null;
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      ProviderScope(overrides: fixtureOverrides, child: const AdminApp()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.byTooltip('Open navigation'));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(Drawer),
        matching: find.text('Safety reports'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsNothing);
    expect(find.text('Safety reports'), findsWidgets);
  });

  testWidgets('desktop keeps the side rail and no menu button', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    auth.value = const AdminSession(name: 'LGU evaluator', role: AdminRole.lgu);
    addTearDown(() async {
      auth.value = null;
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      ProviderScope(overrides: fixtureOverrides, child: const AdminApp()),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Open navigation'), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
  });

  Future<void> phone(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    auth.value = const AdminSession(name: 'LGU evaluator', role: AdminRole.lgu);
    addTearDown(() async {
      auth.value = null;
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      ProviderScope(overrides: fixtureOverrides, child: const AdminApp()),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('phone dashboard leads with Needs attention, no extra links', (
    tester,
  ) async {
    await phone(tester);
    final attention = tester.getTopLeft(find.text('Needs attention')).dy;
    final metrics = tester.getTopLeft(find.text('OPEN SAFETY REPORTS')).dy;
    expect(attention, lessThan(metrics));
    expect(find.text('Open live map'), findsNothing);
    expect(
      find.textContaining('Records are scoped to your access'),
      findsNothing,
    );
  });

  testWidgets('phone toolbar: no appearance button, title scrolls to top', (
    tester,
  ) async {
    await phone(tester);
    expect(find.byTooltip('Appearance'), findsNothing);
    await tester.drag(find.text('Needs attention'), const Offset(0, -500));
    await tester.pumpAndSettle();
    double headingTop() =>
        tester.getTopLeft(find.text('Operations overview')).dy;
    expect(headingTop(), lessThan(0));
    await tester.tap(find.text('Dashboard').first);
    await tester.pumpAndSettle();
    expect(headingTop(), greaterThan(0));

    // Appearance is in Settings now, not the menu or toolbar.
    await tester.tap(find.byTooltip('Open navigation'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Appearance'), findsNothing);
  });

  testWidgets('phone driver filters fold behind a button', (tester) async {
    await phone(tester);
    await tester.tap(find.byTooltip('Open navigation'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(Drawer), matching: find.text('Drivers')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Search drivers'), findsOneWidget);
    expect(find.text('All statuses'), findsNothing);
    await tester.tap(find.byTooltip('Show filters'));
    await tester.pumpAndSettle();
    expect(find.text('All statuses'), findsOneWidget);
    expect(find.text('All TODAs'), findsOneWidget);
  });
}
