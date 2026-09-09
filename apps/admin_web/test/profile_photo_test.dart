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
    'the edit badge renders fully inside its own tappable area, not '
    'poking outside it',
    (tester) async {
      // Regression test for a real bug: the badge used to sit at a
      // negative Positioned offset (right: -2, bottom: -2) so it could
      // visually poke past the avatar's edge -- painted there via
      // Clip.none, but *outside* the GestureDetector's own hit-test
      // bounds (a Positioned child painting outside a Stack's bounds does
      // not extend what that Stack -- or its ancestor GestureDetector --
      // will hit-test). It was visible and looked tappable but a real
      // click on it silently did nothing. A presence-only check
      // (find.bySemanticsLabel, the test above) cannot catch this class
      // of bug; this asserts the actual geometry instead -- everything
      // that paints must stay within the one Rect that is tappable.
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

      final hitTestArea = tester.getRect(
        find.byKey(const ValueKey('avatarHitTestBox')),
      );
      final badge = tester.getRect(find.byIcon(Icons.edit));

      expect(hitTestArea.contains(badge.topLeft), isTrue);
      expect(hitTestArea.contains(badge.bottomRight), isTrue);
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
