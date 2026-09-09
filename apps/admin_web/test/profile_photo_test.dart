import 'package:arangcada_admin/main.dart';
import 'package:arangcada_admin/models.dart';
import 'package:arangcada_admin/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    auth.value = null;
  });

  Future<void> openSettings(WidgetTester tester, AdminSession session) async {
    await tester.binding.setSurfaceSize(const Size(1001, 941));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    auth.value = session;
    await tester.pumpWidget(const ProviderScope(child: AdminApp()));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a connected session with no photo yet offers to change it',
    (tester) async {
      await openSettings(
        tester,
        const AdminSession(
          name: 'Maria Robles',
          email: 'm.robles@calamba.gov.ph',
          role: AdminRole.lgu,
          userId: 'admin-1',
          connected: true,
        ),
      );

      // Initials still render (no photo on file yet).
      expect(find.text('MR'), findsWidgets);
      final semantics = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel(RegExp('Change profile photo')),
        findsOneWidget,
      );
      semantics.dispose();
    },
  );

  testWidgets(
    'a disconnected local-demo session cannot change its photo',
    (tester) async {
      await openSettings(
        tester,
        const AdminSession(name: 'LGU Evaluator', role: AdminRole.lgu),
      );

      final semantics = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel(RegExp('Change profile photo')),
        findsNothing,
      );
      semantics.dispose();
    },
  );
}
