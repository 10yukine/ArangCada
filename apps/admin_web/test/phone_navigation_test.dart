import 'package:arangcada_admin/main.dart';
import 'package:arangcada_admin/models.dart';
import 'package:arangcada_admin/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/admin_fixture.dart';

void main() {
  // The owner found the drawer-only console hard to use on a phone: the main
  // sections are now one tap away and the rest sit under More.
  testWidgets('phones get a tab bar with the rest under More', (tester) async {
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

    final bar = find.byType(NavigationBar);
    expect(bar, findsOneWidget);
    await tester.tap(find.descendant(of: bar, matching: find.text('Safety')));
    await tester.pumpAndSettle();
    expect(find.text('Safety reports'), findsWidgets);

    await tester.tap(find.descendant(of: bar, matching: find.text('More')));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsOneWidget);
    expect(find.text('Evaluation'), findsOneWidget);
  });

  testWidgets('desktop keeps the side rail and no tab bar', (tester) async {
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
    expect(find.byType(NavigationBar), findsNothing);
  });
}
