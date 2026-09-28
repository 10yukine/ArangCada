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
  testWidgets('phones open every section from the menu button', (
    tester,
  ) async {
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
}
